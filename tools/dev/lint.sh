#!/bin/sh
# lint.sh -- x-lang linter wrapper
#
# Runs the x-lang linter on each target file. The linter uses
# the interpreter's own env-alist for known symbols -- no manual
# enumeration needed.
#
# Usage: sh tools/dev/lint.sh [--lib] [--lang LANG] [file.x ...]
#   --lib: suppress unused warnings (for library/export files)
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

# Parse flags (before file args)
while [ $# -gt 0 ]; do
  case "$1" in
    --lib) LIB_MODE=1; shift ;;
    --lang) LANG="$2"; shift 2 ;;
    -*) echo "Usage: $0 [--lib] [--lang LANG] [file.x ...]" >&2; exit 1 ;;
    *) break ;;
  esac
done

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
  # Default fan-out: min(cores, 4).  A child peaks at ~600MB RSS
  # (class.x, measured 2026-08-13); 8-wide OOM-killed the 7GB ubuntu CI
  # runner (SIGTERM 143, ECHILD noise in make) while 14GB macOS
  # survived.  4x600MB leaves headroom everywhere; raise NPROC
  # explicitly on machines with the memory for it.
  if [ -n "$PARALLEL" ]; then
    _NP="$NPROC"
    if [ -z "$_NP" ]; then
      _NP="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
      [ "$_NP" -gt 4 ] && _NP=4
    fi
    printf '%s\n' $_FILES | xargs -P "$_NP" -n 1 sh "$0" --lib || exit 1
    exit 0
  fi
  set -- $_FILES
fi

FAIL=0
for f in "$@"; do
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

  # App target: emit a preload that imports the target's sibling modules so
  # their exports are bound (known) when the target's forms are analysed.
  # The preload EXECUTES (it sits before the linter in the pipe, like the
  # library); the target is read as data after it.  Modules are recognised
  # by carrying a (provide ...); the target itself is never preloaded
  # directly, though a sibling's import chain may pull it in (harmless: the
  # linter collects the file's own defs from its forms regardless).
  _PRELOAD=""
  case "$f" in
    # Dialect entries (lib/x/*.x) reference classes their own (import ...)
    # lines load -- rn.x's system rides Proc (#226).  Same rule as the app
    # arm below: the target's top-level import lines declare the env it
    # boots with; execute just those first.  Modules import-once, so a
    # sibling chain re-pulling one is harmless.
    */lib/x/*.x)
      # TOP-LEVEL imports only, deliberately: call-time (indented)
      # imports can be guarded -- tool/asm.x imports its per-arch
      # backend inside an os match, and executing BOTH here loads the
      # wrong arch's fragment.  A name a guarded/lazy import supplies is
      # declared with a `; lint-known:` marker instead.
      _PRELOAD="$(grep '^(import ' "$f" | tr '\n' ' ')"
      ;;
    */apps/*/*.x|apps/*/*.x)
      _APP_DIR="$(cd "$(dirname "$f")" && pwd)"
      _APPS_ROOT="$(dirname "$_APP_DIR")"
      _APP="$(basename "$_APP_DIR")"
      _ABS_F="$_APP_DIR/$(basename "$f")"
      _PRELOAD="(import-path! \"$_APPS_ROOT\")"
      # Entry files (no provide) cannot be loaded -- they RUN the app -- but
      # their top-level (import ...) lines declare the env the app boots
      # with (e.g. x/num/float); execute just those, in file order, first.
      # The target's own import lines count too: read as data they never run.
      for _m in "$_APP_DIR"/*.x; do
        grep -q '(provide ' "$_m" && [ "$_m" != "$_ABS_F" ] && continue
        _PRELOAD="$_PRELOAD $(grep '^(import ' "$_m" | tr '\n' ' ')"
      done
      for _m in "$_APP_DIR"/*.x; do
        [ "$_m" = "$_ABS_F" ] && continue
        grep -q '(provide ' "$_m" || continue
        _PRELOAD="$_PRELOAD (import $_APP/$(basename "$_m" .x))"
      done
      ;;
  esac

  # Adjudicated lazy references: a `; lint-known: NAME...` header line
  # names %-globals a sibling file defines and a lazy include supplies at
  # runtime (the JIT-deferral pattern).  Bind them nil in the linter env
  # so they are known; the marker sits next to the reason in the file.
  for _k in $(sed -n 's/^; lint-known:\(.*\)$/\1/p' "$f"); do
    _PRELOAD="$_PRELOAD (def $_k 0)"   # 0, not (): a nil binding would fail the value-subject test
  done

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
