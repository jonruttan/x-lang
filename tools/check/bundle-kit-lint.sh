#!/bin/sh
# bundle-kit-lint.sh -- the bundle kit's lint reads a bundle's scoped modules.
#
# tools/bundle-kit/lint.sh lints a bundle one directory at a time, through
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
mkdir -p "$TMP/b/lib/m"
printf '(module m/one)\n(def half (fn (_ n) (/ n 2)))\n(provide m/one half)\n' \
	> "$TMP/b/lib/m/one.x"
printf '(module m/two)\n(import m/one\n  half)\n(def quarter (fn (_ n) (half (half n))))\n(provide m/two quarter)\n' \
	> "$TMP/b/lib/m/two.x"

out=$(BUNDLE="$TMP/b" X="$X" sh tools/bundle-kit/lint.sh 2>&1) && st=0 || st=$?
if [ "$st" = 0 ]; then
	printf '  an import from a scoped sibling is defined: ok\n'
else
	printf 'bundle-kit-lint: an import from a scoped sibling read as undefined:\n%s\n' "$out" >&2
	fails=$((fails + 1))
fi

# The same bundle with a name nobody defines.
printf '(module m/three)\n(def lost (fn (_ n) (nowhere-defined n)))\n(provide m/three lost)\n' \
	> "$TMP/b/lib/m/three.x"
out=$(BUNDLE="$TMP/b" X="$X" sh tools/bundle-kit/lint.sh 2>&1) && st=0 || st=$?
case "$st:$out" in
	0:*) printf 'bundle-kit-lint: an undefined name passed\n' >&2; fails=$((fails + 1)) ;;
	*nowhere-defined*) printf '  an undefined name is still reported: ok\n' ;;
	*) printf 'bundle-kit-lint: the lint failed without naming the undefined name:\n%s\n' "$out" >&2
	   fails=$((fails + 1)) ;;
esac

# The lang contract's rules on a bundle's files.  A fresh bundle: an entry
# listed in bundle.xon, one scoped module whose constructs.x declares a
# letrec-scoped form the linter must read (a self-call in an init is not
# undefined), one imported file that provides but has no header,
# one module whose provide list names a %-private, one module written in two
# files, one file headed with a module's name that the module's file does
# not include and that provides, a data file nothing loads, and a script
# under tools/ nothing loads.
mkdir -p "$TMP/c/lib/m" "$TMP/c/tools"
printf '(name "m")\n(dialect he)\n(entry run)\n' > "$TMP/c/bundle.xon"
printf '(module m/run)\n(import m/one\n  half)\n(import m/loose loose)\n(import m/two step!)\n(def main (fn (_) (half (loose (step!)))))\n(provide m/run main)\n' > "$TMP/c/lib/m/run.x"
printf '(module m/two)\n(def %%count 0)\n(include-once "./two-step.x")\n(provide m/two step!)\n' > "$TMP/c/lib/m/two.x"
printf '(module m/two)\n(def step! (fn (_) (set! %%count (+ %%count 1)) %%count))\n' > "$TMP/c/lib/m/two-step.x"
printf '(module m/one)\n(def stray 1)\n(provide m/one stray)\n' > "$TMP/c/lib/m/stray.x"
printf '(module m/one)\n(def my-letrec let)\n(def half (fn (_ n) (my-letrec ((go (fn (self k) (if (= k 0) 0 (go (- k 1)))))) (go n))))\n(provide m/one half)\n' > "$TMP/c/lib/m/one.x"
printf '(def loose (fn (_ n) (+ n 1)))\n(provide m/loose loose)\n' > "$TMP/c/lib/m/loose.x"
printf '(module m/leaky)\n(def %%secret 1)\n(include-once "./stray.x")\n(provide m/leaky %%secret)\n' > "$TMP/c/lib/m/leaky.x"
printf '(def tool-main (fn (_) 1))\n' > "$TMP/c/tools/script.x"
printf '(\n  (my-letrec (fmt . head-1) (scope . letrec) (branch . none))\n)\n' > "$TMP/c/lib/m/constructs.x"
out=$(BUNDLE="$TMP/c" X="$X" sh tools/bundle-kit/lint.sh --strict 2>&1) && st=0 || st=$?
case "$st" in
	0) printf 'bundle-kit-lint: a file with no module header and a %%-private export passed --strict\n' >&2; fails=$((fails + 1)) ;;
	*)
		case "$out" in *"module: lib/m/loose.x"*) printf '  a file with no (module ...) header is a strict finding: ok\n' ;;
			*) printf 'bundle-kit-lint: the file with no header was not named:\n%s\n' "$out" >&2; fails=$((fails + 1)) ;; esac
		case "$out" in *"provide: lib/m/leaky.x exports %secret"*) printf '  a provide list naming a %%-private is a strict finding: ok\n' ;;
			*) printf 'bundle-kit-lint: the %%-private export was not named:\n%s\n' "$out" >&2; fails=$((fails + 1)) ;; esac
		case "$out" in *"module: lib/m/run.x"*|*"module: tools/script.x"*|*"module: lib/m/constructs.x"*) printf 'bundle-kit-lint: the scoped entry or a file nothing loads was faulted by the module rule:\n%s\n' "$out" >&2; fails=$((fails + 1)) ;;
			*) printf '  a scoped entry passes the module rule, and files nothing loads are exempt: ok\n' ;; esac
		case "$out" in *"module: lib/m/two-step.x"*|*"provide: lib/m/two-step.x"*|*"      %count"*) printf 'bundle-kit-lint: a file of a module was faulted, or its names read as undefined:\n%s\n' "$out" >&2; fails=$((fails + 1)) ;;
			*) printf '  a file headed with its module'"'"'s name, included from the module'"'"'s file, is a file of the module: ok\n' ;; esac
		case "$out" in *"module: lib/m/stray.x is headed (module m/one), and lib/m/one.x does not include it"*) printf '  a file headed with a module'"'"'s name that the module does not include is a strict finding: ok\n' ;;
			*) printf 'bundle-kit-lint: the stray file was not named:\n%s\n' "$out" >&2; fails=$((fails + 1)) ;; esac
		case "$out" in *"provide: lib/m/stray.x provides, and it is a file of m/one"*) printf '  a provide in a file of a module is a strict finding: ok\n' ;;
			*) printf 'bundle-kit-lint: the provide in a file of a module was not named:\n%s\n' "$out" >&2; fails=$((fails + 1)) ;; esac ;;
esac
# Without --strict the same bundle passes: the findings are advisory.
if BUNDLE="$TMP/c" X="$X" sh tools/bundle-kit/lint.sh >/dev/null 2>&1; then
	printf '  without --strict the two findings are advisory: ok\n'
else
	printf 'bundle-kit-lint: the module and provide findings failed a non-strict run\n' >&2
	fails=$((fails + 1))
fi

[ "$fails" = 0 ] || { echo "bundle-kit-lint: $fails failed" >&2; exit 1; }
echo "bundle-kit-lint: the kit lint reads scoped modules' imports."
