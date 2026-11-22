import 'dart:async';

import 'package:flutter/material.dart';

import '../controller/drive_controller.dart';
import '../transport/ble_transport.dart';
import '../transport/robot_transport.dart';
import 'widgets/hud_widgets.dart';

/// Connection dialog.
///
/// Two cards: Wi-Fi UDP (primary) and Bluetooth LE (manual backup). It shows
/// the difference between *radio connected* and *live telemetry*, because a
/// bound socket or a connected peripheral is not a robot link.
class ConnectionPopup extends StatefulWidget {
  const ConnectionPopup({super.key, required this.controller});

  final DriveController controller;

  /// Convenience wrapper used by the HUD status pill.
  static Future<void> show(BuildContext context, DriveController controller) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) => ConnectionPopup(controller: controller),
    );
  }

  @override
  State<ConnectionPopup> createState() => _ConnectionPopupState();
}

class _ConnectionPopupState extends State<ConnectionPopup> {
  StreamSubscription<List<BleScanHit>>? _scanSubscription;
  List<BleScanHit> _hits = <BleScanHit>[];
  bool _scanning = false;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _scanSubscription = widget.controller.bleScanResults.listen(
      (List<BleScanHit> hits) {
        if (!mounted) {
          return;
        }
        setState(() => _hits = hits);
      },
      onError: (Object error) {
        if (!mounted) {
          return;
        }
        setState(() {
          _scanning = false;
          _busy = 'BLE SCAN ERROR: $error';
        });
      },
    );
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    widget.controller.stopBleScan();
    super.dispose();
  }

  Future<void> _connectUdp() async {
    setState(() => _busy = 'OPENING UDP LINK...');
    try {
      await widget.controller.connectUdp();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = 'UDP FAILED: $error');
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _busy = null);
    Navigator.of(context).maybePop();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _busy = null;
      _hits = <BleScanHit>[];
    });
    try {
      await widget.controller.startBleScan();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _scanning = false;
        _busy = 'BLE UNAVAILABLE: $error';
      });
      return;
    }
    // The scan stops itself after the timeout inside BleTransport.
    Future<void>.delayed(const Duration(seconds: 7), () {
      if (mounted) {
        setState(() => _scanning = false);
      }
    });
  }

  Future<void> _connectBle(BleScanHit hit) async {
    setState(() => _busy = 'CONNECTING TO ${hit.name}...');
    try {
      await widget.controller.connectBle(hit.deviceId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = 'BLE FAILED: $error');
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _busy = null);
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (BuildContext context, Widget? _) {
        final DriveController c = widget.controller;
        final TransportKind? kind = c.transportKind;
        final bool udpActive = kind == TransportKind.udp;
        final bool bleActive = kind == TransportKind.ble;

        return AlertDialog(
          backgroundColor: TacticalColors.surface,
          surfaceTintColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(12),
          titlePadding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
          contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          title: Row(
            children: <Widget>[
              const Icon(Icons.settings_input_antenna,
                  size: 18, color: TacticalColors.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'RADIO LINK',
                  style: TextStyle(
                    color: TacticalColors.text,
                    fontSize: 15,
                    letterSpacing: 2.0,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close, size: 18, color: TacticalColors.muted),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _LinkCard(
                    title: 'Wi-Fi UDP',
                    badge: 'PRIMARY',
                    badgeColor: TacticalColors.primary,
                    active: udpActive,
                    detail: 'SSID ROBORACE_ESP32  ·  192.168.4.1:4210\n'
                        'Password race2025  ·  channel 1',
                    hint: 'Join the robot AP in the phone Wi-Fi settings. '
                        'Choose "Stay connected without internet" on Android.',
                    onPrimary: udpActive ? null : _connectUdp,
                    primaryLabel: udpActive ? 'ACTIVE' : 'CONNECT',
                    onSecondary: udpActive
                        ? () async {
                            await c.disconnectTransport();
                            if (mounted) {
                              setState(() {});
                            }
                          }
                        : null,
                    secondaryLabel: 'DISCONNECT',
                    spinner: _busy != null && _busy!.contains('UDP'),
                  ),
                  const SizedBox(height: 10),
                  _LinkCard(
                    title: 'Bluetooth LE',
                    badge: 'BACKUP',
                    badgeColor: TacticalColors.amber,
                    active: bleActive,
                    detail: 'Device ROBORACE_ESP32  ·  manual fallback only\n'
                        'Service 0000abcd-...-00805f9b34fb',
                    hint: 'No automatic failover. Switching closes the UDP '
                        'link and requires a new arm.',
                    onPrimary: _scanning ? null : _scan,
                    primaryLabel: _scanning ? 'SCANNING...' : 'SCAN',
                    onSecondary: bleActive
                        ? () async {
                            await c.disconnectTransport();
                            if (mounted) {
                              setState(() {});
                            }
                          }
                        : null,
                    secondaryLabel: 'DISCONNECT',
                    spinner: _scanning,
                  ),
                  if (_hits.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    const SectionLabel('DISCOVERED PERIPHERALS'),
                    const SizedBox(height: 4),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 130),
                      decoration: BoxDecoration(
                        color: TacticalColors.background.withA(0.5),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: TacticalColors.line),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _hits.length,
                        itemBuilder: (BuildContext context, int index) {
                          final BleScanHit hit = _hits[index];
                          return ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            leading: Icon(
                              Icons.bluetooth,
                              size: 16,
                              color: hit.hasControlService
                                  ? TacticalColors.green
                                  : TacticalColors.muted,
                            ),
                            title: Text(
                              hit.name,
                              style: const TextStyle(
                                color: TacticalColors.text,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              '${hit.deviceId}  ·  ${hit.rssi} dBm',
                              style: TextStyle(
                                color: TacticalColors.muted.withA(0.9),
                                fontSize: 9,
                              ),
                            ),
                            trailing: TextButton(
                              onPressed: _busy == null
                                  ? () => _connectBle(hit)
                                  : null,
                              child: const Text('CONNECT'),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  if (_busy != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      _busy!,
                      style: const TextStyle(
                        color: TacticalColors.amber,
                        fontSize: 10,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  _DiagnosticsStrip(controller: c),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({
    required this.title,
    required this.badge,
    required this.badgeColor,
    required this.active,
    required this.detail,
    required this.hint,
    required this.onPrimary,
    required this.primaryLabel,
    required this.onSecondary,
    required this.secondaryLabel,
    required this.spinner,
  });

  final String title;
  final String badge;
  final Color badgeColor;
  final bool active;
  final String detail;
  final String hint;
  final VoidCallback? onPrimary;
  final String primaryLabel;
  final VoidCallback? onSecondary;
  final String secondaryLabel;
  final bool spinner;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: TacticalColors.background.withA(0.55),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: active ? badgeColor : TacticalColors.line,
          width: active ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                title,
                style: TextStyle(
                  color: TacticalColors.text.withA(0.95),
                  fontSize: 12,
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withA(0.16),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: badgeColor.withA(0.7)),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 8,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              if (spinner)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: TacticalColors.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            style: TextStyle(
              color: TacticalColors.muted.withA(0.95),
              fontSize: 10,
              height: 1.35,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hint,
            style: TextStyle(
              color: TacticalColors.muted.withA(0.75),
              fontSize: 9,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              ElevatedButton(
                onPressed: onPrimary,
                style: ElevatedButton.styleFrom(
                  backgroundColor: badgeColor.withA(0.20),
                  foregroundColor: badgeColor,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  minimumSize: const Size(0, 30),
                ),
                child: Text(
                  primaryLabel,
                  style: const TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (onSecondary != null)
                TextButton(
                  onPressed: onSecondary,
                  style: TextButton.styleFrom(
                    foregroundColor: TacticalColors.red,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 30),
                  ),
                  child: Text(
                    secondaryLabel,
                    style: const TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DiagnosticsStrip extends StatelessWidget {
  const _DiagnosticsStrip({required this.controller});

  final DriveController controller;

  @override
  Widget build(BuildContext context) {
    final DriveController c = controller;
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: <Widget>[
        _Diag('STATUS', c.transportDetail,
            c.isLinkLive ? TacticalColors.green : TacticalColors.amber),
        _Diag('RTT', c.rttMs == null ? '--' : '${c.rttMs} ms', TacticalColors.text),
        _Diag('DROPS', '${c.firmwareDrops}', TacticalColors.text),
        _Diag('TX', '${c.txPackets}', TacticalColors.text),
        _Diag('RX', '${c.rxPackets}', TacticalColors.text),
        _Diag('STATE', c.telemetryStateLabel,
            c.armedConfirmed ? TacticalColors.green : TacticalColors.text),
      ],
    );
  }
}

class _Diag extends StatelessWidget {
  const _Diag(this.label, this.value, this.color);

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            color: TacticalColors.muted.withA(0.85),
            fontSize: 8,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
