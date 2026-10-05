# Building and running

Standard Flutter commands — nothing project-specific beyond what's below.

## Linux desktop

```bash
flutter pub get
flutter run -d linux
```

For a release build:

```bash
flutter build linux
```

The build output is `build/linux/x64/release/bundle/`.

## Android phone or tablet

```bash
flutter devices        # confirm the device shows up
flutter run -d <device id>
```

For a release build you can install:

```bash
flutter build apk --debug    # quick, unsigned, for testing
flutter build apk --release  # needs signing set up in android/ to install on most devices
```

## Android TV

Build and sideload the same APK as for a phone — there's no separate TV build target.
Chameleon detects the shortest screen side at runtime (`isPhoneLayout` in
`utils/orientation.dart`) to decide between the phone layout and the sidebar/remote layout,
not the device type, so a TV just needs a big enough screen to get the wide layout. Test with
an actual D-pad remote (or a game controller / the Android TV remote app) — see
[remote-navigation.md](remote-navigation.md) for what to check.

## iOS

Needs a Mac with Xcode.

```bash
flutter run -d <device or simulator id>
```

AirPlay (`widgets/cast_widgets.dart`'s `AirPlayButton`) only appears on iOS
(`!kIsWeb && Platform.isIOS`), and carries audio only — the picture needs Screen Mirroring
from Control Center, since the player uses `media_kit` rather than Apple's own player.

## App icons

Generated from `assets/icon/icon.png` (plus `icon_foreground.png`/`icon_monochrome.png` for
Android's adaptive icon, and `icon_tinted.png` for iOS's tinted mode) via
`flutter_launcher_icons`, configured in `pubspec.yaml`. After changing any of those source
images:

```bash
dart run flutter_launcher_icons
```

## Checking everything still compiles

```bash
flutter analyze   # should report nothing beyond pre-existing info-level notices
flutter build linux
flutter build apk --debug
```
