import 'package:chameleon/widgets/app_logo.dart';
import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../utils/jellyfin_controller.dart';

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
      setState(() => _error = describeJellyfinError(e));
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
                    height: 48
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
                        Text('Connect to Server', style: style.titleTextStyle),
                        Text('Enter your server address and account.', style: style.subtitleTextStyle),
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
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
                          Text(_error!, style: TextStyle(color: context.theme.colors.error)),
                        FButton(
                          onPress: _busy ? null : _signIn,
                          child: Text(_busy ? 'Connecting…' : 'Sign in'),
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