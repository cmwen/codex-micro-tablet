package com.cmwen.codex_micro_tablet

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.util.ArrayDeque

/**
 * Bounded, read-only DNS-SD browse used to find services advertised on the home LAN.
 *
 * Discovery is untrusted input: results are only endpoint candidates. The Dart layer
 * classifies them and the user must confirm a selection, after which the client still
 * verifies the endpoint contract before saving anything. No credential is sent to a
 * discovered name by this class, and it never advertises or scans continuously.
 */
class LocalServiceDiscovery(context: Context) {
    private val nsd = context.getSystemService(Context.NSD_SERVICE) as? NsdManager
    private val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
    private var multicast: WifiManager.MulticastLock? = null
    private val handler = Handler(Looper.getMainLooper())
    private val queue = ArrayDeque<NsdServiceInfo>()
    private val found = LinkedHashMap<String, Map<String, Any?>>()
    private var generation = 0
    private var running = false
    private var resolving: String? = null
    private var listener: NsdManager.DiscoveryListener? = null
    private var serviceType = DEFAULT_SERVICE_TYPE

    /** Starts one bounded browse and reports the resolved candidates exactly once. */
    fun discover(type: String, timeoutMs: Long, result: (List<Map<String, Any?>>) -> Unit, failure: (String) -> Unit) {
        val manager = nsd
        if (manager == null) {
            failure("This device has no local service discovery")
            return
        }
        stop()
        val boundedTimeout = timeoutMs.coerceIn(1500L, 15000L)
        val current = ++generation
        running = true
        resolving = null
        queue.clear()
        found.clear()
        serviceType = if (VALID_TYPE.matches(type)) type else DEFAULT_SERVICE_TYPE
        // Some Wi-Fi power-save implementations filter multicast unless a lock is held,
        // which silently empties DNS-SD results. It is released with the browse.
        multicast = wifi?.createMulticastLock("codex-micro-discovery")?.apply {
            setReferenceCounted(false)
            runCatching { acquire() }
        }
        lateinit var discovery: NsdManager.DiscoveryListener
        discovery = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) {
                Log.i(TAG, "Browsing $serviceType")
            }
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                if (current != generation) return
                stop()
                failure("Local discovery could not start (error $errorCode)")
            }

            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
                Log.w(TAG, "Stopping local discovery reported error $errorCode")
            }

            override fun onDiscoveryStopped(serviceType: String) = Unit
            override fun onServiceLost(serviceInfo: NsdServiceInfo) {
                // A lost instance is not reported as available after the browse window.
            }

            override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                if (current != generation) return
                Log.i(TAG, "Found ${serviceInfo.serviceName} ${serviceInfo.serviceType}")
                if (!canonicalType(serviceInfo.serviceType).equals(serviceType, true)) return
                queue.addLast(serviceInfo)
                resolveNext(current)
            }
        }
        listener = discovery
        try {
            manager.discoverServices(serviceType, NsdManager.PROTOCOL_DNS_SD, discovery)
        } catch (error: Exception) {
            listener = null
            running = false
            failure(error.message ?: "Local discovery could not start")
            return
        }
        handler.postDelayed({
            if (current == generation) {
                val services = found.values.toList()
                Log.i(TAG, "Browse complete: ${services.size} candidate(s)")
                stop()
                result(services)
            }
        }, boundedTimeout)
    }

    /** Cancels an in-flight browse. Safe to call when nothing is running. */
    fun stop() {
        ++generation
        running = false
        resolving = null
        queue.clear()
        handler.removeCallbacksAndMessages(null)
        multicast?.let { lock -> if (lock.isHeld) runCatching { lock.release() } }
        multicast = null
        val discovery = listener ?: return
        listener = null
        try {
            nsd?.stopServiceDiscovery(discovery)
        } catch (error: Exception) {
            Log.w(TAG, "Stopping local discovery failed: ${error.message}")
        }
    }

    // Android resolves one service at a time; extra requests fail with "listener in use".
    private fun resolveNext(current: Int) {
        if (!running || current != generation || resolving != null) return
        val candidate = queue.pollFirst() ?: return
        val manager = nsd ?: return
        resolving = candidate.serviceName
        // Android 10 can drop a resolve started inside onServiceFound; queue it instead.
        handler.postDelayed({
            if (!running || current != generation) return@postDelayed
            Log.i(TAG, "Resolving ${candidate.serviceName}")
            try {
                @Suppress("DEPRECATION")
                manager.resolveService(candidate, object : NsdManager.ResolveListener {
                    override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                        if (current != generation) return
                        Log.i(TAG, "Unresolved local service ${serviceInfo.serviceName} ($errorCode)")
                        resolving = null
                        resolveNext(current)
                    }

                    override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                        if (current != generation) return
                        val described = describe(serviceInfo)
                        Log.i(TAG, "Resolved ${serviceInfo.serviceName}: host=${serviceInfo.host?.hostAddress} port=${serviceInfo.port} usable=${described != null}")
                        if (described != null) found[serviceInfo.serviceName] = described
                        resolving = null
                        resolveNext(current)
                    }
                })
            } catch (error: Exception) {
                resolving = null
                Log.i(TAG, "Local service resolve rejected: ${error.message}")
                resolveNext(current)
            }
        }, RESOLVE_DELAY_MS)
    }

    private fun describe(info: NsdServiceInfo): Map<String, Any?>? {
        val port = info.port
        if (port !in 1..65535) return null
        val host = info.host?.hostAddress?.takeIf { it.isNotBlank() } ?: return null
        if (!SAFE_HOST.matches(host)) return null
        val name = info.serviceName
        if (name.isBlank() || name.length > 128) return null
        val attributes = LinkedHashMap<String, String>()
        info.attributes?.forEach { (key, value) ->
            val text = value?.toString(Charsets.UTF_8) ?: return@forEach
            if (SAFE_TXT_KEY.matches(key) && text.length <= 255) attributes[key] = text
        }
        return mapOf(
            "name" to name,
            "type" to canonicalType(info.serviceType),
            "host" to host,
            "port" to port,
            "attributes" to attributes,
        )
    }

    // Some Android 10 builds report "._http._tcp" instead of "_http._tcp.".
    private fun canonicalType(value: String): String {
        val trimmed = value.trim().trimStart('.')
        val canonical = if (trimmed.endsWith('.')) trimmed else "$trimmed."
        return if (VALID_TYPE.matches(canonical)) canonical else serviceType
    }

    companion object {
        const val DEFAULT_SERVICE_TYPE = "_http._tcp."
        private const val TAG = "CodexMicroDiscovery"
        private const val RESOLVE_DELAY_MS = 150L
        private val VALID_TYPE = Regex("^_[a-z0-9](?:[a-z0-9-]{0,13}[a-z0-9])?\\._(?:tcp|udp)\\.?$")
        private val SAFE_HOST = Regex("^[A-Za-z0-9.:\\[\\]-]{1,64}$")
        private val SAFE_TXT_KEY = Regex("^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$")
    }
}
