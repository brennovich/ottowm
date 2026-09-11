<div align="center">
  <h3>
    <img src="App/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" alt="OttoWM icon" width="128" height="128"><br>
    OttoWM
  </h3>
  <p>
    A tiny virtual workspace manager for macOS<br>
    <i>Inspired by <a href="https://github.com/venam/2bwm">2bwm</a> and <a href="https://github.com/wmutils/core">wmutils</a>,<br>
    and by the technical approach of <a href="https://github.com/nikitabobko/AeroSpace">AeroSpace</a></i>.
  </p>
</div>

<hr>

OttoWM fakes multiple workspaces on a **single native macOS Space**. No native Spaces, no animations, no Mission Control involved.

Some important features:
- Native Tabbed windows (Terminal, Ghostty, Finder, …) support
- Plays nice with macOS features:
  - You can create native macOS Spaces, OttoWM just ignores them
  - Compatible with native interaction: if you reach a hidden window via Cmd-Tab, the Dock, or Mission Control, OttoWM autoswitches to that window's workspace
  - Fullscreen apps are ignored

Some important foundations:
- Headless agent: no Dock icon, no menu bar item
- No dependency on third-party libraries or frameworks
- Relies on macOS public APIs only (up until now)

### Hotkeys

Out of the box (bundled config):

| Binding                                                                 | Action                                                                                    |
|-------------------------------------------------------------------------|-------------------------------------------------------------------------------------------|
| left&nbsp;Option&nbsp;+&nbsp;1–4                                        | Switch to workspace                                                                       |
| left&nbsp;Option&nbsp;+&nbsp;Shift&nbsp;+&nbsp;1–4                      | Move focused window to workspace                                                          |
| left&nbsp;Option&nbsp;+&nbsp;H/J/K/L                                    | Focus the window to the west/south/north/east                                             |
| left&nbsp;Option&nbsp;+&nbsp;Shift&nbsp;+&nbsp;H/J/K/L                  | Move the focused window west/south/north/east                                             |
| left&nbsp;Option&nbsp;+&nbsp;Ctrl&nbsp;+&nbsp;Shift&nbsp;+&nbsp;H/J/K/L | Make the focused window narrower/taller/shorter/wider                                     |
| left&nbsp;Option&nbsp;+&nbsp;Ctrl&nbsp;+&nbsp;C                         | Center the focused window, keeping its size                                               |
| left&nbsp;Option&nbsp;+&nbsp;Ctrl&nbsp;+&nbsp;M                         | Fill the screen with the focused window, or put it back                                   |
| left&nbsp;Option&nbsp;+&nbsp;Ctrl&nbsp;+&nbsp;H/J/K/L                   | Fill the west/south/north/east half of the screen with the focused window, or put it back |
| Cmd&nbsp;+&nbsp;Ctrl&nbsp;+&nbsp;Option&nbsp;+&nbsp;Shift&nbsp;+&nbsp;Q | Quit OttoWM                                                                               |
| Cmd&nbsp;+&nbsp;Ctrl&nbsp;+&nbsp;Option&nbsp;+&nbsp;Shift&nbsp;+&nbsp;R | Reload the config                                                                         |

> Only the **left** Option key triggers the default workspace bindings; the right one is left free for typing special characters™.

## Install

Download the latest `OttoWM-<version>.zip` from [Releases](https://github.com/brennovich/ottowm/releases):

```sh
curl -fsSL "$(curl -fsSL https://api.github.com/repos/brennovich/ottowm/releases/latest | grep -o 'https://[^"]*\.zip')" -o OttoWM.zip
unzip OttoWM.zip -d /Applications
xattr -cr /Applications/OttoWM.app
open /Applications/OttoWM.app
```

The app is ad-hoc signed, so Gatekeeper refuses it as coming from an unidentified developer until you clear the quarantine attribute. OttoWM needs Accessibility permission; grant it in System Settings → Privacy & Security → Accessibility on first launch.

## Configuration

You can define your own bindings by creating a `~/.config/ottowm/ottowm`, it's a good idea to start from the default:

```sh
mkdir -p ~/.config/ottowm
cp /Applications/OttoWM.app/Contents/Resources/ottowm ~/.config/ottowm/
```

One `key combo = action` per line. Blank lines and anything after a `#` are skipped; there is no quoting and no sections:

```
lopt-1 = switch-to-workspace 1
lopt-shift-1 = move-window-to-workspace 1
lopt-h = focus west
lopt-shift-h = move-window west

hyper-5 = switch-to-workspace 5
```

Workspaces are created on demand:

| Action                            | Effect                                                                                                |
|-----------------------------------|-------------------------------------------------------------------------------------------------------|
| switch-to-workspace&nbsp;`N`      | Switch to workspace N                                                                                 |
| move-window-to-workspace&nbsp;`N` | Move the focused window to workspace N                                                                |
| focus&nbsp;`D`                    | Focus the window `D` leads to: `north`, `east`, `south` or `west`                                     |
| move-window&nbsp;`D`&nbsp;`[N]`   | Move the focused window N points `D`                                                                  |
| resize&nbsp;`C`&nbsp;`[N]`        | Resize the focused window, N points, 15 by default: `C` is `wider`, `narrower`, `taller` or `shorter` |
| center-window                     | Center the focused window on the screen, keeping its size                                             |
| toggle-maximize                   | Fill the screen with the focused window (toggable)                                                    |
| fill&nbsp;`D`                     | Fill the half of the screen `D` leads to (toggable)                                                   |
| quit                              | Quit OttoWM, putting every parked window back                                                         |
| restart                           | Read the config file again and rebind the keys                                                        |

The `restart` action reloads the config without a relaunch: the windows stay where they are. A file that does not parse leaves the bindings already up in place. Errors show up in the log:

```sh
log stream --level debug --predicate 'subsystem == "com.github.brennovich.ottowm" && category == "config"'
```

## Limitations

- No support for two displays at once (yet). But position and windows size are preserved per display
- Switching to a workspace from an unmanaged native Space or a full screen app only works when that workspace has a window to activate. When it has none, another workspace that does is activated instead, because macOS has no public API to switch Spaces

<hr>

**Note**: I have been a software developer for a long time, but this project was built with the help of AI tools, as an opportunity to learn Swift and macOS development.
