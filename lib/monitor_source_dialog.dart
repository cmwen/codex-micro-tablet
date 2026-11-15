import 'dart:async';

import 'package:flutter/material.dart';

import 'bridge_client.dart';
import 'services/local_discovery.dart';

/// Chooses a read-only monitor source.
///
/// Two contracts are kept apart: the legacy FNK0104B bridge (manual address plus a
/// shared monitor key, which also carries prompt delivery) and the Agent Deck LAN
/// read-only snapshot, which is discovered with DNS-SD and verified over HTTPS before
/// anything is saved. Discovery results are untrusted candidates and require an
/// explicit choice; no key is ever sent to a discovered service.
class MonitorSourceDialog extends StatefulWidget {
  const MonitorSourceDialog({super.key, required this.bridge, this.discovery});

  final BridgeClient bridge;
  final LocalServiceDiscovery? discovery;

  @override
  State<MonitorSourceDialog> createState() => _MonitorSourceDialogState();
}

class _MonitorSourceDialogState extends State<MonitorSourceDialog> {
  static const muted = Color(0xffa8bce4);
  static const cyan = Color(0xff31e8ec);
  // The manual fields describe the bridge contract only; a read-only origin must not
  // be suggested as a bridge address.
  late final TextEditingController _url = TextEditingController(
    text: widget.bridge.readOnly ? '' : widget.bridge.baseUrl,
  );
  late final TextEditingController _key = TextEditingController(
    text: widget.bridge.readOnly ? '' : widget.bridge.token,
  );
  List<DiscoveredService>? _services;
  String? _note, _validation;
  bool _searching = false, _saving = false;
  String? _connecting;

  LocalServiceDiscovery get _discovery =>
      widget.discovery ?? const LocalServiceDiscovery();

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _searching = true;
      _note = null;
      _validation = null;
    });
    try {
      final services = await _discovery.discover();
      if (!mounted) return;
      setState(() {
        _services = services;
        _note = services.isEmpty
            ? 'No services answered on this network. Use the manual address below.'
            : null;
      });
    } on DiscoveryException catch (error) {
      if (mounted) setState(() => _note = error.message);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _use(DiscoveredService service) async {
    final origin = service.httpsOrigin;
    if (origin == null) return;
    setState(() {
      _connecting = service.name;
      _validation = null;
      _note = 'Verifying ${origin.host} over HTTPS…';
    });
    try {
      await widget.bridge.configureReadOnly(origin.toString());
      if (!mounted) return;
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _connecting = null;
        _note = null;
        _validation = error is FormatException
            ? error.message
            : 'Could not verify that service.';
      });
    }
  }

  Future<void> _saveBridge() async {
    setState(() {
      _saving = true;
      _validation = null;
    });
    try {
      await widget.bridge.configure(_url.text.trim(), _key.text);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _validation = error is FormatException || error is StateError
            ? error.toString()
            : 'Could not save the bridge settings.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bridge = widget.bridge;
    final busy = _connecting != null;
    return AlertDialog(
      title: const Text('Monitor source'),
      // The dialog must stay reachable on a short landscape screen and in portrait.
      scrollable: true,
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              bridge.baseUrl.isEmpty
                  ? 'No monitor source is configured.'
                  : 'Now using ${bridge.sourceLabel}${bridge.readOnly ? ' (read-only)' : ''}: ${bridge.baseUrl}',
              style: const TextStyle(color: muted),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Read-only monitor on this network',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _searching || busy ? null : _search,
                  icon: _searching
                      ? const SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_find, size: 18),
                  label: Text(_searching ? 'Searching…' : 'Find services'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Uses DNS-SD to list services advertised on this LAN. A candidate is only '
              'saved after its HTTPS origin answers the Agent Deck read-only API.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
            if (_services != null) ...[
              const SizedBox(height: 8),
              if (_services!.isEmpty)
                Text(
                  'Nothing advertised was found.',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              for (final service in _services!)
                _serviceRow(service, busy: busy),
            ],
            if (_note != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _note!,
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 8),
            const Text(
              'Codex bridge (manual)',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'The FNK0104B bridge also accepts follow-up prompts. It is not advertised, '
              'so enter its address and shared monitor key; Bluetooth controls work independently.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Bridge address',
                hintText: 'http://192.168.1.20:8765',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _key,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: 'Monitor key'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Your tablet must reach the source over Wi-Fi. Use HTTPS or a trusted private network.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
            if (_validation != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _validation!,
                  style: const TextStyle(color: Colors.orangeAccent),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: _saving || busy ? null : _saveBridge,
          child: Text(_saving ? 'Connecting…' : 'Save & connect'),
        ),
      ],
    );
  }

  Widget _serviceRow(DiscoveredService service, {required bool busy}) {
    final origin = service.httpsOrigin;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xff355a91)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            origin == null ? Icons.lan_outlined : Icons.dns_outlined,
            color: origin == null ? muted : cyan,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  origin == null
                      ? '${service.host}:${service.port} · no HTTPS origin'
                      : 'Read-only · ${origin.host}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: muted, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (origin == null)
            const Text(
              'Not a monitor',
              style: TextStyle(color: muted, fontSize: 11),
            )
          else
            FilledButton(
              onPressed: busy || _saving ? null : () => _use(service),
              child: Text(_connecting == service.name ? 'Checking…' : 'Use'),
            ),
        ],
      ),
    );
  }
}
