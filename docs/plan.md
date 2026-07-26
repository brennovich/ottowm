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
- **Step 4 — Window service (done):** AX-backed window (frame get/set, focus, flags, tabCount, CGWindowID). Concrete `AXWindow` conforming to the `Window` protocol, plus the pure `AXGeometry` codec (TDD'd); the one sanctioned private symbol `_AXUIElementGetWindow` supplies the id. See the detailed section below.
- **Step 5 — Event service (done):** `AXObserver` (per running app) + `NSWorkspace` launch/terminate → created/focused/destroyed callbacks, plus the `allWindows()` enumeration deferred from Step 4. Concrete `AXWindowObserver` (closure-driven, no protocol); the pure TDD'd piece is `WindowEvent` + the `shouldObserveApplication` predicate. **Two scope decisions:** (1) **manual-navigation / space-change is fully deferred to Step 6** — Step 5 emits only window-lifecycle events, since the space-change signal (`activeSpaceDidChangeNotification`) and its interpretation live in the `Space` strategy; (2) **no `WindowObserver` protocol yet** — deferred to Step 7 when the `Engine` gives it a consumer + test stub (same precedent as the `Screen` protocol, Step 3 → Step 6). See the detailed section below.
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

## Step 4 — detailed plan (done)

**Goal:** the concrete AX-backed `Window` conformer the later `Space`/orchestrator layers
drive. Same shape as Step 3: extract the one genuinely pure sub-helper and TDD it; the live
AX wrapper is verified by manual smoke test (unit-testable window refs don't exist).

**Coordinate system:** AX (`kAXPositionAttribute`/`kAXSizeAttribute`) already reports
**top-left origin, y down** — OttoWM's convention. Window frames pass through with **no
y-flip** (unlike `MainScreen`, which flips `NSScreen`'s bottom-left frames).

**What was built:**
- `Core/AXGeometry.swift` — the pure `AXValue` ⇄ geometry codec: `encodeCGPoint`/`decodeCGPoint`
  and `encodeCGSize`/`decodeCGSize` (used by `AXWindow.frame`'s getter/setter). Decodes guard on
  `AXValueGetType` so a mismatched value returns `nil`. **Unit-tested, TDD** — round-trip cases plus
  the type-mismatch guard in `OttoWMTests/AXGeometryTests.swift`.
- `Core/AXWindow.swift` — `final class AXWindow: Window`. Wraps an `AXUIElement` + its
  `NSRunningApplication`. `id` via the single sanctioned private symbol
  `_AXUIElementGetWindow` (declared `@_silgen_name`, `@discardableResult`, file-private);
  `isStandard`/`isFullScreen`/`isMinimized` via subrole/`"AXFullScreen"`/`kAXMinimizedAttribute`;
  `tabCount` by finding the window's `AXTabGroup` child and counting its children (default 1,
  mirroring Lua `tabCount() or 1`); `frame` get/set over position+size; `focus()` = `AXRaise` +
  `kAXMainAttribute` + `application.activate()`. `isTab(of:)` inherited from the `Window`
  extension. `static func focused()` (system-wide → focused app → focused window) is the
  smoke-test handle only; full window lookup/enumeration is Step 5. **Not unit-tested** (needs
  live windows), covered by the smoke test.
- `App/AppDelegate.swift` — prints `AXWindow.focused()`'s id/appName/frame/flags/tabCount
  alongside the `MainScreen` debug line.

The `@_silgen_name` symbol and AX APIs live in `ApplicationServices` (pulled in transitively by
AppKit), so `Core/` compiling into the host-less `OttoWMTests` bundle links without extra
framework wiring — no fallback needed.

**Verification:**
- `xcodebuild test` green — 34 tests (31 + 3 `AXGeometry` codec cases).
- Manual smoke test on the real machine (pending): `⌘R`, focus a Terminal window with 2 tabs,
  confirm the printed id/appName/frame, `isStandard = true`, `isFullScreen = false`,
  `tabCount = 2`; resize/move and confirm `frame` tracks; toggle full-screen and confirm
  `isFullScreen`. Adjust the `tabCount` traversal if the count is wrong on real windows.

## Step 5 — detailed plan (done)

**Goal:** the native window-lifecycle event source that replaces Hammerspoon's
`hs.window.filter` (`windowCreated`/`windowFocused`/`windowDestroyed`) and the one-shot
`hs.window.allWindows()` seed enumeration. Same shape as Steps 3/4: the OS glue is verified by a
manual smoke test, and only the genuinely pure sub-helper is TDD'd.

**Scope decisions (confirmed):**
- **Manual-navigation / space-change deferred to Step 6.** Step 5 surfaces *only*
  created/focused/destroyed + `allWindows()`. `NSWorkspace.activeSpaceDidChangeNotification` and
  its interpretation (is-this-the-storage-space, switch back) belong to the `Space` strategy
  (`startWatchingForManualNavigation`), keeping all space-awareness in one step.
- **No `WindowObserver` protocol seam yet.** Ship the concrete `AXWindowObserver` only; extract a
  protocol + test stub in Step 7 when the `Engine` consumes it (same deferral precedent as the
  `Screen` protocol, Step 3 → Step 6).

**What was built:**
- `Core/WindowEvent.swift` — the pure piece: the `WindowEvent` enum
  (`created(any Window)`/`focused(any Window)`/`destroyed(CGWindowID)`) and the free
  `shouldObserveApplication(activationPolicy:pid:ownPid:)` predicate deciding which running apps
  get an observer (`.regular` policy, never our own pid). **Unit-tested, TDD** — the predicate
  truth table in `OttoWMTests/WindowEventTests.swift`.
- `Core/AXWindowObserver.swift` — `final class AXWindowObserver`, closure-driven. `start(_:)`
  stores the sink, attaches an `AXObserver` to every current app passing the predicate, and
  subscribes to `NSWorkspace` `didLaunchApplicationNotification` / `didTerminateApplicationNotification`
  to attach/tear-down observers as apps come and go. Per app it registers
  `kAXWindowCreatedNotification` + `kAXFocusedWindowChangedNotification` on the app element and
  adds its run-loop source to `CFRunLoopGetMain()`; the C trampoline carries `self` via
  `Unmanaged` and emits a `WindowEvent` wrapping an `AXWindow`. `kAXUIElementDestroyedNotification`
  fires on an already-dead element, so the `CGWindowID` is captured at creation/enumeration time
  and carried as the destroyed registration's refcon. `allWindows()` enumerates the observable
  apps' `kAXWindowsAttribute` into `AXWindow`s (seeds the model in Step 7). **Not unit-tested**
  (needs live windows), covered by the smoke test.
- `App/AppDelegate.swift` — prints `allWindows()` at launch and streams observer events to the
  console, holding the observer in a stored property so its run-loop sources outlive
  `didFinishLaunching`.

**Follow-up consideration — early event filtering:** the smoke test showed the observer emits
noise from non-window elements — e.g. the Finder desktop reports itself as the focused "window"
(`id 0`, zero-size, positioned just off-screen) every time focus leaves a real Finder window, and
app-internal tabs (Finder/Ghostty/Safari page tabs) correctly produce no window-focus events at
all (they are one window to AX). The current design emits **raw** events and leaves validity
filtering to the Step 7 orchestrator (`isStandard && !isFullScreen && managesWindow`, porting the
Lua `_isValidWindowForVirtualSpace`). Worth reconsidering whether `AXWindowObserver` should apply
a cheap **`isStandard` (and non-zero `id`) guard before emitting**, so phantom desktop/sheet
elements never reach subscribers. Trade-off: it keeps the seam from being purely "raw" and
duplicates part of the orchestrator's validity check, but removes a class of events every consumer
would otherwise have to discard. **Decide when Step 7 wires the real consumer** — that is where
the full validity predicate lives, so the cleanest split (observer pre-filters obvious non-windows
vs. orchestrator owns all filtering) becomes clear with a concrete call site. Note `hs.window.filter`
pre-filtered to standard visible windows, so an observer-level filter is the closer port.

**Refinement needed — focused events on app activation:** the smoke test exposed a gap in the
focused-event coverage. `kAXFocusedWindowChangedNotification` (registered per app) only fires when
*that app's own* focused window changes; switching the frontmost app does not, in general, re-fire
it. Empirically a **single-window** app still emits `.focused` on reactivation (macOS re-promotes
the lone window), but an app whose front window is a **macOS window-merge tab group** emits nothing
on reactivation (the focused tab-window is unchanged) — so focusing away to Xcode and back to a
tabbed Ghostty produced no Ghostty `.focused`, while the same round-trip with a single Ghostty
window did. `hs.window.filter`'s `windowFocused` never hit this because it also tracks the frontmost
**application** and resolves the focused window on app switch. **Fix (in scope for Step 5):** also
subscribe to `NSWorkspace.didActivateApplicationNotification`; on activation, read the newly-frontmost
app's `kAXFocusedWindowAttribute` (reusing `AXWindow.focused()`'s app→window walk) and emit `.focused`
for it. Duplicate `.focused` events (activation path + `kAXFocusedWindowChangedNotification`) are
harmless — the model's focus history de-dupes. This is ordinary focus tracking, distinct from the
Step 6 manual-navigation/space-change work.

**Verification:**
- `xcodebuild test` green — existing 34 tests + the new `shouldObserveApplication` cases; still
  host-less (no agent launch, no Accessibility prompt).
- Manual smoke test on the real machine (done): `⌘R`, confirmed the launch `allWindows()` dump
  matches reality; open a window → `.created` then `.focused`; close a window → `.destroyed(<id>)`
  with the right id; launch/quit a regular app → its windows start/stop producing events with no
  crash. App-internal tab switches fire no window-focus event (expected — one window to AX);
  window-merge tabs are the case the `isTab` grouping handles. Observed noise from non-window
  elements (see the early-filtering follow-up above).
