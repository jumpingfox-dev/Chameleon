part of 'settings.dart';

/// SyncPlay Tab
class _SyncPlayCard extends StatefulWidget {
  const _SyncPlayCard();

  @override
  State<_SyncPlayCard> createState() => _SyncPlayCardState();
}

class _SyncPlayCardState extends State<_SyncPlayCard> {
  late final _name = TextEditingController(text: "${jellyfin.userName ?? 'My'}'s group");
  List<SyncPlayGroup> _groups = const [];
  bool _loading = true;
  bool _busy = false; // creating, joining or leaving
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Keep the list current (new groups, what they're watching) while the tab is open.
    _poll = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!syncPlay.inGroup && !_busy) _refresh(quiet: true);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _name.dispose();
    super.dispose();
  }

  /// [quiet]: an automatic refresh, so no spinner in place of the list.
  Future<void> _refresh({bool quiet = false}) async {
    setState(() {
      if (!quiet) _loading = true;
      _error = null;
    });
    try {
      final groups = await syncPlay.groups();
      if (mounted) setState(() => _groups = groups);
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't load groups. Your server may have SyncPlay turned off.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Runs [action], disabling the buttons meanwhile and showing any error under them.
  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = "That didn't work. Check your connection and try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: syncPlay,
    builder: (context, _) {
      final theme = context.theme;
      final muted = theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground);
      final message = _error ?? syncPlay.message;

      return _SettingsCard(
        children: [
          if (syncPlay.inGroup) ...[
            // ── In a group ──
            _SectionTitle(
              syncPlay.groupName ?? 'SyncPlay group',
              description: 'Play anything and everyone here watches it with you. '
                  'Anyone can pause, seek or skip, and it happens for the whole group.',
              first: true,
            ),
            // What the group is watching: select it to jump in.
            if (syncPlay.current case final entry?)
              _SyncPlayNowPlaying(itemId: entry.itemId, playerOpen: syncPlay.playerOpen)
            else
              Text('Nothing playing yet. Pick something to watch.', style: muted),

            const _SectionTitle('In this group'),
            for (final member in syncPlay.members)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  spacing: 10,
                  children: [
                    Icon(appIcons.profile, size: 18, fill: 1, color: theme.colors.mutedForeground),
                    Expanded(child: Text(member)),
                    if (member == jellyfin.userName) Text('You', style: muted),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            FButton(
              variant: .outline,
              mainAxisSize: .min,
              onPress: _busy
                  ? null
                  : () => _run(() async {
                await syncPlay.leave();
                await _refresh();
              }),
              child: const Text('Leave group'),
            ),
          ] else ...[
            // ── Join one ──
            const _SectionTitle(
              'Join a Group',
              description: 'Select a group to join it. If it is watching something, '
                  'you jump straight in where they are.',
              first: true,
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: FCircularProgress()),
              )
            else if (_groups.isEmpty)
              Text('No groups right now. Start one below, or ask someone to.', style: muted)
            else
              for (final (i, group) in _groups.indexed) ...[
                if (i > 0) const SizedBox(height: 8),
                _SyncPlayGroupTile(
                  group: group,
                  onJoin: _busy ? null : () => _run(() => syncPlay.join(group.id)),
                ),
              ],

            // ── Or start one ──
            const _SectionTitle(
              'Start a Group',
              description: 'Make a group, then have others join it from their own device. '
                  "Jellyfin's web app and other apps with SyncPlay can join too.",
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: [
                FTextField(control: .managed(controller: _name), hint: 'Group name'),
                FButton(
                  onPress: _busy
                      ? null
                      : () => _run(() => syncPlay.create(
                        _name.text.trim().isEmpty ? 'SyncPlay group' : _name.text.trim(),
                      )),
                  child: const Text('Create'),
                ),
              ],
            ),
          ],

          if (message != null) ...[
            const SizedBox(height: 12),
            Text(message, style: muted.copyWith(color: _error != null ? theme.colors.error : null)),
          ],
        ],
      );
    },
  );
}

/// A group you can join, shown by what it's watching when that's known.
class _SyncPlayGroupTile extends StatelessWidget {
  const _SyncPlayGroupTile({required this.group, required this.onJoin});

  final SyncPlayGroup group;
  final VoidCallback? onJoin;

