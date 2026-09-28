#!/bin/sh
# doc-annotations.sh -- every doc annotation names a type
#
# The contract: the T of every (param NAME T ...) and (returns T ...) form
# under lib/, apps/ and tools/ names a runtime type, a class, or one of the
# names tools/contract/doc-annotations.x lists (docs/glossary.md,
# "annotation").  An annotation is documentation and is never evaluated, so
# one that names nothing fails nothing else.
#
# The judging is tools/check/doc-annotations.x.  This script lists the files
# and runs it on xenon, whose boot registers the numeric tower's types.
# lib/x/boot/tower-compiled.x is generated from modules the list already
# holds, and is left out where a build has made it.
set -e

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"

# shellcheck disable=SC2046
exec sh "$ROOT/x.sh" --no-pin -q -l xe -f "$ROOT/tools/check/doc-annotations.x" -- \
  tools/contract/doc-annotations.x \
  $(find lib apps tools -name '*.x' -type f | grep -v '^lib/x/boot/tower-compiled\.x$' | sort)
