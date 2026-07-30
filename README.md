# InputSwitcher

**English** | [한국어](README.ko.md)

A macOS menu bar app that switches keyboard input sources instantly with dedicated hotkeys.
A modern reimplementation of the abandoned [kawa](https://github.com/hatashiro/kawa).

- Example: `⌃⌥⇧⌘J` → Korean, `⌃⌥⇧⌘K` → English, `⌃⌥⇧⌘L` → Japanese (fully configurable)
- Works around macOS's infamous **CJK input source switching bug** (where the menu bar
  icon changes but you keep typing in the previous language)
- Launcher-safe: switching while Spotlight / Raycast is open does **not** dismiss the panel
- **Per-app auto switch**: activate a chosen app and the input source changes automatically
  (e.g. Terminal/iTerm → always English)
- Zero dependencies — no Karabiner, no macism. One app does it all
- Built-in update check against GitHub Releases

## ⚠️ Disclaimer

- **This is a personal project.** Provided "as is" with no warranty of any kind; the
  developer is not responsible for any issues caused by its use.
- When switching to a CJK source, a tiny window flashes in the bottom-right corner for
  ~150 ms. This is **expected behavior** — it is the workaround for the macOS bug.
- Accessibility permission is requested only on the fallback path. Normal operation
  requires no permissions at all.
- Requires macOS 14 (Sonoma) or later, Apple Silicon/Intel. Developed and tested on
  macOS 26 (Tahoe).

## Install

### Download (recommended)

Grab the latest zip from [**Releases**](https://github.com/flutterkage2k/mac_inputswitcher_260721/releases),
unzip, and move `InputSwitcher.app` to your Applications folder.
The app is **Developer ID signed and notarized by Apple**, so it runs without
Gatekeeper warnings.

### Build from source

Only Xcode Command Line Tools required.

```bash
git clone https://github.com/flutterkage2k/mac_inputswitcher_260721.git
cd mac_inputswitcher_260721
./scripts/bundle.sh
cp -Rf build/InputSwitcher.app /Applications/
open /Applications/InputSwitcher.app
```

## Usage

1. Click the keyboard icon in the menu bar
2. Press **단축키설정** (set hotkey) next to each input source and type the shortcut
   you want (a modifier key — ⌘/⌥/⌃/⇧ — is required)
3. Switch instantly from any app. Enable "로그인 시 시작" (launch at login) to start
   automatically after boot
4. Add per-app rules under "앱별 자동 전환" (per-app auto switch): pick a running app
   and an input source

## How it works

`TISSelectInputSource` has a long-standing macOS bug: when a background app switches
to a CJK input source, only the menu bar icon changes — the actual IME does not
(still present on macOS 26). InputSwitcher fixes this with a **focus commit** after
selecting: the app briefly becomes key and returns focus to the previous app (the
same cycle [macism](https://github.com/laishulu/macism) uses), which makes the switch
actually take effect. When a Spotlight/Raycast panel is open, the commit is skipped so
the panel doesn't get dismissed, and a plain select is performed instead.

## Tuning

- CJK commit wait time (default 150 ms — the minimum stable value on Tahoe):
  `defaults write dev.heesung.InputSwitcher verifyDelayMS -int 100`
  Lower is faster but may drop switches. Takes effect after an app restart.
- Diagnostic log: `~/Library/Logs/InputSwitcher.log` (capped at 1 MB). Please attach
  it when reporting issues.
- Source builds (ad-hoc signed) may re-prompt for accessibility permission (fallback
  path only) after each rebuild. Notarized builds from Releases are unaffected.
- "Launch at login" only works when running from an .app bundle (ignored under
  `swift run`).

## Development

```bash
swift build   # build
swift test    # unit tests (18)
./scripts/bundle.sh   # create .app bundle (ad-hoc signed, local use)
./scripts/release.sh  # Developer ID sign + notarize + publish release (maintainer)
```

## License

MIT — [@kage2k](https://github.com/flutterkage2k)
