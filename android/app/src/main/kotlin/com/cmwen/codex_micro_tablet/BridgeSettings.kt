package com.cmwen.codex_micro_tablet

/**
 * Persisted monitor-source kinds.
 *
 * KIND_BRIDGE is the legacy FNK0104B monitor bridge (`GET /v1/status`, `X-Monitor-Key`).
 * KIND_AGENT_DECK is the Agent Deck read-only LAN contract (`GET /api/snapshot`), which
 * carries no shared key. They are never mixed: each kind has its own endpoint and parser.
 */
object BridgeSettings {
    const val KIND_BRIDGE = "bridge"
    const val KIND_AGENT_DECK = "agent-deck"

    fun kind(value: String?): String = if (value == KIND_AGENT_DECK) KIND_AGENT_DECK else KIND_BRIDGE
}
