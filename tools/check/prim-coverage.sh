#!/bin/sh
# prim-coverage.sh -- every C primitive is exercised by a spec, or says why not.
#
# THE CONTRACT: for each primitive the C source registers, the spec suite either
# exercises it -- by name, through its catalog coordinate, or through the class
# that fronts its namespace -- or carries a section saying it is deliberately
# unspecced and why.  A primitive that is neither fails this gate.
#
# WHY.  Thirteen primitives had no spec at all, and nobody knew: the byte-level
# string trio, the pointer word-writer, the heap pin, the allocation guard the
# harness itself arms before every run.  They were found by accident while
# auditing documentation.  Nothing enumerated the surface and asked which parts
# of it ran, so the gap could only ever be found by looking.
#
# The exemption is the part that keeps this honest.  An untestable primitive is
# a decision -- heap-sweep frees live data without an immediately preceding
# mark, and evaluating anything in x allocates, so no correct x-level call site
# exists -- and a decision belongs on the record, next to the subject, where a
# reader meets it.  It is written as a spec section:
#
#     ## heap sweep -- deliberately not specced here
#
#     <the reason, in prose>
#
# so the reason lives with the primitive rather than in a list that drifts from
# it.  Stale exemptions fail too: naming a primitive that no longer exists is
# the same rot pointed the other way.
#
# Shell, per the tools charter: this is a corpus scan over ~135 spec files, and
# the same per-byte cost that keeps dup-defs and bare-globals out of x applies.
# The surface comes from the engine's tools/lib/isa-scan.awk -- the same
# scanner check-isa uses over there, read across the boundary so there is
# one definition of "what counts as a binding site", not two.
set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# The C lives in the x-engine-c submodule (the 2026-08-21 split).  This gate's
# SUBJECT moved; its manifest did not -- tools/contract/ holds runtime boot
# data the library includes, so it stays here and the scan reaches across.
ENGINE="$ROOT/engine"
cd "$ROOT"

SCAN="${TMPDIR:-/tmp}/prim-cov-scan.$$"
trap 'rm -f "$SCAN"' EXIT INT TERM

