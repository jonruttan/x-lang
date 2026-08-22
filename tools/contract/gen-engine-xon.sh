#!/bin/sh
# gen-engine-xon.sh -- generate an engine's x-engine.xon from its own facts.
#
#   Usage: sh tools/contract/gen-engine-xon.sh <engine-dir>   (writes to stdout)
#
# WHY THIS LIVES IN x-lang, NOT IN THE ENGINE.  Generating the declaration needs
# the VOCABULARY -- the tag-to-atom map and, for a split tag, the explicit group
# membership -- and that is tools/contract/features.x, which the language owns.
# An engine that generated its own declaration would be choosing the terms it is
# judged by; the same reason the conformance suite and the compliance checks are
# the language's (see the arc's §5.0 and §6.2).  So the generator is x-lang's and
# is RUN AGAINST an engine directory, which is also what lets one vocabulary
# describe x-engine-c and x-engine-rust in the same words.
#
# WHAT IS DERIVED AND WHAT IS ASSERTED -- the split is the point:
#
#   provides    DERIVED.  Every isa.x row maps to its capability group; a group
#               is provided when the engine has rows for it.  Cannot be inflated
#               by opinion.
#   profiles    DERIVED.  A profile holds when every atom it names is provided.
#   digests     DERIVED.  sha256 of isa.x, and of the layout descriptors.
#   guarantees  ASSERTED.  Behaviours cannot be read off a manifest -- they are
#               what the engine does NOT do -- so the engine states them in its
#               own tools/contract/claims.x and they are copied through verbatim.
#               An asserted row is a CLAIM, not a fact: phase 2a's compliance
#               test is what falsifies it, and until that exists these rows are
#               exactly as trustworthy as the engine author.
#   params      NEITHER, and deliberately absent here.  Word size, byte order,
#               os and arch are facts of a BUILD, not of a source tree: the same
#               repo yields a 32-bit and a 64-bit engine whose provides and
#               layout digests are identical.  They are stamped beside the binary
#               at install time (the arc's phase 4).  Emitting a guessed
#               (param word-size 8) here -- inferred from a build triple -- would
#               be the same class of mistake as putting a width in a requires
#               list, which is the one this arc has already made once.
#
# The output is xon: read with the ordinary reader, NEVER evaluated -- the same
# closed-vocabulary family as pin.xon and pin.lock.xon.
set -e

ENGINE="${1:-}"
[ -n "$ENGINE" ] || { echo "gen-engine-xon: usage: gen-engine-xon.sh <engine-dir>" >&2; exit 2; }
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENGINE="$(cd "$ENGINE" && pwd)"

FEAT="$ROOT/tools/contract/features.x"
ISA="$ENGINE/tools/contract/isa.x"
CLAIMS="$ENGINE/tools/contract/claims.x"
for f in "$FEAT" "$ISA"; do
	[ -f "$f" ] || { echo "gen-engine-xon: missing $f" >&2; exit 2; }
done

W="${TMPDIR:-/tmp}/genxon.$$"
mkdir -p "$W"
trap 'rm -rf "$W"' EXIT INT TERM

digest() {
	if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
	elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
	else echo "gen-engine-xon: no sha256sum or shasum on PATH" >&2; exit 2; fi
}

