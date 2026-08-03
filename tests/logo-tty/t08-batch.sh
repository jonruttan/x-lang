#!/bin/sh
# Behaviors 11+12: batch mode processes a whole program (ch1.logo: exit 0,
# empty stdout -- re-asserting the check-examples pin from inside this
# harness), and an erroring batch reports to stderr and exits 1.
# %logo-on-exit coverage is exit-code-proxied: the hook is nil in batch
# (main.x guards the server fork on %batch?), so a clean exit IS the pin.
set -u
cd "$(dirname "$0")/../.."

out=$(sh x.sh -l logo -f examples/logo/ch1.logo 2>/dev/null)
status=$?
if [ "$status" -ne 0 ] || [ -n "$out" ]; then
	echo "FAIL: ch1.logo batch: status=$status out=<$out>"
	exit 1
fi

tmp="${TMPDIR:-/tmp}/logo-tty-batch-$$.logo"
# `fd` with no argument raises (an UNKNOWN word would not -- dispatch
# silently ignores those).
printf 'print 1 + 2\nfd\n' > "$tmp"
err=$(sh x.sh -l logo -f "$tmp" 2>&1 >/dev/null)
status=$?
rm -f "$tmp"
if [ "$status" -ne 1 ]; then
	echo "FAIL: erroring batch: status=$status (want 1)"
	exit 1
fi
case "$err" in
	*Error*) : ;;
	*) echo "FAIL: erroring batch printed no Error line: <$err>"; exit 1 ;;
esac
exit 0
