package com.cmwen.codex_micro_tablet

import android.os.Process
import androidx.annotation.Keep
import java.io.File
import kotlin.system.exitProcess

/** Finite root child: stdin is stereo S16_LE/44100 PCM; no audio is stored. */
@Keep
object UsbPcmWriter {
    private external fun streamPcm(card: Int, device: Int): Int

    @JvmStatic
    fun main(args: Array<String>) {
        try {
            check(Process.myUid() == 0) { "USB audio writer requires root" }
            require(args.size == 1) { "USB audio writer expects its native library path" }
            val library = File(args[0]).canonicalFile
            require(library.name == "libmicro_usb_audio.so" && library.isFile) {
                "USB audio native library is not installed"
            }
            // Parent can terminate this exact child if ALSA waits for host audio.
            println("PID:${Process.myPid()}")
            System.out.flush()
            System.load(library.path)
            val cards = File("/proc/asound/cards").readText()
            val card = Regex("(?m)^\\s*(\\d+)\\s+\\[[^]]+].*audio_source.*$", RegexOption.IGNORE_CASE)
                .find(cards)?.groupValues?.get(1)?.toIntOrNull()
                ?: error("USB audio-source PCM is unavailable; start USB mode first")
            val pcm = File("/proc/asound/pcm").readLines().firstOrNull {
                it.startsWith("%02d-".format(card)) && it.contains("playback") &&
                    (it.contains("USB audio", ignoreCase = true) || it.contains("USB gadget", ignoreCase = true))
            } ?: error("USB audio-source playback PCM was not found")
            val device = pcm.substringBefore(':').substringAfter('-').trim().toInt()
            exitProcess(streamPcm(card, device))
        } catch (error: Throwable) {
            println("ERROR:${error.message?.replace('\n', ' ')?.take(300) ?: "USB audio writer failed"}")
            System.out.flush()
            exitProcess(1)
        }
    }
}
