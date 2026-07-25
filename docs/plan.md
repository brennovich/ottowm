# OttoWM — native Swift port of the VirtualSpaces Hammerspoon Spoon

## Context

`VirtualSpaces` (at `~/code/VirtualSpaces`) is a Hammerspoon Spoon (Lua). It fakes
multiple workspaces on a **single** native macOS Space: the current workspace's
windows stay in place, every other workspace's windows are shoved to the bottom-right
corner (macOS clamps them to a ~1×38px nub) and restored to their exact saved frame on
switch. All the window/space bookkeeping, focus history, and tab-group logic is pure
state; the OS-touching work is hidden behind a swappable "space strategy" seam.

`OttoWM` (this project, at `~/code/OttoWM`) is a standalone Swift app that provides the
same capability without Hammerspoon, including global key bindings. Work proceeds **step
by step**; this plan is the full roadmap but only **Step 1 (Xcode project + core package
scaffold)** is executed first.

**Design guidance:** do **not** build a 1:1 `hs.*` shim. Prefer idiomatic native
services and **public** frameworks wherever they achieve similar capability; fall back to
private APIs only when nothing public can do the job (see AeroSpace reference — one private
symbol total).

Decisions (confirmed):
- **Name:** display/product name `OttoWM`; bundle id `com.github.brennovich.ottowm` (lowercase). Core package `OttoCore`.
- **Location:** standalone repo at `~/code/OttoWM` (separate from the Lua source at `~/code/VirtualSpaces`).
- **Shell:** headless background agent, `LSUIElement = YES`, no UI (menu bar item can come later).
- **Structure:** a **single Xcode app target** `OttoWM` holds all source (app + pure logic), plus a **host-less `OttoWMTests`** unit-test target (no `TEST_HOST`/`BUNDLE_LOADER`) so tests run fast without launching the agent or triggering the Accessibility prompt. Pure-logic files are compiled into both targets (target membership). No separate module — matches Amethyst's single-target + test-target layout. (Earlier a separate `OttoCore` package was scaffolded then collapsed in, to keep everything named `OttoWM`.)
- **Distribution:** personal/local only. **No App Sandbox** (Accessibility control of other apps + any private API can't be sandboxed). Never App Store.
- **Dependencies:** **Swift Package Manager only** — no CocoaPods, no Carthage. Any third-party lib (e.g. `KeyboardShortcuts`, `MASShortcut`) is added via Xcode "Add Package Dependency". Preference: zero third-party deps where the standard library / system frameworks suffice.

## Capability → native service (what to build, native-first)

We build idiomatic Swift services, not `hs.*` clones. Public API strongly preferred.

| Capability (was Hammerspoon) | Native approach | Public? |
|---|---|---|
| Window geometry/focus/flags/tabCount/id (`hs.window`) | Accessibility (`AXUIElement`: position/size/focused/raise), `NSRunningApplication`; CGWindowID via `_AXUIElementGetWindow` | Public AX (one private accessor for the stable window id) |
| Window lifecycle events (`hs.window.filter`) | `AXObserver` per app (windowCreated / focusedWindowChanged / uiElementDestroyed) + `NSWorkspace` launch/activate/terminate | **Public** |
| **Space-change awareness** (`hs.spaces.activeSpaceOnScreen`, manual-nav detection) | **`NSWorkspace.activeSpaceDidChangeNotification`** (public) tells us the active Space changed; a hidden window gaining focus (AX) tells us the user navigated to a stored window | **Public** — replaces CGS active-space polling |
| **Return to our Space** (`hs.spaces.gotoSpace`) | Focus/raise a managed window via AX — macOS switches to that window's Space natively | **Public** — replaces `CGSManagedDisplaySetCurrentSpace` |
| Hide a window off-screen (the core trick) | `AXSize`/`AXPosition` set to the clamped corner frame; restore saved frame | **Public** |
| Screen bounds/visibleFrame/UUID (`hs.screen`) | `NSScreen` / `CGDisplay` + `CGDisplayCreateUUIDFromDisplayID` | **Public** |
| Global hotkeys (`hs.hotkey`) | `KeyboardShortcuts`/`MASShortcut` (SPM) or Carbon `RegisterEventHotKey` | **Public** |
| Basic logging (`hs.logger`) | `print` for now → `os.Logger`/`OSLog` later | **Public** |
| Consolidate to one Space / `removeSpace` / Mission Control (init-only) | **Likely drop.** Native-first: operate on whichever Space we start on and ignore others. Deleting the user's Spaces needs private CGS; only reintroduce if a real need appears in Step 6. | Prefer none |

Net effect vs. the Lua version: the private SkyLight/CGS layer shrinks to *possibly
nothing*. Finalized in Step 6.

Pure-logic files (no OS dependency, port ~1:1, unit-tested via the host-less
`OttoWMTests` target), source at `~/code/VirtualSpaces`: `SpacesModel.lua`, `Window.lua`.

**Deferred as optimizations (start simple — not in this port):**
- `WindowCache.lua` — caches `hs.window.get()` to dodge its 40–130ms cost. Start with
  direct window lookups; add a cache only if lookups prove slow.
- `Telemetry.lua` — `span()` timing/instrumentation wrapper. Start with plain logging;
  no timing spans. Constructors won't take a `telemetry` dependency.

## Reference: Amethyst (github.com/ianyh/Amethyst)

- **AppKit, non-sandboxed, Accessibility-driven, macOS 10.15+** — same shape as our plan.
- AX/window/space wrappers are an internal layer (historically the **Silica** framework) —
  mirrors our protocol seam (`Space` strategy + `Window` ref) + AX service split inside the `OttoWM` target.
- **Global hotkeys via a maintained SPM lib**, not hand-rolled Carbon: `KeyboardShortcuts`
  (sindresorhus) and `MASShortcut` (shpakovski).
- Reads Spaces via **private CGS** (`CGSInternal`) — the accepted fallback if Step 6 needs it.
- **Launch-at-login:** it uses `LoginServiceKit`; on macOS 13+ prefer public
  **`SMAppService.mainApp.register()`**. Not in Step 1.
- Non-goals for us: RxSwift, Cartography/UI, Sparkle, Yams, SwiftyBeaver (we use `OSLog`).

## Reference: AeroSpace (github.com/nikitabobko/AeroSpace)

Closest architectural precedent — VirtualSpaces copied AeroSpace's off-screen-hiding strategy.
- **Emulates workspaces by moving windows off-screen**, not via native Spaces — identical to
  our core mechanism (keep corner-hiding, don't reintroduce real Spaces).
- **Uses exactly one private API: `_AXUIElementGetWindow`** and nothing else — no private CGS.
  **Hard constraint for OttoWM:** the only sanctioned private symbol anywhere is
  `_AXUIElementGetWindow`; Step 6 defaults to no CGS.
- **Swift, macOS 13+** — same platform floor.
- CLI-first + background daemon, **TOML config**. We start headless with in-code config; a
  TOML/CLI control surface is a plausible later direction (not in this plan).

## Full roadmap (sequence)

- **Step 1 — Scaffold (this step, done):** `OttoWM` Xcode app (headless, non-sandboxed) + host-less `OttoWMTests` target, building, tests green, running an empty agent that requests Accessibility.
- **Step 2 — Pure logic (done):** ported `SpacesModel`→`Workspaces` and `Window` into the `OttoWM` target with tests (translated from `~/code/VirtualSpaces/tests/test_*.lua`) in `OttoWMTests` (30 tests green). The model's OS-free seams are the `Space` strategy protocol (`Space.swift`) and the `Window` ref protocol; `Placement` (active/storage) accompanies them. **No `ScreenRef` at this layer** — the pure model never touches screens, since `Space` hides all screen interaction inside the strategy (in `VirtualSpace.lua` every `hs.screen` call lives inside the strategy). No `WindowCache`/`Telemetry` (deferred). Each new logic file joins both the `OttoWM` and `OttoWMTests` targets.
- **Step 3 — Screen service (done):** thin `NSScreen`/`CGDisplay`-backed screen provider (`fullFrame`/`visibleFrame`/UUID via `CGDisplayCreateUUIDFromDisplayID`). **A `Screen` protocol is deferred to Step 6, not introduced here** — it is a seam *inside* the `Space` implementation, not a model seam, so its shape should be driven by the real geometry call sites (`_hiddenFrameFor`, `_recoverWindowsStuckAtHiddenEdge`) rather than guessed up front. Extract the protocol when Step 6 gives it a consumer.
- **Step 4 — Window service:** AX-backed window (frame get/set, focus, flags, tabCount, CGWindowID).
- **Step 5 — Event service:** `AXObserver` + `NSWorkspace` → created/focused/destroyed callbacks and manual-navigation detection.
- **Step 6 — Space awareness:** `NSWorkspace.activeSpaceDidChangeNotification` + AX-focus-to-switch; **decide** whether any private CGS is needed (default: no). Port `VirtualSpace.lua` as the concrete `Space` implementation; **extract the `Screen` protocol here** (deferred from Step 3) so its geometry (`_hiddenFrameFor`, `_recoverWindowsStuckAtHiddenEdge`) is unit-testable against a stub screen.
- **Step 7 — Hotkeys + orchestrator:** global hotkeys; port `init.lua` orchestration into an `Engine`; default bindings (alt+1..4 switch, alt+shift+1..4 move); acceptance pass on a real machine.

## Step 1 — detailed execution (done)

Actual layout (`~/code/OttoWM`):
```
OttoWM/
  docs/plan.md
  AppDelegate.swift               (@main, headless agent, requests Accessibility)
  AppInfo.swift                   (placeholder logic: version — member of both targets)
  OttoWM-Info.plist               (LSUIElement injected via build setting)
  OttoWM.entitlements             (App Sandbox = false)
  Assets.xcassets
  OttoWM.xcodeproj                (targets: OttoWM app + OttoWMTests)
  OttoWMTests/AppInfoTests.swift  (XCTest, host-less logic bundle)
```

What was set up:
1. **App target `OttoWM`** — `com.github.brennovich.ottowm`, `LSUIElement = YES`
   (`INFOPLIST_KEY_LSUIElement`), `NSApp.setActivationPolicy(.accessory)`, deployment
   target macOS 15.2. `AppDelegate.applicationDidFinishLaunching` requests Accessibility
   via `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])`.
2. **No sandbox** — `OttoWM.entitlements` has `com.apple.security.app-sandbox = false`;
   `CODE_SIGN_ENTITLEMENTS = OttoWM.entitlements`.
3. **Host-less test target `OttoWMTests`** — product type unit-test bundle with **no
   `TEST_HOST`/`BUNDLE_LOADER`**, so `xcodebuild test` runs it without launching the agent.
   Pure-logic files are added to both `OttoWM` and `OttoWMTests` (e.g. `AppInfo.swift`);
   tests reference the types directly (no `@testable import`).
4. **No private-framework work.** If CGS is ever needed (Step 6), bridge it via a small
   module map over `/System/Library/PrivateFrameworks/SkyLight.framework`. Default: not needed.

## Verification (Step 1) — passing

- `xcodebuild -scheme OttoWM build CODE_SIGNING_ALLOWED=NO` → `** BUILD SUCCEEDED **`.
- `xcodebuild -scheme OttoWM test CODE_SIGNING_ALLOWED=NO` → `** TEST SUCCEEDED **`,
  1 test, ~0.003s, no app launch (confirms the host-less bundle).
- Built `OttoWM.app` Info.plist: `LSUIElement = true`, `CFBundleIdentifier = com.github.brennovich.ottowm`.
- Remaining manual check (needs GUI): **⌘R** in Xcode → no window/Dock icon, Accessibility
  prompt on first launch, console logs `OttoWM 0.0.1 launched; accessibility trusted: …`.

Each later step ends with `xcodebuild test` green for new pure logic plus a manual smoke test on
the real machine for the OS-touching layer, culminating in a reimplemented acceptance pass in Step 7.

## Step 3 — detailed plan (done)

**Goal:** a thin concrete screen provider backed by `NSScreen`/`CGDisplay`. **No `Screen`
protocol** — deferred to Step 6, extracted when the `VirtualSpace` geometry gives it a real
consumer (see Step 3 in the roadmap).

**What it exposes** (the fields the future `VirtualSpace` port needs — `_hiddenFrameFor`,
`_recoverWindowsStuckAtHiddenEdge`, and the main-screen UUID):
- `fullFrame: CGRect` — the display's full bounds (was `hs.screen:fullFrame()`).
- `visibleFrame: CGRect` — bounds minus menu bar and Dock (was `hs.screen:frame()`).
- `uuid: String?` — via `CGDisplayCreateUUIDFromDisplayID` + `CFUUIDCreateString`.

**Coordinate system (the one real decision):** frames are returned in **top-left (AX) origin,
y increasing downward** — the same space as AX window frames (`AXPosition`/`AXSize`) that every
other OttoWM layer uses. `NSScreen` reports **bottom-left (Cocoa) origin**, so `y` is flipped
against the **primary** display's height (the screen whose Cocoa `frame.origin == .zero`); `x`,
`width`, `height` are unchanged. Keeping screen and window geometry in one origin means the
Step 6 corner-hiding math ports straight across from the Lua (which already worked in `hs`'s
top-left space).

**Structure & target membership:** one file `Core/MainScreen.swift`. `Core/` is a
filesystem-synchronized group already attached to **both** the `OttoWM` and `OttoWMTests`
targets, so the file compiles into both automatically — no `.pbxproj` edits, no `@testable
import`. Split the file so the pure part is testable:
- a pure y-flip helper (Cocoa rect + primary height → top-left rect) — **unit-tested, TDD**;
- a thin `MainScreen` wrapper that reads `NSScreen.main` / `CGMainDisplayID()` and applies the
  helper — **not unit-tested** (needs a live display), covered by the manual smoke test.

**What was built:** `Core/MainScreen.swift` — the pure `topLeftFrame(fromCocoa:primaryHeight:)`
y-flip helper plus a `MainScreen` struct wrapping `NSScreen.main` (`fullFrame`/`visibleFrame`)
and the UUID via `NSScreenNumber` → `CGDisplayCreateUUIDFromDisplayID` → `CFUUIDCreateString`.
Tests in `OttoWMTests/MainScreenTests.swift` (table-driven, helper only). No `Screen` protocol
(deferred to Step 6).

**Verification:**
- `xcodebuild test` green — 31 tests, including the flip-helper cases (primary no-op, menu-bar
  offset on `visibleFrame`, non-zero-origin flip above and right of the primary).
- Manual smoke test on the real machine (pending): print `MainScreen` `fullFrame`/`visibleFrame`/
  `uuid` and confirm they match the actual display in top-left coordinates.
