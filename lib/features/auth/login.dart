import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/jellyfin/jellyfin_controller.dart';
import 'quick_connect_dialog.dart';
import '../../widgets/app_logo.dart';
import '../../theme/theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final _host = TextEditingController();
  late final _port = TextEditingController(text: '8096');
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (jellyfin.lastServer != null) {
      final (host, port) = splitServerUrl(jellyfin.lastServer!);
      _host.text = host;
      _port.text = port;
    }
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Whether there's somewhere to go back to: the signed-in user (adding an account)
  /// or the other accounts saved on this device.
  bool get _canGoBack => jellyfin.isConnected || jellyfin.accounts.isNotEmpty;

  void _goBack() => context.go(jellyfin.isConnected ? '/home' : '/profiles');

  Future<void> _signIn() async {
    setState(() => _busy = true);
    try {
      await jellyfin.signIn(
        server: composeServerUrl(_host.text, _port.text),
        username: _username.text.trim(),
        password: _password.text,
      );
      if (mounted) context.go('/home');
    } on JellyfinException catch (e) {
      if (mounted) await _showSignInError(context, _signInErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppLogo(
                  asset: 'assets/images/text_logo.svg',
                  colorAsset: 'assets/images/text_logo_color.svg',
                  height: 48,
                  variant: AppLogoVariant.auto,
                ),
                const SizedBox(height: 24),
                Card(child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 12,
                      children: [
                        Text(
                          jellyfin.isConnected ? 'Add an Account' : 'Connect to Server',
                          style: context.text.titleMedium,
                        ),
                        Text(
                          jellyfin.isConnected
                              ? 'Sign in another user. Everyone stays saved on this device.'
                              : 'Enter your server address and account.',
                          style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 8,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _host,
                                enabled: !_busy,
                                decoration: InputDecoration(
                                  label: const Text('Host'),
                                  hintText: '192.168.1.100',
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 100,
                              child: TextField(
                                controller: _port,
                                enabled: !_busy,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: InputDecoration(
                                  label: const Text('Port'),
                                  hintText: '8096',
                                ),
                              ),
                            ),
                          ],
                        ),
                        TextField(
                          controller: _username,
                          enabled: !_busy,
                          decoration: InputDecoration(
                            label: const Text('Username'),
                          ),
                        ),
                        TextField(
                          controller: _password,
                          enabled: !_busy,
                          obscureText: true,
                          decoration: InputDecoration(
                            label: const Text('Password'),
                          ),
                        ),
                        FilledButton(
                          onPressed: _busy ? null : _signIn,
                          child: Text(_busy ? 'Connecting…' : 'Sign in'),
                        ),
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () async {
                            final signedIn = await showQuickConnect(
                              context,
                              server: composeServerUrl(_host.text, _port.text),
                            );
                            if (signedIn && context.mounted) context.go('/home');
                          },
                          child: const Text('Use Quick Connect'),
                        ),
                        if (_canGoBack)
                          OutlinedButton(
                            onPressed: _busy ? null : _goBack,
                            child: Text(jellyfin.isConnected ? 'Cancel' : "Back"),
                          ),
                      ],
                    ),
                  )),
              ],
            ),
          ),
        ),
      ),
    ),
    ),
  );
}

/// A dialog explaining why signing in failed, with an OK button.
Future<void> _showSignInError(BuildContext context, String message) =>
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: context.colors.scrim,
      transitionDuration: const Duration(milliseconds: 150),
      transitionBuilder: (context, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
      pageBuilder: (context, _, _) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Card(child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 8,
                  children: [
                    Text(
                      "Couldn't sign in",
                      style: context.text.titleLarge,
                    ),
                    Text(
                      message,
                      style: context.text.bodyLarge?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        autofocus: true, // Select or Enter closes it straight away
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('OK'),
                      ),
                    ),
                  ],
                ),
              )),
          ),
        ),
      ),
    );

/// Turns whatever went wrong into something a person can act on.
String _signInErrorMessage(Object error) {
  if (error is JellyfinException) {
    final text = describeJellyfinError(error);
    final lower = text.toLowerCase();
    if (lower.contains('401') || lower.contains('unauthorized')) {
      return 'The username or password is incorrect.';
    }
    return text;
  }
  // Anything else is almost always the connection itself: a wrong address or port,
  // the server being off, or the device not being on the same network.
  return "Couldn't reach the server. Check the address and port, and that the server is running.";
}