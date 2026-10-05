import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/app_icons.dart';
import '../utils/jellyfin_controller.dart';
import 'app_logo.dart';
import 'quick_connect_dialog.dart';

// ─── "Who's watching?" ───────────────────────────────────────────────────────
//
// Shows everyone who can use the app on this device: accounts already signed in here
// (switch instantly) and the users the server lists on its login screen (sign in once).

/// The full-screen picker, shown at launch when this device has more than one account,
/// and after signing out while others are still saved. Route: `/profiles`.
class ProfilePickerScreen extends StatelessWidget {
  const ProfilePickerScreen({super.key});

  @override
  Widget build(BuildContext context) => FScaffold(
    child: SafeArea(
      child: ListenableBuilder(
        listenable: jellyfin,
        builder: (context, _) => Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: jellyfin.switching
                // Between two users: the router brings Home back as soon as the new one has loaded.
                ? const Column(
                    mainAxisSize: .min,
                    spacing: 16,
                    children: [FCircularProgress(), Text('Switching…')],
                  )
                : const Column(
                    mainAxisSize: .min,
                    children: [
                      AppLogo(
                        asset: 'assets/images/text_logo.svg',
                        colorAsset: 'assets/images/text_logo_color.svg',
                        height: 48,
                        variant: AppLogoVariant.auto,
                      ),
                      SizedBox(height: 32),
                      // TODO(cleanup): two gaps under the logo; one is a slip
                      SizedBox(height: 32),
                      ProfilePicker(),
                    ],
                  ),
          ),
        ),
      ),
    ),
  );
}

/// The same picker as a pop-up, for the Add User / Switch User button.
Future<void> showProfilePicker(BuildContext context) => showFDialog<void>(
  context: context,
  builder: (context, style, animation) => FDialog(
    animation: animation,
    constraints: const BoxConstraints(minWidth: 280, maxWidth: 760),
    builder: (context, _) => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: .min,
        children: [
          Text("Who's watching?", textAlign: TextAlign.center, style: context.theme.typography.display.xl3),
          const SizedBox(height: 24),
          const Flexible(child: SingleChildScrollView(child: ProfilePicker(inDialog: true))),
        ],
      ),
    ),
  ),
);

/// One person in the picker. At least one of [saved] or [public] is set.
class _Profile {
  const _Profile({required this.name, this.imageUrl, this.saved, this.public});

  final String name;
  final String? imageUrl;
  final SavedAccount? saved; // signed in on this device: switch without a password
  final PublicUser? public; // listed by the server: can sign in

  bool get isCurrent {
    final current = jellyfin.currentAccount;
    return current != null && saved != null && current.isSame(saved!.server, saved!.userId);
  }

  String get key => saved != null ? '${saved!.server}|${saved!.userId}' : '${public!.server}|${public!.id}';
}

/// The row of avatar tiles, plus Add Account.
class ProfilePicker extends StatefulWidget {
  const ProfilePicker({super.key, this.inDialog = false});

  final bool inDialog;

  @override
  State<ProfilePicker> createState() => _ProfilePickerState();
}

class _ProfilePickerState extends State<ProfilePicker> {
  List<PublicUser> _public = const [];
  bool _loadingPublic = true;
  String? _busyKey; // the tile being signed in, shows a spinner
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPublicUsers();
  }

  Future<void> _loadPublicUsers() async {
    final server = jellyfin.client?.baseUrl ?? jellyfin.lastServer;
    final users = server == null ? const <PublicUser>[] : await jellyfin.publicUsers(server);
    if (mounted) {
      setState(() {
        _public = users;
        _loadingPublic = false;
      });
    }
  }

  /// Saved accounts first (in the order they were added), then server users not yet signed in here.
  List<_Profile> get _profiles => [
    for (final a in jellyfin.accounts)
      _Profile(
        name: a.name,
        imageUrl: a.imageUrl,
        saved: a,
        public: _public.where((p) => p.server == a.server && p.id == a.userId).firstOrNull,
      ),
    for (final p in _public)
      if (!jellyfin.accounts.any((a) => a.isSame(p.server, p.id)))
        _Profile(name: p.name, imageUrl: p.imageUrl, public: p),
  ];

  Future<void> _select(_Profile profile) async {
    if (_busyKey != null) return;
    if (profile.isCurrent) {
      if (widget.inDialog) Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busyKey = profile.key;
      _error = null;
    });
    final before = jellyfin.currentAccount;

    try {
      if (profile.saved != null) {
        try {
          await jellyfin.switchTo(profile.saved!);
        } on AccountExpiredException {
          // Its token died. If the server lists this user, ask for their password instead.
          final public = profile.public;
          if (public == null) rethrow;
          if (mounted) setState(() => _busyKey = null);
          if (mounted) await _signInPublic(public);
        }
      } else {
        await _signInPublic(profile.public!);
      }
    } on AccountExpiredException catch (e) {
      if (mounted) setState(() => _error = '${profile.name}: $e');
    } on JellyfinException catch (e) {
      if (mounted) setState(() => _error = describeJellyfinError(e));
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
    // Switched: close the pop-up. The router moves to the new user's Home, but the pop-up
    // can sit above the whole app (opened from the sidebar), where that doesn't close it.
    final now = jellyfin.currentAccount;
    if (now != null && (before == null || !now.isSame(before.server, before.userId))) {
      _closeDialog();
    }
  }

  /// Users without a password sign straight in; everyone else gets the password box.
  Future<void> _signInPublic(PublicUser user) async {
    if (!user.hasPassword) {
      await jellyfin.signIn(server: user.server, username: user.name, password: '');
      return;
    }
    if (mounted) setState(() => _busyKey = null);
    if (!mounted) return;
    await _showPasswordDialog(context, user);
  }

  void _addAccount() {
    final router = GoRouter.of(context); // grabbed first: closing the pop-up unmounts this
    if (widget.inDialog) Navigator.of(context).pop();
    router.go('/login?add=1');
  }

  /// Closes the pop-up this picker is in, if it's still open. Removes exactly that pop-up,
  /// so nothing else gets closed if the router already took it down.
  void _closeDialog() {
    if (!widget.inDialog || !mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && route.isActive) Navigator.of(context).removeRoute(route);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: jellyfin,
    builder: (context, _) {
      final profiles = _profiles;
      return Column(
        mainAxisSize: .min,
        spacing: 16,
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 24,
            runSpacing: 24,
            children: [
              for (final (i, p) in profiles.indexed)
                _ProfileTile(
                  name: p.name,
                  imageUrl: p.imageUrl,
                  current: p.isCurrent,
                  busy: _busyKey == p.key,
                  autofocus: i == 0,
                  onPress: () => _select(p),
                ),
              _ProfileTile(
                name: 'Add account',
                icon: appIcons.addUser,
                autofocus: profiles.isEmpty,
                onPress: _addAccount,
              ),
            ],
          ),
          if (_loadingPublic && profiles.isEmpty) const FCircularProgress(),
          if (_error != null)
            Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: context.theme.colors.error)),
        ],
      );
    },
  );
}

