#!/bin/sh
# prim-coverage.sh -- every C primitive is exercised by a spec, or says why not.
#
# The contract: for each primitive the C source registers, the spec suite
# either exercises it -- by name, through its catalog coordinate, or through
# the class that fronts its namespace -- or carries a section saying it is
# deliberately unspecced and why.  A primitive that is neither fails this gate.
#
# An untestable primitive is a decision: heap-sweep frees live data without an
# immediately preceding mark, and evaluating anything in x allocates, so no
# correct x-level call site exists.  Such a decision is recorded next to its
# subject, as a spec section:
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
#
# The surface is read from tools/contract/isa.x rather than from the C, so the
# gate can be asked about an engine that ships no sources -- which is what
# `make engine` fetches.  That is not a weaker claim: the engine's own
# check-isa holds that manifest against its C on every build of that
# repository, so the manifest is the surface, ratcheted by the project that
# owns it.  The manifest also lists `#t` and `#f`, which a C scanner does not
# emit as value rows; this gate asks about those two as well.
set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# The C lives in the engine, a separate project (the 2026-08-21 split).  This gate's
# SUBJECT moved; its manifest did not -- tools/contract/ holds runtime boot
# data the library includes, so it stays here and the scan reaches across.
ENGINE="$ROOT/engine"
cd "$ROOT"

ISA="$ENGINE/tools/contract/isa.x"
[ -f "$ISA" ] || { echo "prim-coverage: no engine manifest at $ISA" >&2; exit 2; }

SCAN="${TMPDIR:-/tmp}/prim-cov-scan.$$"
trap 'rm -f "$SCAN" "$SCAN.files"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# The three sections that name primitives.  %isa-keep is absent: those are
# names the engine keeps bound but does not register, and this gate asks about
# the registered surface.
awk '
	/^\(def %isa-catalog/ { s="catalog"; next }
	/^\(def %isa-bare/    { s="bare";    next }
	/^\(def %isa-keep/    { s="keep";    next }
	/^\(def %isa-aliases/ { s="";        next }
	/^\(def %isa-values/  { s="value";   next }
	/^  \(/ {
		if (s == "") next
		l = $0; sub(/;.*/, "", l); gsub(/[()]/, "", l); $0 = l
		if (s == "catalog" && NF >= 3)      print "catalog", $1, $2
		else if (s != "catalog" && NF >= 1) print s, $1
	}' "$ISA" > "$SCAN"

# x-lang's specs, and only those: the engine's C suite is not in the tree once
# the engine arrives as a release.  What it uniquely covered is covered here --
# ffi/call by the conformance suite, which reaches primitives through %coord
# (see below), and heap/sweep by a declared exemption.
find tests \( -name '*.spec.md' -o -name '*.spec.c' \) | sort > "$SCAN.files"

awk -v scan="$SCAN" '
BEGIN {
	SQ = sprintf("%c", 39)   # a single quote; see the prim-ref scan below

	# ---- the surface
	while ((getline line < scan) > 0) {
		n = split(line, f, " ")
		# Two kinds of subject, in the terms the contract uses: a bare row is
		# its name and a catalog row is its coordinate, which is how x-lang
		# addresses them.  The registration name a C table carries as a third
		# string is not recorded in isa.x, and a non-C engine has none.
		if (f[1] == "bare" || f[1] == "value") { bare[f[2]] = 1; bound[f[2]] = 1 }
		# KEEP rows are bound but not registered: `%` and the rest of the int
		# operators are reachable by name and filed in the catalog as well.
		# They are not subjects of this gate -- the scanner did not make them
		# subjects either -- but they are how a spec reaches the primitive
		# behind a catalog coordinate, so they count as a way of reaching it.
		else if (f[1] == "keep")               { bound[f[2]] = 1 }
		else if (f[1] == "catalog" && n >= 3)  { cat[f[2] " " f[3]] = f[3] }
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

	# The conformance door.  That suite runs against a bare engine, where
	# prim-ref does not exist -- it is x-level -- so it reaches a primitive by
	# walking the base to the catalog: (%coord (lit ffi) (lit call)).  Reading
	# that idiom is what keeps ffi/call from reading as unexercised.
	#
	# No apostrophes in this program: it is single-quoted by the shell, which
	# is also why the quote character below is built with sprintf.
	s = code
	while (match(s, /%coord[ \t]+\(lit[ \t]+[^ \t)]+\)[ \t]+\(lit[ \t]+[^ \t)]+\)/)) {
		t = substr(s, RSTART, RLENGTH)
		gsub(/%coord[ \t]+/, "", t); gsub(/\(lit[ \t]+/, "", t); gsub(/\)/, "", t)
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

	# --- the bare surface --------------------------------------------------
	# The library saves several primitives under a %-prefixed alias before
	# rebinding the bare name (%int->ptr, %str-length); a spec reaching one of
	# those is reaching the primitive.
	for (p in bare) {
		if ((p in tok) || (("%" p) in tok)) { ok++; barehit[p] = 1; continue }
		if (p in exempt) { ex++; barehit[p] = 1; continue }
		bad++
		printf "  %s -- no spec exercises it, and no section declares it unspecced\n", p
	}

	# --- the catalog surface -----------------------------------------------
	for (c in cat) {
		m = cat[c]
		split(c, f, " ")
		ns = f[1]
		if (c in coord) { ok++; continue }

		cls = toupper(substr(ns,1,1)) substr(ns,2)
		list = cls (ns in alias ? " " alias[ns] : "")
		k = split(list, cc, " ")
		hit = 0
		for (i = 1; i <= k; i++)
			if ((cc[i] " " m) in classcall) { hit = 1; break }
		if (hit) { ok++; continue }

		# The same primitive, reached bare.  `%` is filed at (int %) and also
		# bound bare, so a spec that computes with `%` has exercised the C
		# function behind both.  They are merged only when isa.x lists the
		# name as bound.
		#
		# Reconstructing the registration name: the C files a catalog entry
		# under a name as well as a coordinate -- (alloc limit!) is called as
		# alloc-limit!, (io repl-read) as repl-read -- and that name is a free
		# string in the C table which isa.x does not record.  In practice it is
		# one of two spellings, so both are tried as plain tokens.
		#
		# This is exactly the strength the scanner had: it keyed on that name
		# and matched it as a token, with no check that anything still bound it.
		# Reconstructing the name rather than reading it is the price of not
		# needing the C in the tree, and it is paid in a false PASS at worst --
		# a spec mentioning the token without calling it -- never a false
		# refusal.
		if ((m in tok) || (("%" m) in tok)) { ok++; continue }
		nm = ns "-" m
		if ((nm in tok) || (("%" nm) in tok)) { ok++; continue }

		# exempt by coordinate, or by the method alone -- existing sections are
		# titled `repl-read` and `make-callable`, not `io repl-read`.
		if ((c in exempt) || (m in exempt)) { ex++; used_ex[c in exempt ? c : m] = 1; continue }

		bad++
		printf "  %s -- no spec exercises it, and no section declares it unspecced\n", c
	}

	# stale exemptions: a reason for something that is not a primitive
	for (e in exempt) {
		if (e in bare) continue
		if (e in cat) continue
		stale = 1
		for (c in cat) if (cat[c] == e) { stale = 0; break }
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
