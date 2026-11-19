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
#   no prose         outside a fence there are headings (`##` a section, `###`
#                    a card in it), table rows and blank lines.
#   section order    `## Run` is first; `## Differs` and `## More`, where
#                    present, are last, in that order.  No section is empty.
#   width            no fence line or table row is wider than 80 columns.
#   rows run         in a fence opened as sh, a row `COMMAND -> OUTPUT` is
#                    run from the project root and its standard output is
#                    compared.  A trailing `  # note` is not part of OUTPUT.
#   programs run     in a lang bundle, a fence opened as the lang's name is
#                    one program in that lang.  A line ending in a comment
#                    `# -> TEXT` (`;`, `--` and `//` are markers too) says
#                    TEXT is a line the program prints; the program is run
#                    once and its standard output is those lines, in order.
#                    A fence opened as input, earlier in the section, is the
#                    program's standard input.
#
# A row with no ` -> ` is not run, and nor is a program with no such line.
# Rows in other fences are not run by this check, and the summary counts
# them.
#
# The lang's name is the `(lang "NAME")` row of BUNDLE/lang.xon.  How a
# program is run is the bundle's to say: BUNDLE/tests/card-run.sh FILE, with
# X in the environment and the input on standard input.
#
# In a row, `x` is the x under test: set X to it (default: the x on PATH).
# Set BUNDLE to the project root (default: the working directory).
#
#   BUNDLE=. X=x sh "$(x --share-dir)/tools/lang-kit/card.sh" [CARD]
set -e

BUNDLE="${BUNDLE:-$(pwd)}"
X="${X:-x}"
CARD="${1:-$BUNDLE/docs/card.md}"
MAX_COLS=80

[ -f "$CARD" ] || { echo "card: no such card: $CARD" >&2; exit 2; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

LANG_NAME=
[ -f "$BUNDLE/lang.xon" ] \
	&& LANG_NAME=$(sed -n 's/^(lang "\([^"]*\)").*/\1/p' "$BUNDLE/lang.xon" | head -1)

# The format.  Shell rows go to $TMP/rows as LINE<TAB>COMMAND<TAB>OUTPUT.  A
# program goes to $TMP/prog.N with the lines it prints in $TMP/want.N and its
# input in $TMP/in.N; $TMP/progs lists N<TAB>LINE for each one to run.
awk -v max_cols="$MAX_COLS" -v rows_file="$TMP/rows" \
    -v card="$CARD" -v lang="$LANG_NAME" -v tmp="$TMP" '
function bad(n, msg) { printf "%s:%d: %s\n", card, n, msg; bad_n++ }

# The text after the last comment arrow of s, in `want`; 0 when s has none.
function printed(s,    at, found) {
  at = 0
  found = 0
  while (match(substr(s, at + 1), /(#|;|--|\/\/) -> /)) {
    at += RSTART + RLENGTH - 1
    found = 1
  }
  want = substr(s, at + 1)
  sub(/[ \t]+$/, "", want)
  return found
}

function end_program() {
  close(tmp "/prog." progs)
  if (wants) {
    close(tmp "/want." progs)
    printf "%d\t%d\n", progs, prog_line > (tmp "/progs")
  } else
    unrun += prog_rows
}

NR == 1 {
  if ($0 !~ /^# .+ card$/) bad(1, "the first line is `# NAME card`")
  next
}

/^```/ {
  if (in_fence) {
    if (tag == "input") close(tmp "/input")
    if (lang != "" && tag == lang) end_program()
    in_fence = 0
    next
  }
  in_fence = 1
  tag = substr($0, 4)
  if (!sections) bad(NR, "a fence before the first section")
  if (tag == "input") {
    printf "" > (tmp "/input")
    has_input = 1
  }
  if (lang != "" && tag == lang) {
    progs++
    prog_line = NR
    prog_rows = 0
    wants = 0
    # The section`s input as it stands, or none.
    system((has_input ? "cat " tmp "/input" : ":") " > " tmp "/in." progs)
  }
  next
}

in_fence {
  rows++
  section_rows++
  if (length($0) > max_cols) bad(NR, "a row wider than " max_cols " columns")
  if (tag == "input") { print > (tmp "/input"); next }
  if (lang != "" && tag == lang) {
    prog_rows++
    print > (tmp "/prog." progs)
    if (printed($0)) { wants++; print want > (tmp "/want." progs) }
    next
  }
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
  has_input = 0
  next
}

/^### / {
  if (!sections) bad(NR, "a card before the first section")
  next
}

/^\|/ {
  if (!sections) bad(NR, "a table before the first section")
  rows++
  section_rows++
  if (length($0) > max_cols) bad(NR, "a row wider than " max_cols " columns")
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

# The programs.  The runner is the bundle's; it is given the program as a
# file, so a program is whatever the fence holds, quotes and all.
[ -f "$TMP/progs" ] || : > "$TMP/progs"
RUNNER="$BUNDLE/tests/card-run.sh"
if [ -s "$TMP/progs" ] && [ ! -f "$RUNNER" ]; then
	echo "card: FAIL -- $CARD has $LANG_NAME programs and there is no $RUNNER" >&2
	exit 1
fi
progs=0
while IFS="$TAB" read -r n line; do
	progs=$((progs + 1))
	got=$(cd "$BUNDLE" && X="$X" sh tests/card-run.sh "$TMP/prog.$n" \
		< "$TMP/in.$n" 2> "$TMP/err") || :
	want=$(cat "$TMP/want.$n")
	if [ "$got" != "$want" ]; then
		printf '%s:%s: the %s program printed other lines\n' \
			"$CARD" "$line" "$LANG_NAME" >&2
		printf '%s\n' "$want" | sed 's/^/  expected: /' >&2
		printf '%s\n' "$got" | sed 's/^/  got:      /' >&2
		sed 's/^/  stderr:   /' "$TMP/err" >&2
		fails=$((fails + 1))
	fi
done < "$TMP/progs"

if [ "$fails" -gt 0 ]; then
	echo "card: FAIL -- $fails of $progs programs printed other lines" >&2
	exit 1
fi

printf 'card: ok (%s rows, %s shell rows run, %s programs run, %s rows in other fences not run here)\n' \
	"$rows" "$ran" "$progs" "${unrun:-0}"
