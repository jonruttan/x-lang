#!/bin/sh
# # x-lang -- the bundle kit
#
# ## tools/bundle-kit/doctest.sh -- run the examples a bundle's documentation carries
#
# @description Extracts every (example "IN" "OUT") from the (doc ...) forms of
#   a bundle's modules into a spec, and runs it on the platform's spec runner.
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2026 Jon Ruttan
# @license MIT No Attribution (MIT-0)
#
#     ., .,
#     {O,O}
#     (   )
#      " "
#
# An example in a (doc ...) form is a claim: evaluating IN prints OUT.  The
# platform holds its own library to that with `make doctest`; this holds a
# bundle to it with the same generator, tools/check/doctest.x, so a library
# that leaves x-lang keeps its examples checked.
#
# The walk boots the dialect bundle.xon declares and arms the bundle's root
# and the roots of what it requires, as the spec harness does, and stops
# there: the generator is x-lang, so the bundle's tests/harness.x, which may
# hand the reader to another language, is left out.  Each module under lib/
# is imported in turn and the examples its import registers are emitted.
#
# An import registers the examples of everything it loads, and a helium
# bundle loads platform modules its dialect did not boot.  Those examples
# are the platform's, which `make doctest` holds there.  So the generator
# runs with X_DOCTEST_OWN set and asks the module registry which entries
# the bundle's modules own; the rest are left out.
#
# Not walked: a listed entry, since importing one sets a session up; a file
# that is one of another module's files, headed with that module's name; and
# constructs.x, which is data.
#
# The spec is written under tests/lib/doctest/, beside the generated harness,
# and is never committed.  A bundle with no example passes and says so.
#
#   BUNDLE=. X=x sh "$(x --share-dir)/tools/bundle-kit/doctest.sh"
set -e

BUNDLE="${BUNDLE:-$(pwd)}"
BUNDLE=$(cd "$BUNDLE" && pwd)
X="${X:-x}"

_dt_die() {
	echo "bundle-kit doctest: $*" >&2
	exit 1
}

[ -f "$BUNDLE/bundle.xon" ] || _dt_die "no bundle.xon in $BUNDLE"
[ -d "$BUNDLE/lib" ] || _dt_die "no lib/ in $BUNDLE"

X_ROOT="$("$X" --share-dir)"
[ -n "$X_ROOT" ] || _dt_die "$X --share-dir answered nothing"
X_BIN="${X_BIN:-$("$X" --engine-path)}"
# The generator beside this script when there is one, so a kit newer than
# the x it runs on brings its own; else the x's.
GEN="$(cd "$(dirname "$0")/.." && pwd)/check/doctest.x"
[ -f "$GEN" ] || GEN="$X_ROOT/tools/check/doctest.x"
[ -f "$GEN" ] || _dt_die "no generator at $GEN"

X_ALLOC_LIMIT_OBJS="${X_ALLOC_LIMIT_OBJS:-300000000}"
case "$X_ALLOC_LIMIT_OBJS" in
	'' | *[!0-9]*) X_ALLOC_LIMIT_OBJS=300000000 ;;
esac

OUT="$BUNDLE/tests/lib/doctest"
BOOT="$BUNDLE/tests/lib/doctest.boot.gen.x"
mkdir -p "$OUT"
rm -f "$OUT"/*.spec.md

# The boot and the roots, with no tail.
# The generator is the platform's own, beside the examples generator, so
# this script may be newer than the x it runs on.
BUNDLE="$BUNDLE" X="$X" GEN_HARNESS_TAIL=0 GEN_HARNESS_OUT="$BOOT" \
	sh "${X_BUNDLE_KIT:-$X_ROOT/tools/bundle-kit}/gen-harness.sh"

_NAME=$(sed -n 's/^(name "\([^"]*\)").*/\1/p' "$BUNDLE/bundle.xon" | head -1)
_ENTRIES=" "
for _e in $(sed -n 's/^(entry \([a-z0-9][a-z0-9-]*\)).*/\1/p' "$BUNDLE/bundle.xon"); do
	_ENTRIES="$_ENTRIES$_NAME/$_e "
done

# lib/crypto/aes.x -> crypto/aes; sorted, so the spec is the same each run.
_MODS=""
for _f in $(find "$BUNDLE/lib" -name '*.x' -not -name 'constructs.x' | sort); do
	_m=${_f#"$BUNDLE/lib/"}
	_m=${_m%.x}
	case "$_ENTRIES" in *" $_m "*) continue ;; esac
	# A file headed with another module's name is one of that module's files.
	_h=$(awk '/^[[:space:]]*$/ { next } /^[[:space:]]*;/ { next } { print; exit }' "$_f")
	case "$_h" in
		"(module "*)
			_h=${_h#"(module "}
			_h=${_h%%[ )]*}
			[ "$_h" = "$_m" ] || continue
			;;
	esac
	_MODS="$_MODS $_m"
done

_TMP=$(mktemp) || exit 1
trap 'rm -f "$_TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Generated to a temporary file and verified before it is used: an import
# that reads the stream eats the rest of the generator, the process exits 0
# and a shrunken spec runs green.  The census trailer is the generator's last
# output, so its absence shows the walk did not finish.
# X_DOCTEST_OWN has the generator keep, in each module's section, only the
# entries the bundle's modules own: what an import loads from the platform
# stays out.
# shellcheck disable=SC2086
{
	printf '(alloc-limit! %s)\n' "$X_ALLOC_LIMIT_OBJS"
	cat "$BOOT" "$GEN"
} | X_DOCTEST_OWN=1 "$X_BIN" $_MODS > "$_TMP"

if ! grep -q '^failed imports: ' "$_TMP"; then
	_dt_die "the module walk was cut short: an import is reading the stream"
fi
if ! grep -q '^failed imports: ()$' "$_TMP"; then
	grep '^failed imports: ' "$_TMP" >&2
	_dt_die "some imports failed; their examples are absent"
fi

# The spec is the bundle's sections alone.  The generator also writes the
# platform's own boot surface, which is `make doctest`'s to run, and the
# census, which is its trailer.  It switches the platform's annotation
# checks on and off around each example (tools/check/annotation-check.x,
# installed by the platform's own doctest); a bundle's run does not install
# them, so those lines are left out.
awk '
	/^## census$/ { exit }
	/^## boot surface$/ { skip = 1; next }
	/^## / { skip = 0 }
	skip { next }
	/^\(AnnotationCheck (on|off)!\)$/ { next }
	{ print }' "$_TMP" > "$OUT/doctests.spec.md"

if ! grep -q '^### ' "$OUT/doctests.spec.md"; then
	rm -f "$OUT/doctests.spec.md"
	echo "bundle-kit doctest: ok (no examples)"
	exit 0
fi

SPEC_RUNNER_DIR="$X_ROOT/tests"
export SPEC_RUNNER_DIR
LANG_LIB="$BOOT"
SPEC_PATH="$OUT"
. "$X_ROOT/tests/spec-runner.sh"
