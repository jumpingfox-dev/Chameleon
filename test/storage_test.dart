import 'package:chameleon/core/storage/database.dart';
import 'package:chameleon/core/storage/storage.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<Storage> open() => Storage.open(AppDatabase(NativeDatabase.memory()));

  test('settings are kept per person, starting from the shared value', () async {
    final s = await open();
    await s.setString('selected_theme', 'default'); // nobody signed in: the shared value

    s.useUser('http://server', 'alice');
    expect(s.getString('selected_theme'), 'default', reason: 'falls back to the shared value');
    await s.setString('selected_theme', 'emerald');
    expect(s.getString('selected_theme'), 'emerald');

    s.useUser('http://server', 'bob');
    expect(s.getString('selected_theme'), 'default', reason: "alice's choice doesn't carry over");

    s.useUser('http://server', 'alice');
    expect(s.getString('selected_theme'), 'emerald');
  });

  test('device-wide keys are shared by everyone', () async {
    final s = await open();
    s.useUser('http://server', 'alice');
    await s.setString('jf_server', 'http://server');
    s.useUser('http://server', 'bob');
    expect(s.getString('jf_server'), 'http://server');
  });

  test('switching people tells listeners', () async {
    final s = await open();
    var calls = 0;
    s.user.addListener(() => calls++);
    s.useUser('http://server', 'alice');
    s.useUser('http://server', 'alice'); // the same person: no change
    s.useUser(null, null);
    expect(calls, 2);
  });
}
