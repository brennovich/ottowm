# Contributing

## Build and test

```sh
make build      # xcodebuild, code signing disabled
make test       # runs the OttoWMTests unit-test bundle
make release    # generates a signed OttoWM.app
make install    # copies the signed app to /Applications
make acceptance # e2e of the installed app
make benchmark  # hotkey latency of the installed app
```

Run a single test:

```sh
xcodebuild -scheme OttoWM test CODE_SIGNING_ALLOWED=NO \
  -only-testing:OttoWMTests/WorkspacesTests/testWindowAssignment
```

## Acceptance and benchmark

Both drive the app installed in `/Applications` through the harness in `Harness/`: real hotkeys through the event tap, real frames read back through the accessibility API. Run `make install` first, and grant Accessibility permission to the terminal running them.

The harness sets up a plausible desk before it starts, a Finder window on a scratch directory, a Terminal sitting in it, a Safari page and a TextEdit document, all opened after OttoWM is up so the engine sees them arrive. TextEdit is the window the hotkeys move between workspaces; the other three only move because the workspace they stand on was left. Windows the harness opened are closed on the way out, and applications it launched are quit.

`make benchmark` posts the workspace hotkeys and times how long the whole desk takes to land where the action promised, over a workspace 1 → 2 → 1 round trip so every iteration starts where the last one ended. A switch is only counted as done once the entered workspace is on screen *and* the left one is parked. It writes `build/benchmark.json`, every sample plus min/median/p95/max/mean per operation, the desk it ran on and the machine the numbers came from, and prints the same as a markdown table.

```sh
make benchmark BENCHMARK_ARGS="--iterations 30 --warmup 5"
```

The run fails when a p95 goes over `BENCHMARK_BUDGET_MS`, 500 by default against the tens of milliseconds a four window desk takes, so it catches a collapse rather than policing milliseconds. Tune it once the CI runners have shown what they measure. CI runs it right after the acceptance scenarios on every push, appends the table to the job summary and uploads `benchmark.json` as the `benchmark-<runner>` artifact.

## Releasing

`MARKETING_VERSION` in `OttoWM.xcodeproj/project.pbxproj` is the version. Bump it, commit, and push to `main`, then CI tags `v<version>`, builds the universal zip and publishes the release. Pushing without bumping just builds an workflow artifact.
