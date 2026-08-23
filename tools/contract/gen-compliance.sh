#!/bin/sh
# gen-compliance.sh -- compute the DATA an engine's compliance run needs.
#
#   Usage: sh tools/contract/gen-compliance.sh <engine-dir> <out-dir>
#
# THIS SCRIPT EMITS DATA, NEVER CODE.  Its first version built x-lang out of a
# stack of printf lines -- doubled %% signs, no highlighting, nothing runnable on
# its own, and the only x-lang in the tree that could not be linted was the x-lang
# that tests the engine.  The checks now live in tools/contract/compliance/*.spec.md
# as ordinary spec files, and all this produces is one `(def %expect-... (lit ...))`
# per capability group, which those files read.
#
# WHAT COMPLIANCE ASKS, and why it is not the conformance suite: conformance asks
# "is this a correct x-lang evaluator" and is written against the language;
# compliance asks "does this engine do what IT CLAIMS", and its subject is the
# engine's own x-engine.xon.  check-engine-contract compares provides against
# requires as TEXT, so an engine that over-declares passes it, is chosen by the
# resolver, and fails in the field -- loudly for a capability, SILENTLY for a
# guarantee.  Under-declaring is harmless, so every check is one-directional.
#
# Output, into <out-dir>:
#   expect-<group>.x   the coordinates and bare names that group declares
#   plan               one line per check to run: "<spec-file> [data-file]"
set -e

ENGINE="${1:-}"; OUT="${2:-}"
[ -n "$ENGINE" ] && [ -n "$OUT" ] || {
	echo "gen-compliance: usage: gen-compliance.sh <engine-dir> <out-dir>" >&2; exit 2; }
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENGINE="$(cd "$ENGINE" && pwd)"
mkdir -p "$OUT"

FEAT="$ROOT/tools/contract/features.x"
SPECS="$ROOT/tools/contract/compliance"
XON="$ENGINE/x-engine.xon"
ISA="$ENGINE/tools/contract/isa.x"
for f in "$FEAT" "$XON" "$ISA"; do
	[ -f "$f" ] || { echo "gen-compliance: missing $f" >&2; exit 2; }
done

W="$OUT/.work"; mkdir -p "$W"

