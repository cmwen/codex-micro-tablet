import 'dart:async';

import 'package:flutter/material.dart';

/// FNK0104B usage windows, with reset timestamps expressed in Unix seconds.
class UsagePanel extends StatefulWidget {
  const UsagePanel({
    super.key,
    required this.usage,
    required this.status,
    required this.onSettings,
    required this.onRefresh,
    this.error = '',
    this.lastUpdated,
    this.now,
  });

  final Map? usage;
  final String status, error;
  final VoidCallback onSettings, onRefresh;
  final DateTime? lastUpdated;
  final DateTime Function()? now;

  @override
  State<UsagePanel> createState() => _UsagePanelState();
}

class _UsagePanelState extends State<UsagePanel> {
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = (widget.now?.call() ?? DateTime.now()).toLocal();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xff1b2a30),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Codex usage',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                onPressed: widget.onRefresh,
                tooltip: 'Refresh usage',
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                onPressed: widget.onSettings,
                tooltip: 'Usage bridge settings',
                icon: const Icon(Icons.tune),
              ),
            ],
          ),
          Text(widget.status, style: Theme.of(context).textTheme.bodySmall),
          if (widget.error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                widget.error,
                style: const TextStyle(color: Colors.orangeAccent),
              ),
            ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, bounds) {
              final cards = [
                _window(
                  context,
                  '5-hour usage',
                  widget.usage?['five_hour'] as Map?,
                  now,
                ),
                _window(
                  context,
                  'Weekly usage',
                  widget.usage?['weekly'] as Map?,
                  now,
                ),
              ];
              if (bounds.maxWidth < 360) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [cards[0], const SizedBox(height: 18), cards[1]],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 20),
                  Expanded(child: cards[1]),
                ],
              );
            },
          ),
          if (widget.usage == null) ...[
            const SizedBox(height: 12),
            const Text(
              'Connect the same Wi-Fi bridge used by your ESP32 monitor.',
              style: TextStyle(color: Color(0xffa5b4b5), fontSize: 12),
            ),
          ],
          if (widget.usage != null && widget.lastUpdated != null) ...[
            const SizedBox(height: 12),
            Text(
              'Updated ${_time(context, widget.lastUpdated!.toLocal())} · Reset times are local',
              style: const TextStyle(color: Color(0xffa5b4b5), fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  String _time(BuildContext context, DateTime date) =>
      MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay.fromDateTime(date),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      );

  Widget _window(BuildContext context, String name, Map? values, DateTime now) {
    final rawUsed = values?['used_percent'];
    final used =
        rawUsed is num && rawUsed.isFinite && rawUsed >= 0 && rawUsed <= 100
        ? rawUsed.toDouble()
        : null;
    final rawReset = values?['resets_at'];
    final reset =
        rawReset is num &&
            rawReset.isFinite &&
            rawReset >= 0 &&
            rawReset <= 8640000000000
        ? DateTime.fromMillisecondsSinceEpoch(
            (rawReset * 1000).round(),
            isUtc: true,
          ).toLocal()
        : null;
    final locale = MaterialLocalizations.of(context);
    final duration = reset?.difference(now);
    final String countdown;
    if (duration == null) {
      countdown = 'Reset time unavailable';
    } else if (duration <= Duration.zero) {
      countdown = 'Awaiting bridge reset update';
    } else {
      // Round up so a future reset never appears to have already elapsed.
      final minutes = (duration.inMilliseconds / 60000).ceil();
      countdown = minutes < 60
          ? 'Resets in ${minutes}m'
          : minutes < 1440
          ? 'Resets in ${minutes ~/ 60}h ${minutes % 60}m'
          : 'Resets in ${minutes ~/ 1440}d ${(minutes % 1440) ~/ 60}h';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: const TextStyle(color: Color(0xffa5b4b5))),
        const SizedBox(height: 6),
        Text(
          used == null ? '—' : '${used.round()}% used',
          style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w600),
        ),
        Text(
          used == null
              ? 'Usage unavailable'
              : '${(100 - used).round()}% remaining',
          style: const TextStyle(color: Color(0xffa5b4b5), fontSize: 12),
        ),
        const SizedBox(height: 10),
        LinearProgressIndicator(
          value: (used ?? 0) / 100,
          semanticsLabel:
              '$name: ${used == null ? 'unavailable' : '${used.round()} percent used'}',
          color: used != null && used >= 90
              ? Colors.orangeAccent
              : const Color(0xff86dbc7),
          backgroundColor: Colors.white10,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: 10),
        Text(countdown, style: const TextStyle(fontSize: 12)),
        if (reset != null) ...[
          const SizedBox(height: 4),
          Text(
            'Resets ${locale.formatFullDate(reset)} at ${_time(context, reset)} (${reset.timeZoneName})',
            style: const TextStyle(color: Color(0xffa5b4b5), fontSize: 11),
          ),
        ],
      ],
    );
  }
}
