#!/usr/bin/env bash
# Renders a SwiftLint SARIF report as the markdown that goes into the workflow summary.
set -euo pipefail

report=${1:-build/swiftlint.sarif}
limit=${LINT_SUMMARY_LIMIT:-20}

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

if [ ! -s "$report" ]; then
	echo "## SwiftLint"
	echo
	echo "No report at \`$report\`."
	exit 0
fi

findings=$(jq -r '
	.runs[0].results[]?
	| [ .level,
	    .ruleId,
	    "\(.locations[0].physicalLocation.artifactLocation.uri):\(.locations[0].physicalLocation.region.startLine)",
	    .message.text ]
	| @tsv' "$report")

count() { [ -n "$findings" ] && printf '%s\n' "$findings" | grep -c "^$1	" || true; }
errors=$(count error)
warnings=$(count warning)
files=$([ -n "$findings" ] && printf '%s\n' "$findings" | cut -f3 | cut -d: -f1 | sort -u | wc -l | tr -d ' ' || echo 0)

echo "## SwiftLint"
echo
if [ -z "$findings" ]; then
	echo "No violations."
	exit 0
fi

echo "$errors error(s), $warnings warning(s) in $files file(s), $(jq -r '.runs[0].tool.driver.semanticVersion' "$report")."
echo

printf '%s\n' "$findings" | awk -F'\t' '{ print $2 "\t" $1 }' | sort | uniq -c |
	sort -k1,1nr -k3,3 | awk '{ print $2 "\t" $3 "\t" $1 }' | mdtable 'Rule|Severity|Count'
echo

printf '%s\n' "$findings" | sort -t"$(printf '\t')" -k1,1 -k3,3 | head -n "$limit" |
	awk -F'\t' '{ print $3 "\t" $1 "\t" $2 "\t" $4 }' | mdtable 'Location|Severity|Rule|Message'

total=$((errors + warnings))
if [ "$total" -gt "$limit" ]; then
	echo
	echo "$((total - limit)) more in the uploaded report."
fi
