package com.cmwen.codex_micro_tablet

import androidx.annotation.Keep
import android.os.Process
import android.system.Os
import android.system.OsConstants
import android.system.ErrnoException
import android.util.Base64
import org.json.JSONObject
import java.io.File
import java.io.FileDescriptor
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.channels.FileLock
import java.nio.file.Files
import java.nio.file.Paths
import java.nio.file.StandardCopyOption
import java.util.concurrent.atomic.AtomicBoolean

/** Root-only, pipe-owned gadget session. No service, watchdog, boot script or kernel change. */
@Keep
object UsbRootMain {
    private val gadget = File("/config/usb_gadget/g1")
    private val configuration = File(gadget, "configs/b.1")
    private val recovery = File("/data/local/tmp/codex-micro-usb")
    private val backup = File(recovery, "state.json")
    private const val OWNER = "com.cmwen.codex_micro_tablet.usb.v1"
    private val attributes = listOf(
        "idVendor", "idProduct", "bcdDevice", "bDeviceClass", "bDeviceSubClass", "bDeviceProtocol",
        "strings/0x409/manufacturer", "strings/0x409/product", "configs/b.1/strings/0x409/configuration",
        "functions/hid.gs0/protocol", "functions/hid.gs0/subclass", "functions/hid.gs0/report_length", "functions/hid.gs0/report_desc"
    )
    private val outputLock = Any()
    private fun event(kind: String, extra: JSONObject = JSONObject()) = synchronized(outputLock) {
        println(extra.put("event", kind).toString()); System.out.flush()
    }
    private fun text(relative: String) = File(gadget, relative).readText().trim()
    private fun write(relative: String, value: String) = writeBytes(relative, value.toByteArray())
    private fun writeBytes(relative: String, value: ByteArray) {
        try { FileOutputStream(File(gadget, relative)).use { it.write(value) } }
        catch (e: Exception) { throw java.io.IOException("USB attribute $relative: ${e.message}", e) }
    }

    @Keep @JvmStatic fun main(args: Array<String>) {
        if (Process.myUid() != 0) { event("error", JSONObject().put("message", "Root access is required for USB mode")); return }
        recovery.mkdirs()
        Os.chmod(recovery.path, 448) // 0700; contains only gadget configuration, never audio.
        var lock: FileLock? = null
        FileOutputStream(File(recovery, "session.lock"), true).use { lockFile ->
            try {
                lock = lockFile.channel.tryLock()
                check(lock != null) { "A USB session is already active; stop it before restoring" }
                when (args.firstOrNull()) {
                    "probe" -> event("probe", JSONObject().put("supported", supported()).put("recoveryPending", backup.exists()))
                    "recover" -> { restore(); event("restored") }
                    "run" -> runSession()
                    else -> error("Unknown USB helper operation")
                }
            } catch (e: Exception) {
                e.printStackTrace(System.err)
                event("error", JSONObject().put("message", "${e.javaClass.simpleName}: ${e.message ?: "USB operation failed"}"))
            } finally { runCatching { lock?.release() } }
        }
    }

    private fun supported() = gadget.isDirectory && configuration.isDirectory &&
        File(gadget, "functions/ffs.adb").isDirectory && File(gadget, "functions/hid.gs0/report_desc").exists() &&
        File(gadget, "functions/audio_source.gs3").isDirectory

    private fun property(name: String): String = java.lang.ProcessBuilder("/system/bin/getprop", name).start().inputStream.bufferedReader().readText().trim()
    private fun property(name: String, value: String) {
        val child = java.lang.ProcessBuilder("/system/bin/setprop", name, value).start()
        check(child.waitFor() == 0) { "Could not set temporary USB mode" }
    }
    private fun ownConfiguration() { property("sys.usb.config", "hid,audio_source,adb") }

