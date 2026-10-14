import 'package:dart_jellyfin/dart_jellyfin.dart';
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
  final _server = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _fields = [
    FocusNode(),
    FocusNode(),
    FocusNode(),
  ]; // server, username, password
  bool _busy = false;
  double _keyboard =
      0; // the on-screen keyboard's height, last time it was looked at

  @override
  void initState() {
    super.initState();
    if (jellyfin.lastServer != null) {
      _server.text = displayServerUrl(jellyfin.lastServer!);
    }
    for (final node in _fields) {
      node.addListener(_revealField);
    }
  }

  @override
  void dispose() {
    _server.dispose();
    for (final node in _fields) {
      node.dispose();
    }
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Whether there's somewhere to go back to: the signed-in user (adding an account)
  /// or the other accounts saved on this device.
  bool get _canGoBack => jellyfin.isConnected || jellyfin.accounts.isNotEmpty;

  void _goBack() => context.go(jellyfin.isConnected ? '/home' : '/profiles');

  /// Scrolls the field being typed in to the middle of the space the keyboard leaves, once
  /// that space has settled: on moving to a field, and as the keyboard opens or resizes.
  void _revealField() => WidgetsBinding.instance.addPostFrameCallback((_) {
    final field = _fields.where((node) => node.hasFocus).firstOrNull?.context;
    if (field != null && field.mounted) {
      Scrollable.ensureVisible(
        field,
        alignment: 0.5,
        duration: const Duration(milliseconds: 200),
      );
    }
  });

  Future<void> _signIn() async {
    // Caught here, since the server's own answer to these is a bare "400".
    final missing = _missing(username: true);
    if (missing != null) return _showSignInError(context, missing);
    setState(() => _busy = true);
    try {
      await jellyfin.signIn(
        server: _server.text,
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

  /// What's still to fill in before signing in, if anything.
  String? _missing({required bool username}) {
    if (_server.text.trim().isEmpty) return 'Enter your server\'s address.';
    if (username && _username.text.trim().isEmpty) return 'Enter your username.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // Read above the Scaffold, which hides the keyboard from the page as it makes room for it.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    if (keyboard != _keyboard) {
      _keyboard = keyboard;
      _revealField();
    }
    return Scaffold(
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
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 12,
                          children: [
                            Text(
                              jellyfin.isConnected
                                  ? 'Add an Account'
                                  : 'Connect to Server',
                              style: context.text.titleMedium,
                            ),
                            Text(
                              jellyfin.isConnected
                                  ? 'Sign in another user. Everyone stays saved on this device.'
                                  : 'Enter your server address and account.',
                              style: context.text.bodyMedium?.copyWith(
                                color: context.colors.onSurfaceVariant,
                              ),
                            ),
                            // The port goes in here too, if it isn't Jellyfin's 8096.
                            TextField(
                              controller: _server,
                              focusNode: _fields[0],
                              enabled: !_busy,
                              keyboardType: TextInputType.url,
                              autocorrect: false,
                              decoration: const InputDecoration(
                                label: Text('Server'),
                                hintText: '192.168.1.100:8096',
                              ),
                            ),
                            TextField(
                              controller: _username,
                              focusNode: _fields[1],
                              enabled: !_busy,
                              decoration: InputDecoration(
                                label: const Text('Username'),
                              ),
                            ),
                            TextField(
                              controller: _password,
                              focusNode: _fields[2],
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
                                      final missing = _missing(username: false);
                                      if (missing != null) {
                                        return _showSignInError(context, missing);
                                      }
                                      final signedIn = await showQuickConnect(
                                        context,
                                        server: _server.text,
                                      );
                                      if (signedIn && context.mounted) {
                                        context.go('/home');
                                      }
                                    },
                              child: const Text('Use Quick Connect'),
                            ),
                            if (_canGoBack)
                              OutlinedButton(
                                onPressed: _busy ? null : _goBack,
                                child: Text(
                                  jellyfin.isConnected ? 'Cancel' : "Back",
                                ),
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
      ),
    );
  }
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
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 8,
                  children: [
                    Text("Couldn't sign in", style: context.text.titleLarge),
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
                        autofocus:
                            true, // Select or Enter closes it straight away
                        onPressed: () => Navigator.of(context).pop(),
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
