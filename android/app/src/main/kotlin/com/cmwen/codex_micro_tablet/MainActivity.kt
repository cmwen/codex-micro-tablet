package com.cmwen.codex_micro_tablet

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHidDevice
import android.bluetooth.BluetoothHidDeviceAppSdpSettings
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.security.KeyStore
import java.util.ArrayDeque
import java.util.concurrent.Executor
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Foreground-only Micro companion with BLE HOGP and Classic HID transports. */
@SuppressLint("MissingPermission")
class MainActivity : FlutterActivity() {
    private val handler = Handler(Looper.getMainLooper())
    private val executor = Executor { handler.post(it) }
    private val adapter: BluetoothAdapter? get() = getSystemService(BluetoothManager::class.java)?.adapter
    private var hid: BluetoothHidDevice? = null
    private var transportMode = "ble"
    private val ble by lazy { BleHidPeripheral(this, handler, object : BleHidPeripheral.Listener {
        override fun onRegistered(accepted: Boolean) {
            if (transportMode != "ble") return
            registered = accepted; registering = false
            if (accepted) error = null
            emit()
        }
        override fun onConnection(device: BluetoothDevice?) {
            if (transportMode != "ble") return
            resetLink(); host = device; emit()
        }
        override fun onReport(data: ByteArray) {
            if (transportMode == "ble" && host != null) receive(data)
        }
        override fun onChanged() { emit() }
        override fun onError(message: String) { fail(message) }
    }) }
    private var usbMicRequested = false
    private var foreground = true
    private val usb by lazy { UsbHidTransport(this, handler, object : UsbHidTransport.Listener {
        override fun onRegistered(accepted: Boolean) {
            if (transportMode != "usb") return
            registered = accepted; registering = false
            if (accepted) error = null
            if (accepted && requested && foreground && usbMicRequested) microphone.start()
            emit()
        }
        override fun onConnection(connected: Boolean) {
            if (transportMode != "usb") return
            resetLink(); emit()
        }
        override fun onReport(data: ByteArray) { if (transportMode == "usb") receive(data) }
        override fun onError(message: String) { fail(message) }
        override fun onChanged() { emit() }
    }) }
    private val microphone by lazy { UsbMicrophone(this, handler, object : UsbMicrophone.Listener {
        override fun onChanged() { emit() }
        override fun onError(message: String) { fail(message) }
    }) }
    private fun connected() = if (transportMode == "usb") usb.connected else host != null
    private fun linkReady() = when (transportMode) { "ble" -> ble.ready; "usb" -> usb.active && usb.connected; else -> true }
    private fun recoverUsb() {
        requested = false; usbMicRequested = false
        releaseAll("manual restore")
        microphone.stop()
        ble.stop()
        if (permitted()) { host?.let { hid?.disconnect(it) }; hid?.unregisterApp() }
        registered = false; registering = false; resetLink()
        usb.recover { restored ->
            if (restored) {
                error = null
                getSharedPreferences("hid", MODE_PRIVATE).edit().putBoolean("usbRecoveryNeeded", false).apply()
            }
            emit()
        }
        emit()
    }

    private fun sendReport(body: ByteArray): Boolean = when (transportMode) {
        "usb" -> usb.send(body)
        "ble" -> ble.send(body)
        else -> host?.let { hid?.sendReport(it, MicroWire.REPORT_ID, body) } == true
    }
    private fun disconnectHost(): Boolean {
        if (transportMode == "usb") { microphone.stop(); usb.stop(); return true }
        val device = host ?: return false
        return if (transportMode == "ble") { ble.disconnect(); true } else hid?.disconnect(device) == true
    }
    private fun changeTransport(value: String) {
        require(value in listOf("ble", "classic", "usb")) { "Choose BLE, Classic or USB HID" }
        if (value == transportMode) return
        requested = false
        releaseAll()
        microphone.stop()
        if (transportMode == "ble") ble.stop()
        else if (transportMode == "usb") usb.stop()
        else if (permitted()) { host?.let { hid?.disconnect(it) }; hid?.unregisterApp() }
        registered = false; registering = false; resetLink()
        transportMode = value
        getSharedPreferences("hid", MODE_PRIVATE).edit().putString("transport", value).apply()
        error = null
        if (value == "usb") usb.recover { restored ->
            if (restored) getSharedPreferences("hid", MODE_PRIVATE).edit().putBoolean("usbRecoveryNeeded", false).apply()
            emit()
        }
        emit()
    }
    private var sink: EventChannel.EventSink? = null
    private var host: BluetoothDevice? = null
    private var registered = false
    private var requested = false
    private var registering = false
    private var proxyPending = false
    private var discovered = false
    private var error: String? = null
    private var rxReports = 0L
    private var txReports = 0L
    private val pressed = mutableSetOf<Int>()
    private val decoder = MicroWire.Decoder()
    private val slots = Array(6) { index -> mutableMapOf<String, Any>("id" to index, "present" to false, "color" to 0, "brightness" to 1.0, "effect" to "") }
    private data class Outgoing(val body: ByteArray, val queuedAt: Long = SystemClock.elapsedRealtime())
    private val outgoing = ArrayDeque<Outgoing>()
    private var sending = false
    private var txGeneration = 0L
    private var lastRx = 0L
    private var listening = false

