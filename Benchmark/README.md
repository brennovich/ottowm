# Benchmark

What a hotkey costs the user: the wall time from posting it to seeing every window where the action promised to put it. It drives the installed app through the harness in `Harness/`, the same one the acceptance run drives, so a number here is a number about the shipped bundle. Read `Harness/README.md` for the desk it runs on and what a run needs before it can start. It says what a hotkey costs, not where the cost went: `make profile` records this same run in Instruments, and the Profiling section of `CONTRIBUTING.md` covers it.

| File            | What it holds                                                                         |
| --------------- | ------------------------------------------------------------------------------------- |
| `main.swift`    | Options, the measuring loop, the record it writes and the budget it enforces          |
| `Latency.swift` | The samples, the statistics drawn from them, and the JSON and markdown they turn into |

```sh
make benchmark
make benchmark BENCHMARK_ARGS="--iterations 100 --warmup 5"
make benchmark BENCHMARK_ARGS="--instances 3"
make benchmark BENCHMARK_ARGS="--budget-p95 250"
```

## What it measures

Three operations, over a workspace 1 → 2 → 1 round trip so every iteration starts where the last one ended:

| Operation                  | Done when                                                        |
| -------------------------- | ---------------------------------------------------------------- |
| `move-window-to-workspace` | The moved window is parked at the hidden edge                    |
| `switch-to-workspace`      | The entered workspace is on screen *and* the left one is parked  |
| `focus-direction`          | The window the move is owed to land on holds the focus           |

The return leg moves the window back and switches back, untimed: it starts from a different state than the two above and its numbers would only blur theirs. The first `--warmup` iterations are run and discarded.

The desk stands in the four quarters of the screen, because a focus move is only measurable against a desk whose geometry the run knows: it has to name the window the move is owed to land on. `focus-direction` is measured on the leg from the bottom right window to the top right one, taken last in the iteration on the whole desk the return leg just restored. The focus is put back on the bottom right window first rather than taken to be there, because a switch hands it to whichever window it pleases. Only that one leg is timed: the other three are different pairs of applications, and one blended figure would be a number no pair actually has. At more than one `--instances` the operation is skipped: two desks stand two Safari windows in the same quarter, and the move lands on whichever of them the rule picks, which the run cannot name.

The focus is read through the accessibility API rather than `NSWorkspace.frontmostApplication`, which only updates when the main run loop runs: a measuring loop that polls without running it would read the same stale value until it gave up.

An operation the desk never gets to within 15s warns, drops that sample and lets the run carry on to the next iteration, because aborting would throw away every sample already taken over one window that would not move. The `Samples` column is what the statistics were drawn from, so a run that missed reports fewer than it was asked for. Only a run that measured nothing at all fails.

Before each hotkey goes out the desk is waited on until every window reads the same frame for ten consecutive reads, so the measurement is taken against a desk standing still rather than one on its way somewhere. A fixed sleep was a guess at how long that takes: longer than needed on a good day, and no guarantee on a bad one. Then the clock is read, the hotkey is posted, and the desk is read about every 0.13ms until it satisfies the operation.

## Options

All of them passed through `BENCHMARK_ARGS`, which the Makefile sets to `--budget-p95 500`. Setting it replaces that rather than adding to it, so a run given other flags has no budget unless it names one.

| Flag           | Default                | Effect                                                 |
| -------------- | ---------------------- | ------------------------------------------------------ |
| `--iterations` | 100                    | Measured iterations                                    |
| `--warmup`     | 2                      | Iterations run and discarded first                     |
| `--instances`  | 1                      | Desks staged, four windows each                        |
| `--budget-p95` | none                   | Fails the run when a p95 goes over it                  |
| `--output`     | `build/benchmark.json` | Where the record is written                            |
| `--summary`    | `$GITHUB_STEP_SUMMARY` | A file the markdown table is appended to, if it is set |

## Output

`build/benchmark.json` holds every sample plus min, median, p95, max and mean per operation, the desk it ran on, and the machine and build the numbers came from, because the same numbers from another machine, or from another build on the same one, are only alike when those match. The same summary is printed as a markdown table, and appended to the GitHub step summary when there is one.

Three things to hold on to while reading it.

`resolution` is the mean gap between two reads of the desk while that operation was running. It is the width of the ruler: a latency is only good to that much, and sits about half of it high, because the operation finished somewhere between the read that missed it and the read that caught it. The operations do not poll the same number of windows, so they do not share a resolution, and one blended figure would flatter the expensive one and libel the cheap one. Read it before believing a difference between two runs, a gap smaller than the resolution is not a gap.

`ops/s` is the mean turned around rather than a throughput anyone measured. The run settles the desk between every iteration and never performs these back to back.

Percentiles are nearest rank, so every one reported is a sample that really happened.

## Pricing a window

`--instances` is there to price a window: run the same iterations at one, two and three, and the slope between them is what each window adds to a switch. The desk is staged and torn down per run, so a sweep is three runs and not one, and nothing carries between them beyond the machine. And `resolution` climbs with the instance count too, because a switch is only done once every window is read in place. Part of any slope is the harness looking harder rather than the app working harder, and the resolution column is what tells the two apart.

## Budget

The run fails when a p95 goes over `--budget-p95`, 500 by default against the single digit milliseconds a four window desk takes, so it catches a collapse rather than policing milliseconds. Tune it once the CI runners have shown what they measure.

CI runs the benchmark in its own `benchmark` workflow, on a published release and on `workflow_dispatch`, not on every push. The macOS runners take their turn one after the other rather than at once, and two runs of the workflow never overlap, because concurrent runs share whatever the hosted runners sit on and the numbers then price the neighbour rather than the hotkey. Nothing else runs in the job: the acceptance scenarios run elsewhere, and no log stream is open while measuring. Each runner appends its table to the job summary and uploads `benchmark-<runner>.json` as the `benchmark-<runner>` artifact.

The bundle is the `OttoWM` artifact of a `deployment-pipeline` run, the same zip the release is cut from, rather than a build of its own: a benchmark that compiled the app itself would measure a bundle nobody ships. It defaults to the last run that succeeded on the dispatched ref. `workflow_dispatch` also takes a tag, and the release trigger passes the one it published: a tag takes the run that built the commit it points at, whatever state that run is in, because the pipeline uploads the artifact in its `commit` job and only publishes the release afterwards. Either way the harness is compiled from the commit that run built, so it matches the bundle it drives. Artifacts expire, so a run old enough to have lost its own cannot be benchmarked again.

`workflow_dispatch` takes the number of iterations too.
