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

/** Foreground-only classic Bluetooth HID companion. Android controls PnP identity. */
@SuppressLint("MissingPermission")
class MainActivity : FlutterActivity() {
    private val handler = Handler(Looper.getMainLooper())
    private val executor = Executor { handler.post(it) }
    private val adapter: BluetoothAdapter? get() = getSystemService(BluetoothManager::class.java)?.adapter
    private var hid: BluetoothHidDevice? = null
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
        "supported" to (Build.VERSION.SDK_INT >= 28 && adapter != null),
        "bluetoothEnabled" to (permitted() && adapter?.isEnabled == true),
        "registered" to registered, "connected" to (host != null),
        "hostName" to (if (permitted()) host?.name else null),
        "hostAddress" to host?.address,
        "discovered" to discovered, "error" to error,
        "slots" to slots.map { it.toMap() }, "rxReports" to rxReports, "txReports" to txReports,
        "transport" to "Bluetooth Classic HID",
        "identityNote" to "Android controls the Bluetooth PnP identity. Desktop automatic Micro discovery is unverified; pairing alone does not confirm compatibility."
    )

    private fun emit() { handler.post { sink?.success(snapshot()) } }
    private fun fail(message: String) { error = message; emit() }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "codex_micro/hid").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "status" -> result.success(snapshot())
                    "start" -> { requested = true; error = null; startHid(true); result.success(snapshot()) }
                    "discoverable" -> {
                        check(permitted()) { "Enable Bluetooth access first" }
                        check(adapter?.isEnabled == true) { "Turn on Bluetooth first" }
                        startActivity(Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE).putExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION, 120))
                        result.success(true)
                    }
                    "devices" -> {
                        check(permitted()) { "Enable Bluetooth access first" }
                        result.success(adapter?.bondedDevices?.map { mapOf("name" to (it.name ?: "Bluetooth host"), "address" to it.address) } ?: emptyList<Any>())
                    }
                    "connect" -> {
                        check(permitted() && registered) { "Start Bluetooth HID before connecting" }
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
                        val device = host
                        result.success(device != null && hid?.disconnect(device) == true)
                    }
                    "key" -> {
                        val id = call.argument<Int>("id") ?: error("Missing control")
                        val down = call.argument<Boolean>("pressed") ?: false
                        check(id in 0..16) { "Unknown control" }
                        check(host != null && registered && discovered) { "Waiting for Desktop Micro discovery" }
                        if ((down && pressed.add(id)) || (!down && pressed.remove(id))) enqueue(MicroWire.key(id, down))
                        result.success(true)
                    }
                    "releaseAll" -> { releaseAll(); result.success(true) }
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
    }

    private fun startHid(askPermissions: Boolean) {
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
                if (requested) registerHid()
                emit()
            }
        }
        override fun onServiceDisconnected(profile: Int) {
            handler.post { hid = null; registered = false; registering = false; resetLink(); emit() }
        }
    }

    private fun registerHid() {
        if (!requested || !permitted() || registered || registering) return
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
            registering = false; registered = accepted
            if (!accepted) { resetLink(); error = "HID is inactive. Return to the dashboard and tap Start HID." }
            else { error = null; if (pluggedDevice != null && hid?.getConnectionState(pluggedDevice) == BluetoothProfile.STATE_CONNECTED) host = pluggedDevice }
            emit()
        }
        override fun onConnectionStateChanged(device: BluetoothDevice, state: Int) {
            if (state == BluetoothProfile.STATE_CONNECTED) { resetLink(); host = device; error = null }
            else if (state == BluetoothProfile.STATE_DISCONNECTED && host?.address == device.address) resetLink()
            emit()
        }
        override fun onInterruptData(device: BluetoothDevice, reportId: Byte, data: ByteArray) {
            if (reportId.toInt() == MicroWire.REPORT_ID && host?.address == device.address) receive(data)
        }
        override fun onSetReport(device: BluetoothDevice, type: Byte, id: Byte, data: ByteArray) {
            if (id.toInt() == MicroWire.REPORT_ID && host?.address == device.address &&
                (type == BluetoothHidDevice.REPORT_TYPE_OUTPUT || type == BluetoothHidDevice.REPORT_TYPE_FEATURE)) {
                receive(data)
                hid?.reportError(device, BluetoothHidDevice.ERROR_RSP_SUCCESS)
            } else hid?.reportError(device, BluetoothHidDevice.ERROR_RSP_INVALID_RPT_ID)
        }
        override fun onGetReport(device: BluetoothDevice, type: Byte, id: Byte, bufferSize: Int) {
            if (id.toInt() == MicroWire.REPORT_ID) {
                val body = ByteArray(MicroWire.BODY_SIZE).apply { this[0] = 2 }
                hid?.replyReport(device, type, id, if (bufferSize in 1 until body.size) body.copyOf(bufferSize) else body)
            } else hid?.reportError(device, BluetoothHidDevice.ERROR_RSP_INVALID_RPT_ID)
        }
        override fun onVirtualCableUnplug(device: BluetoothDevice) { resetLink(); emit() }
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
            host?.let { hid?.disconnect(it) }
            return
        }
        MicroWire.frame(json).forEach { outgoing.addLast(Outgoing(it)) }
        if (!sending) { sending = true; drain(txGeneration) }
    }

    private fun drain(generation: Long) {
        if (generation != txGeneration) return
        val device = host
        if (device == null || !registered || outgoing.isEmpty()) { sending = false; return }
        val next = outgoing.peekFirst()
        if (hid?.sendReport(device, MicroWire.REPORT_ID, next.body) == true) {
            outgoing.removeFirst(); txReports++
            handler.postDelayed({ drain(generation) }, 8)
        } else if (SystemClock.elapsedRealtime() - next.queuedAt < 2000) handler.postDelayed({ drain(generation) }, 40)
        else {
            fail("HID send timed out; reconnect the host")
            releaseAll(); hid?.disconnect(device)
        }
        emit()
    }

    /** Complete pending messages, then synchronously release held controls before pause. */
    private fun releaseAll() {
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
                if (state == BluetoothAdapter.STATE_OFF) { registered = false; registering = false; resetLink() }
                if (state == BluetoothAdapter.STATE_ON && requested) startHid(false)
            }
            emit()
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
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
        releaseAll()
        discovered = false
        decoder.reset()
        slots.forEach { it["present"] = false }
        emit()
        super.onPause()
    }
    override fun onResume() { super.onResume(); if (requested) startHid(false); emit() }
    override fun onDestroy() {
        requested = false
        releaseAll()
        if (permitted()) { hid?.unregisterApp(); hid?.let { adapter?.closeProfileProxy(BluetoothProfile.HID_DEVICE, it) } }
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