// ─── A tile ──────────────────────────────────────────────────────────────────

/// A big round avatar with the name under it. Grows and gets a ring when focused,
/// so it's easy to see from across the room.
class _ProfileTile extends StatefulWidget {
  const _ProfileTile({
    required this.name,
    required this.onPress,
    this.imageUrl,
    this.icon,
    this.current = false,
    this.busy = false,
    this.autofocus = false,
  });

  final String name;
  final String? imageUrl;
  final IconData? icon; // instead of a picture, for Add account
  final bool current; // the user signed in now
  final bool busy;
  final bool autofocus;
  final VoidCallback onPress;

  @override
  State<_ProfileTile> createState() => _ProfileTileState();
}

class _ProfileTileState extends State<_ProfileTile> {
  static const _size = 112.0;
  bool _focused = false;
  bool _hovered = false;

  String get _initials {
    final parts = widget.name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return parts.length == 1 ? parts.first[0].toUpperCase() : (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final active = _focused || _hovered;
    final initials = Text(_initials, style: theme.typography.display.xl2);

    final Widget picture = widget.icon != null
        ? FAvatar.raw(size: _size, child: Icon(widget.icon, size: 44, fill: 1))
        : widget.imageUrl != null
        ? FAvatar(image: NetworkImage(widget.imageUrl!), fallback: initials, size: _size)
        : FAvatar.raw(size: _size, child: initials);

    return FocusableActionDetector(
      autofocus: widget.autofocus,
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      onShowHoverHighlight: (v) => setState(() => _hovered = v),
      mouseCursor: SystemMouseCursors.click,
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onPress()),
      },
      child: GestureDetector(
        onTap: widget.onPress,
        child: SizedBox(
          width: _size + 24,
          child: Column(
            mainAxisSize: .min,
            spacing: 10,
            children: [
              AnimatedScale(
                scale: active ? 1.08 : 1,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          width: 3,
                          color: active
                              ? theme.colors.primary
                              : widget.current
                              ? theme.colors.border
                              : Colors.transparent,
                        ),
                      ),
                      child: Opacity(opacity: widget.busy ? 0.4 : 1, child: picture),
                    ),
                    if (widget.busy) const FCircularProgress(),
                  ],
                ),
              ),
              Text(
                widget.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.typography.body.md.copyWith(
                  color: active ? theme.colors.foreground : theme.colors.mutedForeground,
                  fontWeight: active || widget.current ? FontWeight.w600 : null,
                ),
              ),
              if (widget.current)
                Text('Signed in', style: theme.typography.body.xs.copyWith(color: theme.colors.primary)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Password ────────────────────────────────────────────────────────────────

/// Asks for [user]'s password, with Quick Connect as the no-typing alternative.
Future<void> _showPasswordDialog(BuildContext context, PublicUser user) => showFDialog<void>(
  context: context,
  builder: (context, style, animation) => FDialog(
    animation: animation,
    builder: (context, _) => _PasswordBody(user: user),
  ),
);

class _PasswordBody extends StatefulWidget {
  const _PasswordBody({required this.user});

  final PublicUser user;

  @override
  State<_PasswordBody> createState() => _PasswordBodyState();
}

class _PasswordBodyState extends State<_PasswordBody> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await jellyfin.signIn(server: widget.user.server, username: widget.user.name, password: _password.text);
      if (mounted) Navigator.of(context).pop(); // usually already closed by the switch
    } on JellyfinException catch (e) {
      if (mounted) {
        setState(() => _error = e.isAuthError ? 'Wrong password. Try again.' : describeJellyfinError(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _quickConnect() async {
    final signedIn = await showQuickConnect(context, server: widget.user.server);
    if (signedIn && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        spacing: 12,
        children: [
          Text(widget.user.name, style: theme.typography.display.lg),
          FTextField.password(
            control: .managed(controller: _password),
            autofocus: true,
            enabled: !_busy,
            onSubmit: (_) => _signIn(),
          ),
          if (_error != null) Text(_error!, style: TextStyle(color: theme.colors.error)),
          FButton(onPress: _busy ? null : _signIn, child: Text(_busy ? 'Signing in…' : 'Sign in')),
          FButton(variant: .outline, onPress: _busy ? null : _quickConnect, child: const Text('Use Quick Connect')),
          FButton(variant: .ghost, onPress: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ],
      ),
    );
  }
}
