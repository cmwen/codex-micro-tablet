import 'dart:async';

import 'package:flutter/material.dart';

import 'bridge_client.dart';
import 'usage_panel.dart';

/// Read-only, bridge-scoped observations. A connected transport is not complete
/// coverage of every agent application on the desktop.
class MonitorObservation {
  const MonitorObservation({
    required this.running,
    required this.attention,
    required this.fresh,
    required this.unknown,
  });
  final int running, attention;
  final bool fresh, unknown;
  bool get quiet => fresh && !unknown && running == 0 && attention == 0;

  factory MonitorObservation.fromBridge(BridgeClient bridge, DateTime now) {
    final agents = (bridge.snapshot?['agents'] as List? ?? []).whereType<Map>();
    final age = bridge.lastUpdated == null
        ? null
        : now.difference(bridge.lastUpdated!);
    final hasLiveActivity =
        bridge.connected ||
        (bridge.readOnly &&
            bridge.snapshot?['integration'] == 'degraded' &&
            agents.isNotEmpty);
    const known = {
      'running',
      'working',
      'needs_attention',
      'error',
      'idle',
      'completed',
      'stopped',
    };
    return MonitorObservation(
      running: agents
          .where((a) => a['status'] == 'running' || a['status'] == 'working')
          .length,
      attention: agents
          .where(
            (a) => a['status'] == 'needs_attention' || a['status'] == 'error',
          )
          .length,
      fresh:
          hasLiveActivity &&
          bridge.snapshot != null &&
          age != null &&
          age >= const Duration(seconds: -5) &&
          age <= const Duration(seconds: 15),
      unknown:
          bridge.snapshot == null ||
          agents.any((a) => !known.contains(a['status'])),
    );
  }
}

/// Read-only monitor. A bounded shift reduces static pixel wear.
class StandaloneDisplay extends StatefulWidget {
  const StandaloneDisplay({
    super.key,
    required this.bridge,
    required this.onSettings,
    required this.onExit,
  });
  final BridgeClient bridge;
  final VoidCallback onSettings, onExit;
  @override
  State<StandaloneDisplay> createState() => _StandaloneDisplayState();
}

