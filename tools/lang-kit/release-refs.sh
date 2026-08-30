#!/bin/sh
# # x-lang -- the lang kit
#
# ## tools/lang-kit/release-refs.sh -- a declared version is named once
#
# @description Asserts that every version a bundle's lang.xon declares is
#   named in exactly one place, and gated everywhere else.
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2026 Jon Ruttan
# @license MIT No Attribution (MIT-0)
#
#     ., .,
#     {O,O}
#     (   )
#      " "
#
# THE PLATFORM SHIPS IT; BUNDLES DO NOT VENDOR IT.  This is the same ruling
# docs/lang-contract.md makes for the spec runner, applied to the rest of a
# bundle's scaffolding: the check is identical in every bundle, so a copy per
# repository buys nothing and costs an N-repo re-vendor for every fix.  It was
# written twice before it moved here, and the second copy needed three fixes
# backported the day it was written.
#
# WHAT IT CHECKS.  lang.xon declares versions:
#
#   (requires-release "vN.N.N")        the x-lang the bundle was built against
#   (requires-lang "NAME" "vN.N.N")    a lang it is written on top of
#
# Everything else naming one -- a README's status line, a workflow, a doc -- is
# a COPY, and a copy nobody checks goes stale at the next release and tells the
# next reader something false.  The bundle keeps working and its suite stays
# green; the only symptom is a claim about a pairing nobody tested.
#
# GENERIC OVER HOWEVER MANY THERE ARE.  x-r5rs declares one, x-r7rs declares
# two, and a lang built on two others would declare three.  The table is read
# from the manifest rather than written here.
#
# WHAT COUNTS AS A CLAIM: a version preceded, within 24 characters, by the name
# it belongs to.  Proximity is the whole mechanism -- every version in a bundle
# is the same shape, and only what it sits beside says whether it is x-lang's,
# a required lang's, the bundle's own, or the engine's.
#
# `x-lang#527` IS AN ISSUE, NOT A RELEASE.  A `#` between the name and the
# version disqualifies the pair; without that this fires on a line where an
# issue reference and an ENGINE version sit together, and neither is a claim.
#
# A NAME OWNS A VERSION ONLY IF NONE STANDS BETWEEN THEM.  A flat look-back
# spans a neighbouring pair: given a line naming one artifact, its version,
# a second artifact and its version, the window from the second reaches the
# first.  CI caught this on the gate's own header, where the prose example is
# written without the markdown padding that had been hiding it elsewhere.
#
# THE ESCAPE HATCH IS EXPLICIT, because history is worth writing down: a line
# carrying `release-ref: history` is skipped, and having to say so is the point.
#
# BUNDLE is the bundle root; the shim that sources this sets it.
set -e

BUNDLE="${BUNDLE:-$(pwd)}"
cd "$BUNDLE"

MANIFEST=lang.xon
[ -f "$MANIFEST" ] || { echo "release-refs: no $MANIFEST in $BUNDLE" >&2; exit 2; }

# --- The table, read from the manifest ------------------------------------
# One "NAME VERSION" per line.  A required lang's repository is x-NAME by the
# convention every published bundle follows, and that prefixed form is what
# prose and workflows actually write.
decls=$(
	sed -n 's/^(requires-release "\(.*\)")$/x-lang \1/p' "$MANIFEST"
	sed -n 's/^(requires-lang "\([^"]*\)" "\(.*\)")$/x-\1 \2/p' "$MANIFEST"
)
[ -n "$decls" ] || {
	echo "release-refs: $MANIFEST declares no versions to check" >&2
	exit 2
}

files=$(git ls-files | grep -v "^$MANIFEST$" || true)
[ -n "$files" ] || { echo "release-refs: no tracked files" >&2; exit 2; }

# THE NAME IS THE REPOSITORY'S, "x-r5rs" and not "r5rs".  The bare form would
# also match inside the long one and claim lines it does not own; the cost is
# that a line writing the unprefixed name is not checked, which is the right
# way round -- a missed check is a gap, a wrong one is a false alarm that gets
# the gate switched off.
scan() {
	name=$1
	want=$2
	# -I skips binaries (a bundle may ship standards PDFs).
	grep -In "$name" -- $files 2>/dev/null \
		| grep -v 'release-ref: history' \
		| awk -F: -v name="$name" -v want="$want" '
		{
			file = $1; lineno = $2
			# Rebuild the text: the content may itself contain colons.
			text = $0
			sub(/^[^:]*:[^:]*:/, "", text)
			rest = text; off = 0; prev = 0
			while (match(rest, /v[0-9]+\.[0-9]+\.[0-9]+/)) {
				ver   = substr(rest, RSTART, RLENGTH)
				start = off + RSTART
				# The window starts after the PREVIOUS version, so one
				# pair can never span another.
				from = prev + 1
				if (start - 24 > from) from = start - 24
				win = substr(text, from, start - from)
				at  = index(win, name)
				if (at > 0 && index(substr(win, at), "#") == 0 && ver != want)
					printf "%s:%s names %s %s, lang.xon declares %s\n",
						file, lineno, name, ver, want
				prev = start + RLENGTH - 1
				off  = off + RSTART + RLENGTH - 1
				rest = substr(rest, RSTART + RLENGTH)
			}
		}'
}

# A WORKFLOW NEVER PINS A VERSION LITERALLY, and this covers what the scan
# structurally cannot.  `ref:` sits on its own line, so the name it belongs to
# is on a DIFFERENT one and no per-line proximity test can pair them.  Rather
# than teach the scan about YAML, forbid the shape: a ref is derived, or it is
# a bug.
refs=$(grep -n "^[[:space:]]*ref:[[:space:]]*v[0-9]" .github/workflows/*.yml 2>/dev/null || true)
if [ -n "$refs" ]; then
	echo "$refs" | sed 's/^/release-refs: literal ref in a workflow: /' >&2
	echo "" >&2
	echo "  A workflow reads the version from $MANIFEST -- see the prepare job." >&2
	exit 1
fi

bad=$(
	echo "$decls" | while read -r name want; do
		[ -n "$name" ] || continue
		scan "$name" "$want"
	done | sort -u
)

if [ -n "$bad" ]; then
	echo "$bad" | sed 's/^/release-refs: /' >&2
	echo "" >&2
	echo "  These are one fact each.  Update $MANIFEST and the copies together," >&2
	echo "  or mark a deliberate historical mention with 'release-ref: history'." >&2
	exit 1
fi

summary=$(echo "$decls" | sed 's/$/,/' | tr '\n' ' ' | sed 's/, *$//')
echo "release-refs: ok -- $summary, and nothing claims otherwise"
