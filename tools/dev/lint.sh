#!/bin/sh
# lint.sh -- x-lang linter wrapper
#
# Runs the x-lang linter on each target file. The linter uses
# the interpreter's own env-alist for known symbols -- no manual
# enumeration needed.
#
# Usage: sh tools/dev/lint.sh [--lib] [--lang LANG] [file.x ...]
#   --lib: suppress unused warnings (for library/export files)
#   --warnings: also print advisory warnings for files that pass
#   --lang LANG: use language-specific constructs
#   No args: lint lib/x-core.x, lib/x/*.x, and apps/*/*.x in --lib mode
#
# App files (apps/NAME/*.x) reference their sibling modules, so linting one
# in isolation reads every sibling export as "Undefined".  For an app target
# the wrapper LOADS the app's sibling modules (any sibling with a (provide),
# via import so the module registry dedups their cross-imports) ahead of the
# linter, exactly as the library itself is loaded; the target file is still
# analysed as DATA, never run -- which is also what keeps entry files
# (run.x/main.x, no provide) safe to lint: nothing forks a server.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
X_BIN="$PROJECT_DIR/x-bin"
LINTER="$SCRIPT_DIR/lint.x"
LANG_LIB="$PROJECT_DIR/lib/x-core.x"
CONSTRUCTS="$PROJECT_DIR/lib/x/constructs.x"

LIB_MODE=0
LANG=""
SHOW_WARNINGS=0

# Parse flags (before file args)
while [ $# -gt 0 ]; do
  case "$1" in
    --lib) LIB_MODE=1; shift ;;
    --warnings) SHOW_WARNINGS=1; shift ;;
    --group) GROUP_LIST="$2"; shift 2 ;;
    --lang) LANG="$2"; shift 2 ;;
    -*) echo "Usage: $0 [--lib] [--warnings] [--lang LANG] [file.x ...]" >&2; exit 1 ;;
    *) break ;;
  esac
done

