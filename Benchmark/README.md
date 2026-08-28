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

Two operations, over a workspace 1 → 2 → 1 round trip so every iteration starts where the last one ended:

| Operation                  | Done when                                                       |
| -------------------------- | --------------------------------------------------------------- |
| `move-window-to-workspace` | The moved window is parked at the hidden edge                   |
| `switch-to-workspace`      | The entered workspace is on screen *and* the left one is parked |

The return leg moves the window back and switches back, untimed: it starts from a different state than the two above and its numbers would only blur theirs. The first `--warmup` iterations are run and discarded.

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

`resolution` is the mean gap between two reads of the desk while that operation was running. It is the width of the ruler: a latency is only good to that much, and sits about half of it high, because the operation finished somewhere between the read that missed it and the read that caught it. The two operations do not poll the same number of windows, so they do not share a resolution, and one blended figure would flatter the expensive one and libel the cheap one. Read it before believing a difference between two runs, a gap smaller than the resolution is not a gap.

`ops/s` is the mean turned around rather than a throughput anyone measured. The run settles the desk between every iteration and never performs these back to back.

Percentiles are nearest rank, so every one reported is a sample that really happened.

## Pricing a window

`--instances` is there to price a window: run the same iterations at one, two and three, and the slope between them is what each window adds to a switch. The desk is staged and torn down per run, so a sweep is three runs and not one, and nothing carries between them beyond the machine. And `resolution` climbs with the instance count too, because a switch is only done once every window is read in place. Part of any slope is the harness looking harder rather than the app working harder, and the resolution column is what tells the two apart.

## Budget

The run fails when a p95 goes over `--budget-p95`, 500 by default against the single digit milliseconds a four window desk takes, so it catches a collapse rather than policing milliseconds. Tune it once the CI runners have shown what they measure.

CI runs the benchmark right after the acceptance scenarios on every push, on each macOS runner in the matrix, appends the table to the job summary and uploads `benchmark.json` as the `benchmark-<runner>` artifact.
