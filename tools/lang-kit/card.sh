#!/bin/sh
# # x-lang -- the lang kit
#
# ## tools/lang-kit/card.sh -- the card check
#
# @description Holds docs/card.md to the card format and runs its shell rows.
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2026 Jon Ruttan
# @license MIT No Attribution (MIT-0)
#
#     ., .,
#     {O,O}
#     (   )
#      " "
#
# A card is a project's page for recall: what to type, and what it gives.
# The format is docs/contributing.md "The card".  This check holds a card to
# it:
#
#   title            line 1 is `# NAME card`.
#   rows only        outside a fence there are headings and blank lines.
#   section order    `## Run` is first; `## Differs` and `## More`, where
#                    present, are last, in that order.  No section is empty.
#   one page         at most 66 rows of at most 80 columns: a printed page.
#   rows run         in a fence opened as sh, a row `COMMAND -> OUTPUT` is
#                    run from the project root and its standard output is
#                    compared.  A trailing `  # note` is not part of OUTPUT.
#
# A row with no ` -> ` is not run.  Rows in other fences are not run by this
# check, and the summary counts them.
#
# In a row, `x` is the x under test: set X to it (default: the x on PATH).
# Set BUNDLE to the project root (default: the working directory).
#
#   BUNDLE=. X=x sh "$(x --share-dir)/tools/lang-kit/card.sh" [CARD]
set -e

BUNDLE="${BUNDLE:-$(pwd)}"
X="${X:-x}"
CARD="${1:-$BUNDLE/docs/card.md}"
MAX_ROWS=66
MAX_COLS=80

[ -f "$CARD" ] || { echo "card: no such card: $CARD" >&2; exit 2; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# The format.  Shell rows go to $TMP/rows as LINE<TAB>COMMAND<TAB>OUTPUT.
awk -v max_rows="$MAX_ROWS" -v max_cols="$MAX_COLS" -v rows_file="$TMP/rows" \
    -v card="$CARD" '
function bad(n, msg) { printf "%s:%d: %s\n", card, n, msg; bad_n++ }

NR == 1 {
  if ($0 !~ /^# .+ card$/) bad(1, "the first line is `# NAME card`")
  next
}

/^```/ {
  if (in_fence) { in_fence = 0; next }
  in_fence = 1
  tag = substr($0, 4)
  if (!sections) bad(NR, "a fence before the first section")
  next
}

in_fence {
  rows++
  section_rows++
  if (length($0) > max_cols) bad(NR, "a row wider than " max_cols " columns")
  if (index($0, " -> ") == 0) next
  if (tag != "sh") { unrun++; next }
  # The last arrow divides the row: a command may hold one, OUTPUT may not.
  at = 0
  for (i = 1; i <= length($0) - 3; i++)
    if (substr($0, i, 4) == " -> ") at = i
  cmd = substr($0, 1, at - 1)
  want = substr($0, at + 4)
  sub(/[ \t]+# .*$/, "", want)
  sub(/[ \t]+$/, "", cmd)
  printf "%d\t%s\t%s\n", NR, cmd, want > rows_file
  next
}

/^## / {
  if (sections && !section_rows) bad(section_line, "an empty section")
  name[++sections] = substr($0, 4)
  section_line = NR
  section_rows = 0
  next
}

/^[ \t]*$/ { next }

{ bad(NR, "prose outside a fence") }

END {
  if (in_fence) bad(NR, "a fence left open")
  if (sections && !section_rows) bad(section_line, "an empty section")
  if (name[1] != "Run") bad(1, "the first section is `## Run`")
  for (i = 1; i <= sections; i++) {
    if (name[i] == "More" && i != sections)
      bad(1, "`## More` is the last section")
    if (name[i] == "Differs" && i != sections && name[i + 1] != "More")
      bad(1, "`## Differs` is last, or next to last before `## More`")
  }
  if (rows > max_rows) bad(1, rows " rows; a card holds " max_rows)
  printf "%d %d\n", rows, unrun > (rows_file ".count")
  exit bad_n ? 1 : 0
}
' "$CARD" >&2 || { echo "card: FAIL -- $CARD does not hold the card format" >&2; exit 1; }

read -r rows unrun < "$TMP/rows.count"
[ -f "$TMP/rows" ] || : > "$TMP/rows"

# The shell rows.  `x` is a function over $X, so a row reads as a user types
# it and PATH is left alone; `command` keeps the function from calling itself
# when X is plain `x`.
TAB=$(printf '\t')
ran=0
fails=0
while IFS="$TAB" read -r line cmd want; do
	ran=$((ran + 1))
	got=$(cd "$BUNDLE" && X="$X" sh -c 'x() { command "$X" "$@"; }
'"$cmd" < /dev/null 2> "$TMP/err") || :
	if [ "$got" != "$want" ]; then
		printf '%s:%s: %s\n  expected: %s\n  got:      %s\n' \
			"$CARD" "$line" "$cmd" "$want" "$got" >&2
		sed 's/^/  stderr:   /' "$TMP/err" >&2
		fails=$((fails + 1))
	fi
done < "$TMP/rows"

if [ "$fails" -gt 0 ]; then
	echo "card: FAIL -- $fails of $ran shell rows gave other output" >&2
	exit 1
fi

printf 'card: ok (%s rows, %s shell rows run, %s rows in other fences not run here)\n' \
	"$rows" "$ran" "${unrun:-0}"
