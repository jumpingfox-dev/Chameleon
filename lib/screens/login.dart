import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../utils/jellyfin_controller.dart';
import '../widgets/quick_connect_dialog.dart';
import '../widgets/app_logo.dart';

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
  String? _error;

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
    setState(() {
      _busy = true;
      _error = null;
    });
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
  Widget build(BuildContext context) => FScaffold(
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
                FCard(
                  builder: (context, style, _) => Padding(
                    padding: style.padding,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 12,
                      children: [
                        Text(
                          jellyfin.isConnected ? 'Add an Account' : 'Connect to Server',
                          style: style.titleTextStyle,
                        ),
                        Text(
                          jellyfin.isConnected
                              ? 'Sign in another user. Everyone stays saved on this device.'
                              : 'Enter your server address and account.',
                          style: style.subtitleTextStyle,
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 8,
                          children: [
                            Expanded(
                              child: FTextField(
                                control: .managed(controller: _host),
                                label: const Text('Host'),
                                hint: '192.168.1.100',
                                enabled: !_busy,
                              ),
                            ),
                            SizedBox(
                              width: 100,
                              child: FTextField(
                                control: .managed(controller: _port),
                                label: const Text('Port'),
                                hint: '8096',
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                enabled: !_busy,
                              ),
                            ),
                          ],
                        ),
                        FTextField(
                          control: .managed(controller: _username),
                          label: const Text('Username'),
                          enabled: !_busy,
                        ),
                        FTextField.password(
                          control: .managed(controller: _password),
                          label: const Text('Password'),
                          enabled: !_busy,
                        ),
                        if (_error != null)
                          Text(
                            _error!,
                            style: TextStyle(color: context.theme.colors.error),
                          ),
                        FButton(
                          onPress: _busy ? null : _signIn,
                          child: Text(_busy ? 'Connecting…' : 'Sign in'),
                        ),
                        FButton(
                          variant: .outline,
                          onPress: _busy
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
                          FButton(
                            variant: .outline,
                            onPress: _busy ? null : _goBack,
                            child: Text(jellyfin.isConnected ? 'Cancel' : "Back"),
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
    ),
  );
}

/// A dialog explaining why signing in failed, with an OK button.
Future<void> _showSignInError(BuildContext context, String message) =>
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: context.theme.colors.barrier,
      transitionDuration: const Duration(milliseconds: 150),
      transitionBuilder: (context, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
      pageBuilder: (context, _, _) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FCard(
              builder: (context, style, _) => Padding(
                padding: style.padding,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 8,
                  children: [
                    Text(
                      "Couldn't sign in",
                      style: context.theme.typography.display.lg,
                    ),
                    Text(
                      message,
                      style: context.theme.typography.body.md.copyWith(
                        color: context.theme.colors.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FButton(
                        autofocus:
                        true, // Select or Enter closes it straight away
                        mainAxisSize: .min,
                        onPress: () => Navigator.of(context).pop(),
                        child: const Text('OK'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
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