  @override
  Widget build(BuildContext context) {
    final watching = group.watching;
    final people = group.members.join(', ');
    return _SyncPlayTile(
      imageUrl: watching?.imageUrl,
      title: watching?.title ?? group.name,
      lines: [
        if (watching?.subtitle case final subtitle? when subtitle.isNotEmpty) subtitle,
        watching == null ? people : '${group.name} · $people',
      ],
      action: 'Join',
      onPress: onJoin,
    );
  }
}

/// What the group is watching, in the same tile as the groups list. Selecting it opens the
/// player at the group's spot; once the player is open, it just says so.
class _SyncPlayNowPlaying extends StatefulWidget {
  const _SyncPlayNowPlaying({required this.itemId, required this.playerOpen});

  final String itemId;
  final bool playerOpen;

  @override
  State<_SyncPlayNowPlaying> createState() => _SyncPlayNowPlayingState();
}

class _SyncPlayNowPlayingState extends State<_SyncPlayNowPlaying> {
  late Future<JellyfinItem?> _item = jellyfin.client!.items.byId(widget.itemId);

  @override
  void didUpdateWidget(covariant _SyncPlayNowPlaying old) {
    super.didUpdateWidget(old);
    if (old.itemId != widget.itemId) _item = jellyfin.client!.items.byId(widget.itemId);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<JellyfinItem?>(
    future: _item,
    builder: (context, snap) {
      final item = snap.data;
      final isEpisode = item?.type == JellyfinItemKind.episode;
      final season = item?.raw['ParentIndexNumber'], episode = item?.raw['IndexNumber'];

      return _SyncPlayTile(
        imageUrl: item == null ? null : _wideImage(item),
        title: item == null
            ? 'Loading…'
            : isEpisode
            ? (item.raw['SeriesName'] as String?) ?? item.name
            : item.name,
        lines: [
          if (item != null && isEpisode)
            episodeLabel(season, episode, item.name)
          else if (item?.raw['ProductionYear'] case final year?)
            '$year',
          if (widget.playerOpen) "You're watching along.",
        ],
        action: widget.playerOpen ? null : 'Join Playback',
        // Opened as the group's player, so it starts at the group's spot instead of
        // restarting the group from this device.
        onPress: widget.playerOpen ? null : () => GoRouter.of(context).push('/play/${widget.itemId}?syncplay=1'),
        autofocus: !widget.playerOpen,
      );
    },
  );

  /// The backdrop (the show's, for an episode), or else the poster.
  static String? _wideImage(JellyfinItem item) {
    final base = jellyfin.client?.baseUrl;
    if (base == null) return null;
    final parentId = item.raw['ParentBackdropItemId'] as String?;
    return wideImageUrl(base, [
      ('Backdrop', item.id, (item.raw['BackdropImageTags'] as List?)?.firstOrNull as String?),
      (
        'Backdrop',
        parentId ?? '',
        parentId == null ? null : (item.raw['ParentBackdropImageTags'] as List?)?.firstOrNull as String?,
      ),
      ('Primary', item.id, item.imageTags['Primary']),
    ]);
  }
}

/// The SyncPlay tile: a bordered card with a small picture, a title, a line or two under it
/// and an action word on the right. Selecting or hovering it fills it in and lights up the
/// border. Without [onPress], it's shown the same but does nothing.
class _SyncPlayTile extends StatelessWidget {
  const _SyncPlayTile({
    required this.imageUrl,
    required this.title,
    this.lines = const [],
    this.action,
    this.onPress,
    this.autofocus = false,
  });

  final String? imageUrl;
  final String title;
  final List<String> lines;
  final String? action;
  final VoidCallback? onPress;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final muted = theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground);

    return FTappable(
      autofocus: autofocus,
      onPress: onPress,
      builder: (context, states, _) {
        final highlighted = onPress != null && isHighlighted(states);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: highlighted ? theme.colors.secondary : theme.colors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: highlighted ? theme.colors.primary : theme.colors.border),
          ),
          child: Row(
            spacing: 12,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 112,
                  height: 63,
                  child: imageUrl == null
                      ? ColoredBox(
                    color: theme.colors.muted,
                    child: Icon(appIcons.play, color: theme.colors.mutedForeground, fill: 1),
                  )
                      : Image.network(
                    imageUrl!,
                    headers: jellyfin.authHeaders,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => ColoredBox(color: theme.colors.muted),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.typography.body.md.copyWith(fontWeight: FontWeight.w600),
                    ),
                    for (final line in lines)
                      Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                  ],
                ),
              ),
              if (action != null)
                Text(
                  action!,
                  style: theme.typography.body.sm.copyWith(
                    color: theme.colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
