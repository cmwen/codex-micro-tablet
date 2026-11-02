import 'dart:async';

import 'package:flutter/material.dart';

import 'bridge_client.dart';

/// Read-only monitor. A small bounded shift reduces static pixel wear.
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
  Timer? _shiftTimer;
  int _position = 0;
  static const _offsets = [
    Alignment(-1, -1),
    Alignment(1, -1),
    Alignment(1, 1),
    Alignment(-1, 1),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  void _startTimer() {
    _shiftTimer?.cancel();
    _shiftTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      setState(() => _position = (_position + 1) % _offsets.length);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startTimer();
    } else {
      _shiftTimer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shiftTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bridge = widget.bridge;
    final usage = (bridge.snapshot?['codex'] as Map?)?['usage'] as Map?;
    final agents = (bridge.snapshot?['agents'] as List? ?? [])
        .whereType<Map>()
        .toList();
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Align(
        key: const ValueKey('display-shift'),
        alignment: _offsets[_position],
        child: FractionallySizedBox(
          widthFactor: .97,
          heightFactor: .97,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'CODEX MONITOR',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Bridge settings',
                      onPressed: widget.onSettings,
                      icon: const Icon(Icons.settings),
                    ),
                    IconButton(
                      tooltip: 'Exit standalone display',
                      onPressed: widget.onExit,
                      icon: const Icon(Icons.exit_to_app),
                    ),
                  ],
                ),
                Text(
                  bridge.baseUrl.isEmpty
                      ? 'Set up the monitor bridge'
                      : bridge.status,
                ),
                if (bridge.error.isNotEmpty)
                  Text(
                    bridge.error,
                    style: const TextStyle(color: Colors.orangeAccent),
                  ),
                if (bridge.snapshot != null && bridge.lastUpdated != null)
                  Text(
                    'Last update: ${bridge.lastUpdated!.toLocal().toString().split('.').first}',
                  ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 32,
                  runSpacing: 16,
                  children: [
                    _usage('5-hour usage', usage?['five_hour'] as Map?),
                    _usage('Weekly usage', usage?['weekly'] as Map?),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'BRIDGE CHATS · ${agents.length} visible',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const Text(
                  'Only chats visible to the bridge are shown.',
                  style: TextStyle(color: Colors.grey),
                ),
                if (agents.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      bridge.snapshot == null
                          ? 'Chat status unavailable'
                          : 'No visible chats',
                    ),
                  ),
                for (final agent in agents)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.circle,
                      size: 10,
                      color: agent['status'] == 'running'
                          ? Colors.greenAccent
                          : Colors.grey,
                    ),
                    title: Text(
                      (agent['name'] ?? agent['title'] ?? agent['id'])
                          .toString(),
                    ),
                    subtitle: Text(
                      (agent['detail'] ?? agent['status'] ?? 'Unknown')
                          .toString(),
                    ),
                    trailing: Text((agent['status'] ?? 'unknown').toString()),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _usage(String label, Map? bucket) {
    final used = bucket?['used_percent'];
    final reset = bucket?['resets_at'];
    final resetText = reset is num
        ? DateTime.fromMillisecondsSinceEpoch(
            (reset * 1000).toInt(),
          ).toLocal().toString().split('.').first
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        Text(
          used is num ? '${used.toStringAsFixed(0)}% used' : 'Unavailable',
          style: const TextStyle(fontSize: 28),
        ),
        Text(
          resetText == null ? 'Reset time unavailable' : 'Resets $resetText',
        ),
      ],
    );
  }
}
