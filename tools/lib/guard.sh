#!/bin/sh
# guard.sh -- run a command under a wall-time ceiling that a signal can stop.
#
# Usage: sh tools/lib/guard.sh SECONDS COMMAND [ARG...]
#
# `timeout SECONDS COMMAND` on its own cannot be stopped by the script that
# runs it: GNU timeout puts itself in a process group of its own, so an INT or
# TERM sent to the script's group never reaches the command, and the script
# waits for the command to finish before it acts on the signal.  A run that
# writes a state image is seconds of that wait, and the ceiling itself is
# minutes.
#
# So the timeout runs here in the background and this script waits for it: a
# trapped signal interrupts a `wait` where it would wait out a command in the
# foreground.  INT and TERM pass TERM to the timeout's process group, and to
# the timeout itself in case it has not made its group yet, wait for it, and
# exit 130 or 143.  TERM for both, because a command started in the background
# may have INT ignored.
#
# The command's own status is what this script exits with, timeout's 124 for a
# run that hit the ceiling included.
#
# With neither timeout nor gtimeout on PATH there is no ceiling to impose and
# no group to escape, so the command replaces this script and the caller's
# signal reaches it directly.
secs=$1
shift
[ $# -gt 0 ] || { echo "guard: usage: guard.sh SECONDS COMMAND [ARG...]" >&2; exit 2; }

bin=
if command -v timeout >/dev/null 2>&1; then bin=timeout
elif command -v gtimeout >/dev/null 2>&1; then bin=gtimeout
fi
[ -n "$bin" ] || exec "$@"

# The caller's standard input, handed over as a descriptor: a command started
# in the background reads /dev/null, and dash gives it /dev/null whatever
# redirection the command itself carries, so the descriptor is saved before
# the fork.  Callers pipe into this script.
{ "$bin" "$secs" "$@" <&3 3<&- & } 3<&0
guarded=$!

stop() {
	trap '' INT TERM
	kill -s TERM -- "-$guarded" "$guarded" 2>/dev/null || :
	wait "$guarded" 2>/dev/null || :
}
trap 'stop; exit 130' INT
trap 'stop; exit 143' TERM

status=0
wait "$guarded" || status=$?
exit "$status"
