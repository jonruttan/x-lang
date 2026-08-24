#!/bin/sh
# primitives-doc.sh -- docs/primitives.md files each form where it actually lives.
#
# THE DOCUMENT IS PARTITIONED ALONG A SEAM THE SYSTEM ALREADY HAS (#486), and a
# partition nothing checks drifts back into the list it replaced.  Half that
# file's sections used to document x-lang operatives and procedures as if they
# were C -- `if`, `let`, `and`, `or`, `display`, the predicates -- under a title
# that promised the C surface.  Nothing said so, because nothing could: the only
# record of what is C is the engine's own isa.x, and no reader diffs a prose doc
# against a manifest by hand.
#
# WHAT THIS CHECKS.  Every `### `name`` section must sit in the part that says
# what it IS, classified against the SAME manifest `make check-isa` diffs the C
# source against:
#
#   The C instruction set   %isa-bare or %isa-keep -- a bare name bound by C
#   Coordinates             an (ns method) row in %isa-catalog, no bare name
#   What boots on top       in no block at all -- library code
#
# The classification is mechanical and the failure names the section, the part
# it is in, and the part it belongs to, so the fix is never a guess.
#
# WHY THE ENGINE'S MANIFEST AND NOT A LIST HERE: a copy would be right about
# some engine and not necessarily the one this tree builds against, which is
# the same reason the contract manifests travel with the engine.  A second
# engine with a different surface re-partitions this document by rebuilding,
# not by anyone remembering to edit a table.
set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

DOC=docs/primitives.md
ISA="${ENGINE_DIR:-engine}/tools/contract/isa.x"

[ -f "$DOC" ] || { echo "primitives-doc: no $DOC" >&2; exit 2; }
[ -f "$ISA" ] || { echo "primitives-doc: no ISA manifest at $ISA" >&2; exit 2; }

W="${TMPDIR:-/tmp}/primitives-doc.$$"
mkdir -p "$W"
trap 'rm -rf "$W"' EXIT INT TERM

# The four blocks, parsed the way the file is written: rows are INDENTED inside
# `(def %isa-NAME (lit (`, and the block ends at a line-initial `)))`.  An
# anchored `^%isa-catalog:` matches only the format comment and would classify
# every name as library -- a check that passes by seeing nothing.
awk -v w="$W" '
	/^\(def %isa-catalog/ { sec = "catalog"; next }
	/^\(def %isa-bare/    { sec = "bare";    next }
	/^\(def %isa-keep/    { sec = "bare";    next }   # keep-list binds bare too
	/^\(def %isa-/        { sec = "";        next }
	/^\)\)\)/             { sec = "";        next }
	sec != "" && /^[[:space:]]*\(/ {
		line = $0; sub(/;.*/, "", line); gsub(/[()]/, " ", line)
		if (split(line, f, " ") == 0) next
		if (sec == "catalog") print tolower(f[1]) " " f[2] >> (w "/catalog")
		else                  print f[1]                  >> (w "/bare")
	}' "$ISA"
[ -s "$W/catalog" ] || { echo "primitives-doc: parsed no catalog rows from $ISA" >&2; exit 2; }
[ -s "$W/bare" ]    || { echo "primitives-doc: parsed no bare rows from $ISA" >&2; exit 2; }

# Which part each `##` heading opens.  Renaming a part here without renaming it
# in the document is caught below: an unknown part is an error, not a skip.
part_key() {
	case "$1" in
		"The C instruction set") echo c ;;
		"Coordinates")           echo coord ;;
		"What boots on top")     echo library ;;
		*)                       echo "" ;;
	esac
}

# Where a name belongs, from the manifest alone.
belongs() {
	_n="$1"
	case "$_n" in
		*" "*)
			_ns=$(printf '%s' "$_n" | cut -d' ' -f1 | tr 'A-Z' 'a-z')
			_m=$(printf '%s' "$_n" | cut -d' ' -f2-)
			if grep -qxF -- "$_ns $_m" "$W/catalog"; then echo coord; else echo library; fi ;;
		*)
			if grep -qxF -- "$_n" "$W/bare"; then echo c; else echo library; fi ;;
	esac
}

bad=0
n=0
part=""
key=""
while IFS= read -r line; do
	case "$line" in
		"## "*)
			part=${line#\#\# }
			key=$(part_key "$part")
			if [ -z "$key" ]; then
				echo "primitives-doc: unknown part heading '$part'" >&2
				echo "  the parts are the three this check knows; renaming one means" >&2
				echo "  renaming it in tools/check/primitives-doc.sh too." >&2
				exit 1
			fi
			continue ;;
		"### \`"*)
			# A heading may document a PAIR -- `str ->sym` / `sym ->str` -- so
			# every backticked name in it is checked, not just the first.
			# Read them a LINE at a time: `for name in $(...)` word-splits
			# `Type ?` into two names and glob-expands the `*` entry into a
			# directory listing.
			printf '%s\n' "$line" | awk -F'`' '{for (i = 2; i <= NF; i += 2) print $i}' > "$W/names"
			while IFS= read -r name; do
				[ -n "$key" ] || { echo "primitives-doc: \`$name\` sits above every part heading" >&2; bad=1; continue; }
				n=$((n + 1))
				want=$(belongs "$name")
				if [ "$want" != "$key" ]; then
					bad=1
					echo "$name: in '$part', belongs in the $want part" >&2
				fi
			done < "$W/names" ;;
	esac
done < "$DOC"

if [ "$bad" != 0 ]; then
	echo "primitives-doc: FAIL -- a form is documented as something it is not." >&2
	echo "  c       = bound bare by C            (%isa-bare / %isa-keep)" >&2
	echo "  coord   = catalog row, no bare name  (%isa-catalog)" >&2
	echo "  library = in no ISA block            (lib/x/boot, lib/x/core)" >&2
	exit 1
fi
echo "primitives-doc: ok ($n forms, each in the part the ISA says it is in)"