# Compute the preload for one ABSOLUTE target path into _PRELOAD -- the
# imports executed ahead of the linter so the target's legitimate env is
# bound.  Factored out (#323): the per-file loop and the batch grouper
# both need it (the group KEY is the preload text, verbatim).
_preload_for() {
  _PRELOAD=""
  case "$1" in
    */lib/x/*.x)
      _PRELOAD="$(grep '^(import ' "$1" | sed 's/;.*$//' | tr '\n' ' ')"
      ;;
    */apps/*/*.x)
      _APP_DIR="$(cd "$(dirname "$1")" && pwd)"
      _APPS_ROOT="$(dirname "$_APP_DIR")"
      _APP="$(basename "$_APP_DIR")"
      _ABS_F="$_APP_DIR/$(basename "$1")"
      _PRELOAD="(import-path! \"$_APPS_ROOT\")"
      for _m in "$_APP_DIR"/*.x; do
        grep -q '(provide ' "$_m" && [ "$_m" != "$_ABS_F" ] && continue
        _PRELOAD="$_PRELOAD $(grep '^(import ' "$_m" | sed 's/;.*$//' | tr '\n' ' ')"
      done
      for _m in "$_APP_DIR"/*.x; do
        [ "$_m" = "$_ABS_F" ] && continue
        grep -q '(provide ' "$_m" || continue
        _PRELOAD="$_PRELOAD (import $_APP/$(basename "$_m" .x))"
      done
      ;;
  esac
  for _k in $(sed -n 's/^; lint-known:\(.*\)$/\1/p' "$1"); do
    _PRELOAD="$_PRELOAD (def $_k 0)"   # 0, not (): a nil binding would fail the value-subject test
  done
}

# --group LISTFILE (#323): lint every file in LISTFILE (absolute paths,
# one per line, identical preloads by construction) in ONE engine.  The
# stream interleaves (%lint-next-file "NAME") markers with the file
# bodies; the driver emits a %%LINT%% block per file and the awk below
# reassembles the legacy per-file lines.  A file with no verdict (the
# engine died mid-group) reports as a failure, never a silent pass.
if [ -n "${GROUP_LIST:-}" ]; then
  _FIRST=$(head -1 "$GROUP_LIST")
  _preload_for "$_FIRST"
  _CONSTRUCTS_INPUT="$(cat "$CONSTRUCTS") ()"
  _OUT=$({
      printf '%s\n' "$_CONSTRUCTS_INPUT"
      [ "$LIB_MODE" -eq 1 ] && printf '%%lint-lib\n'
      while IFS= read -r _f; do
        printf '(%%lint-next-file "%s")\n' "$(echo "$_f" | sed "s|$PROJECT_DIR/||")"
        cat "$_f"
        printf '\n'
      done < "$GROUP_LIST"
    } | { cat "$LANG_LIB"; printf '%s\n' "$_PRELOAD"; cat "$LINTER" -; } | "$X_BIN" 2>&1)
  printf '%s\n' "$_OUT" | awk -v listfile="$GROUP_LIST" -v proj="$PROJECT_DIR/" '
    BEGIN {
      nf = 0
      while ((getline l < listfile) > 0) { sub(proj, "", l); want[l] = 1; order[++nf] = l }
      fail = 0
    }
    /^%%LINT%% / { name = substr($0, 10); buf = ""; next }
    /^%%OK%%$/   { printf "  \033[1;32m.\033[0m %s\n", name; done[name] = 1; name = ""; next }
    /^%%FAIL%%$/ {
      fail = 1
      printf "  \033[1;31mF\033[0m %s\n", name
      printf "%s", buf
      done[name] = 1; name = ""; next
    }
    name != "" { if ($0 !~ /^\*\*\* ERROR/) buf = buf "    " $0 "\n"; next }
    { stray = stray "    " $0 "\n" }
    END {
      for (i = 1; i <= nf; i++) {
        if (!(order[i] in done)) {
          fail = 1
          printf "  \033[1;31mF\033[0m %s\n", order[i]
          printf "    (no verdict -- engine died mid-group)\n"
          if (stray != "") { printf "%s", stray; stray = "" }
        }
      }
      exit fail
    }'
  exit $?
fi

# Default targets: library files in --lib mode (skip data-only files),
# then every app file -- the sibling preload below makes those lintable.
if [ $# -eq 0 ]; then
  LIB_MODE=1
  _FILES="$LANG_LIB"
  for _f in "$PROJECT_DIR"/lib/x/*.x; do
    case "$_f" in */constructs.x) ;; *) _FILES="$_FILES $_f" ;; esac
  done
  # The library subdirectories -- formerly a sweep blind spot (#226 found
  # rn.x flagging a reference its unlinted importer shared).  The
  # dialect-entry preload arm below covers these too: a module's own
  # top-level (import ...) lines declare its env, and re-importing an
  # already-loaded module is a no-op.
  # Exclusions, each for a reason:
  #   tower-compiled.x   -- GENERATED tower amalgam, not a module
  #   tool/asm/*.x       -- per-arch include FRAGMENTS of tool/asm.x
  #   compile/pipeline.x -- include fragment of tool/compile.x's flow
  for _f in $(find "$PROJECT_DIR/lib/x" -mindepth 2 -name '*.x' | sort); do
    case "$_f" in
      */boot/tower-compiled.x|*/tool/asm/*|*/compile/pipeline.x) continue ;;
    esac
    _FILES="$_FILES $_f"
  done
  for _f in "$PROJECT_DIR"/apps/*/*.x; do
    [ -e "$_f" ] && _FILES="$_FILES $_f"
  done
  # PARALLEL=1: fan the sweep out via self-recursion, one file per child
  # (each file is one engine run either way).  xargs exits nonzero when
  # any child fails, so the gate verdict is preserved.  Child output is
  # per-line atomic; a failing file's block may interleave with others,
  # which a green gate never shows.
  #
  # Default fan-out: min(cores, 4).  A child is NOT small: measured
  # 2026-09-05 (engine v0.2.6, --lib --group, GNU time -v on the 8GB
  # x86-64 Linux guest of tools/dev/x86-vm.sh), the single-file children
  # class.x and pin.x peak at 6.2GB and 7.9GB maxrss (with lint.x's sweep
  # before the first file; 7.3GB and 7.9GB without it) -- so NPROC=2 on
  # a 16GB runner is already the edge, and one such child was OOM-killed
  # at 5.18GB anon-rss.  macOS reports the same runs anywhere between
  # 1GB and 3.6GB (the compressor takes pages out of the resident set;
  # read those as a floor).  The ~600MB figure this comment used to quote
  # (class.x, 2026-08-13) is history: 8-wide OOM-killed the 7GB ubuntu
  # CI runner (SIGTERM 143, ECHILD noise in make) back then, and at
  # today's sizes 4-wide OOM-killed the 16GB release runner twice at the
  # same file (#622 caps that gate at NPROC=2).  Raise NPROC explicitly
  # on machines with the memory for it -- and LOWER it where the memory
  # is the constraint: CI pins NPROC=2 on its ubuntu leg.  The
  # derivation below is min(cores, 4), so it tracks the RUNNER rather
  # than the workload; a caller that knows its box should say so.
  # Within a batch child the driver sweeps the heap before every file
  # (lint.x; x has no automatic GC), so a group costs its heaviest FILE,
  # not the sum of its files: the figures above are per file.
  # Batch by PRELOAD SIGNATURE (#323): one engine boot lints every file
  # that shares an identical mode+preload -- ~160 boots collapse to ~55
  # groups.  Identical preloads are the SOUNDNESS line: batching files
  # with different imports would union their environments and mask
  # missing-import bugs (the exact class this sweep has caught).  The
  # driver's (%lint-next-file ...) markers carry the per-file split;
  # lint-forms resets its analysis state per file.
  _GTMP=$(mktemp -d "${TMPDIR:-/tmp}/lint-groups.XXXXXX") || exit 1
  for _f in $_FILES; do
    _preload_for "$_f"
    _key=$(printf '%s|%s' "$LIB_MODE" "$_PRELOAD" | cksum | tr ' ' '-')
    printf '%s\n' "$_f" >> "$_GTMP/g$_key"
  done
  # Chunk big groups at LINT_BATCH (8) files: one 36-file group as a
  # single child serializes work four slots used to share -- the boots
  # saved were repaid in idle slots (measured ~neutral wall clock).
  # Chunks inherit the group key, so the identical-preload soundness
  # line is untouched.
  : "${LINT_BATCH:=8}"
  for _g in "$_GTMP"/g*; do
    if [ "$(grep -c '' "$_g")" -gt "$LINT_BATCH" ]; then
      split -l "$LINT_BATCH" "$_g" "${_g}-c"
      rm -f "$_g"
    fi
  done
  _NP="$NPROC"
  if [ -z "$_NP" ]; then
    _NP="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
    [ "$_NP" -gt 4 ] && _NP=4
  fi
  if [ -n "$PARALLEL" ]; then
    ls "$_GTMP"/g* | xargs -P "$_NP" -n 1 sh "$0" --lib --group
    _rc=$?
  else
    _rc=0
    for _g in "$_GTMP"/g*; do
      sh "$0" --lib --group "$_g" || _rc=1
    done
  fi
  rm -rf "$_GTMP"
  exit $_rc
fi

FAIL=0
for f in "$@"; do
  # Normalize to an absolute path: the preload arms below match on
  # */lib/x/*.x and */apps/*/*.x, which a relative argument like
  # lib/x/tool/pin.x never hits -- skipping the preload and producing
  # spurious Undefined findings the absolute-path sweep doesn't show.
  case "$f" in
    /*) ;;
    *) f="$(cd "$(dirname "$f")" && pwd)/$(basename "$f")" ;;
  esac
  _NAME=$(echo "$f" | sed "s|$PROJECT_DIR/||")

  # Auto-detect language from file path if not specified
  _LANG="$LANG"
  if [ -z "$_LANG" ]; then
    case "$f" in
      */lang/r5rs/*) _LANG="r5rs" ;;
      */lang/r7rs/*) _LANG="r7rs" ;;
      */lang/krn/*)  _LANG="krn"  ;;
      */lang/ash/*)  _LANG="ash"  ;;
      */lang/sweet/*) _LANG="sweet" ;;
      */lang/sl/*)   _LANG="sl"   ;;
    esac
  fi

  # Build constructs input: base + lang (or ())
  _LANG_CONSTRUCTS=""
  if [ -n "$_LANG" ] && [ -f "$PROJECT_DIR/lang/$_LANG/lib/constructs.x" ]; then
    _LANG_CONSTRUCTS="$PROJECT_DIR/lang/$_LANG/lib/constructs.x"
  fi
  if [ -n "$_LANG_CONSTRUCTS" ]; then
    _CONSTRUCTS_INPUT="$(cat "$CONSTRUCTS") $(cat "$_LANG_CONSTRUCTS")"
  else
    _CONSTRUCTS_INPUT="$(cat "$CONSTRUCTS") ()"
  fi

  # Preload: factored into _preload_for (#323) -- the batch grouper
  # keys on the same text this loop executes.
  _preload_for "$f"

  # Run linter: library [+ app preload] + linter code, then constructs +
  # [mode flag] + target
  if [ "$LIB_MODE" -eq 1 ]; then
    _OUT=$({ printf '%s\n%%lint-lib\n' "$_CONSTRUCTS_INPUT"; cat "$f"; } | { cat "$LANG_LIB"; printf '%s\n' "$_PRELOAD"; cat "$LINTER" -; } | "$X_BIN" 2>&1)
  else
    _OUT=$({ printf '%s\n' "$_CONSTRUCTS_INPUT"; cat "$f"; } | { cat "$LANG_LIB"; printf '%s\n' "$_PRELOAD"; cat "$LINTER" -; } | "$X_BIN" 2>&1)
  fi
  # Decide pass/fail from the linter's own output, not $?: an uncaught
  # x-lang (error) now exits non-zero, but output-based detection also
  # catches a crash that never reaches the (error) call.  A clean file
  # prints "ok"; findings (Undefined:/Unused:) or a crash produce no
  # "ok" line.
  if printf '%s\n' "$_OUT" | grep -qx "ok"; then
    printf '  \033[1;32m.\033[0m %s\n' "$_NAME"
    # Advisory warnings (ladder, arity, shadow, ...) ride a file that still
    # verdicts "ok", so they are dropped with the rest of its output unless
    # asked for.  --warnings surfaces them without failing the lint, which
    # is what a report-only rule needs to be readable at all.
    if [ "$SHOW_WARNINGS" -eq 1 ]; then
      printf '%s\n' "$_OUT" | sed -n '/^Warnings:/,$p' | while IFS= read -r line; do
        case "$line" in
          ""|ok) ;;
          *) printf '    %s\n' "$line" ;;
        esac
      done
    fi
  else
    FAIL=1
    printf '  \033[1;31mF\033[0m %s\n' "$_NAME"
    printf '%s\n' "$_OUT" | while IFS= read -r line; do
      case "$line" in
        "*** ERROR"*) ;;
        *) printf '    %s\n' "$line" ;;
      esac
    done
  fi
done

[ "$FAIL" -eq 0 ]
