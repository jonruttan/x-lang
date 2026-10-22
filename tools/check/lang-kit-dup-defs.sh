#!/bin/sh
# lang-kit-dup-defs.sh -- the lang kit's dup-defs reads a bundle's sources.
#
# tools/lang-kit/dup-defs.sh, run over a fixture bundle, one case each:
#
#   - two files defining one name differently are red, and both are named;
#   - the same definition, text for text, in two files is green;
#   - two fetches of one catalogue entry are green, whichever quote spelling,
#     and two fetches of different entries are red;
#   - two scoped modules sharing a private name are green, and one scoped
#     module defining a private name two ways is red, beside another def
#     on its line or not;
#   - two scripts under tools/ sharing a name are green, and a script
#     redefining a module's name is red;
#   - the generated harness, tests/lib/, is not read, nor a checkout in a
#     dot-directory (.x-lang, as bundle CI makes one);
#   - the spec gate stops on a clash before the suite runs.
#
# No x boots.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_DIR" || exit 1
KIT="$PROJECT_DIR/tools/lang-kit"

TMP=$(mktemp -d)
TMP=$(cd "$TMP" && pwd)
trap 'rm -rf "$TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fails=0

# A fresh bundle holding FILE CONTENT pairs, then the scan's status and output.
_case() {
	rm -rf "$TMP/b"
	mkdir -p "$TMP/b"
	while [ $# -gt 1 ]; do
		mkdir -p "$TMP/b/$(dirname "$1")"
		printf '%s\n' "$2" > "$TMP/b/$1"
		shift 2
	done
	out=$(BUNDLE="$TMP/b" sh "$KIT/dup-defs.sh" 2>&1) && st=0 || st=$?
}

_green() {
	if [ "$st" = 0 ]; then printf '  %s: ok\n' "$1"
	else printf 'lang-kit-dup-defs: %s read as red:\n%s\n' "$1" "$out" >&2; fails=$((fails + 1)); fi
}

# _red WHAT TEXT...: red, and the output holds every TEXT.
_red() {
	_what=$1; shift
	if [ "$st" = 0 ]; then
		printf 'lang-kit-dup-defs: %s read as green\n' "$_what" >&2; fails=$((fails + 1)); return
	fi
	for _t in "$@"; do
		case "$out" in
			*"$_t"*) ;;
			*) printf 'lang-kit-dup-defs: %s is red without naming %s:\n%s\n' "$_what" "$_t" "$out" >&2
			   fails=$((fails + 1)); return ;;
		esac
	done
	printf '  %s: ok\n' "$_what"
}

_case a/one.x '(def %v (fn (_ t) (vec-ref t 1)))' a/two.x '(def %v 0)'
_red "two meanings of one name" "%v" "a/one.x" "a/two.x"

_case a/one.x '(def %min (fn (_ a b) (if (< a b) a b)))' a/two.x '(def %min (fn (_ a b) (if (< a b) a b)))'
_green "one definition written twice"

_case a/one.x "(def %rd (prim-ref 'io 'read))" a/two.x '(def %rd (prim-ref (lit io) (lit read)))'
_green "one catalogue entry fetched twice"

_case a/one.x "(def %rd (prim-ref 'io 'read))" a/two.x "(def %rd (prim-ref 'io 'write))"
_red "two catalogue entries under one name" "%rd" "DIFFERENT catalogue entries"

_case a/one.x '(module a/one)
(def %step 1)
(provide a/one)' a/two.x '(module a/two)
(def %step 2)
(provide a/two)'
_green "one private name in two scoped modules"

_case a/one.x '(module a/one)
(def %sent 1) (def %asked 4)
(def %remotes 6) (def %asked 7)
(provide a/one)'
_red "one private name defined twice in a scoped module" "%asked" "within a/one.x"

_case a/one.x '(module a/one)
(def %asked 4)
(def %asked 4)
(provide a/one)'
_green "one private definition written twice in a scoped module"

_case a/one.x '(def %n 1)' tools/p.x '(def %say 1)' tools/q.x '(def %say 2)'
_green "one name in two scripts"

_case a/one.x '(def %n 1)' tools/p.x '(def %n 2)'
_red "a script redefining a module's name" "%n" "a/one.x" "tools/p.x"

_case a/one.x '(def %n 1)' tests/lib/harness.gen.x '(def %n 2)'
_green "the generated harness left out"

# CI checks the platform out inside the bundle; its files are not the bundle's.
_case a/one.x '(def %n 1)' .x-lang/lib/a.x '(def %n 2)' .x-lang/lib/b.x '(def %m 1)' .x-r5rs/r/c.x '(def %m 2)'
_green "a checkout in a dot-directory left out"

# The gate: a clash stops it, and the suite never starts.
_case a/one.x '(def %v 1)' a/two.x '(def %v 2)'
mkdir -p "$TMP/b/tests/contract"
printf 'touch "%s/ran"\n' "$TMP" > "$TMP/b/tests/spec-runner.sh"
printf '# none\n' > "$TMP/b/tests/contract/known-failures.txt"
out=$(BUNDLE="$TMP/b" KIT="$KIT" sh "$KIT/spec-gate.sh" 2>&1) && st=0 || st=$?
if [ -f "$TMP/ran" ]; then
	printf 'lang-kit-dup-defs: the spec gate ran the suite past a clash\n' >&2; fails=$((fails + 1))
else
	_red "the spec gate on a clash" "%v" "two meanings"
fi

[ "$fails" = 0 ] || { echo "lang-kit-dup-defs: $fails failed" >&2; exit 1; }
echo "lang-kit-dup-defs: one global name, one meaning, across a bundle's files."