# --- coordinate -> capability group, as the contract gate computes it --------
awk '/^\(def %feature-group-rows/{f=1;next} /^\)\)\)/{f=0}
     f && /^  \(/ { l=$0; sub(/;.*/,"",l); gsub(/[()]/,"",l); $0=l
                    for (i=2;i<=NF;i++) print $i, $1 }' "$FEAT" | sort > "$W/exp"
awk '/^\(def %feature-capabilities/{f=1;next} /^\)\)\)/{f=0}
     f && /^  \(/ { l=$0; sub(/;.*/,"",l); gsub(/[()]/,"",l); $0=l
                    if (NF>=2 && $2!="rows" && $2!="-") print $2, $1 }' "$FEAT" | sort -k1,1 > "$W/tagmap"
# Catalog rows carry an ns/method split; bare and keep rows do not, and are probed
# by resolving the symbol instead of by walking the catalog.
# VALUES probe exactly like bare names -- evaluate the symbol and see whether it
# resolves -- so they enter as `bare`.  They were skipped, which is why the rows
# meta/identity is made of had no compliance probe: declared, required, and
# never falsified.  Their isa.x entries carry no tag column, hence the NF>=1.
awk '/^\(def %isa-catalog/{s="cat";next} /^\(def %isa-bare/{s="bare";next}
     /^\(def %isa-keep/{s="bare";next} /^\(def %isa-aliases/{s="";next}
     /^\(def %isa-values/{s="values";next} /^\)\)\)/{s=s}
     /^  \(/ { if (s=="") next
               l=$0; sub(/;.*/,"",l); gsub(/[()]/,"",l); $0=l
               if (s=="cat" && NF>=3) print $1 "/" $2, $3, "coord"
               else if (s=="values" && NF>=1) print $1, "value", "bare"
               else if (s=="bare" && NF>=2) print $1, $2, "bare" }' "$ISA" | sort > "$W/isa"

sort -k2,2 "$W/isa" > "$W/isa-bytag"
join -1 2 -2 1 -o 1.1,2.2,1.3 "$W/isa-bytag" "$W/tagmap" | sort > "$W/bytag"
# explicit membership wins over the tag mapping (the `ffi` tag splits three ways)
awk 'NR==FNR{g[$1]=$2;next} {print $1, ($1 in g ? g[$1] : $2), $3}' "$W/exp" "$W/bytag" \
	| sort -u > "$W/c2g"
# rows named explicitly but whose tag no capability claims are absent from bytag
# FILENAME==ARGV[1] for the same reason as in gen-engine-xon.sh: c2g is empty for
# an engine that declares no isa rows at all, and NR==FNR inverts on an empty
# first file rather than failing.
awk 'FILENAME==ARGV[1]{seen[$1];next} !($1 in seen) { print $1, $2 }' "$W/c2g" "$W/exp" > "$W/exp-only"
while read -r coord grp; do
	kind=$(awk -v c="$coord" '$1==c {print $3}' "$W/isa" | head -1)
	if [ -n "$kind" ]; then echo "$coord $grp $kind" >> "$W/c2g"; fi
done < "$W/exp-only"
sort -u -o "$W/c2g" "$W/c2g"

# --- one data file per declared group ----------------------------------------
: > "$OUT/plan"
awk '/^\(provides /{ l=$0; gsub(/[()]/,"",l); $0=l; print $2 }' "$XON" | sort -u \
	| while read -r grp; do
	coords=$(awk -v g="$grp" '$2==g && $3=="coord" {print $1}' "$W/c2g" | sort)
	bares=$(awk -v g="$grp" '$2==g && $3=="bare" {print $1}' "$W/c2g" | sort)
	[ -n "$coords$bares" ] || continue
	safe=$(printf '%s' "$grp" | tr '/' '-')
	{
		printf '; expect-%s.x -- generated DATA for the compliance run; do not edit.\n' "$safe"
		printf '; The coordinates and bare names that (provides %s) claims.\n' "$grp"
		# read, never `for ... in $var`: an unquoted expansion is GLOBBED as well as
		# word-split, and one of the bare primitives is literally `*` -- it expanded
		# to every file in the working directory and put CHANGELOG.md into the
		# engine's capability list.  Found by the check actually running.
		printf '(def %%expect-coords (lit (\n'
		printf '%s\n' "$coords" | while IFS= read -r c; do
			[ -n "$c" ] || continue
			printf '  (%s %s)\n' "${c%%/*}" "${c#*/}"
		done
		printf ')))\n(def %%expect-bare (lit (\n'
		printf '%s\n' "$bares" | while IFS= read -r b; do
			[ -n "$b" ] || continue
			printf '  %s\n' "$b"
		done
		printf ')))\n'
	} > "$OUT/expect-$safe.x"
	printf '%s/provides.spec.md %s/expect-%s.x %s\n' "$SPECS" "$OUT" "$safe" "$grp" >> "$OUT/plan"
done

# --- the build's declared params, where an experiment exists ------------------
# x-engine.xon carries no param rows -- they are facts of a BINARY -- so these
# come from the build declaration beside it.  Only a param with a falsifying
# experiment gets a check; the rest are recorded facts, not claims to audit.
if [ -f "$ENGINE/x-engine-build.xon" ]; then
	if grep -qE '^\(param word-size [48]\)' "$ENGINE/x-engine-build.xon"; then
		f="$SPECS/param-word-size.spec.md"
		if [ -f "$f" ]; then printf '%s - param word-size\n' "$f" >> "$OUT/plan"; fi
	fi
fi

# --- one entry per declared guarantee that has an experiment ------------------
# A guarantee with no spec file is NOT silently skipped: the driver reports it.
awk '/^\(guarantee /{ l=$0; gsub(/[()]/,"",l); $0=l; print $2 }' "$XON" | sort -u \
	| while read -r g; do
	safe=$(printf '%s' "$g" | tr '/' '-')
	f="$SPECS/guarantee-$safe.spec.md"
	# `if`, not `[ ... ] && ...`: a guarantee with no spec file would make the
	# test the loop's last command and take the whole script down under set -e.
	if [ -f "$f" ]; then printf '%s - guarantee %s\n' "$f" "$g" >> "$OUT/plan"; fi
done

rm -rf "$W"
echo "gen-compliance: $(wc -l < "$OUT/plan" | tr -d ' ') checks planned in $OUT/plan"
