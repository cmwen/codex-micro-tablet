import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bridge_client.dart';
import 'hid_service.dart';
import 'usage_panel.dart';

const ink = Color(0xff101b20);
const panel = Color(0xff1b2a30);
const mint = Color(0xff86dbc7);
const cream = Color(0xfff2eddf);
const muted = Color(0xffa5b4b5);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  runApp(const MicroTabletApp());
}

class MicroTabletApp extends StatelessWidget {
  const MicroTabletApp({super.key, this.hid, this.bridge});
  final HidService? hid;
  final BridgeClient? bridge;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Codex Micro Tablet',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: ink,
      colorScheme: ColorScheme.fromSeed(
        seedColor: mint,
        brightness: Brightness.dark,
        surface: panel,
      ),
      textTheme: ThemeData.dark().textTheme.apply(
        bodyColor: cream,
        displayColor: cream,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
      ),
    ),
    home: Dashboard(hid: hid, bridge: bridge),
  );
}

class Dashboard extends StatefulWidget {
  const Dashboard({super.key, this.hid, this.bridge});
  final HidService? hid;
  final BridgeClient? bridge;
  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> with WidgetsBindingObserver {
  late final HidService hid;
  late final BridgeClient bridge;
  final message = TextEditingController();
  String? target;
  String result = '';
  bool sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    hid = widget.hid ?? HidService();
    bridge = widget.bridge ?? BridgeClient();
    hid.addListener(_changed);
    bridge.addListener(_changed);
    unawaited(hid.initialize());
    unawaited(_loadBridge());
  }

  Future<void> _loadBridge() async {
    try {
      await bridge.load();
    } catch (_) {
      if (mounted) {
        setState(
          () => result =
              'Saved bridge settings could not be loaded. Open Bridge settings to reconnect.',
        );
      }
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(hid.releaseAll());
    } else {
      unawaited(hid.refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    hid.removeListener(_changed);
    bridge.removeListener(_changed);
    unawaited(hid.releaseAll());
    if (widget.hid == null) hid.dispose();
    if (widget.bridge == null) bridge.dispose();
    message.dispose();
    super.dispose();
  }

  Future<void> _connections() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ConnectionSheet(hid: hid),
    );
  }

