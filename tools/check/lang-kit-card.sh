#!/bin/sh
# lang-kit-card.sh -- the lang kit's card check refuses what the format refuses.
#
# tools/lang-kit/card.sh holds a docs/card.md to the card format
# (docs/contributing.md "The card").  Held here, on fixture cards whose rows
# need no x:
#
#   - a card in the format passes, its shell rows run;
#   - each rule fails alone: the title, prose outside a fence, a first
#     section that is not Run, a section after More, an empty section, a row
#     past 80 columns, more than 66 rows;
#   - a shell row whose command gives other output fails, and the report
#     names the row.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_DIR" || exit 1

TMP=$(mktemp -d)
TMP=$(cd "$TMP" && pwd)
trap 'rm -rf "$TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fails=0
F='```'

# card NAME -- a fixture card from stdin.
card() { mkdir -p "$TMP/$1/docs"; cat > "$TMP/$1/docs/card.md"; }

# passes NAME / refuses NAME TEXT -- run the check on a fixture; a refusal
# must say TEXT.
passes() {
	if out=$(BUNDLE="$TMP/$1" sh tools/lang-kit/card.sh 2>&1); then
		printf '  %s: ok\n' "$1"
	else
		printf 'lang-kit-card: %s was refused:\n%s\n' "$1" "$out" >&2
		fails=$((fails + 1))
	fi
}
refuses() {
	if out=$(BUNDLE="$TMP/$1" sh tools/lang-kit/card.sh 2>&1); then
		printf 'lang-kit-card: %s passed:\n%s\n' "$1" "$out" >&2
		fails=$((fails + 1))
	elif printf '%s\n' "$out" | grep -q -- "$2"; then
		printf '  %s is refused: ok\n' "$1"
	else
		printf 'lang-kit-card: %s was refused without "%s":\n%s\n' "$1" "$2" "$out" >&2
		fails=$((fails + 1))
	fi
}

card good <<EOF
# demo card

## Run

${F}sh
echo hi -> hi
printf 'a -> b\n' | cut -c 1 -> a          # a note
demo --help                               # not run
${F}

## Differs

${F}
this    that
${F}

## More

${F}sh
demo --help
${F}
EOF
passes good

card title <<EOF
# demo

## Run

${F}sh
echo hi -> hi
${F}
EOF
refuses title 'the first line is'

card prose <<EOF
# demo card

## Run

Run it like this.

${F}sh
echo hi -> hi
${F}
EOF
refuses prose 'prose outside a fence'

card first <<EOF
# demo card

## Lists

${F}sh
echo hi -> hi
${F}
EOF
refuses first 'the first section is'

card order <<EOF
# demo card

## Run

${F}sh
echo hi -> hi
${F}

## More

${F}sh
demo --help
${F}

## Lists

${F}sh
echo hi -> hi
${F}
EOF
refuses order 'is the last section'

card empty <<EOF
# demo card

## Run

## More

${F}sh
demo --help
${F}
EOF
refuses empty 'an empty section'

card wide <<EOF
# demo card

## Run

${F}sh
echo 0123456789012345678901234567890123456789012345678901234567890123456789012345
${F}
EOF
refuses wide 'a row wider than'

{
	printf '# demo card\n\n## Run\n\n%ssh\n' "$F"
	i=0
	while [ "$i" -lt 67 ]; do printf 'demo %s\n' "$i"; i=$((i + 1)); done
	printf '%s\n' "$F"
} | card long
refuses long '67 rows'

card output <<EOF
# demo card

## Run

${F}sh
echo hi -> ho
${F}
EOF
refuses output 'expected: ho'

if [ "$fails" -gt 0 ]; then
	echo "lang-kit-card: FAIL ($fails)" >&2
	exit 1
fi
echo "lang-kit-card: ok"
