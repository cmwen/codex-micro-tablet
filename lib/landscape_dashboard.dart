import 'package:flutter/material.dart';

import 'bridge_client.dart';
import 'hid_service.dart';
import 'main.dart' show HoldControl, ink, panel, cream, muted, mint;
import 'usage_panel.dart';

const cyan = Color(0xff00cdeb);

/// The ESP32 monitor's status / quota / action hierarchy, sized for a desk tablet.
/// Bridge thread selection and Desktop's HID slots are independent destinations.
class LandscapeDashboard extends StatelessWidget {
  const LandscapeDashboard({
    super.key,
    required this.hid,
    required this.bridge,
    required this.target,
    required this.onTarget,
    required this.onConnections,
    required this.onBridgeSettings,
    required this.onCompose,
  });

  final HidService hid;
  final BridgeClient bridge;
  final String? target;
  final ValueChanged<String?> onTarget;
  final VoidCallback onConnections, onBridgeSettings, onCompose;

  List<Map> get agents =>
      (bridge.snapshot?['agents'] as List? ?? []).whereType<Map>().toList();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(),
        const SizedBox(height: 10),
        Expanded(
          child: LayoutBuilder(
            builder: (context, bounds) => Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 6,
                  child: _statusPane(
                    bounds.maxHeight,
                    Column(
                      children: [
                        UsagePanel(
                          compact: true,
                          usage:
                              (bridge.snapshot?['codex'] as Map?)?['usage']
                                  as Map?,
                          status: bridge.baseUrl.isEmpty
                              ? 'Connect monitor bridge'
                              : bridge.status,
                          error: bridge.error,
                          lastUpdated: bridge.lastUpdated,
                          onSettings: onBridgeSettings,
                          onRefresh: bridge.refresh,
                        ),
                        const SizedBox(height: 10),
                        Expanded(child: _agents()),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 5,
                  child: SingleChildScrollView(
                    child: _keys(context, bounds.maxHeight),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        _footer(),
      ],
    ),
  );

  Widget _statusPane(double height, Widget content) => height < 300
      ? SingleChildScrollView(child: SizedBox(height: 420, child: content))
      : content;

  Widget _header() => Container(
    height: 52,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: panel,
      border: Border.all(color: cyan.withValues(alpha: .45)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        const Icon(Icons.dashboard_rounded, color: cyan, size: 26),
        const SizedBox(width: 10),
        const Text(
          'CODEX / MICRO',
          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1.5),
        ),
        if (hid.microphoneActive)
          const Padding(
            padding: EdgeInsets.only(left: 12),
            child: Text(
              'USB microphone on',
              style: TextStyle(color: mint, fontSize: 11),
            ),
          ),
        Expanded(
          child: Text(
            hid.ready
                ? 'Micro linked · ${hid.hostName}'
                : hid.connected
                ? 'Waiting for Micro discovery'
                : 'Micro disconnected',
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: hid.ready ? mint : muted, fontSize: 12),
          ),
        ),
        IconButton(
          tooltip: 'Release controls / restore USB',
          onPressed: hid.restoreUsb,
          icon: const Icon(Icons.restart_alt),
        ),
        IconButton(
          tooltip: 'Connection settings',
          onPressed: onConnections,
          icon: Icon(hid.isUsb ? Icons.usb : Icons.bluetooth, color: cyan),
        ),
      ],
    ),
  );