  Future<void> _bridgeSettings() async {
    final url = TextEditingController(text: bridge.baseUrl);
    final key = TextEditingController(text: bridge.token);
    String? validation;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Connect your monitor bridge'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Use the same FNK0104B bridge on your Mac for usage and named chats. Bluetooth controls work independently.',
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: url,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Bridge address',
                      hintText: 'http://192.168.1.20:8765',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: key,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(labelText: 'Monitor key'),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Your tablet must reach the bridge over Wi-Fi. Use HTTPS or a trusted private network.',
                    style: TextStyle(color: muted),
                  ),
                  if (validation != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        validation!,
                        style: const TextStyle(color: Colors.orangeAccent),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await bridge.configure(url.text.trim(), key.text);
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  update(() => validation = e.toString());
                }
              },
              child: const Text('Save & connect'),
            ),
          ],
        ),
      ),
    );
    // Dialog route removal can animate after completion; controllers are kept
    // until widgets using them have been removed from the tree.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    url.dispose();
    key.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, bounds) {
          final wide = bounds.maxWidth >= 800;
          return SingleChildScrollView(
            padding: EdgeInsets.all(wide ? 28 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(),
                const SizedBox(height: 20),
                _linkBanner(),
                const SizedBox(height: 18),
                UsagePanel(
                  usage: (bridge.snapshot?['codex'] as Map?)?['usage'] as Map?,
                  status: bridge.baseUrl.isEmpty
                      ? 'Set up your monitor bridge'
                      : bridge.status,
                  error: bridge.error,
                  lastUpdated: bridge.lastUpdated,
                  onSettings: _bridgeSettings,
                  onRefresh: bridge.refresh,
                ),
                const SizedBox(height: 22),
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 7, child: _controls()),
                      const SizedBox(width: 24),
                      Expanded(flex: 5, child: _bridgePanel()),
                    ],
                  )
                else ...[
                  _controls(),
                  const SizedBox(height: 24),
                  _bridgePanel(),
                ],
                const SizedBox(height: 18),
                const Text(
                  'Unofficial Micro compatibility · Keep this dashboard open while connected.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );

  Widget _header() => Row(
    children: [
      Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: mint,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.dashboard_rounded, color: ink),
      ),
      const SizedBox(width: 12),
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CODEX / MICRO',
              style: TextStyle(fontSize: 12, color: mint, letterSpacing: 2),
            ),
            Text(
              'Your desk, connected.',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      IconButton.filledTonal(
        tooltip: 'Bluetooth connection',
        onPressed: _connections,
        icon: const Icon(Icons.bluetooth),
      ),
    ],
  );

  Widget _linkBanner() {
    final title = hid.ready
        ? 'Micro linked · ${hid.hostName}'
        : hid.connected
        ? 'Bluetooth connected · Waiting for Micro discovery'
        : hid.registered
        ? 'Ready to pair with your Mac'
        : 'Connect your Mac to get started';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hid.ready ? mint.withValues(alpha: .10) : panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hid.ready ? mint.withValues(alpha: .5) : Colors.white12,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            hid.ready ? Icons.check_circle_outline : Icons.bluetooth_searching,
            color: mint,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  hid.ready
                      ? 'Controls follow your Desktop Micro assignments.'
                      : 'Pairing and Desktop discovery are separate steps. Controls unlock after a Micro exchange.',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
                if (hid.error.isNotEmpty)
                  Text(
                    hid.error,
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _connections,
            child: Text(hid.ready ? 'Manage' : 'Set up'),
          ),
        ],
      ),
    );
  }

  Widget _controls() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _section('AGENT KEYS', 'Desktop slots'),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, bounds) => GridView(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: bounds.maxWidth >= 420 ? 3 : 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 110,
          ),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: List.generate(6, (id) {
            final slot = hid.slots.where((s) => s['id'] == id).firstOrNull;
            final color = slot?['color'] is num
                ? Color(0xff000000 | (slot!['color'] as num).toInt())
                : muted;
            final present = slot?['present'] == true;
            return HoldControl(
              key: ValueKey('agent-$id'),
              enabled: hid.ready,
              onChanged: (down) => hid.key(id, down),
              onTap: () => hid.tap(id),
              label: 'Agent ${id + 1}',
              icon: Icons.smart_toy_outlined,
              accent: present ? color : muted,
              subtitle: present
                  ? 'Desktop lighting'
                  : 'Slot ${id + 1} · AG0$id',
            );
          }),
        ),
      ),
      const SizedBox(height: 24),
      _section('COMMAND KEYS', 'Your mappings'),
      const SizedBox(height: 12),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final action in [
            (6, 'Fast', Icons.bolt),
            (7, 'Approve', Icons.check),
            (8, 'Reject', Icons.close),
            (9, 'Fork', Icons.call_split),
          ])
            SizedBox(
              width: 112,
              height: 80,
              child: _control(action.$1, action.$2, action.$3),
            ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 90,
              child: _control(
                10,
                'Hold to talk',
                Icons.mic_none,
                subtitle: 'Mac microphone',
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 90,
              child: _control(
                11,
                'Voice',
                Icons.graphic_eq,
                subtitle: 'Map ACT11',
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 90,
              child: _control(12, 'Send', Icons.arrow_upward, accent: mint),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      const Text(
        'Voice controls use your Mac’s microphone. Tablet audio is not transmitted over HID.',
        style: TextStyle(color: muted, fontSize: 12),
      ),
      const SizedBox(height: 20),
      _section('NAVIGATION', 'Analog directions'),
      const SizedBox(height: 10),
      Row(
        children: [
          for (final direction in [
            (16, 'Left', Icons.arrow_back),
            (13, 'Up', Icons.arrow_upward),
            (14, 'Down', Icons.arrow_downward),
            (15, 'Right', Icons.arrow_forward),
          ]) ...[
            Expanded(
              child: SizedBox(
                height: 72,
                child: _control(direction.$1, direction.$2, direction.$3),
              ),
            ),
            if (direction.$1 != 15) const SizedBox(width: 10),
          ],
        ],
      ),
    ],
  );

  Widget _control(
    int id,
    String label,
    IconData icon, {
    String? subtitle,
    Color accent = cream,
  }) => HoldControl(
    key: ValueKey('control-$id'),
    enabled: hid.ready,
    onChanged: (down) => hid.key(id, down),
    onTap: () => hid.tap(id),
    label: label,
    icon: icon,
    accent: accent,
    subtitle: subtitle,
    compact: true,
  );

  Widget _section(String title, String trailing) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            color: muted,
            letterSpacing: 1.8,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      Text(trailing, style: const TextStyle(color: muted, fontSize: 11)),
    ],
  );

  Widget _bridgePanel() {
    final snapshot = bridge.snapshot;
    final agents = (snapshot?['agents'] as List? ?? [])
        .whereType<Map>()
        .toList();
    final missingTarget =
        target != null && !agents.any((a) => a['id'] == target);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Live workspace',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                onPressed: _bridgeSettings,
                icon: const Icon(Icons.tune),
                tooltip: 'Bridge settings',
              ),
              IconButton(
                onPressed: bridge.busy ? null : bridge.refresh,
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh workspace',
              ),
            ],
          ),
          Text(
            bridge.status,
            style: TextStyle(
              color: bridge.connected ? mint : muted,
              fontSize: 12,
            ),
          ),
          if (bridge.error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                bridge.error,
                style: const TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: 12,
                ),
              ),
            ),
          const SizedBox(height: 24),
          _section('BRIDGE CHATS', '${agents.length} visible'),
          const SizedBox(height: 12),
          if (agents.isEmpty)
            const Text(
              'Connect your monitor bridge to see named chats and usage. Micro slots above follow Desktop assignments independently.',
              style: TextStyle(color: muted, height: 1.5),
            )
          else
            for (final agent in agents)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Icon(
                        Icons.circle,
                        size: 8,
                        color: _agentColor(agent['status']?.toString()),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (agent['name'] ??
                                    agent['title'] ??
                                    agent['id'] ??
                                    'Chat')
                                .toString(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            (agent['detail'] ?? agent['status'] ?? '')
                                .toString(),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          const Divider(height: 32),
          const Text(
            'Send a message',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('destination-$target'),
            initialValue: target,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Destination'),
            items: [
              if (missingTarget)
                DropdownMenuItem<String>(
                  value: target,
                  child: const Text('Selected chat unavailable'),
                ),
              const DropdownMenuItem<String>(
                value: null,
                child: Text('New chat / bridge dispatcher'),
              ),
              for (final agent in agents)
                DropdownMenuItem(
                  value: agent['id']?.toString(),
                  child: Text(
                    (agent['name'] ?? agent['title'] ?? agent['id']).toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) => setState(() => target = value),
          ),
          if (missingTarget)
            const Text(
              'Choose a destination before sending. The selected chat is no longer available.',
              style: TextStyle(color: Colors.orangeAccent),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: message,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Message',
              hintText: 'What would you like to work on?',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: !bridge.connected || sending || missingTarget
                ? null
                : () => _send(target),
            icon: sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_outlined),
            label: const Text('Send through bridge'),
          ),
          if (result.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                result,
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            'Bridge messages do not grant approvals. Review approval requests on your Mac.',
            style: TextStyle(color: muted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Future<void> _send(String? agentId) async {
    final text = message.text.trim();
    if (text.isEmpty) return;
    setState(() {
      sending = true;
      result = '';
    });
    try {
      final response = await bridge.sendText(text, agentId: agentId);
      if (!mounted) return;
      setState(() {
        result = response['action'] == 'queued'
            ? 'Accepted by bridge. Check the chat for progress.'
            : 'Message accepted by bridge.';
        message.clear();
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => result =
              'Send not confirmed: $e. Check the chat before sending again.',
        );
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Color _agentColor(String? status) => switch (status) {
    'working' || 'running' => mint,
    'needs_attention' => Colors.orangeAccent,
    'error' => Colors.redAccent,
    _ => muted,
  };
}

/// A tap recognizer arbitrates against scrolling and owns its primary pointer.
/// Release is sent for cancellation, disable and disposal as well as touch-up.
class HoldControl extends StatefulWidget {
  const HoldControl({
    super.key,
    required this.enabled,
    required this.onChanged,
    required this.onTap,
    required this.label,
    required this.icon,
    this.accent = cream,
    this.subtitle,
    this.compact = false,
  });
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final VoidCallback onTap;
  final String label;
  final IconData icon;
  final Color accent;
  final String? subtitle;
  final bool compact;
  @override
  State<HoldControl> createState() => _HoldControlState();
}

class _HoldControlState extends State<HoldControl> {
  bool pointerHeld = false;
  LogicalKeyboardKey? keyboardKey;
  bool get keyboardHeld => keyboardKey != null;

  void release() {
    if (!pointerHeld && !keyboardHeld) return;
    pointerHeld = false;
    keyboardKey = null;
    widget.onChanged(false);
  }

  void releasePointer() {
    if (pointerHeld) setState(release);
  }

  @override
  void didUpdateWidget(HoldControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) release();
  }

  @override
  void dispose() {
    release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: widget.enabled,
    label: widget.label,
    onTap: widget.enabled ? widget.onTap : null,
    child: Focus(
      onFocusChange: (focused) {
        if (!focused && keyboardHeld) setState(release);
      },
      onKeyEvent: (_, event) {
        if (!widget.enabled ||
            (event.logicalKey != LogicalKeyboardKey.enter &&
                event.logicalKey != LogicalKeyboardKey.space)) {
          return KeyEventResult.ignored;
        }
        if (event is KeyDownEvent && !pointerHeld && !keyboardHeld) {
          setState(() => keyboardKey = event.logicalKey);
          widget.onChanged(true);
        }
        if (event is KeyUpEvent && event.logicalKey == keyboardKey) {
          setState(release);
        }
        return KeyEventResult.handled;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTapDown: widget.enabled
            ? (_) {
                if (pointerHeld || keyboardHeld) return;
                setState(() => pointerHeld = true);
                widget.onChanged(true);
              }
            : null,
        onTapUp: widget.enabled ? (_) => releasePointer() : null,
        onTapCancel: widget.enabled ? releasePointer : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          padding: EdgeInsets.all(widget.compact ? 10 : 12),
          decoration: BoxDecoration(
            color: pointerHeld || keyboardHeld
                ? widget.accent.withValues(alpha: .20)
                : panel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: pointerHeld || keyboardHeld
                  ? widget.accent
                  : Colors.white12,
            ),
          ),
          child: Opacity(
            opacity: widget.enabled ? 1 : .4,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: widget.compact
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: [
                Icon(
                  widget.icon,
                  color: widget.accent,
                  size: widget.compact ? 23 : 24,
                ),
                SizedBox(height: widget.compact ? 4 : 8),
                Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: widget.compact ? 13 : 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (widget.subtitle != null)
                  Text(
                    widget.subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: muted, fontSize: 10),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class ConnectionSheet extends StatefulWidget {
  const ConnectionSheet({super.key, required this.hid});
  final HidService hid;
  @override
  State<ConnectionSheet> createState() => _ConnectionSheetState();
}

class _ConnectionSheetState extends State<ConnectionSheet> {
  List<Map<String, dynamic>> devices = [];
  @override
  void initState() {
    super.initState();
    widget.hid.addListener(_changed);
    unawaited(_refresh());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    await widget.hid.refresh();
    final value = await widget.hid.devices();
    if (mounted) setState(() => devices = value);
  }

  @override
  void dispose() {
    widget.hid.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hid = widget.hid;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .9,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Pair with your Mac',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('BLE HID')),
                  ButtonSegment(value: false, label: Text('Classic HID')),
                ],
                selected: {hid.isBle},
                onSelectionChanged: (value) => hid.setTransport(value.first),
              ),
              const SizedBox(height: 12),
              Text(
                hid.isBle
                    ? '1. Start BLE HID.\n2. On your Mac, open Bluetooth settings and pair with Codex Micro Tablet. Forget an old tablet pairing first if needed.\n3. Open Codex’s Micro settings. Your Mac initiates the BLE connection.'
                    : '1. Start HID and make the tablet discoverable.\n2. On your Mac, open Bluetooth settings and pair with this tablet.\n3. Select the paired Mac below, then open Codex’s Micro settings.',
                style: TextStyle(color: muted, height: 1.6),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: hid.start,
                    icon: const Icon(Icons.power_settings_new),
                    label: Text(hid.isBle ? 'Start BLE HID' : 'Start HID'),
                  ),
                  if (!hid.isBle)
                    OutlinedButton(
                      onPressed: hid.registered ? hid.discoverable : null,
                      child: const Text('Make discoverable'),
                    ),
                  TextButton(
                    onPressed: hid.settings,
                    child: const Text('Bluetooth settings'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'HID profile: ${hid.registered ? "registered" : "not registered"}  ·  Bluetooth: ${hid.connected ? "connected" : "not connected"}',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
              Text(
                'Micro discovery: ${hid.discovered ? "received" : "waiting"}  ·  Reports RX ${hid.state['rxReports'] ?? 0} / TX ${hid.state['txReports'] ?? 0}',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
              if (hid.isBle)
                Text(
                  'BLE advertising: ${hid.advertising ? "active" : "off"}  ·  MTU ${hid.state['mtu'] ?? 23}',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              if (hid.error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    hid.error,
                    style: const TextStyle(color: Colors.orangeAccent),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      hid.isBle
                          ? 'Paired computers · connect from Mac'
                          : 'Paired computers',
                    ),
                  ),
                  IconButton(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh paired devices',
                  ),
                ],
              ),
              if (devices.isEmpty)
                const Text(
                  'No paired devices yet. Pair from macOS, then refresh.',
                  style: TextStyle(color: muted),
                ),
              for (final device in devices)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.computer),
                  title: Text((device['name'] ?? 'Paired device').toString()),
                  subtitle: Text((device['address'] ?? '').toString()),
                  trailing: hid.isBle
                      ? null
                      : TextButton(
                          onPressed: hid.registered
                              ? () => hid.connect(device['address'].toString())
                              : null,
                          child: const Text('Connect'),
                        ),
                ),
              if (hid.connected)
                TextButton(
                  onPressed: hid.disconnect,
                  child: const Text('Disconnect'),
                ),
              const SizedBox(height: 16),
              Text(
                hid.isBle
                    ? 'BLE advertises the Micro vendor and product identity. Pairing and a successful Micro discovery exchange are both needed before controls become available.'
                    : 'Classic HID uses Android’s device identity. A Bluetooth connection alone does not confirm Micro compatibility.',
                style: TextStyle(color: muted, fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
