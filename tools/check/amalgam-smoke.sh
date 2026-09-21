#!/bin/sh
# amalgam-smoke.sh -- boot every generated amalgam entry in batch mode and
# pin a smoke expression through it.  A generator
# slip (wrapped form, wrong order, missing file) dies here, not in an
# installed tree.  Same self-limit as the other harnesses.
#
# App amalgams are generated but not smoked, and there are none to generate
# at present.  The exemption is structural: an app entry may fork a server or
# claim a terminal, so booting one headless belongs to another layer.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
X_BIN="${X_BIN:-$PROJECT_DIR/x-bin}"
cd "$PROJECT_DIR" || exit 1

X_ALLOC_LIMIT_OBJS="${X_ALLOC_LIMIT_OBJS:-300000000}"
case "$X_ALLOC_LIMIT_OBJS" in
  ''|*[!0-9]*) X_ALLOC_LIMIT_OBJS=300000000 ;;
esac

STATUS=0

smoke() { # entry expected-output extra-form
	_out=$({
		printf '(alloc-limit! %s)\n' "$X_ALLOC_LIMIT_OBJS"
		cat "build/boot/$1.x"
		printf '(display (+ 1 2))(newline)(import x/type/set)(display ((Set of 1 2 2 3) length))(newline)%s' "$3"
	} | "$X_BIN" "--batch" 2>&1)
	_rc=$?
	if [ "$_out" = "$2" ]; then
		echo "amalgam-smoke: $1 ok"
	else
		STATUS=1
		# The exit status separates the failure modes: >128 = died by
		# signal (128+N); 0 with short output = the engine saw a
		# premature EOF and stopped cleanly mid-stream (empty output =
		# stdout died in the pipe buffer, so "expected vs actual" alone
		# cannot tell these apart).
		echo "amalgam-smoke: $1 FAIL (exit status $_rc)" >&2
		printf 'expected:\n%s\nactual:\n%s\n' "$2" "$_out" >&2
	fi
}

CORE_EXPECT='3
3'
TOWER_EXPECT='3
3
1/3'

smoke x "$CORE_EXPECT" ''
smoke he "$CORE_EXPECT" ''
smoke x-core "$CORE_EXPECT" ''
smoke helium "$CORE_EXPECT" ''
smoke xe "$TOWER_EXPECT" '(display (/ 1 3))(newline)'
smoke rn "$TOWER_EXPECT" '(display (/ 1 3))(newline)'
smoke x-base "$TOWER_EXPECT" '(display (/ 1 3))(newline)'
smoke xenon "$TOWER_EXPECT" '(display (/ 1 3))(newline)'
smoke radon "$TOWER_EXPECT" '(display (/ 1 3))(newline)'

# A scoped module's header reads every form after it into the module, up to
# the end marker the generator writes, so nothing may be spliced inside a
# scoped file.  A file it includes once or imports is spliced ahead of it
# instead; a plain include inside it is refused.  A throwaway tree holds the
# generator, an empty x-core.x (it reads the boot entry's pre-seeded names),
# a scoped file that includes another once, and one that includes another
# plainly.  A selective import, (import NAME sym ...), loads and binds: the
# module is spliced as for a bare import, ahead of a scoped importer or in
# place in an unscoped one, and the line itself is kept, since binding the
# names is its other half and the load is a no-op once the splice has marked
# the module loaded.
nest_tree=$(mktemp -d "${TMPDIR:-/tmp}/amalgam-nest.XXXXXX") || exit 1
mkdir -p "$nest_tree/tools/release" "$nest_tree/lib/nest"
cp tools/release/amalgamate.sh "$nest_tree/tools/release/"
: > "$nest_tree/lib/x-core.x"
printf '(include-once "lib/nest/outer.x")\n' > "$nest_tree/lib/nest-entry.x"
printf '; outer.x -- scoped, and it includes another file once.\n(module nest/outer)\n(include-once "lib/nest/inner.x")\n' > "$nest_tree/lib/nest/outer.x"
printf '(def nest-inner 1)\n' > "$nest_tree/lib/nest/inner.x"
printf '(include-once "lib/nest/plain.x")\n' > "$nest_tree/lib/plain-entry.x"
printf '; plain.x -- scoped, and it includes another file plainly.\n(module nest/plain)\n(include "lib/nest/inner.x")\n' > "$nest_tree/lib/nest/plain.x"
_hoist_out=$(sh "$nest_tree/tools/release/amalgamate.sh" lib/nest-entry.x 2>&1)
_hoist_rc=$?
_plain_err=$(sh "$nest_tree/tools/release/amalgamate.sh" lib/plain-entry.x 2>&1 >/dev/null)
_plain_rc=$?
printf '(module nest/sel-inner)\n(def sel-name 1)\n(provide nest/sel-inner sel-name)\n' > "$nest_tree/lib/nest/sel-inner.x"
printf '; sel-outer.x -- scoped, and it imports a name.\n(module nest/sel-outer)\n(import nest/sel-inner sel-name)\n' > "$nest_tree/lib/nest/sel-outer.x"
printf '(include-once "lib/nest/sel-outer.x")\n' > "$nest_tree/lib/sel-entry.x"
printf '(import nest/sel-inner (sel-name other))\n(def sel-after 1)\n' > "$nest_tree/lib/sel2-entry.x"
_sel_out=$(sh "$nest_tree/tools/release/amalgamate.sh" lib/sel-entry.x 2>&1)
_sel_rc=$?
_sel2_out=$(sh "$nest_tree/tools/release/amalgamate.sh" lib/sel2-entry.x 2>&1)
_sel2_rc=$?
rm -rf "$nest_tree"
_inner_at=$(printf '%s\n' "$_hoist_out" | grep -n '^; ---- begin lib/nest/inner.x ----' | cut -d: -f1)
_outer_at=$(printf '%s\n' "$_hoist_out" | grep -n '^; ---- begin lib/nest/outer.x ----' | cut -d: -f1)
if [ "$_hoist_rc" = 0 ] && [ -n "$_inner_at" ] && [ -n "$_outer_at" ] && [ "$_inner_at" -lt "$_outer_at" ] \
	&& printf '%s\n' "$_hoist_out" | grep -q '^; (include-once lib/nest/inner.x) -- inlined above$'; then
	echo "amalgam-smoke: a file a scoped module includes once is spliced ahead of it ok"
