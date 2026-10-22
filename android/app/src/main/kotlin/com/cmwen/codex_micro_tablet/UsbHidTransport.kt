package com.cmwen.codex_micro_tablet

import android.content.Context
import android.os.Handler
import android.util.Base64
import org.json.JSONObject
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Owns one root helper over private process pipes; no exported command endpoint. */
class UsbHidTransport(
    private val context: Context,
    private val handler: Handler,
    private val listener: Listener
) {
    interface Listener {
        fun onRegistered(registered: Boolean)
        fun onConnection(connected: Boolean)
        fun onReport(data: ByteArray)
        fun onError(message: String)
        fun onChanged()
    }
    companion object {
        private fun quote(value: String) = "'" + value.replace("'", "'\"'\"'") + "'"
        fun rootCommand(context: Context, args: List<String>): Process =
            rootClassCommand(context, "com.cmwen.codex_micro_tablet.UsbRootMain", args)
        fun rootClassCommand(context: Context, className: String, args: List<String>): Process {
            require(className.matches(Regex("com\\.cmwen\\.codex_micro_tablet\\.[A-Za-z0-9_]+")))
            val command = "CLASSPATH=${quote(context.applicationInfo.sourceDir)} /system/bin/app_process /system/bin " +
                className + args.joinToString(separator = "", transform = { " " + quote(it) })
            return ProcessBuilder("su", "-c", command).start()
        }
    }
    private val operations = Executors.newSingleThreadExecutor { task -> Thread(task, "micro-usb-operations").apply { isDaemon = true } }
    @Volatile private var generation = 0L
    @Volatile private var process: Process? = null
    @Volatile private var writer: Thread? = null
    private var queue: ArrayBlockingQueue<String>? = null
    var active = false; private set
    var connected = false; private set
    var status = "USB inactive"; private set

    private fun ui(token: Long, block: () -> Unit) { handler.post { if (generation == token) block() } }
    private fun inactive() { active = false; connected = false; listener.onRegistered(false); listener.onConnection(false); listener.onChanged() }
    private fun failed(message: String) { status = message; inactive(); listener.onError(message) }
    private fun rememberRecovery(needed: Boolean) {
        context.getSharedPreferences("hid", Context.MODE_PRIVATE).edit().putBoolean("usbRecoveryNeeded", needed).commit()
    }

    fun start() {
        if (active) {
            // A cable detach can close ADB FunctionFS and unbind the composite.
            // An explicit Start restarts it; no background watchdog is needed.
            if (!connected) recover { restored -> if (restored) start() }
            return
        }
        val token = ++generation
        status = "Starting rooted USB mode"; listener.onChanged()
        // Written before spawning root or changing the gadget, so process death
        // cannot erase the app's knowledge that recovery may be needed.
        rememberRecovery(true)
        operations.execute {
            try {
                stopProcess()
                if (token != generation) return@execute
                val child = rootCommand(context, listOf("run", java.io.File(context.applicationInfo.nativeLibraryDir, "libmicro_usb_audio.so").path))
                process = child
                val outgoing = ArrayBlockingQueue<String>(128)
                queue = outgoing
                drainErrors(child)
                writer = Thread({
                    try {
                        val pipe = child.outputStream.bufferedWriter()
                        while (generation == token) {
                            val line = outgoing.take()
                            pipe.write(line); pipe.newLine(); pipe.flush()
                        }
                    } catch (_: InterruptedException) { }
                    catch (e: Exception) { ui(token) { failed("USB report pipe failed: ${e.message}") } }
                }, "micro-usb-writer").apply { isDaemon = true; start() }
                Thread({ readSession(child, token) }, "micro-usb-reader").apply { isDaemon = true; start() }
            } catch (e: Exception) { ui(token) { failed("Cannot start rooted USB mode: ${e.message}") } }
        }
    }

    private fun readSession(child: Process, token: Long) {
        var clean = false
        var explicitError = false
        try {
            child.inputStream.bufferedReader().useLines { lines -> lines.forEach { line ->
                if (line.length > 8192) error("Oversized USB helper response")
                val event = JSONObject(line)
                when (event.optString("event")) {
                    "ready" -> ui(token) { active = true; status = "USB HID + ADB enabled"; listener.onRegistered(true); listener.onChanged() }
                    "connection" -> ui(token) { connected = event.optBoolean("connected"); listener.onConnection(connected); listener.onChanged() }
                    "report" -> {
                        val data = Base64.decode(event.getString("data"), Base64.DEFAULT)
                        if (data.size in 2..MicroWire.BODY_SIZE) ui(token) { listener.onReport(data) }
                    }
                    "error" -> { explicitError = true; ui(token) { failed(event.optString("message", "Root USB operation failed")) } }
                    "closed" -> { clean = true; ui(token) { rememberRecovery(false); status = "Original USB mode restored"; inactive() } }
                }
            } }
            if (!clean && !explicitError) ui(token) { failed("USB helper stopped; use Release controls / restore USB") }
        } catch (e: Exception) { ui(token) { failed("USB helper connection ended: ${e.message}. Restore USB manually.") } }
    }

    fun send(body: ByteArray): Boolean {
        if (!active || !connected || body.size != MicroWire.BODY_SIZE) return false
        return queue?.offer(JSONObject().put("body", Base64.encodeToString(body, Base64.NO_WRAP)).toString()) == true
    }

    fun stop() {
        if (!active && process == null &&
            !context.getSharedPreferences("hid", Context.MODE_PRIVATE).getBoolean("usbRecoveryNeeded", false)) return
        recover()
    }
    fun recoverIfNeeded(onDone: (Boolean) -> Unit = {}) {
        if (!context.getSharedPreferences("hid", Context.MODE_PRIVATE).getBoolean("usbRecoveryNeeded", false)) { onDone(true); return }
        recover(onDone)
    }
    fun recover(onDone: (Boolean) -> Unit = {}) {
        val token = ++generation
        status = "Restoring original USB mode"; inactive()
        operations.execute {
            val success = try {
                stopProcess()
                val child = rootCommand(context, listOf("recover"))
                child.outputStream.close(); drainErrors(child)
                check(child.waitFor(12, TimeUnit.SECONDS)) { child.destroyForcibly(); "USB recovery timed out" }
                val events = child.inputStream.bufferedReader().readLines().mapNotNull { runCatching { JSONObject(it) }.getOrNull() }
                val error = events.firstOrNull { it.optString("event") == "error" }
                check(error == null && child.exitValue() == 0 && events.any { it.optString("event") == "restored" }) {
                    error?.optString("message") ?: "Root did not confirm USB recovery"
                }
                rememberRecovery(false)
                true
            } catch (e: Exception) {
                ui(token) { failed("USB restore failed: ${e.message}") }
                false
            }
            ui(token) {
                if (success) { status = "Original USB mode restored"; inactive() }
                onDone(success)
            }
        }
    }
    private fun stopProcess() {
        writer?.interrupt(); writer = null; queue = null
        val child = process ?: return
        process = null
        // EOF is the normal session boundary. A separate recover invocation
        // handles hard-killed helpers which cannot run their finally block.
        runCatching { child.outputStream.close() }
        if (!child.waitFor(3, TimeUnit.SECONDS)) {
            child.destroy()
            if (!child.waitFor(1, TimeUnit.SECONDS)) child.destroyForcibly()
        }
    }
    private fun drainErrors(child: Process) {
        Thread({ runCatching { child.errorStream.bufferedReader().useLines { lines -> lines.forEach { /* never echo root command lines */ } } } },
            "micro-usb-root-stderr").apply { isDaemon = true; start() }
    }
}