    private fun permitted(): Boolean = Build.VERSION.SDK_INT < 31 ||
        (checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED &&
         checkSelfPermission(Manifest.permission.BLUETOOTH_ADVERTISE) == PackageManager.PERMISSION_GRANTED)

    private fun snapshot(): Map<String, Any?> = mapOf(
        "supported" to (Build.VERSION.SDK_INT >= 28 && (transportMode == "usb" || (adapter != null && (transportMode != "ble" || ble.supported)))),
        "bluetoothEnabled" to (permitted() && adapter?.isEnabled == true),
        "registered" to registered, "connected" to connected(),
        "hostName" to (if (transportMode == "usb") "USB host" else if (permitted()) host?.name else null),
        "hostAddress" to host?.address,
        "discovered" to (discovered && linkReady()), "error" to error,
        "slots" to slots.map { it.toMap() }, "rxReports" to rxReports, "txReports" to txReports,
        "transportMode" to transportMode,
        "transport" to when(transportMode) { "usb" -> "USB HID + microphone"; "ble" -> "Bluetooth LE HID"; else -> "Bluetooth Classic HID" },
        "usbActive" to usb.active, "usbStatus" to usb.status,
        "microphoneActive" to microphone.active, "microphoneStatus" to microphone.status,
        "microphoneFrames" to microphone.frames,
        "usbRecoveryNeeded" to getSharedPreferences("hid", MODE_PRIVATE).getBoolean("usbRecoveryNeeded", false),
        "advertising" to (transportMode == "ble" && ble.advertising),
        "mtu" to (if (transportMode == "ble") ble.mtu else null),
        "identityNote" to (if (transportMode == "usb") "USB mode uses the stock HID and audio-source drivers. Restore USB to return to the previous configuration." else if (transportMode == "ble") "BLE advertises Micro vendor 303a / product 8360. Waiting for the Mac's Micro protocol exchange confirms compatibility."
            else "Classic HID uses Android's PnP identity. Pairing alone does not confirm Micro compatibility.")
    )

