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
make benchmark BENCHMARK_ARGS="--iterations 100 --warmup 5"
make benchmark BENCHMARK_INSTANCES=3
```

`BENCHMARK_INSTANCES` stages that many copies of the whole desk, so three is twelve windows rather than four. It is there to price a window: run the same iterations at one, two and three, and the slope between them is what each window adds to a switch. Two things to hold on to while reading that slope. The desk is staged and torn down per run, so a sweep is three runs and not one, and nothing carries between them beyond the machine. And `resolution` climbs with the instance count too, because a switch is only done once every window is read in place — part of any slope is the harness looking harder, not the app working harder, and the resolution column is what tells the two apart.

Every window is titled after the run and its instance, and each is claimed as it is found, so the second Finder cannot answer to the first one's title. Safari is the exception to how the windows are opened: `open -a Safari` hands the page to whichever window is already up when Safari prefers tabs, and a tab that is not the active one cannot be read through the accessibility API, so the second desk's page opens and is unfindable at the same time. It is asked for a new document instead, which is Safari's own word for a window. That needs Automation permission for whatever runs the harness; without it the harness says so and opens Safari the plain way, which stages a single desk fine and cannot stage a sweep.

Each operation carries its own `resolution`, the mean gap between two reads of the desk while it was running. It is the width of the ruler: a latency is only good to that much, and sits about half of it high, because the operation finished somewhere between the read that missed it and the read that caught it. The two operations do not poll the same number of windows, so they do not share a resolution. Read it before believing a difference between two runs — a gap smaller than the resolution is not a gap. `ops/s` is the mean turned around rather than a throughput anyone measured; the run resets the desk between every iteration and never performs these back to back.

The run fails when a p95 goes over `BENCHMARK_BUDGET_MS`, 500 by default against the single digit milliseconds a four window desk takes, so it catches a collapse rather than policing milliseconds. Tune it once the CI runners have shown what they measure. CI runs it right after the acceptance scenarios on every push, appends the table to the job summary and uploads `benchmark.json` as the `benchmark-<runner>` artifact.

## Releasing

`MARKETING_VERSION` in `OttoWM.xcodeproj/project.pbxproj` is the version. Bump it, commit, and push to `main`, then CI tags `v<version>`, builds the universal zip and publishes the release. Pushing without bumping just builds an workflow artifact.
