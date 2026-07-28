# OttoWM

A tiny virtual workspace manager for macOS.

Inspired on  [2bwm](https://github.com/venam/2bwm) and [wmutils](https://github.com/wmutils/core). OttoWM does **not tile**.

## Functionality

OttoWM fakes multiple workspaces on a **single native macOS Space**: the active workspace's windows stay where you put them; every other workspace's windows are parked off-screen and restored to their exact frame when you switch back. No native Spaces, no animations, no Mission Control involved.

- Virtual workspaces on a single native Space
- Focus history per workspace
- Tabbed windows (Safari, Terminal, Finder, …) support.
- Compatible with native interaction: if you reach a hidden window via Cmd-Tab, the Dock, or Mission Control, OttoWM switches to that window's workspace
- Headless agent: no Dock icon, no menu bar item, no UI.

### Hotkeys

There is no configuration yet, but the following hotkeys are hardcoded:

| Binding | Action |
|---|---|
| left&nbsp;Option + 1–4 | Switch to workspace |
| left&nbsp;Option + Shift + 1–4 | Move focused window to workspace |

> Only the **left** Option key triggers the bindings; the right one is left free for typing special characters.

## Limitations

- Key bindings are hardcoded (left Option + 1–4).
- Single screen only.
- Fullscreen windows are ignored (they live on their own native Space anyway).

## Build and test

```sh
make build   # xcodebuild, code signing disabled
make test    # runs the OttoWMTests unit-test bundle
```

Run a single test:

```sh
xcodebuild -scheme OttoWM test CODE_SIGNING_ALLOWED=NO \
  -only-testing:OttoWMTests/WorkspacesTests/testWindowAssignment
```

No third-party dependencies.

## Background

OttoWM is a native Swift port of a Hammerspoon Spoon (VirtualSpaces.spoon). The off-screen-hiding approach (same mechanism as AeroSpace) exists because programmatically moving windows between real Spaces is broken on macOS Sequoia onwards. The only private API used is `_AXUIElementGetWindow`, for stable window ids.
