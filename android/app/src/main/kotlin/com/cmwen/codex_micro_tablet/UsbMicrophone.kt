package com.cmwen.codex_micro_tablet

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import java.io.File
import java.util.UUID

/** Foreground capture -> a finite root PCM writer. No recordings or monitor service. */
class UsbMicrophone(
    private val context: Context,
    private val handler: Handler,
    private val listener: Listener
) {
    interface Listener {
        fun onChanged()
        fun onError(message: String)
    }

    private class Session(val niceName: String) {
        @Volatile var closed = false
        @Volatile var process: Process? = null
        @Volatile var rootPid = 0
        @Volatile var ready = false
        @Volatile var failure: String? = null
        @Volatile var record: AudioRecord? = null
    }
    @Volatile private var session: Session? = null
    @Volatile var active = false; private set
    @Volatile var status = "Microphone off"; private set
    @Volatile var frames = 0L; private set
    @Volatile var error: String? = null; private set

    private fun changed() { handler.post { listener.onChanged() } }
    private fun update(current: Session, block: () -> Unit) {
        handler.post { if (session === current && !current.closed) { block(); listener.onChanged() } }
    }

    fun start() {
        if (session != null) return
        if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            error = "Allow microphone access before starting USB microphone"
            status = "Microphone permission required"
            listener.onError(error!!); changed(); return
        }
        val current = Session("cmicpcm_" + UUID.randomUUID().toString().replace("-", "").take(6))
        session = current
        active = false; frames = 0; error = null; status = "Starting USB microphone"
        changed()
        Thread({ capture(current) }, "micro-usb-capture").apply { isDaemon = true; start() }
    }

    /** Stop capture promptly; ALSA/pipe teardown runs off the UI thread. */
    fun stop() {
        val current = session
        session = null
        current?.closed = true
        active = false
        status = "Microphone off"
        changed()
        if (current != null) Thread({ cleanup(current) }, "micro-usb-audio-stop").apply { isDaemon = true; start() }
    }

    private fun quote(value: String) = "'" + value.replace("'", "'\\''") + "'"

    @SuppressLint("MissingPermission")
    private fun capture(current: Session) {
        try {
            val directory = context.applicationInfo.nativeLibraryDir
            val library = File(directory, "libmicro_usb_audio.so")
            check(library.isFile) { "USB audio native library is missing; reinstall this build" }
            val is64 = directory.contains("arm64") || directory.contains("x86_64") || directory.contains("riscv64")
            val interpreter = File(if (is64) "/system/bin/app_process64" else "/system/bin/app_process32")
                .takeIf { it.exists() }?.path ?: "/system/bin/app_process"
            val command = "CLASSPATH=${quote(context.applicationInfo.sourceDir)} ${quote(interpreter)} /system/bin " +
                "--nice-name=${quote(current.niceName)} com.cmwen.codex_micro_tablet.UsbPcmWriter ${quote(library.path)}"
            if (current.closed) return
            val process = ProcessBuilder("su", "-c", command).start()
            current.process = process
            // Status contains only state, PID and frame counts, never audio bytes.
            Thread({
                try {
                    process.inputStream.bufferedReader().useLines { lines ->
                        lines.forEach { line ->
                            when {
                                line.startsWith("PID:") -> {
                                    current.rootPid = line.removePrefix("PID:").toIntOrNull() ?: 0
                                    if (current.closed) terminateRoot(current)
                                }
                                line == "READY" -> current.ready = true
                                line.startsWith("FRAMES:") -> {
                                    val count = line.removePrefix("FRAMES:").toLongOrNull()
                                    if (count != null) update(current) { frames = count }
                                }
                                line.startsWith("ERROR:") -> current.failure = line.removePrefix("ERROR:").take(300)
                            }
                        }
                    }
                    if (!current.closed && current.failure == null) current.failure = "USB audio writer stopped; reconnect USB mode"
                } catch (_: Exception) {
                    if (!current.closed && current.failure == null) current.failure = "USB audio writer connection closed"
                }
            }, "micro-usb-audio-status").apply { isDaemon = true; start() }
            Thread({
                try {
                    process.errorStream.bufferedReader().useLines { lines ->
                        lines.forEach { line ->
                            if (!current.closed && current.failure == null && line.contains("denied", ignoreCase = true))
                                current.failure = "USB audio root permission was denied"
                        }
                    }
                } catch (_: Exception) { }
            }, "micro-usb-audio-errors").apply { isDaemon = true; start() }
            val until = System.nanoTime() + 10_000_000_000L
            while (!current.ready && !current.closed && current.failure == null && System.nanoTime() < until) {
                if (!process.isAlive) break
                Thread.sleep(20)
            }
            if (current.closed) return
            current.failure?.let { error(it) }
            check(current.ready) { "USB audio writer is not ready; check root permission and USB audio mode" }
            val minimum = AudioRecord.getMinBufferSize(44100, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
            check(minimum > 0) { "Built-in microphone does not support 44100 Hz PCM" }
            val record = AudioRecord.Builder()
                .setAudioSource(MediaRecorder.AudioSource.VOICE_RECOGNITION)
                .setAudioFormat(AudioFormat.Builder().setSampleRate(44100)
                    .setChannelMask(AudioFormat.CHANNEL_IN_MONO).setEncoding(AudioFormat.ENCODING_PCM_16BIT).build())
                .setBufferSizeInBytes(maxOf(minimum * 2, 8820))
                .build()
            current.record = record
            if (current.closed) return
            check(record.state == AudioRecord.STATE_INITIALIZED) { "Could not initialize the tablet microphone" }
            val manager = context.getSystemService(AudioManager::class.java)
            val builtIn = manager.getDevices(AudioManager.GET_DEVICES_INPUTS)
                .firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_MIC }
                ?: error("Built-in tablet microphone is unavailable")
            check(record.setPreferredDevice(builtIn)) { "Could not select the built-in tablet microphone" }
            record.startRecording()
            check(record.recordingState == AudioRecord.RECORDSTATE_RECORDING) { "Tablet microphone did not start" }
            update(current) { active = true; status = "USB microphone streaming · 44.1 kHz" }
            val mono = ShortArray(882) // 20 ms, bounded latency and memory.
            val stereo = ByteArray(mono.size * 4)
            while (!current.closed && current.failure == null) {
                val count = record.read(mono, 0, mono.size, AudioRecord.READ_BLOCKING)
                if (current.closed) break
                check(count > 0) { "Tablet microphone read failed ($count)" }
                monoToStereo(mono, count, stereo)
                process.outputStream.write(stereo, 0, count * 4)
            }
            if (!current.closed) current.failure?.let { error(it) }
        } catch (failure: Exception) {
            if (!current.closed) {
                // The PCM status pipe can trail a broken audio pipe briefly.
                // Prefer the native ALSA explanation over a generic EPIPE.
                if (current.failure == null && failure is java.io.IOException) {
                    repeat(5) { if (current.failure == null && !current.closed) Thread.sleep(20) }
                }
                val message = (current.failure ?: failure.message)?.replace('\n', ' ')?.take(300)
                    ?: "USB microphone stopped unexpectedly"
                handler.post {
                    if (session === current) {
                        session = null
                        error = message; active = false; status = "Microphone unavailable"
                        listener.onError(message); listener.onChanged()
                    }
                }
            }
        } finally {
            cleanup(current)
        }
    }

    private fun cleanup(current: Session) {
        current.closed = true
        val record = synchronized(current) { current.record.also { current.record = null } }
        runCatching { record?.stop() }
        runCatching { record?.release() }
        runCatching { current.process?.outputStream?.close() }
        terminateRoot(current)
        runCatching { current.process?.destroy() }
    }

    private fun terminateRoot(current: Session) {
        val pid = current.rootPid
        if (pid <= 0) return
        // PID + per-session process name guards against terminating a reused PID.
        val command = "if [ \"\$(cat /proc/$pid/comm 2>/dev/null)\" = ${quote(current.niceName)} ]; then kill -TERM $pid; fi"
        runCatching {
            val kill = ProcessBuilder("su", "-c", command).start()
            if (!kill.waitFor(2, java.util.concurrent.TimeUnit.SECONDS)) kill.destroy()
        }
    }

    companion object {
        /** Duplicate mono samples to little-endian L/R without mixing device audio. */
        fun monoToStereo(mono: ShortArray, count: Int, destination: ByteArray) {
            require(count in 0..mono.size && destination.size >= count * 4)
            for (index in 0 until count) {
                val value = mono[index].toInt()
                val low = value.toByte()
                val high = (value shr 8).toByte()
                val offset = index * 4
                destination[offset] = low; destination[offset + 1] = high
                destination[offset + 2] = low; destination[offset + 3] = high
            }
        }
    }
}
