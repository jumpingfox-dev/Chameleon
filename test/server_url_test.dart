import 'package:chameleon/core/jellyfin/jellyfin_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a bare address gets http and Jellyfin\'s default port', () {
    expect(normalizeServerUrl('192.168.1.20'), 'http://192.168.1.20:8096');
    expect(normalizeServerUrl(' 192.168.1.20/ '), 'http://192.168.1.20:8096');
  });

  test('a typed port is kept', () {
    expect(normalizeServerUrl('192.168.4.2:8098'), 'http://192.168.4.2:8098');
  });

  test('the default port goes before a path', () {
    expect(normalizeServerUrl('nas.local/jellyfin'), 'http://nas.local:8096/jellyfin');
  });

  test('an address with a scheme is taken as is', () {
    expect(normalizeServerUrl('https://jellyfin.example.com/'), 'https://jellyfin.example.com');
    expect(normalizeServerUrl('http://10.0.0.5'), 'http://10.0.0.5');
  });

  test('the field shows saved addresses without http://', () {
    expect(displayServerUrl('http://192.168.4.2:8098'), '192.168.4.2:8098');
    expect(displayServerUrl('https://jellyfin.example.com'), 'https://jellyfin.example.com');
  });
}