    private fun snapshot() {
        check(supported()) { "This firmware does not provide the required HID, audio-source and ADB gadget functions" }
        val links = JSONObject()
        configuration.listFiles()?.forEach { item ->
            if (Files.isSymbolicLink(item.toPath())) {
                val target = Files.readSymbolicLink(item.toPath())
                val canonical = item.toPath().parent.resolve(target).normalize().toString()
                check(canonical.startsWith(File(gadget, "functions").path + "/")) { "Unexpected USB configuration; refusing to replace it" }
                check(item.name.matches(Regex("[A-Za-z0-9_.-]+"))) { "Invalid USB function link" }
                links.put(item.name, target.toString())
            }
        }
        check(links.keys().asSequence().any { links.getString(it).endsWith("/ffs.adb") }) { "USB mode requires ADB to be present in the original gadget" }
        val udc = text("UDC")
        check(udc.isNotEmpty() && udc != "none") { "The original USB gadget is not bound to a controller" }
        val values = JSONObject()
        attributes.forEach { values.put(it, Base64.encodeToString(File(gadget, it).readBytes(), Base64.NO_WRAP)) }
        val state = JSONObject().put("owner", OWNER).put("udc", udc).put("attributes", values).put("links", links).put("usbConfig", property("sys.usb.config")).put("usbState", property("sys.usb.state"))
        val temporary = File(recovery, "state.tmp")
        FileOutputStream(temporary).use { it.write(state.toString().toByteArray()); it.fd.sync() }
        Files.move(temporary.toPath(), backup.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
    }

    private fun unlinkFunctions() {
        configuration.listFiles()?.filter { Files.isSymbolicLink(it.toPath()) }?.forEach { Files.deleteIfExists(it.toPath()) }
    }
    private fun unbind() { if (text("UDC").isNotEmpty()) write("UDC", "\n") }
    private fun link(name: String, function: String) {
        val path = File(configuration, name).toPath()
        val target = File(gadget, "functions/$function").toPath()
        if (Files.isSymbolicLink(path) && path.parent.resolve(Files.readSymbolicLink(path)).normalize() == target) return
        Files.createSymbolicLink(path, target)
    }
    private fun bindStable(controller: String) {
        // adbd closes/reopens FunctionFS once after the old gadget disconnects.
        // That closure unregisters the whole composite gadget. Settle this
        // bounded startup transition before reporting ready; no background repair.
        val deadline = System.nanoTime() + 10_000_000_000L
        var stableSince = 0L
        while (System.nanoTime() < deadline) {
            if (text("UDC").isEmpty()) {
                stableSince = 0L
                if (property("sys.usb.ffs.ready") == "1") {
                    try { write("UDC", controller) } catch (_: java.io.IOException) { }
                }
            } else {
                if (stableSince == 0L) stableSince = System.nanoTime()
                if (System.nanoTime() - stableSince >= 1_500_000_000L) return
            }
            Thread.sleep(100)
        }
        error("USB ADB FunctionFS did not settle; original USB mode will be restored")
    }

    private fun activate() {
        // A leftover backup always wins: restore before taking another snapshot.
        if (backup.exists()) restore()
        snapshot()
        try {
            val state = JSONObject(backup.readText())
            ownConfiguration(); unbind(); unlinkFunctions()
            write("functions/hid.gs0/protocol", "0")
            write("functions/hid.gs0/subclass", "0")
            write("functions/hid.gs0/report_length", "64")
            writeBytes("functions/hid.gs0/report_desc", MicroWire.DESCRIPTOR)
            write("idVendor", "0x303a"); write("idProduct", "0x8360"); write("bcdDevice", "0x0100")
            write("bDeviceClass", "0"); write("bDeviceSubClass", "0"); write("bDeviceProtocol", "0")
            write("strings/0x409/manufacturer", "Min")
            write("strings/0x409/product", "Codex Micro Tablet")
            write("configs/b.1/strings/0x409/configuration", "Micro HID + microphone + ADB")
            // Retain ADB as interface zero without stopping adbd or changing persistent properties.
            link("f1", "ffs.adb"); link("f2", "hid.gs0"); link("f3", "audio_source.gs3")
            bindStable(state.getString("udc"))
            property("sys.usb.state", "hid,audio_source,adb")
        } catch (e: Exception) {
            try { restore() } catch (rollback: Exception) {
                throw IllegalStateException("USB setup failed; manual restore remains required: ${rollback.message}", e)
            }
            throw e
        }
    }

    private fun restore() {
        if (!backup.exists()) return
        val state = JSONObject(backup.readText())
        check(state.optString("owner") == OWNER) { "Unrecognized USB recovery file; refusing to apply it" }
        val saved = state.getJSONObject("attributes")
        check(saved.keys().asSequence().toSet() == attributes.toSet()) { "USB recovery attributes are incomplete" }
        val links = state.getJSONObject("links")
        links.keys().forEach { check(it.matches(Regex("[A-Za-z0-9_.-]+"))) { "Invalid USB recovery link" } }
        val controller = state.getString("udc")
        check(controller.matches(Regex("[A-Za-z0-9_.-]+"))) { "Invalid USB recovery controller" }
        ownConfiguration(); unbind(); unlinkFunctions()
        if (Base64.decode(saved.getString("functions/hid.gs0/report_desc"), Base64.DEFAULT).isEmpty()) {
            // A zero-length configfs write cannot reliably clear a descriptor.
            // Recreate an originally empty, unlinked HID instance instead.
            val function = File(gadget, "functions/hid.gs0")
            check(function.delete() && function.mkdir()) { "Could not reset the original empty HID function" }
        }
        attributes.forEach { writeBytes(it, Base64.decode(saved.getString(it), Base64.DEFAULT)) }
        links.keys().forEach { name ->
            val target = Paths.get(links.getString(name))
            check(configuration.toPath().resolve(target).normalize().startsWith(File(gadget, "functions").toPath())) { "Invalid USB recovery target" }
            val path = File(configuration, name).toPath()
            if (!Files.isSymbolicLink(path) || path.parent.resolve(Files.readSymbolicLink(path)).normalize() != configuration.toPath().resolve(target).normalize()) Files.createSymbolicLink(path, configuration.toPath().resolve(target).normalize())
        }
        write("UDC", controller)
        property("sys.usb.state", state.optString("usbState", "adb"))
        property("sys.usb.config", state.optString("usbConfig", "adb"))
        check(backup.delete()) { "USB restored but its recovery marker could not be removed" }
    }

    private fun runSession() {
        var input: FileInputStream? = null
        var writeFd: FileDescriptor? = null
        val running = AtomicBoolean(true)
        try {
            activate()
            val number = text("functions/hid.gs0/dev")
            check(number.matches(Regex("[0-9]+:[0-9]+"))) { "HID device number is unavailable" }
            val nodeName = File("/sys/dev/char/$number").canonicalFile.name
            check(nodeName.matches(Regex("hidg[0-9]+"))) { "Unexpected HID device node" }
            val node = File("/dev/$nodeName")
            val deviceDeadline = System.nanoTime() + 2_000_000_000L
            while (!node.exists() && System.nanoTime() < deviceDeadline) Thread.sleep(20)
            check(node.exists()) { "The HID character device was not created" }
            input = FileInputStream(node)
            writeFd = Os.open(node.path, OsConstants.O_WRONLY or OsConstants.O_NONBLOCK, 0)
            val controller = JSONObject(backup.readText()).getString("udc")
            var previousConnection: Boolean? = null
            fun publishConnection(configured: Boolean) = synchronized(outputLock) {
                if (configured != previousConnection) {
                    event("connection", JSONObject().put("connected", configured))
                    previousConnection = configured
                }
            }
            fun isConfigured() = runCatching {
                File("/sys/class/udc/$controller/state").readText().trim() == "configured"
            }.getOrDefault(false)
            // Register before any connection/report event reaches the app.
            event("ready")
            publishConnection(isConfigured())
            Thread({
                val buffer = ByteArray(64)
                while (running.get()) {
                    try {
                        if (input == null) input = FileInputStream(node)
                        val size = input!!.read(buffer)
                        if (size <= 0) throw java.io.IOException("USB HID reader closed")
                        val body = MicroWire.bleBody(buffer.copyOf(size)) ?: continue
                        synchronized(outputLock) {
                            // A first OUT report can arrive before the status poll.
                            if (isConfigured()) publishConnection(true)
                            event("report", JSONObject().put("data", Base64.encodeToString(body, Base64.NO_WRAP)))
                        }
                    } catch (_: Exception) {
                        runCatching { input?.close() }; input = null
                        if (running.get()) Thread.sleep(100)
                    }
                }
            }, "micro-usb-reports").apply { isDaemon = true; start() }
            Thread({
                while (running.get()) {
                    publishConnection(isConfigured())
                    Thread.sleep(250)
                }
            }, "micro-usb-connection").apply { isDaemon = true; start() }
            val lines = System.`in`.bufferedReader()
            while (running.get()) {
                val line = lines.readLine() ?: break
                check(line.length <= 2048) { "USB command too large" }
                val command = JSONObject(line)
                if (command.optString("command") == "stop") break
                val body = Base64.decode(command.getString("body"), Base64.DEFAULT)
                check(body.size == MicroWire.BODY_SIZE) { "Invalid HID report length" }
                val report = byteArrayOf(MicroWire.REPORT_ID.toByte()) + body
                val deadline = System.nanoTime() + 500_000_000L
                while (true) {
                    try {
                        check(Os.write(writeFd, report, 0, report.size) == report.size) { "Short USB HID write" }
                        break
                    } catch (e: ErrnoException) {
                        if (e.errno != OsConstants.EAGAIN || System.nanoTime() >= deadline) throw e
                        Thread.sleep(5)
                    }
                }
            }
        } finally {
            running.set(false)
            runCatching { writeFd?.let { Os.close(it) } }
            runCatching { input?.close() }
            restore()
            event("closed")
        }
    }
}
