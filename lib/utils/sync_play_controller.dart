import 'dart:async';
import 'dart:convert';

import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'item_format.dart';
import 'jellyfin_controller.dart';

/// A play/pause/seek/stop instruction from the group, to carry out at [when].
class SyncPlayCommand {
  const SyncPlayCommand({
    required this.command,
    required this.when,
    required this.position,
    required this.playlistItemId,
  });

  /// `Pause`, `Unpause`, `Seek` or `Stop`.
  final String command;

  /// When to do it, already converted to this device's clock.
  final DateTime when;

  /// Where in the video the group is (or should be) at [when].
  final Duration position;
  final String? playlistItemId;
}

/// What a group is watching right now, for showing it before you join.
typedef SyncPlayWatching = ({String itemId, String title, String? subtitle, String? imageUrl});

/// A group someone else made, from the server's list, with what it's watching when known.
typedef SyncPlayGroup = ({
String id,
String name,
List<String> members,
String state,
SyncPlayWatching? watching,
});

/// One entry in the group's play queue: the item, and the group's own id for that entry.
typedef SyncPlayEntry = ({String itemId, String playlistItemId});

/// What the player does when the group moves to another item: switch to [itemId] from [start].
typedef SyncPlaySwitch = void Function(String itemId, Duration start);

/// Watch Together, using Jellyfin's SyncPlay.
///
/// Everyone in a group watches the same thing at the same moment. Instead of pausing or
/// seeking straight away, the player asks the server ([requestPause], [requestSeek] …);
/// the server then tells every member exactly when to do it ([commands]). Works with
/// Jellyfin's own apps too, so people can join from a browser.
///
/// The server talks back over the WebSocket (`/socket`), which is opened while in a group.
class SyncPlayController extends ChangeNotifier {
  // ── Group ──
  String? groupId;
  String? groupName;
  List<String> members = const [];

  /// The group's state: `Idle`, `Waiting` (for everyone to load), `Paused` or `Playing`.
  String state = 'Idle';

  /// Something to tell the user (someone joined, an error …). Cleared on the next change.
  String? message;

  bool get inGroup => groupId != null;

  // ── Queue ──
  List<SyncPlayEntry> queue = const [];
  int playingIndex = -1;
  Duration startPosition = Duration.zero;

  /// Whether the group wants to be playing (rather than paused).
  bool isPlaying = false;

  SyncPlayEntry? get current =>
      playingIndex >= 0 && playingIndex < queue.length ? queue[playingIndex] : null;
  bool get hasNext => playingIndex >= 0 && playingIndex + 1 < queue.length;

  /// Opens the player for [itemId] when the group starts something and no player is open.
  /// Set once at startup (main.dart), where the router lives.
  void Function(String itemId)? openPlayer;

  final _commands = StreamController<SyncPlayCommand>.broadcast();

  /// Instructions for the player to carry out.
  Stream<SyncPlayCommand> get commands => _commands.stream;

  SyncPlaySwitch? _attached; // the open player, if there is one
  StreamSubscription<JellyfinNotification>? _socket;
  Timer? _pingTimer;

  /// Server clock minus this device's clock. Commands are timed on the server's clock.
  Duration _offset = Duration.zero;

  JellyfinClient get _client => jellyfin.client!;

  // ── Player hook-up ──

  /// The player calls this while it's open, so group changes switch it in place
  /// instead of opening a second one.
  // These run while the player is being built or torn down, when listeners can't rebuild
  // yet, so they're told a moment later.
  void attach(SyncPlaySwitch onSwitch) {
    _attached = onSwitch;
    scheduleMicrotask(notifyListeners);
  }

  void detach(SyncPlaySwitch onSwitch) {
    if (_attached == onSwitch) _attached = null; // tear-offs are equal, not identical
    scheduleMicrotask(notifyListeners);
  }

  /// Whether the player is open on this device.
  bool get playerOpen => _attached != null;

  // ── Groups ──

  /// The groups you can join, each with what its members are watching (when the server
  /// lets this account see other people's sessions: admins always can).
  Future<List<SyncPlayGroup>> groups() async {
    final (list, watching) = await (_client.syncPlay.list(), _nowPlayingByUser()).wait;
    return [
      for (final g in list)
        if (g['GroupId'] case final String id)
              () {
            final members = [for (final m in (g['Participants'] as List?) ?? const []) '$m'];
            return (
            id: id,
            name: (g['GroupName'] as String?) ?? 'Watch party',
            members: members,
            state: (g['State'] as String?) ?? 'Idle',
            // Anyone in the group who's playing something: that's what the group watches.
            watching: members.map((m) => watching[m]).nonNulls.firstOrNull,
            );
          }(),
    ];
  }

