<div align="center">
  <h3>
    <img src="App/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" alt="OttoWM icon" width="128" height="128"><br>
    OttoWM
  </h3>
  <p>
    A tiny virtual workspace manager for macOS<br>
    <i>Inspired on <a href="https://github.com/venam/2bwm">2bwm</a> and <a href="https://github.com/wmutils/core">wmutils</a>,<br>
    and on <a href="https://github.com/nikitabobko/AeroSpace">AeroSpace</a> technical aspects</i>.
  </p>
</div>

<hr>

OttoWM fakes multiple workspaces on a **single native macOS Space**: the active workspace's windows stay where you put them; every other workspace's windows are parked off-screen and restored to their exact frame when you switch back. No native Spaces, no animations, no Mission Control involved.

- Workspaces on a single native Space
- Native Tabbed windows (Terminal, Ghostty, Finder, …) support.
- Compatible with native interaction: if you reach a hidden window via Cmd-Tab, the Dock, or Mission Control, OttoWM switches to that window's workspace
- Headless agent: no Dock icon, no menu bar item, no UI.
- Leaves the desk as it found it: quitting the agent (`killall OttoWM`) puts every parked window back at its own frame first.

### Hotkeys

Out of the box (bundled config):

| Binding | Action |
|---|---|
| left&nbsp;Option + 1–4 | Switch to workspace |
| left&nbsp;Option + Shift + 1–4 | Move focused window to workspace |

> Only the **left** Option key triggers the default bindings; the right one is left free for typing special characters™.

## Install

Download the latest `OttoWM-<version>.zip` from [Releases](https://github.com/brennovich/ottowm/releases):

```sh
unzip OttoWM-0.1.0.zip -d /Applications
xattr -cr /Applications/OttoWM.app
open /Applications/OttoWM.app
```

The app is ad-hoc signed, so Gatekeeper refuses it as coming from an unidentified developer until you clear the quarantine attribute. OttoWM needs Accessibility permission; grant it in System Settings → Privacy & Security → Accessibility on first launch.

## Configuration

OttoWM reads `~/.config/ottowm/ottowm` (or `$XDG_CONFIG_HOME/ottowm/ottowm`. The defaults ship inside the app, so start from those:

```sh
mkdir -p ~/.config/ottowm
cp /Applications/OttoWM.app/Contents/Resources/ottowm ~/.config/ottowm/
```

One `key combo = action` per line. Blank lines are skipped; there is no quoting, no sections and no comments:

```
lopt-1 = switch-to-workspace 1
lopt-shift-1 = move-window-to-workspace 1

hyper-5 = switch-to-workspace 5
```

Actions take a workspace number, and workspaces are created on demand:

| Action                       | Effect                                 |
|------------------------------|----------------------------------------|
| `switch-to-workspace N`      | Switch to workspace N                  |
| `move-window-to-workspace N` | Move the focused window to workspace N |

Config is read once at launch; restart the agent to pick up edits. Errors show up in the log:

```sh
log stream --level debug --predicate 'subsystem == "com.github.brennovich.ottowm" && category == "config"'
```

## Limitations

- No Multi-Single screen support (yet)
- No Window controls (move, resize)

<hr>

**Note**: though I've been a software developer for quite some time, this project was built with the assistance of AI tools, undertaking the opportunity to learn Swift and macOS development.
