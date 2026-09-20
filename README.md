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
  <p>
    <a href="https://github.com/brennovich/ottowm/releases/latest"><img src="https://img.shields.io/github/v/release/brennovich/ottowm?sort=semver" alt="Latest release"></a>
    <a href="https://github.com/brennovich/ottowm/actions/workflows/deployment-pipeline.yml"><img src="https://img.shields.io/github/actions/workflow/status/brennovich/ottowm/deployment-pipeline.yml?branch=main&amp;label=pipeline" alt="Pipeline status"></a>
    <a href="https://github.com/brennovich/ottowm/actions/workflows/deployment-pipeline.yml"><img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fgist.githubusercontent.com%2Fbrennovich%2Faddbbeb4ae9b27eb25fcdd5bc136ee5d%2Fraw%2Fcoverage.json" alt="Coverage"></a>
  </p>
</div>

<hr>

![OttoWM preview](assets/preview.png)

OttoWM is a window manager for macOS under intense development.

Some important foundations:
- No dependency on third-party libraries or frameworks
- Relies on macOS public APIs only (up until now)
- Backwards compatibility, it works on macOS Big Sur onwards

## Features

It brings the workflow of a common Linux window manager to macOS, without fighting with Mission Control:

- Native macOS Spaces keep working, whatever happens there won't affect OttoWM
- Full screen apps are restored to their respective state when leaving full screen
- Reaching a window through Cmd-Tab, the Dock or Mission Control switches to its workspace

### Workspaces

Multiple workspaces on a **single native macOS Space**: no Space switch animation, no Mission Control. A window that leaves a workspace is parked in the bottom right corner, a point of it left on screen, and comes back to the frame it had, with the focus it had.

### Pager

OttoWM relies on the same strategy as [AeroSpace](https://nikitabobko.github.io/AeroSpace/guide#emulation-of-virtual-workspaces), a tiny portion of windows accumulates in the bottom right corner, so the Pager covers this spot while offering nice other features.

<table>
  <tr>
    <th width="33%" align="center">Current workspace badge</th>
    <th width="33%" align="center">Smart auto-hide</th>
    <th width="33%" align="center">Secure input cue</th>
  </tr>
  <tr>
    <td align="center"><img src="assets/current-workspace-badge.gif" alt="Current workspace badge" width="200"></td>
    <td align="center"><img src="assets/smart-autohide.gif" alt="Smart auto-hide" width="200"></td>
    <td align="center"><img src="assets/secure-input-cue.gif" alt="Secure input cue" width="200"></td>
  </tr>
  <tr>
    <td valign="top">The tab tells which workspace is current.</td>
    <td valign="top">It squeezes against the screen edge while a window reaches into the corner, and comes back once the corner is free.</td>
    <td valign="top">A pulse cue irradiates while an app holds secure input, e.g. a password field is focused, Password.app auth: every keystroke is withheld from OttoWM, so no binding works.</td>
  </tr>
</table>

### Tabbed windows

Native tab groups (Terminal, Ghostty, Finder, …) count as one window: sending a tab to another workspace takes the whole group, and the group comes back with the tab that was active.

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

```
# This is a comment

# One `key combo = action`
lopt-1 = switch-to-workspace 1

# or `setting = value` per line
spacing = 20

lopt-shift-1 = move-window-to-workspace 1
lopt-h = focus west
lopt-shift-h = move-window west

# CMD+Ctrl+Option+Shift+Q quits OttoWM
hyper-5 = switch-to-workspace 5
```

| Entry                             | Type    | Default                                                                 | Description                                                                                            |
|-----------------------------------|---------|-------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------|
| switch-to-workspace&nbsp;`N`      | Action  | left&nbsp;Option&nbsp;+&nbsp;1–4                                        | Switch to workspace N                                                                                  |
| move-window-to-workspace&nbsp;`N` | Action  | left&nbsp;Option&nbsp;+&nbsp;Shift&nbsp;+&nbsp;1–4                      | Move the focused window to workspace N                                                                 |
| focus&nbsp;`D`                    | Action  | left&nbsp;Option&nbsp;+&nbsp;H/J/K/L                                    | Focus the window `D` leads to: `north`, `east`, `south` or `west`                                      |
| move-window&nbsp;`D`              | Action  | left&nbsp;Option&nbsp;+&nbsp;Shift&nbsp;+&nbsp;H/J/K/L                  | Move the focused window `D` by the spacing                                                             |
| resize&nbsp;`C`                   | Action  | left&nbsp;Option&nbsp;+&nbsp;Ctrl&nbsp;+&nbsp;Shift&nbsp;+&nbsp;H/J/K/L | Resize the focused window by the spacing: `C` is `wider`, `narrower`, `taller` or `shorter`            |
| center-window                     | Action  | left&nbsp;Option&nbsp;+&nbsp;Ctrl&nbsp;+&nbsp;C                         | Center the focused window on the screen, keeping its size                                              |
| maximize                          | Action  | left&nbsp;Option&nbsp;+&nbsp;Ctrl&nbsp;+&nbsp;M                         | Fill the screen with the focused window (toggable)                                                     |
| tile&nbsp;`D`                     | Action  | left&nbsp;Option&nbsp;+&nbsp;Ctrl&nbsp;+&nbsp;H/J/K/L                   | Tile the focused window to the half of the screen `D` leads to (toggable)                              |
| quit                              | Action  | Cmd&nbsp;+&nbsp;Ctrl&nbsp;+&nbsp;Option&nbsp;+&nbsp;Shift&nbsp;+&nbsp;Q | Quit OttoWM, putting every parked window back                                                          |
| restart                           | Action  | Cmd&nbsp;+&nbsp;Ctrl&nbsp;+&nbsp;Option&nbsp;+&nbsp;Shift&nbsp;+&nbsp;R | Read the config file again and rebind the keys                                                         |
| pager&nbsp;=&nbsp;`off`           | Setting | `on`                                                                    | Hide the tab in the bottom right corner that shows the current workspace and covers the parked windows |
| spacing&nbsp;=&nbsp;`N`           | Setting | `15`                                                                    | Number of points for the _gap_, the `move-window` _step_ and the `resize` change                       |

**Note**: _by default only the **left** Option key triggers the default workspace bindings; the right one is left free for typing special characters™._

## Debugging

```sh
log stream --level debug --predicate 'subsystem == "com.github.brennovich.ottowm"'
```

## Limitations

- No support for two displays at once (yet). But position and windows size are preserved per display
- Switching to a workspace from an unmanaged native Space or a full screen app only works when that workspace has a window to activate. When it has none, another workspace that does is activated instead, because macOS has no public API to switch Spaces

<hr>

**Note**: I have been a software developer for a long time, but this project was built with the help of AI tools, as an opportunity to learn Swift and macOS development.
