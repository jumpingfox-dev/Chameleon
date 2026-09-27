<div align="center">
   <img src="./assets/images/text_logo_color.svg" alt="Chameleon" style="margin: 20px 0;">
</div>

# Chameleon

Chameleon is a free and open-source, deeply customizable Jellyfin client built to adapt seamlessly across your screens with high-performance playback and personalized library layouts.

Most clients lock you into a rigid layout. Chameleon gives you complete control over your interface while maximizing direct play to keep your server quiet and cool.

## Highlights

* **Adaptive Interfaces:** Completely customize your home shelf rows, metadata layouts, and poster aspect ratios to match your library aesthetic.
* **Direct Play First:** Built to prioritize native direct streams (HEVC, AV1, HDR/Dolby Vision) to minimize server transcoding overhead.
* **Living Room & Mobile Ready:** Fluid touch controls for handheld devices paired with a first-class, snappy D-pad navigation model for Android TV and Apple TV.
* **Advanced Subtitle Engine:** Native support for styled anime subtitles (`.ass`/`.ssa`) with fine-grained control over typography, sizing, and vertical offsets.
* **Multi-Account & Server Switching:** Instant switching between local and remote server profiles without having to re-authenticate.
* **Zero Telemetry:** Completely private with no analytics, trackers, or middleman servers—your device communicates strictly with your Jellyfin instance.

## Platforms & Downloads

Grab the latest stable build from the [Releases](https://github.com/jumpingfox-dev/chameleon/releases) page.

### Android & Android TV / Google TV
Universal build supporting phones, tablets, foldables, and TV remotes:

[<img src="https://img.shields.io/badge/GitHub_Release-APK-2ea44f?style=for-the-badge&logo=android&logoColor=white" alt="Download APK" />](https://github.com/jumpingfox-dev/chameleon/releases/latest)
[<img src="https://img.shields.io/badge/Google_Play-Coming_Soon-414141?style=for-the-badge&logo=google-play&logoColor=white" alt="Google Play" />](#)
[<img src="https://img.shields.io/badge/F--Droid-Coming_Soon-1976D2?style=for-the-badge&logo=f-droid&logoColor=white" alt="F-Droid" />](#)

### iOS, iPadOS & Apple TV (tvOS)
Join our community testing pool on TestFlight:

[<img src="https://img.shields.io/badge/Apple_TestFlight-Join_Beta-0D96F6?style=for-the-badge&logo=apple&logoColor=white" alt="TestFlight" />](https://testflight.apple.com)
[<img src="https://img.shields.io/badge/App_Store-Coming_Soon-0D96F6?style=for-the-badge&logo=app-store&logoColor=white" alt="App Store" />](#)

## Development & Building

### Prerequisites
* [Android Studio](https://developer.android.com/studio) (Ladybug / Meerkat or later)
* Android SDK 35+
* JDK 17 or 21

### Local Setup

1. **Clone the repository:**
   ```bash
   git clone https://github.com/jumpingfox-dev/chameleon.git
   cd chameleon