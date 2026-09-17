#!/bin/sh
# lang-kit-harness.sh -- the lang kit's harness generator boots what lang.xon
# declares.
#
# tools/lang-kit/gen-harness.sh writes a bundle's spec harness.  Held here:
#
#   - the dialect's body is found through its entry, loaded from its amalgam,
#     the install layout ahead of the checkout's;
#   - required langs are found by declared name, X_LANG_DIR ahead of the
#     bundle's siblings, and armed deepest first, each once;
#   - the bundle's own root, %lang-root and %lang-lead follow, then its
#     tests/harness.x;
#   - each way the inputs can be wrong stops with a message naming it;
#   - in this tree, every dialect's body has an amalgam in build/boot/.
#
# The fixtures are directories and a stand-in for x that answers --share-dir,
# so nothing boots and the check can sit in gates-fast.  Every capture carries
# `|| true`: set -e does not spare a command substitution.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_DIR" || exit 1
GEN="$PROJECT_DIR/tools/lang-kit/gen-harness.sh"

TMP=$(mktemp -d)
TMP=$(cd "$TMP" && pwd)
trap 'rm -rf "$TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fails=0

# want NAME EXPECTED ACTUAL
want() {
	if [ "$2" = "$3" ]; then
		printf '  %s: ok\n' "$1"
	else
		printf 'lang-kit-harness: %s -- expected [%s], got [%s]\n' "$1" "$2" "$3" >&2
		fails=$((fails + 1))
	fi
}

# refuses NAME TEXT OUTPUT -- the generator failed and said TEXT
refuses() {
	case "$3" in
		"FAILED:"*"$2"*) printf '  %s: ok\n' "$1" ;;
		*)
			printf 'lang-kit-harness: %s -- expected a refusal naming [%s], got [%s]\n' "$1" "$2" "$3" >&2
			fails=$((fails + 1))
			;;
	esac
}

# The x the generator asks for its root.
printf '#!/bin/sh\n[ "$1" = --share-dir ] && echo "$FAKE_X_ROOT"\n' > "$TMP/x"
chmod +x "$TMP/x"

# A platform tree: two entries naming bodies, one naming none, and amalgams in
# the checkout layout.
ROOT="$TMP/root"
mkdir -p "$ROOT/lib" "$ROOT/build/boot"
printf '(include "lib/x/boot/helium.x")\n(repl)\n' > "$ROOT/lib/he.x"
printf '(include "lib/x/boot/xenon.x")\n(repl)\n' > "$ROOT/lib/xe.x"
printf '(include "lib/x/boot/radon.x")\n(repl)\n' > "$ROOT/lib/rn.x"
printf '(repl)\n' > "$ROOT/lib/bare.x"
: > "$ROOT/build/boot/helium.x"
: > "$ROOT/build/boot/xenon.x"

# bundle DIR NAME DIALECT [REQUIRED...] -- a bundle with a harness tail
bundle() {
	_d="$1" _n="$2" _dl="$3"
	shift 3
	mkdir -p "$_d/tests"
	{
		printf '(lang "%s")\n' "$_n"
		[ -z "$_dl" ] || printf '(dialect %s)\n' "$_dl"
		for _r in "$@"; do printf '(requires-lang "%s")\n' "$_r"; done
	} > "$_d/lang.xon"
	printf '(import %s/base)\n' "$_n" > "$_d/tests/harness.x"
}

# gen BUNDLE [ROOT] -- the generated forms, or FAILED: and the message
gen() {
	if _out=$(FAKE_X_ROOT="${2:-$ROOT}" BUNDLE="$1" X="$TMP/x" sh "$GEN" 2>&1); then
		grep -v '^;' "$1/tests/lib/harness.gen.x"
	else
		printf 'FAILED: %s' "$_out"
	fi
}

L="$TMP/langs"
bundle "$L/core" core he
bundle "$L/mid" mid he core
# the version rides on the row and is not compared
printf '(lang "app")\n(requires-lang "mid" "v9.9.9")\n(requires-lang "core")\n' > "$L/app.xon"
bundle "$L/app" app ""
mv "$L/app.xon" "$L/app/lang.xon"

