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
# The platform ships this check; a bundle runs it rather than vendoring a copy.
#
# lang.xon declares the versions:
#
#   (requires-release "vN.N.N")        the x-lang the bundle was built against
#   (requires-lang "NAME" "vN.N.N")    a lang it is written on top of
#
# Anywhere else a version appears -- a README status line, a workflow, a doc --
# is a copy, and a stale copy claims a pairing nobody tested while the bundle
# and its suite stay green.  However many versions the manifest declares, the
# table is read from it rather than written here.
#
# A claim is a version preceded, within 24 characters, by the name it belongs
# to: every version in a bundle has the same shape, so only what it sits beside
# says whether it is x-lang's, a required lang's, the bundle's own or the
# engine's.  Two rules narrow that window:
#
#   A `#` between the name and the version disqualifies the pair, so an issue
#   reference such as `x-lang#527` does not read as a release.
#
#   A name owns a version only if no other name stands between them, so the
#   look-back cannot reach across a neighbouring pair.
#
# A line carrying `release-ref: history` is skipped.
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

# The name matched is the repository's, "x-r5rs" rather than "r5rs": the bare
# form also matches inside the long one and would claim lines it does not own.
# A line writing the unprefixed name therefore goes unchecked.
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

# A workflow may not pin a version literally.  A `ref:` sits on its own line,
# so the name it belongs to is on another one and the per-line proximity test
# above cannot pair them; the shape is forbidden instead.  A ref is derived.
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
