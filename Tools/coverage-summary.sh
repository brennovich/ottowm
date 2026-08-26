#!/usr/bin/env bash
# Renders an xcresult coverage report as the markdown that goes into the workflow summary.
set -euo pipefail

bundle=${1:-build/Coverage.xcresult}
target=${2:-OttoWM.app}
limit=${COVERAGE_SUMMARY_LIMIT:-20}

mdtable() {
	awk -F'\t' -v header="$1" '
		function pad(text, width,   out) { out = text; while (length(out) < width) out = out " "; return out }
		function dashes(width,   out) { out = ""; while (length(out) < width) out = out "-"; return out }
		function emit(r,   i, out) { out = "|"; for (i = 1; i <= columns; i++) out = out " " pad(cell[r, i], width[i]) " |"; print out }
		BEGIN { columns = split(header, names, "|"); for (i = 1; i <= columns; i++) { cell[0, i] = names[i]; width[i] = length(names[i]) } }
		{ rows++; for (i = 1; i <= columns; i++) { cell[rows, i] = $i; if (length($i) > width[i]) width[i] = length($i) } }
		END {
			if (rows == 0) exit
			emit(0)
			out = "|"
			for (i = 1; i <= columns; i++) out = out " " dashes(width[i]) " |"
			print out
			for (r = 1; r <= rows; r++) emit(r)
		}
	'
}

echo "## Coverage"
echo

if [ ! -d "$bundle" ]; then
	echo "No result bundle at \`$bundle\`."
	exit 0
fi

report=$(xcrun xccov view --report --json "$bundle")

overall=$(printf '%s' "$report" | jq -r --arg target "$target" '
	.targets[] | select(.name == $target)
	| "\(.lineCoverage * 10000 | round / 100)% (\(.coveredLines)/\(.executableLines) lines)"')

if [ -z "$overall" ]; then
	echo "No coverage for \`$target\` in \`$bundle\`."
	exit 0
fi

files=$(printf '%s' "$report" | jq -r --arg target "$target" '
	.targets[] | select(.name == $target) | .files[]
	| [ .name, "\(.lineCoverage * 10000 | round / 100)%", "\(.coveredLines)/\(.executableLines)" ]
	| @tsv' | sort -t"$(printf '\t')" -k2,2n)

echo "$target: $overall."
echo

printf '%s\n' "$files" | head -n "$limit" | mdtable 'File|Coverage|Lines'

total=$(printf '%s\n' "$files" | wc -l | tr -d ' ')
if [ "$total" -gt "$limit" ]; then
	echo
	echo "$((total - limit)) more file(s) at or above $(printf '%s\n' "$files" | sed -n "${limit}p" | cut -f2)."
fi