else
	STATUS=1
	echo "amalgam-smoke: FAIL -- a file a scoped module includes once was not spliced ahead of it" >&2
	printf '%s\n' "$_hoist_out" >&2
fi
case "$_plain_rc:$_plain_err" in
	0:*)
		STATUS=1
		echo "amalgam-smoke: FAIL -- a plain include inside a scoped module was accepted" >&2 ;;
	*"lib/nest/plain.x includes lib/nest/inner.x, which would splice it inside the scoped module"*)
		echo "amalgam-smoke: a plain include inside a scoped module is refused ok" ;;
	*)
		STATUS=1
		echo "amalgam-smoke: FAIL -- a plain include inside a scoped module failed for another reason: $_plain_err" >&2 ;;
esac

# A scoped importer: the module ahead of it, marked loaded, the line kept.
_sin_at=$(printf '%s\n' "$_sel_out" | grep -n '^; ---- begin lib/nest/sel-inner.x ----' | cut -d: -f1)
_sout_at=$(printf '%s\n' "$_sel_out" | grep -n '^; ---- begin lib/nest/sel-outer.x ----' | cut -d: -f1)
_sline_at=$(printf '%s\n' "$_sel_out" | grep -n '^(import nest/sel-inner sel-name)$' | cut -d: -f1)
if [ "$_sel_rc" = 0 ] && [ -n "$_sin_at" ] && [ -n "$_sout_at" ] && [ -n "$_sline_at" ] \
	&& [ "$_sin_at" -lt "$_sout_at" ] && [ "$_sout_at" -lt "$_sline_at" ] \
	&& printf '%s\n' "$_sel_out" | grep -q '^(%module-loaded! (lit nest/sel-inner))$'; then
	echo "amalgam-smoke: a selective import in a scoped module splices ahead of it and keeps its line ok"
else
	STATUS=1
	echo "amalgam-smoke: FAIL -- a selective import in a scoped module was not spliced ahead with its line kept" >&2
	printf '%s\n' "$_sel_out" >&2
fi
# An unscoped importer: the module in place, then the line, alias and all.
_s2end_at=$(printf '%s\n' "$_sel2_out" | grep -n '^; ---- end lib/nest/sel-inner.x ----' | cut -d: -f1)
_s2line_at=$(printf '%s\n' "$_sel2_out" | grep -n '^(import nest/sel-inner (sel-name other))$' | cut -d: -f1)
if [ "$_sel2_rc" = 0 ] && [ -n "$_s2end_at" ] && [ -n "$_s2line_at" ] && [ "$_s2end_at" -lt "$_s2line_at" ] \
	&& printf '%s\n' "$_sel2_out" | grep -q '^(%module-loaded! (lit nest/sel-inner))$'; then
	echo "amalgam-smoke: a selective import at the top of an unscoped file splices in place and keeps its line ok"
else
	STATUS=1
	echo "amalgam-smoke: FAIL -- a selective import in an unscoped file was not spliced in place with its line kept" >&2
	printf '%s\n' "$_sel2_out" >&2
fi

exit "$STATUS"