class _StandaloneDisplayState extends State<StandaloneDisplay>
    with WidgetsBindingObserver {
  Timer? _shiftTimer, _clockTimer;
  int _position = 0;
  static const _offsets = [
    Alignment(-1, -1),
    Alignment(1, -1),
    Alignment(1, 1),
    Alignment(-1, 1),
  ];
  static const cyan = Color(0xff31e8ec),
      muted = Color(0xffa8bce4),
      panel = Color(0xff091a35);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimers();
  }

  void _startTimers() {
    _shiftTimer?.cancel();
    _clockTimer?.cancel();
    _shiftTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() => _position = (_position + 1) % _offsets.length);
      }
    });
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startTimers();
    } else {
      _shiftTimer?.cancel();
      _clockTimer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shiftTimer?.cancel();
    _clockTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bridge = widget.bridge, now = DateTime.now().toLocal();
    final observation = MonitorObservation.fromBridge(bridge, now);
    final usage = (bridge.snapshot?['codex'] as Map?)?['usage'] as Map?;
    final agents = (bridge.snapshot?['agents'] as List? ?? [])
        .whereType<Map>()
        .toList();
    int rank(Map a) => switch (a['status']) {
      'needs_attention' || 'error' => 0,
      'running' || 'working' => 1,
      _ => 2,
    };
    agents.sort((a, b) => rank(a).compareTo(rank(b)));
    final attention = observation.attention > 0;
    final active = observation.running > 0 || attention;
    final status = !observation.fresh
        ? 'Activity stale or unavailable'
        : observation.unknown
        ? 'Some activity unknown'
        : attention
        ? '${observation.attention} need attention'
        : observation.quiet
        ? 'No visible running chats'
        : '${observation.running} running · visible chats';
    final label = attention
        ? 'Needs attention'
        : active
        ? 'Running chats'
        : observation.quiet
        ? 'AMBIENT DISPLAY'
        : 'Chat activity';
    final clock =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final day = MaterialLocalizations.of(context).formatMediumDate(now);
    final source = bridge.sourceLabel;
    return ColoredBox(
      color: const Color(0xff030d22),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Align(
          key: const ValueKey('display-shift'),
          alignment: _offsets[_position],
          child: FractionallySizedBox(
            widthFactor: .97,
            heightFactor: .97,
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.layers_outlined, color: cyan, size: 30),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Agent Control',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Monitor source',
                      onPressed: widget.onSettings,
                      icon: const Icon(Icons.settings_outlined, color: muted),
                    ),
                    IconButton(
                      tooltip: 'Exit standalone display',
                      onPressed: widget.onExit,
                      icon: const Icon(Icons.exit_to_app, color: muted),
                    ),
                  ],
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 10),
                        Text(
                          status,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: observation.fresh ? cyan : Colors.amber,
                            fontSize: 14,
                          ),
                        ),
                        if (bridge.baseUrl.isEmpty)
                          const Text(
                            'Set up a monitor source',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: muted),
                          ),
                        if (bridge.error.isNotEmpty)
                          Text(
                            bridge.error,
                            style: const TextStyle(color: Colors.orangeAccent),
                          ),
                        if (bridge.snapshot != null &&
                            bridge.lastUpdated != null)
                          Text(
                            'Last update: ${bridge.lastUpdated!.toLocal().toString().split('.').first}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: muted, fontSize: 11),
                          ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            image: const DecorationImage(
                              image: AssetImage('assets/monitor-horizon.png'),
                              fit: BoxFit.fill,
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                label,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: muted,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (active) ...[
                                Text(
                                  '${attention ? observation.attention : observation.running}'
                                      .padLeft(2, '0'),
                                  style: TextStyle(
                                    fontSize: 84,
                                    height: 1.2,
                                    color: attention
                                        ? Colors.amber
                                        : Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  observation.fresh
                                      ? '${observation.running} running · visible chats'
                                      : '${observation.running} last reported running',
                                  style: const TextStyle(color: cyan),
                                ),
                              ] else ...[
                                const SizedBox(height: 6),
                                // Ambient mode keeps a compact date/time so quota
                                // and source detail keep the available height.
                                Semantics(
                                  label: 'Local time $clock, $day',
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.baseline,
                                      textBaseline: TextBaseline.alphabetic,
                                      children: [
                                        Text(
                                          clock,
                                          style: const TextStyle(
                                            fontSize: 38,
                                            height: 1.1,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                            fontFeatures: [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          day,
                                          style: const TextStyle(
                                            color: muted,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (!active && !observation.quiet)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'Waiting for fresh activity',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.amber),
                            ),
                          ),
                        if (active) ...[
                          const SizedBox(height: 14),
                          for (final agent in agents)
                            _agentCard(agent, observation.fresh),
                        ],
                        const SizedBox(height: 16),
                        UsagePanel(
                          usage: usage,
                          status: bridge.status,
                          readOnly: true,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '${source.toUpperCase()} CHATS · ${agents.length} visible',
                          style: const TextStyle(
                            color: muted,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                          ),
                        ),
                        Text(
                          bridge.readOnly
                              ? 'Read-only Agent Deck snapshot of Codex and T3 Code.'
                              : 'Only chats visible to the bridge are shown.',
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                        if (!active && agents.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          for (final agent in agents)
                            _agentCard(agent, observation.fresh),
                        ],
                        if (agents.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              bridge.snapshot == null
                                  ? 'Chat status unavailable'
                                  : 'No visible chats',
                              style: const TextStyle(color: muted),
                            ),
                          ),
                        const SizedBox(height: 12),
                        Text(
                          bridge.readOnly
                              ? 'Read-only Agent Deck source · local clock'
                              : 'Codex account quota · local clock · read-only',
                          style: const TextStyle(color: muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _agentCard(Map agent, bool fresh) {
    final attention =
        agent['status'] == 'needs_attention' || agent['status'] == 'error';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: panel,
        border: Border.all(
          color: attention ? Colors.amber : const Color(0xff355a91),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            attention ? Icons.notification_important_outlined : Icons.code,
            color: attention ? Colors.amber : cyan,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (agent['name'] ??
                          agent['title'] ??
                          agent['id'] ??
                          'Untitled chat')
                      .toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  (agent['detail'] ?? agent['status'] ?? 'Unknown').toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '${fresh ? '' : 'Last seen: '}${agent['status'] ?? 'unknown'}',
              style: TextStyle(
                color: fresh ? cyan : Colors.amber,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
