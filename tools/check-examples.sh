#!/bin/sh
# check-examples.sh -- every example runs under its documented dialect.
#
# The examples are the first code a newcomer runs, and they were the last
# code in the repo with no gate: the -f discard shipped broken for three
# months because nothing executed them.  This gate covers parse/eval/output
# rot.  (It cannot cover tty-side regressions -- the fd-3 swap class is
# isatty-guarded and needs a real terminal.)
#
# Discovery is automatic: every file under examples/*/ runs.  The dialect
# comes from the directory name, resolved the way x.sh resolves -l NAME
# (lib first, then apps/NAME/run.x -- #35).
#
# Output pinning: if tests/examples/<dir>/<file>.expect exists, the example's
# stdout must match it byte-for-byte.  (.expect, not .out: .gitignore's
# global *.out rule for compiler artifacts would silently swallow the
# sidecars, demoting every pinned example to status-only in a fresh clone.)  Without a sidecar the example is
# STATUS-ONLY (exit 0 is the whole check) and says so -- no silent caps.
# Status-only is deliberate for output that cannot be pinned portably:
# or/hello.x prints a per-OS syscall number, execve-ls.x prints a live
# directory listing.
#
#   UPDATE=1 sh tools/check-examples.sh   # regenerate existing sidecars
#
# UPDATE rewrites only sidecars that already exist -- promoting a
# status-only example to pinned is a deliberate act (create the file, run
# UPDATE, review the diff).
#
# Memory guard: the interpreter arms its own allocation ceiling via
# (alloc-limit! N) fed ahead of the library, exactly as spec-runner.sh
# does -- a runaway example fails instead of eating the machine.
set -u

cd "$(dirname "$0")/.." || exit 1

X_BIN="${X_BIN:-./x}"
X_ALLOC_LIMIT_OBJS="${X_ALLOC_LIMIT_OBJS:-300000000}"

ANSI_GREEN='\033[1;32m'
ANSI_RED='\033[1;31m'
ANSI_RESET='\033[0m'

# Wall-time guard, same detection as spec-runner.sh (macOS: gtimeout).
_TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then
  _TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  _TIMEOUT_BIN="gtimeout"
fi
TIMEOUT_CMD=""
if [ -n "$_TIMEOUT_BIN" ]; then
  TIMEOUT_CMD="$_TIMEOUT_BIN ${TIMEOUT_EXAMPLE_SECS:-120}"
fi

# x.sh's -l resolution (#35): lib/x.x for the base dir, then lib/x-DIR.x,
# then apps/DIR/run.x.
entry_for_dir() {
  case "$1" in
    x) echo "lib/x.x"; return ;;
  esac
  if [ -e "lib/x-$1.x" ]; then
    echo "lib/x-$1.x"
  elif [ -e "apps/$1/run.x" ]; then
    echo "apps/$1/run.x"
  else
    echo ""
  fi
}

_TMP="${TMPDIR:-/tmp}/check-examples.$$"
mkdir -p "$_TMP"
trap 'rm -rf "$_TMP"' EXIT

total=0; pinned=0; failed=0

for f in examples/*/*; do
  case "$f" in
    */README.md) continue ;;
  esac
  [ -f "$f" ] || continue

  dir=$(basename "$(dirname "$f")")
  entry=$(entry_for_dir "$dir")
  if [ -z "$entry" ]; then
    printf '%bFAIL%b %s: no dialect entry for examples/%s/\n' \
      "$ANSI_RED" "$ANSI_RESET" "$f" "$dir"
    failed=$((failed + 1)); total=$((total + 1))
    continue
  fi

  out="$_TMP/out"; errf="$_TMP/err"
  { printf '(alloc-limit! %s)\n' "$X_ALLOC_LIMIT_OBJS"; cat "$entry" "$f"; } \
    | $TIMEOUT_CMD "$X_BIN" --batch >"$out" 2>"$errf"
  status=$?
  total=$((total + 1))

  if [ "$status" -ne 0 ]; then
    printf '%bFAIL%b %s: exit %s (dialect %s)\n' \
      "$ANSI_RED" "$ANSI_RESET" "$f" "$status" "$dir"
    sed 's/^/  stderr: /' "$errf" | head -10
    failed=$((failed + 1))
    continue
  fi

  expect="tests/examples/${f#examples/}.expect"
  if [ -n "${UPDATE:-}" ] && [ -e "$expect" ]; then
    cp "$out" "$expect"
    printf 'update %s\n' "$expect"
    pinned=$((pinned + 1))
  elif [ -e "$expect" ]; then
    if cmp -s "$out" "$expect"; then
      pinned=$((pinned + 1))
    else
      printf '%bFAIL%b %s: output differs from %s\n' \
        "$ANSI_RED" "$ANSI_RESET" "$f" "$expect"
      diff "$expect" "$out" | head -20
      failed=$((failed + 1))
      continue
    fi
  else
    printf 'note %s: status-only (no %s)\n' "$f" "$expect"
  fi
done

if [ "$failed" -eq 0 ]; then
  printf '%bexamples: %s ok (%s output-pinned)%b\n' \
    "$ANSI_GREEN" "$total" "$pinned" "$ANSI_RESET"
  exit 0
fi
printf '%bexamples: %s of %s FAILED%b\n' "$ANSI_RED" "$failed" "$total" "$ANSI_RESET"
exit 1
