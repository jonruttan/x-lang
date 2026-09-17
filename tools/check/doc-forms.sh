#!/bin/sh
# doc-forms.sh -- every class member must reach the generated reference
#
# The contract: every member declared in a (def-class ...) body under lib/
# appears as an entry on that module's page in docs/ref/x.
#
# Coverage is the checkable property.  A closed vocabulary of class-body forms
# is not: a member is declared as (name), (name default) or
# (name default "description"), so the head is the member's own name and the
# set is open.  Declared against rendered is what catches a generator that
# drops members while the page still looks finished.
#
# Needs the reference BUILT: run after `make doc-x`, which is why this hangs
# off the docs path and not the contract gates (a separate CI job with no
# docs/ref of its own).
set -e

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"

CHUNK=${DOC_FORMS_CHUNK:-25}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [ ! -d docs/ref/x ]; then
  echo "doc-forms: docs/ref/x is not built -- run make doc-x first" >&2
  exit 1
fi

# No exclusions: this PARSES, it does not evaluate, so an include fragment or
# a generated amalgam reads as happily as a module.
find lib -name '*.x' | sort > "$TMP/files"

: > "$TMP/forms"
awk -v d="$TMP" -v n="$CHUNK" '{ f = d "/chunk." int((NR-1)/n); print > f }' "$TMP/files"

for chunk in "$TMP"/chunk.*; do
  [ -f "$chunk" ] || continue
  # shellcheck disable=SC2046
  sh "$ROOT/x.sh" --no-pin -q -f "$ROOT/tools/check/doc-forms.x" -- $(cat "$chunk") \
    >> "$TMP/forms" 2>"$TMP/err" || {
      # Name the file that actually failed, not the chunk's first: a chunk
      # is 25 files and blaming the wrong one sends the reader to a healthy
      # file to look for a fault that is not there.
      while read -r one; do
        sh "$ROOT/x.sh" --no-pin -q -f "$ROOT/tools/check/doc-forms.x" -- "$one" \
          >/dev/null 2>"$TMP/err1" || {
            echo "doc-forms: the walker failed on $one" >&2
            cat "$TMP/err1" >&2
            exit 1
          }
      done < "$chunk"
      echo "doc-forms: the walker failed on this chunk but no single file reproduces it" >&2
      cat "$TMP/err" >&2
      exit 1
    }
done

[ -s "$TMP/forms" ] || { echo "doc-forms: no class bodies found -- the walker is broken" >&2; exit 1; }

# Structural forms carry their own rendering; everything else is a member.
# The list mirrors tools/contract/doc-forms.x, which says what each one is.
STRUCTURAL='^(doc|method|static|interface|private|protected)$'

missing=0
checked=0
while read -r file cname form; do
  echo "$form" | grep -qE "$STRUCTURAL" && continue
  # lib/x/foo/bar.x -> docs/ref/x/foo/bar.md
  page="docs/ref/$(echo "${file#lib/}" | sed 's/\.x$/.md/')"
  # A module with no page of its own (an include fragment) cannot be checked.
  [ -f "$page" ] || continue
  checked=$((checked + 1))
  if ! grep -qF "### \`$form\`" "$page"; then
    if [ "$missing" -eq 0 ]; then
      echo "doc-forms: FAIL -- members declared but never rendered:" >&2
    fi
    missing=$((missing + 1))
    [ "$missing" -le 10 ] && printf '  %s  class %s  member %s  (absent from %s)\n' \
      "$file" "$cname" "$form" "$page" >&2
  fi
done < "$TMP/forms"

if [ "$missing" -gt 0 ]; then
  printf '  %d missing. Teach lib/x/doc/doc-gen.x to render them.\n' "$missing" >&2
  exit 1
fi

printf 'doc-forms: ok (%d members, all rendered)\n' "$checked"
