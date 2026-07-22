#!/bin/sh
# amalgam-smoke.sh -- boot every generated amalgam entry in batch mode and
# pin a smoke expression through it.  A generator
# slip (wrapped form, wrong order, missing file) dies here, not in an
# installed tree.  Same self-limit as the other harnesses.
#
# The logo app amalgam is generated but not smoked: its entry forks a
# server; booting it headless is a test for another layer.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
X_BIN="${X_BIN:-$PROJECT_DIR/x}"
cd "$PROJECT_DIR" || exit 1

X_ALLOC_LIMIT_OBJS="${X_ALLOC_LIMIT_OBJS:-300000000}"
case "$X_ALLOC_LIMIT_OBJS" in
  ''|*[!0-9]*) X_ALLOC_LIMIT_OBJS=300000000 ;;
esac

STATUS=0

smoke() { # entry expected-output extra-form
	_out=$({
		printf '(alloc-limit! %s)\n' "$X_ALLOC_LIMIT_OBJS"
		cat "build/boot/$1.x"
		printf '(display (+ 1 2))(newline)(import x/type/set)(display ((Set of 1 2 2 3) length))(newline)%s' "$3"
	} | "$X_BIN" "--batch" 2>&1)
	if [ "$_out" = "$2" ]; then
		echo "amalgam-smoke: $1 ok"
	else
		STATUS=1
		echo "amalgam-smoke: $1 FAIL" >&2
		printf 'expected:\n%s\nactual:\n%s\n' "$2" "$_out" >&2
	fi
}

CORE_EXPECT='3
3'
TOWER_EXPECT='3
3
1/3'

smoke x "$CORE_EXPECT" ''
smoke he "$CORE_EXPECT" ''
smoke xe "$TOWER_EXPECT" '(display (/ 1 3))(newline)'
smoke rn "$TOWER_EXPECT" '(display (/ 1 3))(newline)'
smoke x-base "$TOWER_EXPECT" '(display (/ 1 3))(newline)'

exit "$STATUS"