awk -v names=1 -f "$ENGINE"/tools/lib/isa-scan.awk \
	"$ENGINE"/src/*.c "$ENGINE"/src/x-prim/*.c "$ENGINE"/src/x-syntax/*.c \
	"$ENGINE"/opt/x-prim/*.c > "$SCAN"

# The C suite is part of the answer: ffi-call, ptr->str and token-read are
# exercised there and nowhere else, so a scan of the x specs alone reports
# them missing.
find tests "$ENGINE"/tests \( -name '*.spec.md' -o -name '*.spec.c' \) | sort > "$SCAN.files"

awk -v scan="$SCAN" '
BEGIN {
	SQ = sprintf("%c", 39)   # a single quote; see the prim-ref scan below

	# ---- the surface
	while ((getline line < scan) > 0) {
		n = split(line, f, " ")
		if (f[1] == "bare" || f[1] == "value") { prim[f[2]] = ""; cfn[f[2]] = f[3] }
		else if (f[1] == "catalog" && n >= 4)  { prim[f[4]] = f[2] " " f[3]; cfn[f[4]] = f[5] }
	}
	close(scan)
}

# ---- what the specs EXECUTE.  Only code counts: a primitive named in prose
# is not a primitive under test, and counting prose would pass this gate on
# the very sections that declare something unspecced.  It would also have
# swallowed the two false leads that sent me chasing ghosts -- a C comment
# reading "ptr->string round-trips" and a spec paragraph mentioning
# token-read-string.
FNR == 1 { in_fence = 0; is_c = (FILENAME ~ /\.spec\.c$/) }

# A section declaring a primitive deliberately unspecced (prose, outside code).
!is_c && /^## .* -- deliberately not specced/ {
	s = $0
	sub(/^## /, "", s)
	sub(/ -- deliberately not specced.*$/, "", s)
	exempt[s] = FILENAME
	next
}

!is_c && /^```/ { in_fence = !in_fence; next }

{
	if (is_c) {
		# In the C suite the x-lang under test lives in string literals.
		# Test DESCRIPTIONS are string literals too, so only strings that
		# look like source -- containing a paren -- are counted.
		code = ""
		s = $0
		while (match(s, /"[^"]*"/)) {
			lit = substr(s, RSTART + 1, RLENGTH - 2)
			if (index(lit, "(") > 0) code = code " " lit
			s = substr(s, RSTART + RLENGTH)
		}
		# A C test may drive the primitive by calling its C function
		# directly rather than through an x-lang string -- ffi-call, clock
		# and atomic are all tested that way.
		s = $0
		while (match(s, /x_(prim|syntax)_[A-Za-z_0-9]+/)) {
			ctok[substr(s, RSTART, RLENGTH)] = 1
			s = substr(s, RSTART + RLENGTH)
		}
		if (code == "") next
	} else {
		if (!in_fence) next
		code = $0
	}

	# prim-ref coordinates.  The quote character is built with sprintf: this
	# awk program is itself single-quoted by the shell, so it cannot contain
	# one.
	s = code
	while (match(s, "prim-ref[ \t]+" SQ "[^ \t)]+[ \t]+" SQ "[^ \t)]+")) {
		t = substr(s, RSTART, RLENGTH)
		gsub(/prim-ref[ \t]+/, "", t)
		gsub(SQ, "", t)
		sub(/[ \t]+/, " ", t)
		coord[t] = 1
		s = substr(s, RSTART + RLENGTH)
	}

	# class calls: (Heap mark-hook! ...) -- the class fronting a namespace
	s = code
	while (match(s, /\([ \t]*[A-Z][A-Za-z0-9]*[ \t]+[^ \t()]+/)) {
		t = substr(s, RSTART, RLENGTH)
		sub(/^\([ \t]*/, "", t); sub(/[ \t]+/, " ", t)
		classcall[t] = 1
		s = substr(s, RSTART + RLENGTH)
	}

	# bare tokens.  Split on structure rather than matching an identifier
	# shape: primitive names include ~ & << >> | ^ = < - * /, which no
	# word-ish pattern accepts, and those were exactly the ones missed.
	s = code
	gsub(/[()`",;]/, " ", s)
	n = split(s, w, /[ \t]+/)
	for (i = 1; i <= n; i++) if (w[i] != "") tok[w[i]] = 1
	next
}

END {
	# class names that front a namespace: Ns capitalised, plus the aliases
	# the library actually uses.
	alias["str"] = "Str Str8 StrUtf8"
	alias["int"] = "Int Num"
	alias["sym"] = "Sym Symbol"
	alias["bytes"] = "Bytes"
	alias["obj"] = "Obj Object"

	for (p in prim) {
		# The library saves several primitives under a %-prefixed alias
		# before rebinding the bare name (%int->ptr, %str-length); a spec
		# reaching one of those is reaching the primitive.
		if ((p in tok) || (("%" p) in tok)) { ok++; continue }
		if (cfn[p] != "" && (cfn[p] in ctok)) { ok++; continue }

		hit = 0
		if (prim[p] != "") {
			split(prim[p], c, " ")
			ns = c[1]; m = c[2]
			if ((ns " " m) in coord) hit = 1
			if (!hit) {
				cls = toupper(substr(ns,1,1)) substr(ns,2)
				list = cls (ns in alias ? " " alias[ns] : "")
				k = split(list, cc, " ")
				for (i = 1; i <= k; i++)
					if ((cc[i] " " m) in classcall) { hit = 1; break }
			}
		}
		if (hit) { ok++; continue }

		# exempt by name or by coordinate
		if ((p in exempt) || (prim[p] != "" && (prim[p] in exempt))) { ex++; continue }

		bad++
		printf "  %s%s -- no spec exercises it, and no section declares it unspecced\n",
			p, (prim[p] != "" ? " [" prim[p] "]" : "")
	}

	# stale exemptions: a reason for something that is not a primitive
	for (e in exempt) {
		if (e in prim) continue
		stale = 1
		for (p in prim) if (prim[p] == e) { stale = 0; break }
		if (stale) {
			printf "  %s -- declared unspecced in %s, but no such primitive is registered\n",
				e, exempt[e]
			bad++
		}
	}

	if (bad) {
		printf "prim-coverage: FAIL -- %d primitive(s) unaccounted for.\n", bad
		exit 1
	}
	printf "prim-coverage: ok (%d exercised, %d declared unspecced).\n", ok, ex
}
' $(cat "$SCAN.files")
rm -f "$SCAN.files"
