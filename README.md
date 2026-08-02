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

Out of the box:

| Binding | Action |
|---|---|
| left&nbsp;Option + 1–4 | Switch to workspace |
| left&nbsp;Option + Shift + 1–4 | Move focused window to workspace |

> Only the **left** Option key triggers the default bindings; the right one is left free for typing special characters.

## Configuration

OttoWM reads `~/.config/ottowm/ottowm` (or `$XDG_CONFIG_HOME/ottowm/ottowm`, or whatever
`$OTTOWM_CONFIG` points at). The defaults ship inside the app, so start from those:

```sh
mkdir -p ~/.config/ottowm
cp /Applications/OttoWM.app/Contents/Resources/ottowm ~/.config/ottowm/
```

One `key combo = action` per line. Blank lines are skipped; there is no quoting, no sections and no
comments:

```
lopt-1 = switch-to-workspace 1
lopt-shift-1 = move-window-to-workspace 1

hyper-5 = switch-to-workspace 5
```

Your file **replaces** the defaults, so list every binding you want. The bundled defaults only stand
in when there is no file at all: a file that is there but fails to parse stops the agent with the
reason in the log, rather than silently leaving you with bindings you did not write. An empty file is
taken at its word and binds nothing.

Parsing stops at the first problem, so a file with several mistakes reports them one at a time.

Binding the same combo twice is fine: the last line wins. Two *different* combos that one keystroke
could satisfy are not. `opt-1` and `lopt-1` both fire on left-Option-1, and since nothing decides
between them the file is rejected rather than picking one arbitrarily.

A key combo is `modifier-…-key`:

- **Modifiers** — `cmd`, `ctrl`, `opt` (or `alt`), `shift`. Prefix `l` or `r` to pin a side (`lopt`,
  `rcmd`); `hyper` is short for `cmd-ctrl-alt-shift`. Any modifier you do not name must be absent,
  so `opt-1` does not fire on Cmd-Option-1.
- **Keys** — `0`–`9`, `a`–`z`, `f1`–`f20`, `space`, `tab`, `return`, `escape`, `delete`, the arrow
  keys, `home`/`end`/`pageup`/`pagedown`, punctuation (`minus`, `equal`, `comma`, …), or
  `keycode:79` for anything unnamed. Names follow the ANSI US layout, because virtual key codes
  address physical positions.

Actions take a workspace number, and workspaces are created on demand — bind a 9 if you want nine:

| Action | Effect |
|---|---|
| `switch-to-workspace N` | Switch to workspace N |
| `move-window-to-workspace N` | Move the focused window to workspace N |

Config is read once at launch; restart the agent to pick up edits. Errors show up in the log:

```sh
log stream --predicate 'subsystem == "com.github.brennovich.ottowm" && category == "config"'
```

## Limitations

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

OttoWM is a native Swift port of a Hammerspoon Spoon (VirtualSpaces.spoon). The off-screen-hiding approach (same mechanism as AeroSpace) exists because programmatically moving windows between real Spaces is broken on macOS Sequoia onwards.
