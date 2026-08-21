#!/bin/sh
# highlight-sweep.sh -- render x-lang code blocks in markdown, in place
#
#   sh tools/dev/highlight-sweep.sh FILE...
#
# Each ```x and ```x-repl fence becomes the span markup x/tool/highlight
# emits; every other fence, and the prose around them, passes through
# byte-for-byte.  Files are rewritten in place, so this is meant for a STAGED
# copy of the documentation (the site build) rather than the working tree --
# the markdown in git keeps its fences, which is what github.com renders.
#
# ONE ENGINE, no chunking, and that is a fact worth stating because the
# sibling sweeps chunk hard.  tools/dev/doc-sweep.sh must: it holds a scratch
# base per file and cannot collect mid-batch, so it bounds garbage by bounding
# files per process (25, ~1.7GB).  This tool owns nothing but strings on the
# running base, so tools/dev/highlight.x calls (heap collect) between blocks
# and its working set stays flat -- the whole corpus, 17 pages and 521 blocks,
# peaks at 987MB against a ~844MB boot baseline (measured 2026-08-20, arm64
# macOS).  Without that collect the same run climbed with every block: a 5.6KB
# page cost 3.3GB and an early draft OOM-killed the machine outright.  If a
# future change makes this climb again, fix the collect -- do not reach for
# chunking to hide it.
set -e

[ $# -gt 0 ] || { echo "Usage: sh tools/dev/highlight-sweep.sh FILE..." >&2; exit 1; }

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

# x.sh resolves the library against the CURRENT directory, so the engine has
# to run from the repository root -- which means the paths handed to it must
# survive that move.  Resolve them all to absolute first, then never think
# about the caller's directory again.
ABS=""
for f in "$@"; do
  case "$f" in
    /*) abs="$f" ;;
    *)  abs="$(cd "$(dirname "$f")" && pwd)/$(basename "$f")" ;;
  esac
  [ -f "$abs" ] || { echo "highlight-sweep: no such file: $f" >&2; exit 1; }
  ABS="$ABS $abs"
done
set -- $ABS
cd "$ROOT"

# The tool streams bare for ONE file and behind sentinels for several, so a
# single-file invocation is padded to keep one code path here.
if [ $# -eq 1 ]; then
  sh "$ROOT/x.sh" --no-pin -q -f "$ROOT/tools/dev/highlight.x" -- "$1" "$1" > "$TMP/raw"
else
  sh "$ROOT/x.sh" --no-pin -q -f "$ROOT/tools/dev/highlight.x" -- "$@" > "$TMP/raw"
fi

# Split the sentinel stream back into pages, writing each to its own path.
# A page is written only when its sentinel names a file we asked for, so a
# stray line in the stream can never clobber something outside the list.
awk -v tmp="$TMP" '
  /^%%HL-X-PAGE%% / {
    if (out != "") close(out)
    name = substr($0, index($0, " ") + 1)
    gsub(/\//, "_", name)
    out = tmp "/page_" name
    printf "" > out
    next
  }
  out != "" { print >> out }
' "$TMP/raw"

count=0
for f in "$@"; do
  key=$(printf '%s' "$f" | tr '/' '_')
  page="$TMP/page_$key"
  if [ ! -f "$page" ]; then
    printf 'highlight-sweep: no page for %s\n' "$f" >&2
    exit 1
  fi
  # A page that came back empty for a non-empty source means the tool died
  # mid-stream; refuse rather than truncate someone's documentation.
  if [ ! -s "$page" ] && [ -s "$f" ]; then
    printf 'highlight-sweep: empty page for %s\n' "$f" >&2
    exit 1
  fi
  cp "$page" "$f"
  count=$((count + 1))
done

printf 'highlight-sweep: %d pages\n' "$count"
