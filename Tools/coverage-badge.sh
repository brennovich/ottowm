#!/usr/bin/env bash
# Renders an xcresult coverage report as the shields.io endpoint JSON published to the badge gist.
set -euo pipefail

bundle=${1:-build/Coverage.xcresult}
target=${2:-OttoWM.app}

if [ ! -d "$bundle" ]; then
	echo "No result bundle at $bundle" >&2
	exit 1
fi

percent=$(xcrun xccov view --report --json "$bundle" | jq -r --arg target "$target" '
	.targets[] | select(.name == $target) | .lineCoverage * 10000 | round / 100')

if [ -z "$percent" ] || [ "$percent" = "null" ]; then
	echo "No coverage for $target in $bundle" >&2
	exit 1
fi

color=$(awk -v p="$percent" 'BEGIN {
	if (p < 50) print "red"
	else if (p < 60) print "orange"
	else if (p < 70) print "yellow"
	else if (p < 80) print "yellowgreen"
	else if (p < 90) print "green"
	else print "brightgreen"
}')

jq -n --arg message "$percent%" --arg color "$color" \
	'{schemaVersion: 1, label: "coverage", message: $message, color: $color}'