  Widget _agents() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: panel,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.hub_outlined, color: cyan, size: 18),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'LIVE WORKSPACE',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '${agents.length} chats',
              style: const TextStyle(color: muted, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: agents.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        bridge.connected ? Icons.task_alt : Icons.link_off,
                        color: bridge.connected ? mint : muted,
                        size: 32,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        bridge.connected
                            ? 'All quiet. Ready for your next idea.'
                            : 'Connect your monitor bridge',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Named chats and live status appear here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                      if (!bridge.connected)
                        TextButton(
                          onPressed: onBridgeSettings,
                          child: const Text('Set up bridge'),
                        ),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: agents.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final agent = agents[index];
                    final selected = target == agent['id'];
                    final status = agent['status']?.toString() ?? 'unknown';
                    final color = switch (status) {
                      'running' || 'working' => cyan,
                      'needs_attention' => Colors.amber,
                      'error' => Colors.redAccent,
                      _ => mint,
                    };
                    return Material(
                      color: selected ? cyan.withValues(alpha: .12) : ink,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () =>
                            onTarget(selected ? null : agent['id'] as String),
                        child: Semantics(
                          selected: selected,
                          button: true,
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 21,
                                  backgroundColor: color.withValues(alpha: .12),
                                  child: Icon(
                                    Icons.smart_toy_outlined,
                                    color: color,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        (agent['name'] ??
                                                agent['title'] ??
                                                agent['id'])
                                            .toString(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        status.replaceAll('_', ' '),
                                        style: TextStyle(
                                          color: color,
                                          fontSize: 11,
                                        ),
                                      ),
                                      if (selected && agent['detail'] != null)
                                        Text(
                                          agent['detail'].toString(),
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: muted,
                                            fontSize: 12,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  selected
                                      ? Icons.check_circle
                                      : Icons.chevron_right,
                                  color: selected ? cyan : muted,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(height: 6),
        Text(
          target == null
              ? 'Tap a chat to target a bridge message'
              : agents.any((a) => a['id'] == target)
              ? 'Chat selected · tap Message to write'
              : 'Selected chat unavailable · choose a destination',
          style: TextStyle(
            color: target != null && !agents.any((a) => a['id'] == target)
                ? Colors.amber
                : muted,
            fontSize: 11,
          ),
        ),
      ],
    ),
  );

  Widget _keys(BuildContext context, double availableHeight) {
    final keyHeight = ((availableHeight - 184) / 2).clamp(74.0, 220.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'DESKTOP SLOTS',
          style: TextStyle(color: muted, fontSize: 11, letterSpacing: 1.4),
        ),
        const SizedBox(height: 6),
        GridView(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            mainAxisExtent: keyHeight,
          ),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: List.generate(6, (id) {
            final slot = hid.slots.where((s) => s['id'] == id).firstOrNull;
            final color = slot?['present'] == true && slot?['color'] is num
                ? Color(0xff000000 | (slot!['color'] as num).toInt())
                : cyan;
            return HoldControl(
              key: ValueKey('agent-$id'),
              enabled: hid.ready,
              onChanged: (down) => hid.key(id, down),
              onTap: () => hid.tap(id),
              label: 'Agent ${id + 1}',
              icon: Icons.smart_toy_outlined,
              accent: color,
              compact: true,
              subtitle: slot?['present'] == true
                  ? 'Desktop lighting'
                  : 'AG0$id',
            );
          }),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 64,
          child: Row(
            children: [
              for (final action in [
                (6, 'Fast', Icons.bolt),
                (7, 'Approve', Icons.check),
                (8, 'Reject', Icons.close),
                (9, 'Fork', Icons.call_split),
              ]) ...[
                if (action.$1 != 6) const SizedBox(width: 6),
                Expanded(
                  child: _key(
                    action.$1,
                    action.$2,
                    action.$3,
                    accent: action.$1 == 7 ? mint : cream,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 64,
          child: Row(
            children: [
              for (final action in [
                (16, 'Left', Icons.arrow_back),
                (13, 'Up', Icons.arrow_upward),
                (14, 'Down', Icons.arrow_downward),
                (15, 'Right', Icons.arrow_forward),
              ]) ...[
                if (action.$1 != 16) const SizedBox(width: 6),
                Expanded(child: _key(action.$1, action.$2, action.$3)),
              ],
            ],
          ),
        ),
        if (hid.error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              hid.error,
              style: const TextStyle(color: Colors.amber, fontSize: 11),
            ),
          ),
      ],
    );
  }

  Widget _key(
    int id,
    String label,
    IconData icon, {
    Color accent = cream,
    String? subtitle,
  }) => HoldControl(
    key: ValueKey('control-$id'),
    enabled: hid.ready,
    onChanged: (down) => hid.key(id, down),
    onTap: () => hid.tap(id),
    label: label,
    icon: icon,
    compact: true,
    accent: accent,
    subtitle: subtitle,
    immediateHold: id == 10,
  );

  Widget _footer() => SizedBox(
    height: 78,
    child: Row(
      children: [
        Expanded(
          flex: 4,
          child: _key(
            10,
            'Hold to talk',
            Icons.mic_none,
            accent: mint,
            subtitle: hid.isUsb && hid.usbAudioSupported
                ? 'Tablet microphone'
                : 'Mac microphone',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: _key(
            11,
            'Voice',
            Icons.graphic_eq,
            subtitle: 'Desktop mapping',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: _key(
            12,
            'Send',
            Icons.arrow_upward,
            accent: cyan,
            subtitle: 'Desktop mapping',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(78),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: onCompose,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Message'),
          ),
        ),
      ],
    ),
  );
}