# --- the engine's facts: coordinate -> tag -----------------------------------
awk '
	/^\(def %isa-catalog/ { s="catalog"; next }
	/^\(def %isa-bare/    { s="bare";    next }
	/^\(def %isa-keep/    { s="keep";    next }
	/^\(def %isa-aliases/ { s="";        next }
	/^\(def %isa-values/  { s="";        next }
	/^  \(/ {
		if (s == "") next
		l = $0; sub(/;.*/, "", l); gsub(/[()]/, "", l); $0 = l
		if (s == "catalog" && NF >= 3) print $1 "/" $2, $3
		else if (s != "catalog" && NF >= 2) print $1, $2
	}' "$ISA" > "$W/isa"

# --- the vocabulary: coordinate -> capability group --------------------------
awk '/^\(def %feature-group-rows/{f=1;next} /^\)\)\)/{f=0}
     f && /^  \(/ { l=$0; sub(/;.*/,"",l); gsub(/[()]/,"",l); $0=l
                    for (i=2;i<=NF;i++) print $i, $1 }' "$FEAT" | sort > "$W/exp"
awk '/^\(def %feature-capabilities/{f=1;next} /^\)\)\)/{f=0}
     f && /^  \(/ { l=$0; sub(/;.*/,"",l); gsub(/[()]/,"",l); $0=l
                    if (NF>=2 && $2!="rows" && $2!="-") print $2, $1 }' "$FEAT" | sort -k1,1 > "$W/tagmap"
sort -k2,2 "$W/isa" > "$W/isa-bytag"
join -1 2 -2 1 -o 1.1,2.2 "$W/isa-bytag" "$W/tagmap" | sort > "$W/bytag"
# The explicit rows must be INTERSECTED with what this engine actually has.
# Without that, any group with explicit membership in features.x was reported as
# provided by every engine -- the generator manufacturing a capability claim the
# engine never made.  A minimal engine with zero ffi and zero syscall rows
# declared (provides isa/ffi-call) and (provides isa/syscall), and compliance
# would then have audited a lie the tooling wrote rather than one the engine told.
# Found by generating a declaration for a second engine for the first time.
awk '{print $1}' "$W/isa" | sort -u > "$W/have"
join "$W/have" "$W/exp" > "$W/exp-present"
{ cat "$W/exp-present"; awk 'NR==FNR{o[$1];next} !($1 in o)' "$W/exp-present" "$W/bytag"; } \
	| sort -u > "$W/coord2group"

# The groups the engine has rows for.
awk '{print $2}' "$W/coord2group" | sort -u > "$W/provided"

# Capabilities that are NOT isa rows at all (build flags, protocol promises) are
# not derivable from the manifest.  They are claimed, like guarantees -- listed in
# the engine's claims.x under (provides ...).  A capability that is neither an isa
# group nor claimed is simply absent, which is the safe direction.
if [ -f "$CLAIMS" ]; then
	awk '/^  \(provides /{ l=$0; sub(/;.*/,"",l); gsub(/[()]/,"",l); $0=l
	                       for (i=2;i<=NF;i++) print $i }' "$CLAIMS" >> "$W/provided"
fi
sort -u -o "$W/provided" "$W/provided"

# --- profiles that hold ------------------------------------------------------
# A profile holds when every atom it names is provided; a named profile expands
# to its own atoms first (the chain is closed, checked by check-engine-contract).
awk '/^\(def %feature-profiles/{f=1;next} /^\)\)\)/{f=0}
     f { l=$0; sub(/;.*/,"",l); if (l ~ /^[ \t]*$/) next
         buf = (buf=="" ? l : buf " " l)
         n=gsub(/\(/,"(",buf); m=gsub(/\)/,")",buf)
         if (n>0 && n==m) { gsub(/[()]/,"",buf); $0=buf; $1=$1; print; buf="" } }' "$FEAT" > "$W/profiles"

: > "$W/holds"
while read -r prow; do
	pname=$(echo "$prow" | awk '{print $1}')
	# expand: atoms, plus the atoms of any profile named
	echo "$prow" | cut -d' ' -f2- | tr ' ' '\n' | grep -v '^$' > "$W/atoms.$pname"
	changed=1
	while [ "$changed" = 1 ]; do
		changed=0
		while read -r a; do
			if grep -q "^$a\$" "$W/holds" 2>/dev/null; then
				grep "^$a " "$W/profiles" | cut -d' ' -f2- | tr ' ' '\n' | grep -v '^$' >> "$W/atoms.$pname"
				sort -u -o "$W/atoms.$pname" "$W/atoms.$pname"
			fi
		done < "$W/atoms.$pname"
		changed=0
	done
	# substitute any profile name by its atoms (one level is enough: the chain is linear)
	: > "$W/flat.$pname"
	while read -r a; do
		if grep -q "^$a " "$W/profiles"; then
			if [ -f "$W/flat.$a" ]; then cat "$W/flat.$a" >> "$W/flat.$pname"; fi
		else
			echo "$a" >> "$W/flat.$pname"
		fi
	done < "$W/atoms.$pname"
	sort -u -o "$W/flat.$pname" "$W/flat.$pname"
	missing=""
	while read -r a; do
		grep -q "^$a\$" "$W/provided" || missing="$missing $a"
	done < "$W/flat.$pname"
	if [ -z "$missing" ]; then echo "$pname" >> "$W/holds"; fi
	echo "$pname |$missing" >> "$W/profile-report"
done < "$W/profiles"

# --- emit --------------------------------------------------------------------
name=$(basename "$ENGINE")
isa_d=$(digest "$ISA")
lay=""
for f in obj-layout base-paths base-layout; do
	[ -f "$ENGINE/tools/contract/$f.x" ] && lay="$lay $ENGINE/tools/contract/$f.x"
done
if [ -n "$lay" ]; then
	# One digest over the layout trio, concatenated in a fixed order, because they
	# are pinned as a UNIT: an amalgam binds against all three or none.
	# shellcheck disable=SC2086
	cat $lay > "$W/layout-all"
	layout_d=$(digest "$W/layout-all")
fi

printf '; x-engine.xon -- generated by x-lang tools/contract/gen-engine-xon.sh; do not edit\n'
printf ';\n'
printf '; provides/profile rows are DERIVED from tools/contract/isa.x against x-lang'"'"'s\n'
printf '; feature vocabulary.  guarantee rows are CLAIMS copied from claims.x -- the\n'
printf '; compliance test is what falsifies them.  param rows are absent on purpose:\n'
printf '; word size, byte order and arch are facts of a BUILD, stamped beside the\n'
printf '; binary at install time, not properties of this source tree.\n'
printf '(engine-name "%s")\n' "$name"
printf '(binary "x-bin")\n'
printf '(isa "sha256:%s")\n' "$isa_d"
[ -n "${layout_d:-}" ] && printf '(layout "sha256:%s")\n' "$layout_d"
while read -r p; do printf '(profile %s)\n' "$p"; done < "$W/holds"
while read -r c; do printf '(provides %s)\n' "$c"; done < "$W/provided"
if [ -f "$CLAIMS" ]; then
	awk '/^  \(guarantee /{ l=$0; sub(/;.*/,"",l); gsub(/^[ \t]+|[ \t]+$/,"",l); print l }' "$CLAIMS"
fi
