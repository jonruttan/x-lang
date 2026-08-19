#!/bin/sh
# doc-sweep.sh -- generate docs/ref/x from the library source (#321, #322)
#
# The old Makefile loop booted one engine per library file -- ~98 serial
# boots at ~1s each, ~287s of CI wall clock that was ~70% engine boot.
# doc.x now accepts a file LIST and streams every page to stdout behind
# "%%DOC-X-PAGE%% <source>" sentinel lines; this driver feeds it chunks
# and splits the stream into the per-file pages.
#
# CHUNKS, deliberately, and SEQUENTIALLY: one engine process per
# DOC_CHUNK (default 25) files bounds the per-process parse garbage (a
# scratch base per file accumulates until process exit -- there is no
# safe mid-batch collect, see the seam note in tests/spec-runner.awk),
# and running the chunks one at a time keeps `make doc-x` a
# one-process-at-a-time tool on a shared box.  A 25-file chunk peaks at
# ~1.7GB RSS (measured 2026-08-19, arm64 macOS) -- do NOT fan the
# chunks out with xargs -P without re-doing that arithmetic against the
# smallest target machine; four of these side by side is most of a CI
# runner's memory (the 2026-08-19 lesson).  ~5 boots instead of ~98 is
# already the whole win: measured 128s -> 28s locally.
#
# The file list is an explicit find, NOT the old `lib/x/**/*.x` glob:
# under POSIX sh `**` is not recursive, so depth-3 modules
# (lib/x/protocol/str/*, lib/x/tool/compile/emit.x) were silently never
# documented (#322).  Exclusions mirror tools/dev/lint.sh, each for a
# reason:
#   boot/tower-compiled.x -- GENERATED tower amalgam, not a module
#   tool/asm/*.x          -- per-arch include FRAGMENTS of tool/asm.x
#   compile/pipeline.x    -- include fragment of tool/compile.x's flow
#
# Page semantics are unchanged from the old loop: a failed file is a
# loud FAIL; an empty page for a file that declares (doc (provide is a
# loud EMPTY; an empty page for a file with no doc-provide is skipped
# and removed.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_DIR"

OUT_ROOT="docs/ref/x"
DOC_X="tools/dev/doc.x"
: "${DOC_CHUNK:=25}"

_TMP=$(mktemp -d)
trap 'rm -rf "$_TMP"' EXIT

# The sweep list, in stable sorted order.
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

# Source path -> output page path (the old Makefile's sed, kept exact).
_out_for() {
  echo "$1" | sed 's|^lib/x/||; s|^lib/||; s|\.x$||; s|^|docs/ref/x/|; s|$|.md|'
}

# Chunk the list.
awk -v n="$DOC_CHUNK" -v dir="$_TMP" \
  '{ print > (dir "/chunk-" int((NR-1)/n)) }' "$_TMP/files.lst"

FAIL=0
for _chunk in "$_TMP"/chunk-*; do
  # One engine run for the whole chunk; raw stream to a file so the
  # engine's exit status is read directly (no pipeline-status games).
  # shellcheck disable=SC2046
  if ! sh x.sh --no-pin -q -f "$DOC_X" -- $(cat "$_chunk") > "$_TMP/raw" 2>"$_TMP/err"; then
    _last=$(sed -n 's/^%%DOC-X-PAGE%% //p' "$_TMP/raw" | tail -1)
    printf '  \033[1;31mFAIL\033[0m %s\n' "${_last:-$(head -1 "$_chunk")}"
    sed -n '$p' "$_TMP/raw"
    cat "$_TMP/err" >&2
    exit 1
  fi

  # Split the sentinel stream into pages.  Every listed file gets a
  # page file (created empty if its section held nothing), so the
  # post-check below can apply the EMPTY/skip rule uniformly.
  awk -v root="$OUT_ROOT" '
    /^%%DOC-X-PAGE%% / {
      if (out != "") close(out)
      src = substr($0, 16)
      out = src
      sub(/^lib\/x\//, "", out); sub(/^lib\//, "", out); sub(/\.x$/, "", out)
      out = root "/" out ".md"
      dir = out; sub(/\/[^\/]*$/, "", dir)
      system("mkdir -p " dir)
      printf "" > out
      next
    }
    out != "" { print > out }
  ' "$_TMP/raw"

  # Per-file verdicts, same rules and same lines as the old loop.
  while IFS= read -r f; do
    _page=$(_out_for "$f")
    if [ ! -s "$_page" ]; then
      if grep -q '(doc (provide' "$f"; then
        printf '  \033[1;31mEMPTY\033[0m %s\n' "$_page"
        exit 1
      else
        rm -f "$_page"
        printf '  skip %s (no doc-provide)\n' "$f"
        continue
      fi
    fi
    printf '  %s\n' "$_page"
  done < "$_chunk"
done

exit $FAIL
