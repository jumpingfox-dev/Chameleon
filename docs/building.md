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

The same APK as for a phone. The manifest marks touchscreen and leanback as optional and adds
the `LEANBACK_LAUNCHER` category, so the app (with `tv_banner`) shows on the TV home screen.

At startup `detectTv` (`core/platform/orientation.dart`) checks for Android's
`android.software.leanback` feature. Screen size can't decide this on its own: most 1080p TVs
report 960 × 540, which is phone-sized. On a TV the app always uses the sidebar layout and never
asks for portrait. `--dart-define=TV=true` forces TV mode, for an emulator or desktop.

### Testing without a TV

**TV-shaped emulator (day to day: debug builds, hot reload).** Google's TV system images
are 32-bit x86 only, and Flutter no longer builds for 32-bit x86, so `flutter run` can't target
them. Instead, use a normal 64-bit image with the TV hardware profile:

```bash
avdmanager create avd -n Chameleon_TV_x64 -d tv_1080p \
  -k "system-images;android-37.1;google_apis_ps16k;x86_64"
# then in the AVD's config.ini: hw.keyboard=yes (arrow keys act as the D-pad), hw.gpu.enabled=yes
emulator -avd Chameleon_TV_x64
adb shell settings put system accelerometer_rotation 0   # keep it landscape
adb shell settings put system user_rotation 0
flutter run -d emulator-5554 --dart-define=TV=true
```

**Real Google TV image (the real launcher and keyboard; release builds only).** The Google TV
image runs 32-bit ARM apps through its translation layer, so build for `android-arm`:

```bash
avdmanager create avd -n Chameleon_GoogleTV -d tv_1080p -k "system-images;android-34;google-tv;x86"
emulator -avd Chameleon_GoogleTV
flutter build apk --release --target-platform android-arm
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Translation makes it slower than a real device, so judge layout and navigation here, not speed.

**A real TV (best).** On a Chromecast with Google TV, Google TV Streamer or Android TV box:
Settings → System → About → press *Android TV OS build* seven times, then Developer options →
*USB debugging* (and *Wireless debugging* where offered). Then:

```bash
adb connect <tv ip>:5555     # accept the prompt on the TV
flutter run -d <tv ip>:5555
```

That gives debug builds and hot reload on the real hardware, with a real remote. See
[remote-navigation.md](remote-navigation.md) for what to check.

## iOS

Needs a Mac with Xcode.

```bash
flutter run -d <device or simulator id>
```

AirPlay (`features/player/cast_widgets.dart`'s `AirPlayButton`) only appears on iOS
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

## Splash screens

`flutter_native_splash`, configured in `pubspec.yaml`, generates the Android splash: the icon
on `#0a0d18` before Android 12 (`assets/icon/icon_foreground.png`), and on Android 12+ the
same icon inside the system's circle, whose background is set to the same color so the
circle doesn't show (`assets/icon/splash_android12.png`, 1152 px with the icon inside the
middle 768 px). After changing either:

```bash
dart run flutter_native_splash:create
```

The app keeps the system splash up until its first page is ready (`FlutterNativeSplash.preserve`
in `main.dart`).

TVs get the full wordmark instead, which the generator can't do, so it's set up by hand and
the generator leaves it alone:

- `android/app/src/main/res/values-television-v31/styles.xml`: Android 12+ TVs, whose system
  splash can only show a small icon, show just the background, and the app's first frame
  draws the wordmark (`lib/app/splash.dart`) while it loads.
- `android/app/src/main/res/drawable-television/launch_background.xml`: older TVs show
  `tv_banner.png`, and `TvSplash` draws the wordmark in the same place and size.

## Checking everything still compiles

```bash
flutter analyze   # should report nothing beyond pre-existing info-level notices
flutter build linux
flutter build apk --debug
```
