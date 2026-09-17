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
smoke xe "$TOWER_EXPECT" '(display (/ 1 3))(newline)'
smoke rn "$TOWER_EXPECT" '(display (/ 1 3))(newline)'
smoke x-base "$TOWER_EXPECT" '(display (/ 1 3))(newline)'

# A scoped module's header reads every form after it into the module, up to
# the end marker the generator writes, so a file spliced inside a scoped
# module would load into that module instead of the root.  The generator
# refuses that.  A throwaway tree holds the generator, an empty x-core.x (it
# reads the boot entry's pre-seeded names) and a scoped file that includes
# another; the generator must fail and say which file would be spliced where.
nest_tree=$(mktemp -d "${TMPDIR:-/tmp}/amalgam-nest.XXXXXX") || exit 1
mkdir -p "$nest_tree/tools/release" "$nest_tree/lib/nest"
cp tools/release/amalgamate.sh "$nest_tree/tools/release/"
: > "$nest_tree/lib/x-core.x"
printf '(include-once "lib/nest/outer.x")\n' > "$nest_tree/lib/nest-entry.x"
printf '; outer.x -- scoped, and it includes another file.\n(module nest/outer)\n(include-once "lib/nest/inner.x")\n' > "$nest_tree/lib/nest/outer.x"
printf '(def nest-inner 1)\n' > "$nest_tree/lib/nest/inner.x"
_nest_err=$(sh "$nest_tree/tools/release/amalgamate.sh" lib/nest-entry.x 2>&1 >/dev/null)
_nest_rc=$?
rm -rf "$nest_tree"
case "$_nest_rc:$_nest_err" in
	0:*)
		STATUS=1
		echo "amalgam-smoke: FAIL -- a file spliced inside a scoped module was accepted" >&2 ;;
	*"lib/nest/outer.x would splice lib/nest/inner.x inside the scoped module"*)
		echo "amalgam-smoke: a splice inside a scoped module is refused ok" ;;
	*)
		STATUS=1
		echo "amalgam-smoke: FAIL -- a splice inside a scoped module failed for another reason: $_nest_err" >&2 ;;
esac

exit "$STATUS"
