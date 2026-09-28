#!/bin/sh
# profile.sh -- which functions a program's evaluation goes to
#
# Usage: sh tools/dev/profile.sh [-l LIB] [-n ROWS] [--tsv] [-x X-OPTION]...
#                                FILE [ARG...]
#
# Boots LIB on the profiling engine, sets every eval count to zero, runs
# FILE, and prints the functions whose bodies evaluation reached most, most
# first, with the source line each body starts on.  The boot is left out of
# the counts and FILE's own top-level forms are not functions, so what is
# listed is what FILE called.
#
# FILE is included, not piped in after the library as x.sh -f does: piped
# forms belong to no file and their lines count from the start of the
# stream, so FILE's own functions would be listed as ":<line of the stream>".
# Included, they are listed by FILE's path and their own lines.
#
#   -l LIB        the dialect or bundle to boot, as x.sh's -l (default: x.sh's)
#   -n ROWS       rows to print (default 30)
#   --tsv         every row, unsorted, tab-separated and led by PROF, for a
#                 script to merge: PROF file line calls evals pairs saturated
#   -x X-OPTION   one option for x.sh, such as -x --no-image; repeatable
#
# Each ARG reaches FILE as x.sh hands arguments on, after a `--`.
#
# A count stops at 1,048,575.  A row whose evals end in + holds a count that
# reached it, and its sum is a lower bound: profile a shorter run.
#
# Needs x-bin-profile (make x-bin-profile), which an engine release ships
# from x-engine-c v0.2.15 on.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
X_PROFILE_BIN="${X_BIN:-$ROOT/x-bin-profile}"

usage() {
	echo "Usage: $0 [-l LIB] [-n ROWS] [--tsv] [-x X-OPTION]... FILE [ARG...]" >&2
	exit 2
}

LIB=""
ROWS=30
TSV=0
FILE=""
# x.sh's options, one per line: an option holds no newline, and a list kept
# this way needs no eval to hand back.
XOPTS=""
while [ $# -gt 0 ]; do
	case "$1" in
		-l) [ $# -ge 2 ] || usage; LIB="$2"; shift 2 ;;
		-n) [ $# -ge 2 ] || usage; ROWS="$2"; shift 2 ;;
		-x) [ $# -ge 2 ] || usage; XOPTS="$XOPTS$2
"; shift 2 ;;
		--tsv) TSV=1; shift ;;
		-*) usage ;;
		*) FILE="$1"; shift; break ;;
	esac
done

[ -n "$FILE" ] || usage
[ -f "$FILE" ] || { echo "profile: $FILE not found" >&2; exit 1; }
case "$ROWS" in
	'' | *[!0-9]*) echo "profile: -n takes a number, not $ROWS" >&2; exit 2 ;;
esac
[ -x "$X_PROFILE_BIN" ] || {
	echo "profile: no profiling engine at $X_PROFILE_BIN (run: make x-bin-profile)" >&2
	exit 1
}

PROGRAM="${TMPDIR:-/tmp}/x-profile.$$.x"
trap 'rm -f "$PROGRAM"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# FILE's absolute path, as an x string literal: a backslash or a double quote
# in it is escaped.
FILE_ABS="$(cd "$(dirname "$FILE")" && pwd)/$(basename "$FILE")"
FILE_LIT=$(printf '%s' "$FILE_ABS" | sed 's/[\\"]/\\&/g')

{
	echo '(import x/tool/profile profile-clear! profile-rows profile-report)'
	echo '(profile-clear!)'
	printf '(include "%s")\n' "$FILE_LIT"
	if [ "$TSV" -eq 1 ]; then
		cat "$SCRIPT_DIR/profile-tsv.x"
	else
		echo "(profile-report $ROWS)"
	fi
} > "$PROGRAM"

# The program's arguments are the positional parameters that remain.  x.sh's
# own go in front of them, in the order they were given.
[ $# -gt 0 ] && set -- -- "$@"
set -- -f "$PROGRAM" "$@"
_rest=$XOPTS
_opts=""
while [ -n "$_rest" ]; do
	_opt=${_rest%%"
"*}
	_rest=${_rest#*"
"}
	_opts="$_opt
$_opts"
done
while [ -n "$_opts" ]; do
	_opt=${_opts%%"
"*}
	_opts=${_opts#*"
"}
	set -- "$_opt" "$@"
done
[ -n "$LIB" ] && set -- -l "$LIB" "$@"

X_BIN="$X_PROFILE_BIN" sh "$ROOT/x.sh" -q "$@"
