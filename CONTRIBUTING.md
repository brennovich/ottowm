# Contributing

## Build and test

```sh
make build             # xcodebuild, code signing disabled
make test              # runs the OttoWMTests unit-test bundle
make lint              # SwiftLint over every Swift target
make bump              # bumps MARKETING_VERSION, also bump/minor and bump/major
make release           # generates a signed OttoWM.app
make install           # copies the signed app to /Applications
make acceptance        # e2e of the installed app
make benchmark         # hotkey latency of the installed app
make roundtrips        # streams the calls each operation makes out of the process
make roundtrips/pretty # the same stream, one call per line
make profile           # records the installed app in Instruments under the benchmark
```

Run a single test:

```sh
xcodebuild -scheme OttoWM test CODE_SIGNING_ALLOWED=NO \
  -only-testing:OttoWMTests/WorkspacesTests/testWindowAssignment
```

`ARCHITECTURE.md` is what the app is made of and why.

## Static analysis

`make lint` runs SwiftLint (`brew install swiftlint`) against the rules in `.swiftlint.yml`. Error-severity violations fail the build, warnings do not: the thresholds sit just above what the codebase does today, so a rule fires when new code goes past the current worst case. `force_cast` is a warning because the accessibility API returns `CFTypeRef` and `as?` succeeds for any type.

CI runs it first in the `commit` job as `make lint/report`, which writes `build/swiftlint.sarif`. The report is uploaded as the `swiftlint` artifact and to code scanning, so violations show up in the Security tab and as PR annotations. `make lint/summary` renders the same report as the markdown table in the workflow summary; `Tools/lint-summary.sh` is what builds it.

## Acceptance and benchmark

`Acceptance/` is one scenario, a window sent to another workspace parks at the hidden edge and comes back, and the desk it was standing on goes with the workspace it belongs to. `Benchmark/` times the same hotkeys and prices them; see `Benchmark/README.md`.

Both drive the app installed in `/Applications` through the harness in `Harness/`: real hotkeys through the event tap, real frames read back through the accessibility API. Run `make install` first, and grant Accessibility permission to the terminal running them. `Harness/README.md` covers the desk they run on, the permissions they need and what they leave behind.

CI runs the acceptance scenarios on every push, on each macOS runner in the matrix. The benchmark has a workflow of its own, on a published release and on `workflow_dispatch`, where the runners take their turn one after the other: a measurement taken beside another job prices that job too.

## Profiling

Placing or reading a window leaves the process: an accessibility call is a synchronous round trip to the application that owns the window, capped at `axMessagingTimeoutSeconds`, and the on-screen window list is a round trip to the window server. An operation is mostly the main thread blocked waiting, and a sampling profiler sees the stalled thread rather than the call, so `Core/Infra/RoundTrips.swift` counts them at the boundary instead.

Counting is always on, release builds included, because the acceptance and benchmark runs drive the installed bundle. It costs a clock read and a dictionary update per round trip.

### The round trips

`make roundtrips` streams one line per operation:

```
switch-to-workspace 4.20ms, 27 round trips 3.95ms: write AXEnhancedUserInterface x8 1.40ms, read AXPosition+AXSize x5 0.90ms, read CGWindowList x1 0.42ms, action AXRaise x1 0.21ms
```

The first pair is the whole operation, the second is the part spent out of the process, and the gap between them is what OttoWM itself did. A placement pass that fans its writes out by application overlaps its round trips, so the second number can be larger than the first: it is then the time the calls cost added up, not the time the operation waited for them. Then every call, most expensive first, named by what was asked and of what; `x8` is eight round trips. A read of several attributes is one round trip named by all of them, because `AXUIElementCopyMultipleAttributeValues` asks for them together.

An operation that makes no round trip reports nothing. A nested operation is counted into the one around it, not reported on its own.

`make roundtrips/pretty` pipes the same stream through `Tools/roundtrips-pretty.sh`, which drops the log prefix and puts each call on its own line:

```
• switch-to-workspace 4.20ms, 27 round trips 3.95ms
    └─ write AXEnhancedUserInterface x8 1.40ms
    └─ read AXPosition+AXSize x5 0.90ms
    └─ read CGWindowList x1 0.42ms
    └─ action AXRaise x1 0.21ms
```

A line that carries no log prefix is passed through unchanged, so the stream's own status lines stay readable.

| Counted                                    | Where                                        |
| ------------------------------------------ | -------------------------------------------- |
| Every accessibility read, write and action | `Core/Infra/AX.swift`, `Core/AXWindow.swift` |
| The AX notification subscriptions          | `Core/AXAppObserver.swift`                   |
| The on-screen window list                  | `App/AppDelegate.swift`                      |
| Activating an application                  | `Core/AXWindow.swift`                        |
| The frontmost application                  | `Core/AXWindow.swift`                        |

### The trace

`make profile` records the installed app in Instruments while the benchmark drives it. `make install` first, and the same Accessibility grant the benchmark needs:

```sh
make profile
make profile PROFILE_ARGS="--iterations 50 --instances 3"
make profile PROFILE_INSTRUMENTS="Time Profiler,os_signpost,Thread State Trace"
```

The benchmark launches the app itself, so `Tools/profile.sh` waits for it to come up, attaches, and stops the recording when the benchmark ends. The trace lands in `build/OttoWM.trace`.

Time Profiler is the stacks. `os_signpost` reads the intervals `Core/Infra/Signposts.swift` emits on the Points of Interest track, one per engine operation and one per round trip inside it, which tells which operation a stack belongs to and how many round trips it was waiting on. `Thread State Trace` shows the blocking itself, which the time profiler does not.

## Releasing

`MARKETING_VERSION` in `OttoWM.xcodeproj/project.pbxproj` is the version. `make bump` rewrites it and prints the new one, `make bump/minor` or `make bump/major` for the other two digits. Commit the change and push to `main`, then CI tags `v<version>`, builds the universal zip and publishes the release. Pushing without bumping just builds a workflow artifact.
