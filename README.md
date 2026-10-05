# PinTop

**English** | [Русский](README.ru.md)

A macOS menu bar app (Apple Silicon, macOS 14+) that keeps the window you choose above all others, like PowerToys "Always on Top".

## Features

- Pin or unpin the active window with a shortcut (default `⌃⌘T`).
- Unpin all windows with a shortcut (default `⌃⇧⌘T`).
- Pinned windows get a border. You can set its width, opacity, color, gradient (optionally animated) and outer glow. The border's corner radius matches the window's own radius, measured from the transparent corners of the captured frame.
- Sounds when a window is pinned or unpinned (can be turned off in Settings).
- Menu bar icon: `mdi-pin` (F0403) when at least one window is pinned, `mdi-pin-off` (F0404) otherwise.
- Menu: Pin/Unpin Active Window, Unpin All Windows, a list of pinned windows (click one to unpin it), Settings…, Quit.
- Settings: a General tab (launch at login, sounds, shortcuts, permission status) and a Border Appearance tab (border options with a live preview).

## Installation

1. Download `PinTop-<version>-arm64.zip` from [Releases](https://github.com/nex8er/pintop/releases/latest), unzip it and move `PinTop.app` to `/Applications`.
2. The app is not notarized, so macOS blocks it on first launch. Click **Open Anyway** in **System Settings › Privacy & Security**, or run:
   ```bash
   xattr -dr com.apple.quarantine /Applications/PinTop.app
   ```
3. Grant both permissions (see below) and restart PinTop.

## How it works

macOS has no public API for changing the window level of **another** app's window. PinTop instead places a transparent floating panel over the pinned window:

- **When the window is active**, the panel shows only the border, and clicks go through to the window.
- **When the window is in the background**, the panel shows a live view of the window (ScreenCaptureKit), so it stays visible above other windows. Clicking the view focuses the real window, and scrolling is passed to the window directly.

The border follows the window as you move or resize it. It hides when the window is minimized, its app is hidden, or the window is on another Space. Closing a window unpins it automatically.

## Permissions

PinTop needs both of these (System Settings › Privacy & Security):

- **Accessibility**, to find the active window, track it and focus it.
- **Screen & System Audio Recording**, for the live view of the window. Restart PinTop after granting it.

## Building

```bash
scripts/build.sh            # build build/PinTop.app
scripts/build.sh install    # build, install to /Applications and launch
```

The script signs the app with the first `Apple Development` or `Developer ID` certificate it finds. Because the signature stays the same, granted permissions survive rebuilds. To use a different identity, set `CODESIGN_IDENTITY`; `-` means ad-hoc signing.

Turn on "Launch at login" after the app is installed in `/Applications`.

## Sounds

`Resources/Sounds/pin.caf` and `unpin.caf` are `switch_007` and `switch_006` from [Kenney Interface Sounds](https://kenney.nl/assets/interface-sounds) (CC0), converted to CAF. To change the sounds, replace these files and rebuild the app.
