#!/bin/sh
# help-examples.sh -- the HELP-EXAMPLE ratchet: how many doc entries show the
# reader no example.
#
# help renders an entry's (example ...) and (sample ...) forms alike, under
# the description, so an entry with either shows the reader one.  The
# 2026-10-26 UX audit counted 61% of the registry without: every method of
# List, Str8, Vector and Dict a tutorial reader meets first answers (help
# Class method) with a description and nothing to try.  The examples are
# written one area at a time, and this check keeps the number of bare
# entries from growing back while that happens.
#
# The count comes from the doctest walk (tools/check/doctest.x), which
# already imports every library module and reads the registry help reads;
# its census trailer carries the tally, and this script holds the one number
# to the ceiling in tools/contract/help-examples.x:
#
#   - over the ceiling fails: a new entry that shows no example, or an
#     example dropped from one;
#   - under it is printed, not failed, with the row to ratchet down.  Two
#     branches that each add examples then merge in either order; the row
#     is lowered in the branch that stands on both.
#
# The same trailer lists the def entries whose name the root does not bind
# and no module provides -- an entry left behind when its name was made
# %-private or deleted -- and any one fails the check.
#
# The walk takes the doctest's time (about twenty seconds here) and memory,
# so the Makefile files this under `gates`, not the pre-push `gates-fast`.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_DIR" || exit 1

MANIFEST=tools/contract/help-examples.x

_TMP=$(mktemp) || exit 1
trap 'rm -f "$_TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# doctest.sh refuses a truncated walk and a failed import itself; either
# would under-count here, so its failure is this check's failure.
if ! sh tools/check/doctest.sh > "$_TMP"; then
  echo "help-examples: FAIL -- the doctest walk did not complete; see above" >&2
  exit 1
fi

n_entries=$(sed -n 's/^entries: \([0-9][0-9]*\)$/\1/p' "$_TMP")
n_example=$(sed -n 's/^with example: \([0-9][0-9]*\)$/\1/p' "$_TMP")
n_sample=$(sed -n 's/^with sample only: \([0-9][0-9]*\)$/\1/p' "$_TMP")
bare_line=$(sed -n 's/^without example or sample: //p' "$_TMP")
n_bare=$(printf '%s\n' "$bare_line" | sed -n 's/^\([0-9][0-9]*\) .*/\1/p')

if [ -z "$n_entries" ] || [ -z "$n_bare" ]; then
  echo "help-examples: FAIL -- the census trailer carries no tally" >&2
  exit 1
fi

ceiling=$(sed -n 's/^(entries-without-example \([0-9][0-9]*\)).*/\1/p' "$MANIFEST")
if [ -z "$ceiling" ]; then
  echo "help-examples: FAIL -- $MANIFEST holds no (entries-without-example N) row" >&2
  exit 1
fi

echo "help-examples: $n_entries entries; $n_example with an example, $n_sample with a sample only"
echo "help-examples: $bare_line"

# A def entry whose name nothing binds documents a retired name: the root
# does not bind it and no module provides it.  The walk lists them as
# (NAME MODULE), MODULE the import it met the entry under, () at boot.
unbound=$(sed -n 's/^unbound defs: //p' "$_TMP")
if [ -z "$unbound" ]; then
  echo "help-examples: FAIL -- the census trailer carries no unbound-defs line" >&2
  exit 1
fi
if [ "$unbound" != "()" ]; then
  echo "help-examples: FAIL -- doc entries for names nothing binds; remove each entry, or bind or provide the name: $unbound" >&2
  exit 1
fi

if [ "$n_bare" -gt "$ceiling" ]; then
  echo "help-examples: FAIL -- $n_bare entries show no example, over the ceiling of $ceiling; give the new entries an (example \"in\" \"out\") form (docs/contributing.md)" >&2
  exit 1
fi
if [ "$n_bare" -lt "$ceiling" ]; then
  echo "help-examples: $n_bare is under the ceiling of $ceiling -- ratchet the row down in $MANIFEST"
else
  echo "help-examples: at the ceiling of $ceiling"
fi