got=$(gen "$L/app" || true)
want "helium by default, required langs deepest first and once, then the bundle" \
"(def %install-root \"$ROOT\")
(include \"$ROOT/build/boot/helium.x\")
(import-path! \"$L/core\")
(import-path! \"$L/mid\")
(import-path! \"$L/app\")
(def %lang-root \"$L/app\")
(def %lang-lead \"app\")
(import app/base)" "$got"

# Sourced, as a bundle's shim runs it.
rm -f "$L/core/tests/lib/harness.gen.x"
got=$( (FAKE_X_ROOT="$ROOT" BUNDLE="$L/core" X="$TMP/x"; export FAKE_X_ROOT BUNDLE X; . "$GEN") 2>&1 && grep -c '' "$L/core/tests/lib/harness.gen.x" || true)
want "runs sourced from a shim" "9" "$got"

bundle "$TMP/xe/lisp" lisp xe
got=$(gen "$TMP/xe/lisp" | sed -n 2p || true)
want "a declared dialect boots its own body" "(include \"$ROOT/build/boot/xenon.x\")" "$got"

cp -R "$ROOT" "$TMP/installed"
mkdir -p "$TMP/installed/boot"
: > "$TMP/installed/boot/helium.x"
got=$(gen "$L/core" "$TMP/installed" | sed -n 2p || true)
want "the install layout ahead of the checkout's" "(include \"$TMP/installed/boot/helium.x\")" "$got"

bundle "$TMP/elsewhere/core" core he
got=$(X_LANG_DIR="$TMP/elsewhere" gen "$L/mid" | sed -n 3p || true)
want "X_LANG_DIR ahead of the siblings" "(import-path! \"$TMP/elsewhere/core\")" "$got"

bundle "$TMP/notail/t" t he
rm "$TMP/notail/t/tests/harness.x"
refuses "no tests/harness.x" "tests/harness.x" "$(gen "$TMP/notail/t" || true)"

bundle "$TMP/nodialect/t" t zz
refuses "a dialect with no entry" "dialect 'zz', which has no entry" "$(gen "$TMP/nodialect/t" || true)"

bundle "$TMP/nobody/t" t bare
refuses "an entry that includes no body" "includes no body" "$(gen "$TMP/nobody/t" || true)"

bundle "$TMP/noamalgam/t" t rn
refuses "a body with no amalgam" "run 'make boot'" "$(gen "$TMP/noamalgam/t" || true)"

bundle "$TMP/cycle/a" a he b
bundle "$TMP/cycle/b" b he a
refuses "a cycle" "in a cycle: a b a" "$(gen "$TMP/cycle/a" || true)"

bundle "$TMP/twice/one" dup he
bundle "$TMP/twice/two" dup he
bundle "$TMP/twice/t" t he dup
refuses "two bundles claiming one name" "two bundles both call themselves 'dup'" "$(gen "$TMP/twice/t" || true)"

bundle "$TMP/missing/t" t he nowhere
refuses "a required lang that is not there" "lang 'nowhere' is required but was not found" "$(gen "$TMP/missing/t" || true)"

# This tree: each dialect's body has the amalgam `make boot` writes.
for _dl in he xe rn; do
	bundle "$TMP/tree/$_dl" "t$_dl" "$_dl"
	_inc=$(gen "$TMP/tree/$_dl" "$PROJECT_DIR" | sed -n 's/^(include "\(.*\)")$/\1/p' || true)
	if [ -n "$_inc" ] && [ -f "$_inc" ]; then
		printf '  %s boots a built body: ok\n' "$_dl"
	else
		printf 'lang-kit-harness: dialect %s -- no built body amalgam (%s); does make boot write it?\n' "$_dl" "${_inc:-none}" >&2
		fails=$((fails + 1))
	fi
done

if [ "$fails" -gt 0 ]; then
	echo "lang-kit-harness: $fails failed" >&2
	exit 1
fi
echo "lang-kit-harness: ok"
