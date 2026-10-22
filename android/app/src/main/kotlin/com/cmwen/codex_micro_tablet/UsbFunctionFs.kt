package com.cmwen.codex_micro_tablet

import androidx.annotation.Keep
import java.io.File

/** Root-process-only FunctionFS HID, bypassing Lenovo's hardcoded f_hid. */
@Keep
class UsbFunctionFs(library: File, private val received: (ByteArray) -> Unit) {
    init {
        require(library.name == "libmicro_usb_audio.so" && library.isFile)
        System.load(library.canonicalPath)
    }
    external fun start(path: String, reportDescriptor: ByteArray)
    external fun send(report: ByteArray): Boolean
    external fun stop()
    @Keep fun onReport(report: ByteArray) = received(report)
}
