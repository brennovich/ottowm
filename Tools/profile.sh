#!/bin/bash
# Records the installed app while the benchmark drives it. The benchmark launches the app
# itself, so the recording attaches to it once it is up rather than launching it.
set -uo pipefail

BENCHMARK=${1:?usage: profile.sh BENCHMARK TRACE [BENCHMARK_ARGS...]}
TRACE=${2:?usage: profile.sh BENCHMARK TRACE [BENCHMARK_ARGS...]}
shift 2

INSTRUMENTS=${PROFILE_INSTRUMENTS:-Time Profiler,os_signpost}
PROCESS=${PROFILE_PROCESS:-OttoWM}
LAUNCH_TIMEOUT=${PROFILE_LAUNCH_TIMEOUT:-60}

instruments=()
IFS=',' read -ra names <<<"$INSTRUMENTS"
for name in "${names[@]}"; do instruments+=(--instrument "$name"); done

rm -rf "$TRACE"

"$BENCHMARK" "$@" &
benchmark=$!

app=""
deadline=$((SECONDS + LAUNCH_TIMEOUT))
while [ $SECONDS -lt $deadline ]; do
	app=$(pgrep -x "$PROCESS" | head -1)
	[ -n "$app" ] && break
	kill -0 $benchmark 2>/dev/null || break
	sleep 0.2
done

if [ -z "$app" ]; then
	echo "profile: $PROCESS never came up within ${LAUNCH_TIMEOUT}s, nothing to record" >&2
	wait $benchmark
	exit 1
fi

echo "profile: recording $PROCESS pid $app into $TRACE"
xcrun xctrace record "${instruments[@]}" --attach "$app" --output "$TRACE" --no-prompt &
recording=$!

wait $benchmark
status=$?

# xctrace finishes the trace on SIGINT. Killing it any harder leaves nothing on disk.
kill -INT $recording 2>/dev/null
wait $recording

echo "profile: recorded $TRACE, open it with: open $TRACE"
exit $status
