#!/bin/sh
# lang-kit-lint.sh -- the lang kit's lint reads a bundle's scoped modules.
#
# tools/lang-kit/lint.sh lints a bundle one directory at a time, through
# tools/dev/lint.sh with X_LINT_MODULE_ROOT.  Held here, on a fixture bundle
# of two scoped modules:
#
#   - a name one module imports from its sibling, by name and over several
#     lines, is defined, whichever file of the directory the group's preload
#     is computed from;
#   - a name nothing defines or imports is still reported, so the check can
#     fail.
#
# The fixture boots this tree's x, once per case.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_DIR" || exit 1
X="$PROJECT_DIR/x.sh"

TMP=$(mktemp -d)
TMP=$(cd "$TMP" && pwd)
trap 'rm -rf "$TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fails=0

# A bundle: m/one exports half; m/two imports it over two lines.
mkdir -p "$TMP/b/m"
printf '(module m/one)\n(def half (fn (_ n) (/ n 2)))\n(provide m/one half)\n' \
	> "$TMP/b/m/one.x"
printf '(module m/two)\n(import m/one\n  half)\n(def quarter (fn (_ n) (half (half n))))\n(provide m/two quarter)\n' \
	> "$TMP/b/m/two.x"

out=$(BUNDLE="$TMP/b" X="$X" sh tools/lang-kit/lint.sh 2>&1) && st=0 || st=$?
if [ "$st" = 0 ]; then
	printf '  an import from a scoped sibling is defined: ok\n'
else
	printf 'lang-kit-lint: an import from a scoped sibling read as undefined:\n%s\n' "$out" >&2
	fails=$((fails + 1))
fi

# The same bundle with a name nobody defines.
printf '(module m/three)\n(def lost (fn (_ n) (nowhere-defined n)))\n(provide m/three lost)\n' \
	> "$TMP/b/m/three.x"
out=$(BUNDLE="$TMP/b" X="$X" sh tools/lang-kit/lint.sh 2>&1) && st=0 || st=$?
case "$st:$out" in
	0:*) printf 'lang-kit-lint: an undefined name passed\n' >&2; fails=$((fails + 1)) ;;
	*nowhere-defined*) printf '  an undefined name is still reported: ok\n' ;;
	*) printf 'lang-kit-lint: the lint failed without naming the undefined name:\n%s\n' "$out" >&2
	   fails=$((fails + 1)) ;;
esac

[ "$fails" = 0 ] || { echo "lang-kit-lint: $fails failed" >&2; exit 1; }
echo "lang-kit-lint: the kit lint reads scoped modules' imports."
