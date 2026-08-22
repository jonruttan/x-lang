#!/bin/sh
# constraints.sh -- diff the source's platform-parameter markers against the
# committed manifest tools/contract/constraints.x.
#
# THE CONTRACT: a module that only works at one value of a platform parameter
# (word size, byte order) says so at the code, as a one-line marker:
#
#     ; constraint: word-size = 8 -- struct addrinfo pointer offsets
#
# and carries the matching row in the manifest.  The diff runs BOTH ways, so a
# marker without a row fails (an assumption added silently) and a row without a
# marker fails (a row outliving its subject) -- the discipline check/prim-coverage.sh
# applies to its exemptions, pointed at a different kind of claim.
#
# WHY THIS EXISTS.  A parameter is not a capability.  `word-size = 8` in a
# requires-list would lock out the 32-bit Pi, a supported target, and would be
# false besides: obj-layout.x is expressed in WORDS and lib/x/boot/data.x probes
# the width at boot, so the core is width-agnostic by construction.  The syscall
# and FFI layer is not -- it decodes C structs at offsets taken from 64-bit
# headers -- and before this those assumptions were prose beside the code, seen
# by no gate.  Now a 32-bit engine can be told which modules to refuse instead of
# decoding garbage into a plausible-looking alist.
#
# WHAT IT PROVES.  That every declared assumption is recorded and every record
# still has a subject.  NOT that a module is correct at another parameter value:
# only running it there shows that, and that needs a 32-bit engine.  Undeclared
# assumptions are still found by reading.
#
# Shell, per the tools charter: a corpus scan over ~150 files, the same per-byte
# grounds as check/dup-defs.sh and check/bare-globals.sh.
#
# Usage: sh tools/check/constraints.sh
set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

MAN="tools/contract/constraints.x"
[ -f "$MAN" ] || { echo "constraints: no manifest at $MAN" >&2; exit 2; }

SCRATCH="${TMPDIR:-/tmp}"
SRC_LIST="$SCRATCH/constraints-src.$$"
MAN_LIST="$SCRATCH/constraints-man.$$"
DIFF_OUT="$SCRATCH/constraints-diff.$$"
# One trap covering all three: an interrupt between the diff and an inline rm
# used to leak the diff output in the older scans.
trap 'rm -f "$SRC_LIST" "$MAN_LIST" "$DIFF_OUT"' EXIT INT TERM

# --- 1. the SOURCE's view: every marker line, as "PATH param op value" -------
# The scan covers the same trees the other library gates do (lib + apps + tools);
# a marker anywhere else is not a module anyone imports.  The MANIFEST itself is
# excluded: it lives under tools/contract/ and its header quotes the marker
# syntax, so a reworded sentence there would otherwise scan as a phantom row in a
# file that is data, not a module.
find lib apps tools -name '*.x' -type f \
	! -path "./$MAN" ! -path "$MAN" \
	| sort \
	| xargs awk '
		/^[ \t]*; *constraint:/ {
			line = $0
			sub(/^[ \t]*; *constraint:[ \t]*/, "", line)
			sub(/[ \t]*--.*$/, "", line)          # drop the reason
			gsub(/[ \t]+$/, "", line)
			n = split(line, f, /[ \t]+/)
			if (n != 3) {
				printf "constraints: malformed marker in %s:%d: %s\n", FILENAME, FNR, $0 > "/dev/stderr"
				bad = 1
				next
			}
			printf "%s %s %s %s\n", FILENAME, f[1], f[2], f[3]
		}
		END { if (bad) exit 1 }
	' > "$SRC_LIST"

# --- 2. the MANIFEST's view: the same four fields ---------------------------
# Rows are anchored (constraint "PATH" param op value) forms, one per line.
awk '
	/^[ \t]*\(constraint "/ {
		line = $0
		sub(/^[ \t]*\(constraint[ \t]+"/, "", line)
		path = line
		sub(/".*$/, "", path)
		sub(/^[^"]*"[ \t]*/, "", line)
		sub(/\).*$/, "", line)
		gsub(/[ \t]+$/, "", line)
		n = split(line, f, /[ \t]+/)
		if (n != 3) {
			printf "constraints: malformed row in the manifest: %s\n", $0 > "/dev/stderr"
			bad = 1
			next
		}
		printf "%s %s %s %s\n", path, f[1], f[2], f[3]
	}
	END { if (bad) exit 1 }
' "$MAN" > "$MAN_LIST"

# --- 3. diff ----------------------------------------------------------------
sort -o "$SRC_LIST" "$SRC_LIST"
sort -o "$MAN_LIST" "$MAN_LIST"

if ! diff -u "$MAN_LIST" "$SRC_LIST" > "$DIFF_OUT" 2>&1; then
	echo "source markers and $MAN disagree (-manifest +source):"
	grep '^[-+][^-+]' "$DIFF_OUT"
	echo "FAIL: a '; constraint:' marker gained or lost a row (or a row went stale)."
	echo "  a module that only works at one parameter value declares it at the code"
	echo "  AND in the manifest; see the manifest header for the row format."
	exit 1
fi

echo "constraint check: $(grep -c . "$MAN_LIST") rows, source and $MAN agree."
exit 0