  /// What each signed-in user is playing right now, from the server's session list.
  Future<Map<String, SyncPlayWatching>> _nowPlayingByUser() async {
    final base = _client.baseUrl;
    if (base == null) return const {};
    try {
      final sessions = await jellyfin.getJson(
        '/Sessions',
        query: const {'activeWithinSeconds': '960'},
        timeout: const Duration(seconds: 5),
      );
      final result = <String, SyncPlayWatching>{};
      for (final session in sessions as List) {
        if (session is! Map) continue;
        final user = session['UserName'] as String?;
        final item = session['NowPlayingItem'];
        if (user == null || item is! Map || item['Id'] is! String) continue;
        result[user] = _watchingFrom(base, item);
      }
      return result;
    } catch (_) {
      return const {}; // just show the groups without it
    }
  }

  static SyncPlayWatching _watchingFrom(String base, Map item) {
    final id = item['Id'] as String;
    final isEpisode = item['Type'] == 'Episode';

    // A wide picture: the item's backdrop, the show's backdrop, or the poster.
    final parentId = item['ParentBackdropItemId'] as String?;
    final imageUrl = wideImageUrl(base, [
      ('Backdrop', id, (item['BackdropImageTags'] as List?)?.firstOrNull as String?),
      (
        'Backdrop',
        parentId ?? '',
        parentId == null ? null : (item['ParentBackdropImageTags'] as List?)?.firstOrNull as String?,
      ),
      ('Primary', id, (item['ImageTags'] as Map?)?['Primary'] as String?),
    ]);

    return (
    itemId: id,
    title: isEpisode ? (item['SeriesName'] as String?) ?? '${item['Name']}' : '${item['Name']}',
    subtitle: isEpisode
        ? episodeLabel(item['ParentIndexNumber'], item['IndexNumber'], '${item['Name']}')
        : item['ProductionYear']?.toString(),
    imageUrl: imageUrl,
    );
  }

  Future<void> create(String name) async {
    await _connect();
    await _client.syncPlay.createGroup(groupName: name);
  }

  /// Joins a group. If it's already watching something, the server sends its queue straight
  /// after, and the player opens at the group's spot: no need to find it and press play.
  Future<void> join(String id) async {
    await _connect();
    await _client.syncPlay.joinGroup(groupId: id);
  }

  Future<void> leave() async {
    try {
      await _client.syncPlay.leaveGroup();
    } catch (_) {
      // Already gone on the server's side: just tidy up here.
    }
    _reset();
  }

  // ── Requests (the server answers with a command for everyone) ──

  Future<void> requestPause() => _quietly(_client.syncPlay.pause);
  Future<void> requestUnpause() => _quietly(_client.syncPlay.unpause);
  Future<void> requestSeek(Duration to) =>
      _quietly(() => _client.syncPlay.seek(positionTicks: to.inMicroseconds * 10));

  /// Replaces what the group is watching: [itemIds] in order, starting with the first.
  Future<void> play(List<String> itemIds, {Duration start = Duration.zero}) => _quietly(
        () => _client.syncPlay.setNewQueue(
      playingQueue: itemIds,
      playingItemPosition: 0,
      startPositionTicks: start.inMicroseconds * 10,
    ),
  );

  Future<void> requestNext() async {
    final entry = current;
    if (entry == null) return;
    await _quietly(() => _client.syncPlay.nextItem(playlistItemId: entry.playlistItemId));
  }

  /// This device is loading or rebuffering: the group waits for it.
  Future<void> buffering(Duration position, {required bool playing}) async {
    final entry = current;
    if (entry == null) return;
    await _quietly(
          () => _client.syncPlay.buffering(
        playlistItemId: entry.playlistItemId,
        positionTicks: position.inMicroseconds * 10,
        isPlaying: playing,
      ),
    );
  }

  /// This device is loaded and ready to go.
  Future<void> ready(Duration position, {required bool playing}) async {
    final entry = current;
    if (entry == null) return;
    await _quietly(
          () => _client.syncPlay.ready(
        playlistItemId: entry.playlistItemId,
        positionTicks: position.inMicroseconds * 10,
        isPlaying: playing,
      ),
    );
  }

  Future<void> _quietly(Future<void> Function() request) async {
    try {
      await request();
    } catch (e) {
      debugPrint('SyncPlay request failed: $e');
    }
  }

  // ── Connection ──