    private fun emit() { handler.post { sink?.success(snapshot()) } }
    private fun fail(message: String) { error = message; emit() }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        transportMode = getSharedPreferences("hid", MODE_PRIVATE).getString("transport", "ble")?.takeIf { it in listOf("classic", "usb") } ?: "ble"
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "codex_micro/hid").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "status" -> result.success(snapshot())
                    "setTransport" -> { changeTransport(call.argument<String>("transport") ?: "ble"); result.success(snapshot()) }
                    "start" -> { requested = true; error = null; startHid(true); result.success(snapshot()) }
                    "restoreUsb" -> { recoverUsb(); result.success(snapshot()) }
                    "stopMicrophone" -> { usbMicRequested = false; microphone.stop(); result.success(snapshot()) }
                    "startMicrophone" -> {
                        check(transportMode == "usb" && usb.active) { "Start USB mode first" }
                        usbMicRequested = true
                        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED)
                            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 431)
                        else microphone.start()
                        result.success(snapshot())
                    }
                    "discoverable" -> {
                        check(permitted()) { "Enable Bluetooth access first" }
                        check(adapter?.isEnabled == true) { "Turn on Bluetooth first" }
                        if (transportMode == "ble") {
                            check(registered) { "Start BLE HID first" }
                            // LE advertising is already connectable; Classic visibility is unrelated.
                            emit()
                        } else startActivity(Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE).putExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION, 120))
                        result.success(true)
                    }
                    "devices" -> {
                        check(permitted()) { "Enable Bluetooth access first" }
                        result.success(adapter?.bondedDevices?.map { mapOf("name" to (it.name ?: "Bluetooth host"), "address" to it.address) } ?: emptyList<Any>())
                    }
                    "connect" -> {
                        check(permitted() && registered) { "Start Bluetooth HID before connecting" }
                        check(transportMode == "classic") { "Connect BLE from the Mac; USB connects when the cable is attached" }
                        val address = call.argument<String>("address") ?: error("Choose a paired host")
                        check(BluetoothAdapter.checkBluetoothAddress(address)) { "Invalid host address" }
                        val device = adapter?.bondedDevices?.firstOrNull { it.address == address } ?: error("Pair this host in Bluetooth settings first")
                        error = null
                        val accepted = hid?.connect(device) == true
                        if (!accepted) fail("Bluetooth did not accept the connection request")
                        result.success(accepted)
                    }
                    "disconnect" -> {
                        releaseAll()
                        result.success(disconnectHost())
                    }
                    "key" -> {
                        val id = call.argument<Int>("id") ?: error("Missing control")
                        val down = call.argument<Boolean>("pressed") ?: false
                        check(id in 0..16) { "Unknown control" }
                        if (down) {
                            check(connected() && registered && discovered && linkReady()) { "Waiting for Desktop Micro discovery" }
                            if (pressed.add(id)) {
                                if (id == 10) Log.i("CodexMicroHid", "Push-to-talk down")
                                enqueue(MicroWire.key(id, true))
                            }
                        } else if (pressed.remove(id)) {
                            // Releases remain valid if discovery/suspend state changed
                            // after keydown. A failed neutral report times out/disconnects.
                            if (id == 10) Log.i("CodexMicroHid", "Push-to-talk up")
                            if (connected() && registered) enqueue(MicroWire.key(id, false))
                        }
                        result.success(true)
                    }
                    "releaseAll" -> { releaseAll("dashboard lifecycle"); result.success(true) }
                    "settings" -> { startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS)); result.success(true) }
                    "loadBridgeSettings" -> result.success(loadBridgeSettings())
                    "saveBridgeSettings" -> {
                        saveBridgeSettings(call.argument<String>("url") ?: "", call.argument<String>("token") ?: "")
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (exception: Exception) {
                fail(exception.message ?: "Bluetooth operation failed")
                result.error("hid_error", error, null)
            }
        }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "codex_micro/hid_events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) { sink = events; emit() }
            override fun onCancel(arguments: Any?) { sink = null }
        })
        val filter = IntentFilter().apply {
            addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
            addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
        }
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
        else registerReceiver(receiver, filter)
        listening = true
        if (getSharedPreferences("hid", MODE_PRIVATE).getBoolean("usbRecoveryNeeded", false)) recoverUsb()
    }

    private fun startHid(askPermissions: Boolean) {
        if (transportMode == "usb") {
            if (!foreground) return
            if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                if (askPermissions) requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 430)
                else fail("Allow microphone access before starting USB HID + microphone")
                return
            }
            if (usb.active || registering) { emit(); return }
            check(getSharedPreferences("hid", MODE_PRIVATE).edit().putBoolean("usbRecoveryNeeded", true).commit())
            usbMicRequested = true; registering = true
            usb.start()
            return
        }
        if (adapter == null || Build.VERSION.SDK_INT < 28) { fail("Bluetooth HID Device requires Android 9 or newer and Bluetooth hardware"); return }
        if (!permitted()) {
            if (askPermissions && Build.VERSION.SDK_INT >= 31) requestPermissions(arrayOf(Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_ADVERTISE), 420)
            else fail("Bluetooth permissions are required")
            return
        }
        if (adapter?.isEnabled != true) {
            if (askPermissions) startActivityForResult(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE), 421)
            else fail("Turn on Bluetooth, then tap Start HID")
            return
        }
        if (registered || registering) { emit(); return }
        if (transportMode == "ble") {
            registering = true
            Log.i("CodexMicroHid", "Starting BLE HID 1812, USB VID303a PID8360, report6/63")
            ble.start()
            return
        }
        if (hid != null) registerHid()
        else if (!proxyPending) {
            proxyPending = adapter?.getProfileProxy(this, serviceListener, BluetoothProfile.HID_DEVICE) == true
            if (!proxyPending) fail("This Android firmware did not provide the HID Device profile")
        }
    }

    private val serviceListener = object : BluetoothProfile.ServiceListener {
        override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
            handler.post {
                proxyPending = false
                hid = proxy as BluetoothHidDevice
                if (requested && transportMode == "classic") registerHid()
                emit()
            }
        }
        override fun onServiceDisconnected(profile: Int) {
            handler.post { hid = null; proxyPending = false; if (transportMode == "classic") { registered = false; registering = false; resetLink(); emit() } }
        }
    }

    private fun registerHid() {
        if (transportMode != "classic" || !requested || !permitted() || registered || registering) return
        val settings = BluetoothHidDeviceAppSdpSettings(
            "Codex Micro Tablet", "Unofficial Codex Micro compatible tablet controls", "Min", 0.toByte(), MicroWire.DESCRIPTOR
        )
        registering = hid?.registerApp(settings, null, null, executor, callback) == true
        if (!registering) fail("HID registration request was rejected; another HID app may be active")
        handler.postDelayed({
            if (registering && !registered) { registering = false; fail("HID registration timed out; return to this app and tap Start HID") }
        }, 10000)
    }

    private val callback = object : BluetoothHidDevice.Callback() {
        override fun onAppStatusChanged(pluggedDevice: BluetoothDevice?, accepted: Boolean) {
            if (transportMode != "classic") return
            registering = false; registered = accepted
            if (!accepted) { resetLink(); error = "HID is inactive. Return to the dashboard and tap Start HID." }
            else { error = null; if (pluggedDevice != null && hid?.getConnectionState(pluggedDevice) == BluetoothProfile.STATE_CONNECTED) host = pluggedDevice }
            emit()
        }
        override fun onConnectionStateChanged(device: BluetoothDevice, state: Int) {
            if (transportMode != "classic") return
            if (state == BluetoothProfile.STATE_CONNECTED) { resetLink(); host = device; error = null }
            else if (state == BluetoothProfile.STATE_DISCONNECTED && host?.address == device.address) resetLink()
            emit()
        }
        override fun onInterruptData(device: BluetoothDevice, reportId: Byte, data: ByteArray) {
            if (transportMode == "classic" && reportId.toInt() == MicroWire.REPORT_ID && host?.address == device.address) receive(data)
        }
        override fun onSetReport(device: BluetoothDevice, type: Byte, id: Byte, data: ByteArray) {
            if (transportMode == "classic" && id.toInt() == MicroWire.REPORT_ID && host?.address == device.address &&
                (type == BluetoothHidDevice.REPORT_TYPE_OUTPUT || type == BluetoothHidDevice.REPORT_TYPE_FEATURE)) {
                receive(data)
                hid?.reportError(device, BluetoothHidDevice.ERROR_RSP_SUCCESS)
            } else hid?.reportError(device, BluetoothHidDevice.ERROR_RSP_INVALID_RPT_ID)
        }
        override fun onGetReport(device: BluetoothDevice, type: Byte, id: Byte, bufferSize: Int) {
            if (transportMode != "classic") return
            if (id.toInt() == MicroWire.REPORT_ID) {
                val body = ByteArray(MicroWire.BODY_SIZE).apply { this[0] = 2 }
                hid?.replyReport(device, type, id, if (bufferSize in 1 until body.size) body.copyOf(bufferSize) else body)
            } else hid?.reportError(device, BluetoothHidDevice.ERROR_RSP_INVALID_RPT_ID)
        }
        override fun onVirtualCableUnplug(device: BluetoothDevice) { if (transportMode == "classic") { resetLink(); emit() } }
    }

    private fun resetLink() {
        txGeneration++
        host = null; discovered = false; pressed.clear(); outgoing.clear(); sending = false; decoder.reset()
        slots.forEach { it["present"] = false; it["color"] = 0; it["brightness"] = 1.0; it["effect"] = "" }
    }

    private fun receive(data: ByteArray) {
        rxReports++
        val now = SystemClock.elapsedRealtime()
        if (now - lastRx > 2000) decoder.reset()
        lastRx = now
        if (!decoder.feed(data) { json -> process(json) }) error = "Malformed or oversized HID report discarded"
        emit()
    }

    private fun process(json: String) {
        try {
            val request = JSONObject(json)
            val method = request.optString("m").ifEmpty { request.optString("method") }
            if (method.isEmpty() || method.length >= 48) return
            val id = request.opt("id")
            val hasId = id != null && id != JSONObject.NULL
            if (hasId && id !is String && id !is Int && id !is Long) return
            val params = if (request.has("p")) request.opt("p") else request.opt("params")
            var ack = false
            val response = JSONObject()
            when (method) {
                "device.status", "sys.version" -> {
                    val value = JSONObject().put("version", "0.1.0-tablet-hid")
                    if (method == "device.status") {
                        val battery = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
                        val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
                        val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
                        value.put("profile_index", 0).put("layer_index", 1)
                            .put("battery", if (level >= 0 && scale > 0) level * 100 / scale else JSONObject.NULL)
                            .put("is_charging", (battery?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0) != 0)
                    }
                    response.put("result", value)
                    discovered = true
                }
                "v.oai.thstatus" -> {
                    if (params !is JSONArray) return
                    for (i in 0 until params.length()) {
                        val item = params.optJSONObject(i) ?: continue
                        val index = item.optInt("id", -1)
                        if (index !in 0..5) continue
                        val slot = slots[index]
                        slot["present"] = true
                        if (item.has("c")) {
                            val color = item.optLong("c", -1)
                            if (color in 0..0xffffff) slot["color"] = color.toInt()
                        }
                        if (item.has("b")) {
                            val brightness = item.optDouble("b", 1.0)
                            slot["brightness"] = if (brightness.isFinite()) brightness.coerceIn(0.0, 1.0) else 1.0
                        }
                        if (item.has("e")) slot["effect"] = item.optString("e").take(32)
                    }
                    response.put("result", JSONObject().put("ok", 1)); ack = true; discovered = true
                }
                "v.oai.rgbcfg", "lights.preview", "host.focused_app" -> {
                    response.put("result", JSONObject().put("ok", 1)); ack = true
                }
                else -> response.put("error", JSONObject().put("code", -32601).put("message", "Method not found"))
            }
            if (hasId || ack) enqueue(response.put("id", if (hasId) id else JSONObject.NULL).put("method", method).toString())
            error = null
            emit()
        } catch (_: Exception) { fail("Invalid HID JSON message discarded") }
    }

    private fun enqueue(json: String) {
        if (outgoing.size > 128) {
            fail("HID output queue overflow; reconnect the host")
            releaseAll()
            disconnectHost()
            return
        }
        MicroWire.frame(json).forEach { outgoing.addLast(Outgoing(it)) }
        if (!sending) { sending = true; drain(txGeneration) }
    }

    private fun drain(generation: Long) {
        if (generation != txGeneration) return
        if (!connected() || !registered || outgoing.isEmpty()) { sending = false; return }
        val next = outgoing.peekFirst()
        if (sendReport(next.body)) {
            outgoing.removeFirst(); txReports++
            handler.postDelayed({ drain(generation) }, 8)
        } else if (SystemClock.elapsedRealtime() - next.queuedAt < 2000) handler.postDelayed({ drain(generation) }, 40)
        else {
            fail(if (transportMode == "ble" && ble.mtu < MicroWire.BODY_SIZE + 3)
                "BLE MTU ${ble.mtu} is too small; the Mac must negotiate at least 66 bytes"
                else "HID send timed out; reconnect the host")
            releaseAll(); disconnectHost()
        }
        emit()
    }

    /** Complete pending messages, then synchronously release held controls before pause. */
    private fun releaseAll(reason: String = "connection change") {
        if (transportMode == "usb") {
            if (usb.active && usb.connected) {
                for (id in pressed.toList()) MicroWire.frame(MicroWire.key(id, false)).forEach { outgoing.addLast(Outgoing(it)) }
                pressed.clear()
                if (!sending && outgoing.isNotEmpty()) { sending = true; drain(txGeneration) }
            } else { outgoing.clear(); pressed.clear() }
            emit(); return
        }
        if (pressed.contains(10)) Log.i("CodexMicroHid", "Push-to-talk released: $reason")
        if (transportMode == "ble") {
            // Notifications are asynchronous. Preserve any fragmented message, enqueue
            // neutral reports, and disconnect if completion cannot be confirmed.
            val generation = txGeneration
            val address = host?.address
            if (host != null && registered) {
                for (id in pressed.toList()) MicroWire.frame(MicroWire.key(id, false)).forEach { outgoing.addLast(Outgoing(it)) }
                pressed.clear()
                if (!sending && outgoing.isNotEmpty()) { sending = true; drain(generation) }
                handler.postDelayed({
                    if (generation == txGeneration && host?.address == address && (outgoing.isNotEmpty() || ble.busy)) {
                        disconnectHost(); fail("BLE releases did not complete; disconnected to clear held controls")
                    }
                }, 1000)
            } else { outgoing.clear(); pressed.clear() }
            emit(); return
        }
        txGeneration++
        sending = false
        val device = host
        // Complete any partially transmitted JSON before adding a release. Dropping
        // the tail of a fragmented ACK would corrupt the host's next message.
        if (device != null && registered) {
            while (outgoing.isNotEmpty()) {
                if (hid?.sendReport(device, MicroWire.REPORT_ID, outgoing.removeFirst().body) == true) txReports++
                else {
                    outgoing.clear(); pressed.clear(); hid?.disconnect(device)
                    error = "Pending HID output failed; disconnected to clear held controls"
                    emit(); return
                }
            }
        } else outgoing.clear()
        if (device != null && registered) for (id in pressed.toList()) {
            for (body in MicroWire.frame(MicroWire.key(id, false))) {
                if (hid?.sendReport(device, MicroWire.REPORT_ID, body) == true) txReports++
                else {
                    pressed.clear(); hid?.disconnect(device)
                    error = "Release could not be sent; disconnected to clear held controls"
                    emit(); return
                }
            }
        }
        pressed.clear()
        emit()
    }

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == BluetoothAdapter.ACTION_STATE_CHANGED) {
                val state = intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)
                if (state == BluetoothAdapter.STATE_OFF) { if (transportMode == "ble") ble.stop(); registered = false; registering = false; resetLink() }
                if (state == BluetoothAdapter.STATE_ON && requested) startHid(false)
            }
            emit()
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 430) {
            if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
                requested = true; startHid(false)
            } else { requested = false; fail("Microphone permission declined. USB mode was not enabled.") }
        }
        if (requestCode == 431) {
            if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED && usb.active) microphone.start()
            else fail("Microphone access was not granted or USB mode stopped")
        }
        if (requestCode == 420) {
            if (permitted()) startHid(true) else fail("Bluetooth permission was declined; enable it in Android app settings")
        }
    }

    @Deprecated("Android activity compatibility callback")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 421) startHid(false)
    }

    override fun onPause() {
        foreground = false
        releaseAll("activity paused")
        microphone.stop()

        // Android pairing/permission dialogs pause this activity. A surviving BLE
        // link remains discovered; held controls are still released above.
        if (transportMode == "classic") {
            discovered = false
            decoder.reset()
            slots.forEach { it["present"] = false }
        }
        emit()
        super.onPause()
    }
    override fun onStop() {
        requested = false; usbMicRequested = false
        releaseAll("dashboard no longer visible")
        microphone.stop(); usb.stop()
        ble.stop()
        if (permitted()) hid?.unregisterApp()
        registered = false; registering = false; resetLink(); emit()
        super.onStop()
    }
    override fun onResume() { super.onResume(); foreground = true; if (requested) startHid(false); emit() }
    override fun onDestroy() {
        requested = false
        releaseAll("activity destroyed")
        microphone.stop(); usb.stop()
        if (permitted()) { ble.stop(); hid?.unregisterApp(); hid?.let { adapter?.closeProfileProxy(BluetoothProfile.HID_DEVICE, it) } }
        if (listening) unregisterReceiver(receiver)
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    private fun bridgeKey(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey("codex_micro_bridge", null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder("codex_micro_bridge", KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }

    private fun saveBridgeSettings(url: String, token: String) {
        require(url.length <= 2048 && token.length <= 4096) { "Bridge settings are too long" }
        val prefs = getSharedPreferences("bridge", MODE_PRIVATE)
        if (url.isEmpty()) { prefs.edit().clear().apply(); return }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, bridgeKey()) }
        val ciphertext = cipher.doFinal(token.toByteArray(Charsets.UTF_8))
        check(prefs.edit().putString("url", url).putString("token", Base64.encodeToString(ciphertext, Base64.NO_WRAP))
            .putString("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP)).commit()) { "Unable to save bridge settings" }
    }

    private fun loadBridgeSettings(): Map<String, String> {
        val prefs = getSharedPreferences("bridge", MODE_PRIVATE)
        val url = prefs.getString("url", "") ?: ""
        if (url.isEmpty()) return mapOf("url" to "", "token" to "")
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(Cipher.DECRYPT_MODE, bridgeKey(), GCMParameterSpec(128, Base64.decode(prefs.getString("iv", ""), Base64.NO_WRAP)))
        }
        val token = String(cipher.doFinal(Base64.decode(prefs.getString("token", ""), Base64.NO_WRAP)), Charsets.UTF_8)
        return mapOf("url" to url, "token" to token)
    }
}
