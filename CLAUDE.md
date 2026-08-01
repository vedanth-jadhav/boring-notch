# boring.notch

A macOS menu bar app that replaces the notch with a customizable media player, HUD overlays, live activities, and lock screen widgets.

## Build & Run

```bash
# Build
swift build

# Package as .app bundle (replaces binary in existing bundle)
scripts/package_swift_cli.sh

# Run from existing bundle
open build/swift-cli/boringNotch.app

# Quick rebuild + relaunch (dev loop)
pkill boringNotch; \
cp .build/arm64-apple-macosx/debug/boringNotch build/swift-cli/boringNotch.app/Contents/MacOS/boringNotch; \
codesign --force --sign - build/swift-cli/boringNotch.app; \
open build/swift-cli/boringNotch.app
```

## Project Structure

```
boringNotch/
  boringNotchApp.swift          # @main, AppDelegate, window management
  ContentView.swift             # Root notch view
  BoringViewCoordinator.swift   # Tab/switching state
  managers/                     # Singleton services
    MusicManager.swift          # Media playback state + lyrics
    LockScreenMusicWindowManager.swift
    Lyrics/
      LyricFeverLyricsService.swift  # 3 lyric providers: Spotify → LRCLIB → NetEase
    Buds/                       # OnePlus Buds integration
  components/
    LockScreen/                 # Lock screen music widget + lyrics
      LockScreenMusicWidgetView.swift
      LockScreenLyricLineView.swift   # Shared lyric line renderer (extracted)
    Lyrics/
      LockScreenLyricLineView.swift   # Reusable lyric line component
    Notch/                      # Notch UI
      BoringHeader.swift        # Top bar (camera, tabs)
      NotchHomeView.swift       # Music controls, lyrics in-notch
    Settings/                   # Settings window
    Live activities/            # HUD, battery, downloads
    Music/                      # Visualizer
  helpers/
    LiquidGlassBackground.swift # NSGlassEffectView wrapper (NSViewRepresentable)
  services/
    LyricRomanizationService.swift  # CFStringTransform-based Hinglish romanization
  models/
    Constants.swift             # All Defaults.Keys
    Lyrics/
      BoringLyricLine.swift     # BoringLyricLine + LockScreenLyricDisplayLine models
  Shortcuts/
    ShortcutConstants.swift     # KeyboardShortcuts.Name definitions
```

## Key Patterns

### Lyrics Providers (LyricFeverLyricsService)

Providers are tried in order: **Spotify** → **LRCLIB** → **NetEase**. First one with >1 synced line wins.

- **Spotify**: Reads `spDcCookie` from `UserDefaults["spDcCookie"]`. User must paste this in Settings → Media. Requires the `sp_dc` cookie from the browser.
- **LRCLIB**: Public API at `lrclib.net`. First tries exact `/api/get` match by artist+track+album. Falls back to `/api/search` by artist+track → picks best album match → fetches by ID.
- **NetEase**: Third-party Vercel proxy for Chinese NetEase Cloud Music API.

### Liquid Glass

`LiquidGlassBackground` in `helpers/LiquidGlassBackground.swift` wraps the private `NSGlassEffectView` API via `NSClassFromString`. The view is an `NSViewRepresentable` with variant support (0-19, default `.v11`). It configures `CABackdropLayer` properties for proper glass rendering.

### Romanization

`LyricRomanizationService` uses `CFStringTransform` with `kCFStringTransformToLatin` + strip combining marks. Applied in `MusicManager.lyricLine(at:)` and `displayLine(index:role:)` when `Defaults[.enableLyricRomanization]` is true and the text contains Indic unicode characters.

### Lyrics Display

- **In-notch**: `NotchHomeView.swift` → `MusicManager.lyricLine(at:)` with TimelineView
- **Lock screen**: `LockScreenMusicWidgetView.swift` → `MusicManager.lyricDisplayContext(at:)` → `LockScreenLyricLineView`
- **Translation**: Native macOS `Translation` framework via `LockScreenLyricsTranslationBridge`

### Window Management

- Notch windows: `BoringNotchSkyLightWindow` (in ContentView)
- Lock screen: `LockScreenMusicWindowManager` → creates NSWindow with `.nonactivatingPanel` at `CGShieldingWindowLevel()`
- All floating windows follow the same pattern: borderless, `.nonactivatingPanel`, clear background, `collectionBehavior: [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]`

### Settings

All settings use `Defaults` (sindresorhus/Defaults) package. Define new keys in `models/Constants.swift` under `extension Defaults.Keys`. Use `@Default(.keyName)` in views. Settings tabs are in `SettingsView.swift`.

### Key Constants

- `hideFromScreenRecording` — sets `sharingType = .none` on all windows
- `enableLyrics` — master toggle for all lyric features
- `enableLyricRomanization` — CFStringTransform-based Hinglish conversion
- `lockScreenMusicWidget`/`lockScreenMusicLiquidGlassVariant` — lock screen panel config

## Dependencies

- Defaults, KeyboardShortcuts, LaunchAtLogin-Modern (sindresorhus)
- SkyLightWindow (Lakr233) — window server interaction
- Sparkle — auto-update
- lottie-spm — Lottie animations
- swiftui-introspect — NSView introspection
- MacroVisionKit (TheBoredTeam) — camera effects