  Future<void> _connect() async {
    if (_socket != null) return;
    // Still closing from a moment ago (leaving, then joining again): finish that first.
    if (_client.notifications.isConnected) await _client.notifications.close();
    final stream = await _client.notifications.connect();
    _socket = stream.listen(
      _onMessage,
      onError: (Object e) => debugPrint('SyncPlay socket: $e'),
      onDone: () {
        _socket = null;
        if (inGroup) {
          message = 'Lost connection to the watch party.';
          _reset(keepMessage: true);
        }
      },
    );
    await _reportCapabilities();
    await _syncClock();
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) => _syncClock());
  }

  /// Tells the server this session can be told what to play, which SyncPlay needs.
  Future<void> _reportCapabilities() async {
    final base = _client.baseUrl;
    if (base == null) return;
    try {
      await http.post(
        Uri.parse('$base/Sessions/Capabilities/Full'),
        headers: {...jellyfin.authHeaders, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'PlayableMediaTypes': ['Video'],
          'SupportedCommands': <String>[],
          'SupportsMediaControl': true,
        }),
      );
    } catch (_) {}
  }

  /// Measures how far this device's clock is from the server's, like NTP: a few
  /// round trips, keeping the quickest (the least distorted by network delay).
  /// Also tells the server the round-trip time, which it uses to time commands.
  Future<void> _syncClock() async {
    final base = _client.baseUrl;
    if (base == null) return;
    Duration? bestRtt;
    for (var i = 0; i < 3; i++) {
      try {
        final sent = DateTime.now().toUtc();
        final res = await http.get(Uri.parse('$base/GetUtcTime')).timeout(const Duration(seconds: 3));
        final received = DateTime.now().toUtc();
        if (res.statusCode != 200) continue;
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final serverIn = DateTime.parse(json['RequestReceptionTime'] as String);
        final serverOut = DateTime.parse(json['ResponseTransmissionTime'] as String);
        final rtt = received.difference(sent) - serverOut.difference(serverIn);
        if (bestRtt == null || rtt < bestRtt) {
          bestRtt = rtt;
          _offset = (serverIn.difference(sent) + serverOut.difference(received)) ~/ 2;
        }
      } catch (_) {}
    }
    if (bestRtt != null && inGroup) {
      await _quietly(() => _client.syncPlay.ping(ping: bestRtt!.inMilliseconds));
    }
  }

  void _disconnect() {
    _pingTimer?.cancel();
    _pingTimer = null;
    final socket = _socket;
    _socket = null;
    socket?.cancel();
    if (jellyfin.client case final client?) unawaited(client.notifications.close());
  }

  void _reset({bool keepMessage = false}) {
    groupId = null;
    groupName = null;
    members = const [];
    state = 'Idle';
    queue = const [];
    playingIndex = -1;
    isPlaying = false;
    if (!keepMessage) message = null;
    _disconnect();
    notifyListeners();
  }

  // ── Messages from the server ──

  void _onMessage(JellyfinNotification n) {
    final data = n.data;
    if (data is! Map) return;
    switch (n.messageType) {
      case 'SyncPlayGroupUpdate':
        _onGroupUpdate(data);
      case 'SyncPlayCommand':
        _onCommand(data);
    }
  }

  void _onGroupUpdate(Map update) {
    final payload = update['Data'];
    message = null;
    switch (update['Type']) {
      case 'GroupJoined':
        if (payload is Map) {
          groupId = (payload['GroupId'] as String?) ?? update['GroupId'] as String?;
          groupName = payload['GroupName'] as String?;
          members = [for (final m in (payload['Participants'] as List?) ?? const []) '$m'];
          state = (payload['State'] as String?) ?? 'Idle';
        }
      case 'UserJoined':
        if (payload is String && !members.contains(payload)) {
          members = [...members, payload];
          message = '$payload joined';
        }
      case 'UserLeft':
        if (payload is String) {
          members = [...members]..remove(payload);
          message = '$payload left';
        }
      case 'StateUpdate':
        if (payload is Map) state = (payload['State'] as String?) ?? state;
      case 'PlayQueue':
        if (payload is Map) _onQueue(payload);
      case 'GroupLeft' || 'NotInGroup':
        _reset();
        return;
      case 'GroupDoesNotExist':
        message = 'That group has ended.';
        _reset(keepMessage: true);
        return;
      case 'CreateGroupDenied' || 'JoinGroupDenied':
        message = "Your account isn't allowed to use Watch Together. An admin can turn it on.";
      case 'LibraryAccessDenied':
        message = "Someone in the group can't access what's playing.";
    }
    notifyListeners();
  }

  void _onQueue(Map payload) {
    final before = current?.playlistItemId;
    queue = [
      for (final e in (payload['Playlist'] as List?) ?? const [])
        if (e is Map && e['ItemId'] is String && e['PlaylistItemId'] is String)
          (itemId: e['ItemId'] as String, playlistItemId: e['PlaylistItemId'] as String),
    ];
    playingIndex = (payload['PlayingItemIndex'] as int?) ?? -1;
    isPlaying = payload['IsPlaying'] as bool? ?? false;
    final ticks = payload['StartPositionTicks'];
    startPosition = ticks is int ? Duration(microseconds: ticks ~/ 10) : Duration.zero;

    // Something new to watch: switch the open player to it, or open one.
    final now = current;
    if (now == null || now.playlistItemId == before) return;
    final attached = _attached;
    if (attached != null) {
      attached(now.itemId, startPosition);
    } else {
      openPlayer?.call(now.itemId);
    }
  }

  void _onCommand(Map data) {
    final whenServer = DateTime.tryParse('${data['When']}');
    final ticks = data['PositionTicks'];
    _commands.add(
      SyncPlayCommand(
        command: '${data['Command']}',
        // Server time → this device's time.
        when: (whenServer ?? DateTime.now().toUtc().add(_offset)).subtract(_offset).toLocal(),
        position: ticks is int ? Duration(microseconds: ticks ~/ 10) : Duration.zero,
        playlistItemId: data['PlaylistItemId'] as String?,
      ),
    );
  }
}

final syncPlay = SyncPlayController();