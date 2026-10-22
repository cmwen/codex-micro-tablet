package com.cmwen.codex_micro_tablet

import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.os.Handler
import android.os.ParcelUuid
import android.util.Log
import java.util.ArrayDeque
import java.util.UUID

/** One foreground HOGP peripheral. All state and Android callbacks live on the UI looper. */
@SuppressLint("MissingPermission")
class BleHidPeripheral(
    private val context: Context,
    private val handler: Handler,
    private val listener: Listener
) {
    interface Listener {
        fun onRegistered(registered: Boolean)
        fun onConnection(device: BluetoothDevice?)
        fun onReport(data: ByteArray)
        fun onChanged()
        fun onError(message: String)
    }
    companion object {
        fun uuid(short: String): UUID = UUID.fromString("0000$short-0000-1000-8000-00805f9b34fb")
        val HID_UUID = uuid("1812")
        val REPORT_UUID = uuid("2a4d")
        val CCCD_UUID = uuid("2902")
        val REFERENCE_UUID = uuid("2908")
        val PNP_VALUE = byteArrayOf(2, 0x3a, 0x30, 0x60, 0x83.toByte(), 0xb0.toByte(), 0)
        private const val NAME = "Codex Micro Tablet"
    }
    private val manager = context.getSystemService(BluetoothManager::class.java)
    private val adapter get() = manager?.adapter
    private var server: BluetoothGattServer? = null
    private var advertisingCallback: AdvertiseCallback? = null
    private var oldName: String? = null
    private var epoch = 0L
    private var peer: BluetoothDevice? = null
    private var linkEpoch = 0L
    private var input: BluetoothGattCharacteristic? = null
    private var output: BluetoothGattCharacteristic? = null
    private var feature: BluetoothGattCharacteristic? = null
    private var reportMap: BluetoothGattCharacteristic? = null
    private var cccd: BluetoothGattDescriptor? = null
    private var pendingNotify = false
    private var notificationSequence = 0L
    private var suspended = false
    private var subscribed = false
    private var published = false
    private var lastInput = idleReport()
    private val services = ArrayDeque<BluetoothGattService>()
    var advertising = false; private set
    var mtu = 23; private set
    val supported get() = adapter?.isMultipleAdvertisementSupported == true
    val ready get() = published && peer != null && subscribed && !suspended && mtu >= MicroWire.BODY_SIZE + 3
    val busy get() = pendingNotify

    private fun idleReport() = ByteArray(MicroWire.BODY_SIZE).apply { this[0] = 2 }
    private fun changed() = listener.onChanged()
    private fun problem(message: String) { listener.onError(message); changed() }
    private fun onMain(token: Long, block: () -> Unit) { handler.post { if (token == epoch) block() } }

    fun start() {
        if (server != null) return
        if (adapter?.isEnabled != true) { listener.onRegistered(false); problem("Turn on Bluetooth before starting BLE HID"); return }
        if (!supported) { listener.onRegistered(false); problem("This tablet does not support BLE peripheral advertising"); return }
        val token = ++epoch
        try {
            server = manager?.openGattServer(context, callbacks(token))
            if (server == null) { listener.onRegistered(false); problem("Android could not open the BLE GATT server"); return }
            makeServices()
            addNextService()
            handler.postDelayed({
                if (token == epoch && server != null && !published) {
                    stop(); problem("BLE service publication timed out. This firmware may restrict the HID service UUID; inspect Bluetooth logs.")
                }
            }, 12000)
        } catch (e: Exception) { stop(); problem("BLE HID startup failed: ${e.message}") }
    }

    private fun read(uuid: String, value: ByteArray, permissions: Int = BluetoothGattCharacteristic.PERMISSION_READ): BluetoothGattCharacteristic =
        BluetoothGattCharacteristic(uuid(uuid), BluetoothGattCharacteristic.PROPERTY_READ, permissions).apply { this.value = value }

    private fun makeServices() {
        services.clear()
        val hid = BluetoothGattService(HID_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        hid.addCharacteristic(read("2a4a", byteArrayOf(0x11, 0x01, 0, 1))) // HID 1.11, normally connectable
        reportMap = read("2a4b", MicroWire.DESCRIPTOR)
        hid.addCharacteristic(reportMap)
        hid.addCharacteristic(BluetoothGattCharacteristic(uuid("2a4c"), BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE,
            BluetoothGattCharacteristic.PERMISSION_WRITE_ENCRYPTED).apply { value = byteArrayOf(0) })
        hid.addCharacteristic(BluetoothGattCharacteristic(uuid("2a4e"), BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE,
            BluetoothGattCharacteristic.PERMISSION_READ_ENCRYPTED or BluetoothGattCharacteristic.PERMISSION_WRITE_ENCRYPTED).apply { value = byteArrayOf(1) })
        input = report(1, BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_READ_ENCRYPTED)
        cccd = BluetoothGattDescriptor(CCCD_UUID, BluetoothGattDescriptor.PERMISSION_READ_ENCRYPTED or BluetoothGattDescriptor.PERMISSION_WRITE_ENCRYPTED).apply {
            value = BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE.copyOf()
        }
        input!!.addDescriptor(cccd)
        output = report(2, BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE,
            BluetoothGattCharacteristic.PERMISSION_READ_ENCRYPTED or BluetoothGattCharacteristic.PERMISSION_WRITE_ENCRYPTED)
        feature = report(3, BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_WRITE,
            BluetoothGattCharacteristic.PERMISSION_READ_ENCRYPTED or BluetoothGattCharacteristic.PERMISSION_WRITE_ENCRYPTED)
        hid.addCharacteristic(input); hid.addCharacteristic(output); hid.addCharacteristic(feature)
        services.add(hid)
        services.add(BluetoothGattService(uuid("180a"), BluetoothGattService.SERVICE_TYPE_PRIMARY).apply {
            addCharacteristic(read("2a29", "Work Louder".toByteArray()))
            addCharacteristic(read("2a24", NAME.toByteArray()))
            addCharacteristic(read("2a50", PNP_VALUE))
        })
        val battery = context.getSystemService(android.os.BatteryManager::class.java)?.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1
        services.add(BluetoothGattService(uuid("180f"), BluetoothGattService.SERVICE_TYPE_PRIMARY).apply {
            addCharacteristic(read("2a19", byteArrayOf(battery.coerceIn(0, 100).toByte())))
        })
    }

    private fun report(type: Int, properties: Int, permissions: Int): BluetoothGattCharacteristic =
        BluetoothGattCharacteristic(REPORT_UUID, properties, permissions).apply {
            value = idleReport()
            addDescriptor(BluetoothGattDescriptor(REFERENCE_UUID, BluetoothGattDescriptor.PERMISSION_READ).apply {
                value = byteArrayOf(MicroWire.REPORT_ID.toByte(), type.toByte())
            })
        }

    private fun addNextService() {
        if (services.isEmpty()) { advertise(); return }
        val service = services.removeFirst()
        Log.i("CodexMicroHid", "Publishing BLE service ${service.uuid}")
        if (server?.addService(service) != true) { stop(); problem("Android rejected BLE service ${service.uuid}") }
    }

    private fun advertise() {
        val advertiser = adapter?.bluetoothLeAdvertiser
        if (advertiser == null) { stop(); problem("BLE advertising is unavailable on this tablet"); return }
        val token = epoch
        // Android's public scan-response API uses the adapter's local name.
        if (oldName == null) oldName = adapter?.name
        if (adapter?.name != NAME && adapter?.setName(NAME) != true) {
            stop(); problem("Could not set the Bluetooth peripheral name"); return
        }
        val callback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) = onMain(token) {
                Log.i("CodexMicroHid", "BLE advertising started: HID1812 PnP=02:3a30:6083:b000")
                advertising = true; published = true; listener.onRegistered(true); changed()
            }
            override fun onStartFailure(errorCode: Int) = onMain(token) {
                stop(); problem("BLE advertising failed (Android code $errorCode)")
            }
        }
        advertisingCallback = callback
        advertiser.startAdvertising(
            AdvertiseSettings.Builder().setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                .setConnectable(true).setTimeout(0).setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM).build(),
            AdvertiseData.Builder().addServiceUuid(ParcelUuid(HID_UUID)).build(),
            AdvertiseData.Builder().setIncludeDeviceName(true).build(), callback
        )
    }

    fun disconnect() {
        // A pending notification has no connection ID in Android's completion
        // callback. Recreate its server to prevent an old completion from being
        // attributed to a new connection to the same Mac address.
        val recreate = pendingNotify
        peer?.let { server?.cancelConnection(it) }
        if (recreate) { stop(); if (adapter?.isEnabled == true) start() }
        else { clearPeer(); if (published && !advertising) advertise() }
    }
    private fun clearPeer() {
        linkEpoch++
        peer = null; mtu = 23; subscribed = false; suspended = false; pendingNotify = false; notificationSequence++
        lastInput = idleReport(); cccd?.value = BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE.copyOf()
        listener.onConnection(null); changed()
    }
    fun stop() {
        epoch++
        advertisingCallback?.let { callback -> runCatching { adapter?.bluetoothLeAdvertiser?.stopAdvertising(callback) } }
        advertisingCallback = null; advertising = false; published = false
        peer?.let { device -> runCatching { server?.cancelConnection(device) } }
        runCatching { server?.close() }; server = null; services.clear()
        clearPeer(); listener.onRegistered(false)
        oldName?.let { previous -> runCatching { if (adapter?.name == NAME && previous != NAME) adapter?.setName(previous) } }
        oldName = null
    }

    /** Submit one report; another may only follow its onNotificationSent callback. */
    fun send(body: ByteArray): Boolean {
        val device = peer ?: return false
        val characteristic = input ?: return false
        if (!ready || pendingNotify || body.size != MicroWire.BODY_SIZE) return false
        characteristic.value = body.copyOf()
        val accepted = server?.notifyCharacteristicChanged(device, characteristic, false) == true
        if (accepted) {
            lastInput = body.copyOf(); pendingNotify = true
            val token = epoch
            val sequence = ++notificationSequence
            handler.postDelayed({
                if (token == epoch && sequence == notificationSequence && pendingNotify) {
                    disconnect(); problem("BLE notification timed out; reconnect the Mac")
                }
            }, 2000)
        }
        return accepted
    }

    private fun callbacks(token: Long) = object : BluetoothGattServerCallback() {
        override fun onServiceAdded(status: Int, service: BluetoothGattService) = onMain(token) {
            Log.i("CodexMicroHid", "BLE service ${service.uuid} status=$status")
            if (status == BluetoothGatt.GATT_SUCCESS) addNextService()
            else { stop(); problem("BLE service ${service.uuid} registration failed (status $status); firmware may restrict HID services") }
        }
        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) = onMain(token) {
            Log.i("CodexMicroHid", "BLE connection state=$newState status=$status")
            if (newState == BluetoothProfile.STATE_CONNECTED && status == BluetoothGatt.GATT_SUCCESS) {
                if (peer != null) {
                    if (peer?.address != device.address) server?.cancelConnection(device)
                    return@onMain
                }
                advertisingCallback?.let { callback -> adapter?.bluetoothLeAdvertiser?.stopAdvertising(callback) }
                advertisingCallback = null; advertising = false
                clearPeer(); peer = device; listener.onConnection(device); changed()
            } else if (peer?.address == device.address) {
                if (pendingNotify) { stop(); if (adapter?.isEnabled == true) start() }
                else { clearPeer(); if (published && !advertising) advertise() }
            }
        }
        override fun onMtuChanged(device: BluetoothDevice, value: Int) = onMain(token) {
            if (peer?.address == device.address) {
                Log.i("CodexMicroHid", "BLE MTU=$value")
                mtu = value
                if (value < MicroWire.BODY_SIZE + 3) problem("Mac negotiated BLE MTU $value; Micro requires at least 66 bytes")
                changed()
            }
        }
        override fun onNotificationSent(device: BluetoothDevice, status: Int) {
            val connection = linkEpoch
            onMain(token) {
                if (connection == linkEpoch && peer?.address == device.address && pendingNotify) {
                    pendingNotify = false; notificationSequence++
                    if (status != BluetoothGatt.GATT_SUCCESS) { disconnect(); problem("BLE notification failed (status $status); reconnect the Mac") }
                    changed()
                }
            }
        }
        override fun onCharacteristicReadRequest(device: BluetoothDevice, requestId: Int, offset: Int, characteristic: BluetoothGattCharacteristic) = onMain(token) {
            Log.i("CodexMicroHid", "BLE read ${characteristic.uuid} offset=$offset")
            val value = if (characteristic === input || characteristic === output || characteristic === feature) lastInput else characteristic.value ?: byteArrayOf()
            respondRead(device, requestId, offset, value)
        }
        override fun onDescriptorReadRequest(device: BluetoothDevice, requestId: Int, offset: Int, descriptor: BluetoothGattDescriptor) = onMain(token) {
            respondRead(device, requestId, offset, descriptor.value ?: byteArrayOf())
        }
        override fun onCharacteristicWriteRequest(device: BluetoothDevice, requestId: Int, characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray) = onMain(token) {
            Log.i("CodexMicroHid", "BLE write ${characteristic.uuid} length=${value.size} prepared=$preparedWrite offset=$offset")
            var status = validateWrite(device, preparedWrite, offset)
            if (status == BluetoothGatt.GATT_SUCCESS) {
                when {
                    characteristic === output || characteristic === feature -> {
                        if (value.size !in 2..MicroWire.BODY_SIZE) status = BluetoothGatt.GATT_INVALID_ATTRIBUTE_LENGTH
                        else listener.onReport(value.copyOf())
                    }
                    characteristic.uuid == uuid("2a4c") -> {
                        if (value.size != 1 || value[0].toInt() !in 0..1) status = BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED
                        else { suspended = value[0].toInt() == 0; changed() }
                    }
                    characteristic.uuid == uuid("2a4e") -> {
                        if (!value.contentEquals(byteArrayOf(1))) status = BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED
                    }
                    else -> status = BluetoothGatt.GATT_WRITE_NOT_PERMITTED
                }
            }
            if (responseNeeded) server?.sendResponse(device, requestId, status, offset, null)
        }
        override fun onDescriptorWriteRequest(device: BluetoothDevice, requestId: Int, descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray) = onMain(token) {
            var status = validateWrite(device, preparedWrite, offset)
            if (status == BluetoothGatt.GATT_SUCCESS) {
                if (descriptor !== cccd) status = BluetoothGatt.GATT_WRITE_NOT_PERMITTED
                else if (!value.contentEquals(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE) && !value.contentEquals(BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE)) status = BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED
                else {
                    subscribed = value.contentEquals(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
                    Log.i("CodexMicroHid", "BLE report6 notifications=$subscribed MTU=$mtu")
                    descriptor.value = value.copyOf()
                    changed()
                }
            }
            if (responseNeeded) server?.sendResponse(device, requestId, status, offset, null)
        }
        override fun onExecuteWrite(device: BluetoothDevice, requestId: Int, execute: Boolean) = onMain(token) {
            server?.sendResponse(device, requestId, BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED, 0, null)
        }
    }

    private fun validateWrite(device: BluetoothDevice, prepared: Boolean, offset: Int): Int = when {
        peer?.address != device.address -> BluetoothGatt.GATT_WRITE_NOT_PERMITTED
        prepared -> BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED
        offset != 0 -> BluetoothGatt.GATT_INVALID_OFFSET
        else -> BluetoothGatt.GATT_SUCCESS
    }
    private fun respondRead(device: BluetoothDevice, request: Int, offset: Int, value: ByteArray) {
        if (peer?.address != device.address) { server?.sendResponse(device, request, BluetoothGatt.GATT_READ_NOT_PERMITTED, offset, null); return }
        if (offset < 0 || offset > value.size) server?.sendResponse(device, request, BluetoothGatt.GATT_INVALID_OFFSET, offset, null)
        else server?.sendResponse(device, request, BluetoothGatt.GATT_SUCCESS, offset, value.copyOfRange(offset, minOf(value.size, offset + mtu - 1)))
    }
}
