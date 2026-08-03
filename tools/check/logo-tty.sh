#!/bin/sh
# check-logo-tty.sh -- the Logo REPL's tty contract, pinned executably.
#
# The #152/#157 interactive behaviors (ctrl-c cancel, exit paths, hooks,
# execute-once) are isatty-guarded and therefore INVISIBLE to every
# batch-driven suite -- the front-facing-audit lesson.  This harness
# drives real pty sessions with expect(1) and is the only executable
# witness of that contract.  It must be green BEFORE any rewrite of the
# logo reader touches apps/logo, and stay green (modulo known-fail
# deletions) after.
#
# Tests live in tests/logo-tty/: t*.exp run under expect, t*.sh under
# plain sh.  tests/logo-tty/known-fail.txt lists tests that pin the
# POST-rewrite ruling and are expected to fail today; a listed test that
# PASSES is a failure of this harness (the fix landed -- delete its
# line in the same change, so the list can only shrink).
#
#     ., .,
#     {O,O}
#     (   )
#      " "

set -u
cd "$(dirname "$0")/../.."

if ! command -v expect >/dev/null 2>&1; then
	echo "SKIP: expect not installed -- logo tty contract not exercised"
	exit 0
fi
if [ ! -e x-bin ]; then
	echo "check-logo-tty: no x-bin -- run make first" >&2
	exit 1
fi

# Wall-time guard, same detection as spec-runner.sh (macOS: gtimeout).
_TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then
	_TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
	_TIMEOUT_BIN="gtimeout"
fi
TIMEOUT_CMD=""
if [ -n "$_TIMEOUT_BIN" ]; then
	TIMEOUT_CMD="$_TIMEOUT_BIN ${TIMEOUT_LOGO_TTY_SECS:-30}"
fi

ANSI_GREEN='\033[1;32m'
ANSI_RED='\033[1;31m'
ANSI_YELLOW='\033[1;33m'
ANSI_RESET='\033[0m'

KNOWN_FAIL=tests/logo-tty/known-fail.txt

pass=0; fail=0; xfail=0; xpass=0

known_fail() {
	[ -e "$KNOWN_FAIL" ] && grep -qx "$1" "$KNOWN_FAIL"
}

# Each test spawns its own logo session; a wedged one must not strand
# children.  The viewer server ignores SIGINT by design, so sweep by
# command line after every test.
sweep() {
	pkill -f 'x-bin --batch' 2>/dev/null
	sleep 1
}

for t in tests/logo-tty/t*.exp tests/logo-tty/t*.sh; do
	[ -e "$t" ] || continue
	name=$(basename "$t")
	case "$t" in
		*.exp) $TIMEOUT_CMD expect "$t" >/dev/null 2>&1 ;;
		*.sh)  $TIMEOUT_CMD sh "$t" >/dev/null 2>&1 ;;
	esac
	status=$?
	sweep
	if [ "$status" -eq 0 ]; then
		if known_fail "$name"; then
			printf "${ANSI_RED}XPASS${ANSI_RESET} %s -- fixed: delete its known-fail.txt line\n" "$name"
			xpass=$((xpass + 1))
		else
			printf "${ANSI_GREEN}ok${ANSI_RESET}    %s\n" "$name"
			pass=$((pass + 1))
		fi
	else
		if known_fail "$name"; then
			printf "${ANSI_YELLOW}xfail${ANSI_RESET} %s (pins the post-rewrite ruling)\n" "$name"
			xfail=$((xfail + 1))
		else
			printf "${ANSI_RED}FAIL${ANSI_RESET}  %s\n" "$name"
			fail=$((fail + 1))
		fi
	fi
done

echo
if [ "$fail" -eq 0 ] && [ "$xpass" -eq 0 ]; then
	printf "${ANSI_GREEN}logo-tty: %d ok, %d known-fail${ANSI_RESET}\n" "$pass" "$xfail"
	exit 0
fi
printf "${ANSI_RED}logo-tty: %d ok, %d FAIL, %d XPASS, %d known-fail${ANSI_RESET}\n" \
	"$pass" "$fail" "$xpass" "$xfail"
exit 1
