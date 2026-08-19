#!/bin/sh
# tools/dev/fmt-sweep.sh -- format / format-check the whole library (#307)
#
# Usage: sh tools/dev/fmt-sweep.sh [--write]
#   default: CHECK -- three outcomes per file, the #307 contract:
#     .      formatted output is byte-identical to the file
#     F      the file disagrees with the formatter (a real diff)
#     ERROR  the FORMATTER failed -- reported as a crash, never as F
#   --write: rewrite each file with the formatter's output (fmt-x).
#
# The sweep covers lib/x-core.x + ALL of lib/x/** (the old targets
# visited the top level only -- 4 of 111 files).  Exclusions mirror
# lint/doc: tower-compiled.x is a GENERATED amalgam, tool/asm/* and
# compile/pipeline.x are include fragments, not modules.
#
# Files run through tools/dev/fmt.x in chunks of FMT_CHUNK (default 16)
# behind %%FMT-X-PAGE%% sentinels -- one engine boot per chunk instead
# of per file (the doc-sweep pattern; a serial per-file sweep measured
# 5-8 minutes, chunked ~2).  A chunk that exits nonzero names the file
# the formatter died on (the last sentinel in the raw stream) and quotes
# stderr.  Chunks run SEQUENTIALLY -- one engine at a time.
#
# The page comparison is byte-exact (cmp): the question CHECK answers is
# "would --write change this file?", and --write writes the page bytes.

set -e

BASEDIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$BASEDIR"

MODE=check
[ "$1" = "--write" ] && MODE=write

# Chunk size and allocation ceiling move together: the alloc guard
# (X_ALLOC_LIMIT_OBJS, default 300M objects) is a per-FILE runaway
# ceiling, and a chunk pays it CUMULATIVELY -- 16-file chunks died ~11
# files in when the heavy numeric/core neighborhood landed in one
# chunk.  8-file chunks with a 2x ceiling clear the sweep with margin
# while a genuine runaway still trips at 600M.
: "${FMT_CHUNK:=8}"
: "${X_ALLOC_LIMIT_OBJS:=600000000}"
export X_ALLOC_LIMIT_OBJS

_TMP=$(mktemp -d "${TMPDIR:-/tmp}/fmt-sweep.XXXXXX")
trap 'rm -rf "$_TMP"' EXIT

# The sweep list, stable order.
{
  echo "lib/x-core.x"
  for f in lib/x/*.x; do [ -f "$f" ] && echo "$f"; done
  find lib/x -mindepth 2 -name '*.x' | sort | while IFS= read -r f; do
    case "$f" in
      lib/x/boot/tower-compiled.x|lib/x/tool/asm/*|lib/x/tool/compile/pipeline.x) ;;
      *) echo "$f" ;;
    esac
  done
} > "$_TMP/files.lst"

# Measured-heavy files chunk ALONE: the formatter re-prints subforms
# per width measurement, and bigint literals pay limb math per print --
# num/bigint.x peaks ~5GB RSS by itself (filed as the formatter-churn
# issue).  Sharing its chunk stacked neighbors on top (6.7GB observed).
grep -v '^lib/x/num/bigint.x$' "$_TMP/files.lst" > "$_TMP/files-light.lst"
awk -v n="$FMT_CHUNK" -v dir="$_TMP" \
  '{ print > (dir "/chunk-" int((NR-1)/n)) }' "$_TMP/files-light.lst"
grep '^lib/x/num/bigint.x$' "$_TMP/files.lst" > "$_TMP/chunk-heavy-bigint" || true

FAIL=0
for _chunk in "$_TMP"/chunk-*; do
  # shellcheck disable=SC2046
  if ! sh x.sh --no-pin -q -f tools/dev/fmt.x -- $(cat "$_chunk") \
       > "$_TMP/raw" 2> "$_TMP/err"; then
    _last=$(sed -n 's/^%%FMT-X-PAGE%% //p' "$_TMP/raw" | tail -1)
    printf '  \033[1;31mERROR\033[0m %s -- the formatter FAILED (this is not a formatting diff)\n' \
      "${_last:-$(head -1 "$_chunk")}"
    tail -3 "$_TMP/err" | sed 's/^/          /'
    exit 1
  fi
  # Split the sentinel stream into per-file pages.  A ONE-file chunk
  # (the list length modulo FMT_CHUNK can leave one) streams bare --
  # fmt.x's single-file mode is byte-exact by contract, no sentinel --
  # so the raw stream IS that file's page.
  rm -rf "$_TMP/pages"; mkdir "$_TMP/pages"
  if [ "$(grep -c '' "$_chunk")" -eq 1 ]; then
    cp "$_TMP/raw" "$_TMP/pages/$(head -1 "$_chunk" | tr '/' '_')"
  else
    awk -v dir="$_TMP/pages" '
      /^%%FMT-X-PAGE%% /{ f=$2; gsub("/","_",f); out=dir "/" f; next }
      out { print > out }
    ' "$_TMP/raw"
  fi
  while IFS= read -r _f; do
    _page="$_TMP/pages/$(echo "$_f" | tr '/' '_')"
    if [ ! -s "$_page" ]; then
      printf '  \033[1;31mERROR\033[0m %s -- no page in the batch output\n' "$_f"
      FAIL=1
    elif [ "$MODE" = write ]; then
      if cmp -s "$_page" "$_f"; then
        printf '  \033[1;32m.\033[0m %s\n' "$_f"
      else
        cp "$_page" "$_f"
        printf '  \033[1;33mW\033[0m %s\n' "$_f"
      fi
    elif cmp -s "$_page" "$_f"; then
      printf '  \033[1;32m.\033[0m %s\n' "$_f"
    else
      FAIL=1; printf '  \033[1;31mF\033[0m %s\n' "$_f"
    fi
  done < "$_chunk"
done
[ "$FAIL" -eq 0 ]
