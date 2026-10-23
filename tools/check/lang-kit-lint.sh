#!/bin/sh
# lang-kit-lint.sh -- the lang kit's lint reads a bundle's scoped modules.
#
# tools/lang-kit/lint.sh lints a bundle one directory at a time, through
# tools/dev/lint.sh with X_LINT_MODULE_ROOT.  Held here, on a fixture bundle
# of two scoped modules:
#
#   - a name one module imports from its sibling, by name and over several
#     lines, is defined, whichever file of the directory the batch's preload
#     is computed from;
#   - a name nothing defines or imports is still reported, so the check can
#     fail;
#   - the lang contract's rules on a bundle's files hold under --strict: a
#     file with no (module ...) header and a provide list naming a %-private
#     are each named, the entry and a file nothing loads are exempt, and without --strict
#     both are advisory.
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

# The lang contract's rules on a bundle's files.  A fresh bundle: an entry
# named by lang.xon, one scoped module whose constructs.x declares a
# letrec-scoped form the linter must read (a self-call in an init is not
# undefined), one imported file that provides but has no header,
# one module whose provide list names a %-private, one module in two files,
# a data file nothing
# loads, and a script under tools/ nothing loads.
mkdir -p "$TMP/c/m" "$TMP/c/tools"
printf '(lang "c")\n(dialect he)\n(entry "run.x")\n' > "$TMP/c/lang.xon"
printf '(import m/one\n  half)\n(import m/loose loose)\n(import m/two step!)\n(def c-main (fn (_) (half (loose (step!)))))\n' > "$TMP/c/run.x"
printf '(module m/two)\n(def %%count 0)\n(include-once "./two-step.x")\n(provide m/two step!)\n' > "$TMP/c/m/two.x"
printf '(module-part m/two)\n(def step! (fn (_) (set! %%count (+ %%count 1)) %%count))\n' > "$TMP/c/m/two-step.x"
printf '(module m/one)\n(def my-letrec let)\n(def half (fn (_ n) (my-letrec ((go (fn (self k) (if (= k 0) 0 (go (- k 1)))))) (go n))))\n(provide m/one half)\n' > "$TMP/c/m/one.x"
printf '(def loose (fn (_ n) (+ n 1)))\n(provide m/loose loose)\n' > "$TMP/c/m/loose.x"
printf '(module m/leaky)\n(def %%secret 1)\n(provide m/leaky %%secret)\n' > "$TMP/c/m/leaky.x"
printf '(def tool-main (fn (_) 1))\n' > "$TMP/c/tools/script.x"
printf '(\n  (my-letrec (fmt . head-1) (scope . letrec) (branch . none))\n)\n' > "$TMP/c/m/constructs.x"
out=$(BUNDLE="$TMP/c" X="$X" sh tools/lang-kit/lint.sh --strict 2>&1) && st=0 || st=$?
case "$st" in
	0) printf 'lang-kit-lint: a file with no module header and a %%-private export passed --strict\n' >&2; fails=$((fails + 1)) ;;
	*)
		case "$out" in *"module: m/loose.x"*) printf '  a file with no (module ...) header is a strict finding: ok\n' ;;
			*) printf 'lang-kit-lint: the file with no header was not named:\n%s\n' "$out" >&2; fails=$((fails + 1)) ;; esac
		case "$out" in *"provide: m/leaky.x exports %secret"*) printf '  a provide list naming a %%-private is a strict finding: ok\n' ;;
			*) printf 'lang-kit-lint: the %%-private export was not named:\n%s\n' "$out" >&2; fails=$((fails + 1)) ;; esac
		case "$out" in *"module: run.x"*|*"module: tools/script.x"*|*"module: m/constructs.x"*) printf 'lang-kit-lint: the entry or a file nothing loads was held to the module rule:\n%s\n' "$out" >&2; fails=$((fails + 1)) ;;
			*) printf '  the entry and files nothing loads are exempt from the module rule: ok\n' ;; esac
		case "$out" in *"module: m/two-step.x"*|*"      %count"*) printf 'lang-kit-lint: a part of a module was held to the module rule, or its names read as undefined:\n%s\n' "$out" >&2; fails=$((fails + 1)) ;;
			*) printf '  a (module-part ...) header heads a part of a module: ok\n' ;; esac ;;
esac
# Without --strict the same bundle passes: the findings are advisory.
if BUNDLE="$TMP/c" X="$X" sh tools/lang-kit/lint.sh >/dev/null 2>&1; then
	printf '  without --strict the two findings are advisory: ok\n'
else
	printf 'lang-kit-lint: the module and provide findings failed a non-strict run\n' >&2
	fails=$((fails + 1))
fi

[ "$fails" = 0 ] || { echo "lang-kit-lint: $fails failed" >&2; exit 1; }
echo "lang-kit-lint: the kit lint reads scoped modules' imports."
