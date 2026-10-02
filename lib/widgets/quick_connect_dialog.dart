import 'dart:async';

import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../utils/jellyfin_controller.dart';

/// Shows a Quick Connect code for [server] and waits for the user to approve it
/// from another device. Returns true once signed in, false if cancelled.
///
/// After it returns true, do whatever your login screen does after a normal sign-in.
Future<bool> showQuickConnect(BuildContext context, {required String server}) async {
  final result = await showFDialog<bool>(
    context: context,
    barrierDismissible: false, // only Cancel or success closes it, so polling always stops
    builder: (context, style, animation) => FDialog(
      animation: animation,
      builder: (context, _) => _QuickConnectBody(server: server),
    ),
  );
  return result ?? false;
}

class _QuickConnectBody extends StatefulWidget {
  const _QuickConnectBody({required this.server});

  final String server;

  @override
  State<_QuickConnectBody> createState() => _QuickConnectBodyState();
}

class _QuickConnectBodyState extends State<_QuickConnectBody> {
  static const _pollEvery = Duration(seconds: 3);

  QuickConnectRequest? _request;
  String? _error;
  bool _signingIn = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Gets a fresh code and starts checking for approval.
  Future<void> _start() async {
    _timer?.cancel();
    setState(() {
      _request = null;
      _error = null;
    });
    try {
      final request = await jellyfin.startQuickConnect(widget.server);
      if (!mounted) return;
      setState(() => _request = request);
      _timer = Timer.periodic(_pollEvery, (_) => _check());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _check() async {
    final request = _request;
    if (request == null || _signingIn) return;
    try {
      if (!await jellyfin.isQuickConnectApproved(request)) return;
      _timer?.cancel();
      if (mounted) setState(() => _signingIn = true);
      await jellyfin.finishQuickConnect(request);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _timer?.cancel();
      if (mounted) {
        setState(() {
          _signingIn = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final muted = theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground);
    final request = _request;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        spacing: 12,
        children: [
          Text('Quick Connect', style: theme.typography.display.lg),

          if (_error != null) ...[
            Text(_error!, style: muted.copyWith(color: theme.colors.error)),
          ] else if (request == null || _signingIn) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: FCircularProgress()),
            ),
            if (_signingIn) Text('Signing in…', textAlign: TextAlign.center, style: muted),
          ] else ...[
            Text(
              'On a device that\'s already signed in, open Quick Connect and enter this code.',
              style: muted,
            ),
            // The code, big enough to read from the couch.
            Center(
              child: Text(
                request.code,
                style: theme.typography.display.xl4.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 8,
                  color: theme.colors.primary,
                ),
              ),
            ),
            Text(
              'In the Jellyfin web app it\'s under your profile → Quick Connect. '
                  'In Chameleon, it\'s in Settings → Account.',
              style: muted,
            ),
            Text('Waiting for approval…', textAlign: TextAlign.center, style: muted),
          ],

          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: .end,
            spacing: 8,
            children: [
              if (_error != null)
                FButton(
                  variant: .outline,
                  mainAxisSize: .min,
                  onPress: _start,
                  child: const Text('Get a new code'),
                ),
              FButton(
                variant: _error != null ? .ghost : .outline,
                mainAxisSize: .min,
                autofocus: true, // so a remote can cancel straight away
                onPress: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}