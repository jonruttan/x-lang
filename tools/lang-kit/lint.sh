#!/bin/sh
# # x-lang -- the lang kit
#
# ## tools/lang-kit/lint.sh -- the linter, for a bundle's own sources
#
# @description Lints a lang bundle's .x files with the platform's linter,
#   resolved from the installed tree.  --strict fails on advisory warnings.
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2026 Jon Ruttan
# @license MIT No Attribution (MIT-0)
#
#     ., .,
#     {O,O}
#     (   )
#      " "
#
# THE PLATFORM SHIPS IT; BUNDLES DO NOT VENDOR IT -- the ruling
# spec-gate.sh carries, applied to the check that was missing entirely.
# `make lint-x` sweeps lib/ and apps/; a bundle under languages/ was
# swept by nothing, so every rule the linter knows was advice a bundle
# never heard.  x-coreutils accumulated TWENTY-ONE `ladder` findings
# that way -- nested if chains branching on one variable, the shape
# `match` replaces and outruns -- written after the rule existed.
#
# ADVISORY RULES ARE ADVICE UNTIL SOMETHING FAILS ON THEM.  The linter
# reports them as warnings and exits 0, which is right for a sweep and
# wrong for a bundle that wants them gated -- so --strict fails the run.
#
# It fails on the STRUCTURAL rules only: ladder, ladder-dict and shape,
# the ones that say a definition is built wrong.  Not `unused`, which
# an applet protocol trips by design (every applet takes stdin-thunk
# and most never read it), and not `shadow` or `display-chain`, which
# are style.  A gate that fired on those would be turned off inside a
# week, and the structural ones would go unheard again.
#
# Set BUNDLE to the bundle root and X to the x to lint with; both are
# what the bundle's shim passes.
set -e

BUNDLE="${BUNDLE:-$(pwd)}"
X="${X:-x}"
STRICT=0
[ "${1:-}" = "--strict" ] && { STRICT=1; shift; }

command -v "$X" >/dev/null 2>&1 || {
	echo "lang-kit lint: no x on PATH.  Set X=/path/to/x and retry." >&2
	exit 2
}

X_ROOT="$("$X" --share-dir)"
X_BIN="${X_BIN:-$("$X" --engine-path)}"
LINT="$X_ROOT/tools/dev/lint.sh"

[ -f "$LINT" ] || {
	echo "lang-kit lint: no linter at $LINT -- upgrade x" >&2
	exit 2
}

# The targets, ABSOLUTE: the linter cd's to each file's directory to
# find its siblings, so a relative path would resolve against the wrong
# root.  Given none, the caller gets every .x the bundle ships, minus
# its generated harness.
if [ $# -gt 0 ]; then
	_ABS=""
	for _t in "$@"; do
		case "$_t" in
			/*) _ABS="$_ABS $_t" ;;
			*)  _ABS="$_ABS $BUNDLE/$_t" ;;
		esac
	done
	# shellcheck disable=SC2086
	set -- $_ABS
else
	# shellcheck disable=SC2046
	set -- $(find "$BUNDLE" -name '*.x' \
		-not -path '*/tests/lib/*' -not -path '*/.git/*' | sort)
fi

# ONE BOOT PER DIRECTORY, not one per file.  The platform's --group
# path lints a set of files sharing a PRELOAD in a single engine (#323),
# and the preload is a property of the directory: cu/*.x import the same
# siblings, the entry beside run.x imports the module namespace.  Mixing
# them in one group would lint every file against the first one's
# environment, which reads as a wall of Undefined.
_STATUS=0
_WARNINGS=0
_DIRS=$(for _t in "$@"; do dirname "$_t"; done | sort -u)
for _d in $_DIRS; do
	_LIST=$(mktemp "${TMPDIR:-/tmp}/lang-kit-lint.XXXXXX") || exit 1
	for _t in "$@"; do
		[ "$(dirname "$_t")" = "$_d" ] && printf '%s\n' "$_t"
	done > "$_LIST"
	# --lib: a bundle's modules export to each other, so an unused
	# warning on a provided name is noise.  --warnings surfaces the
	# advisory rules, which is the point of running this at all.
	if _OUT=$(X_LINT_ROOT="$X_ROOT" X_BIN="$X_BIN" X_LINT_MODULE_ROOT="$BUNDLE" \
		sh "$LINT" --lib --warnings --group "$_LIST" 2>&1); then
		:
	else
		_STATUS=1
	fi
	rm -f "$_LIST"
	printf '%s\n' "$_OUT"
	# COUNT THE FINDINGS, NOT THE LINES.  The linter prints one line per
	# rule with every definition on it -- "ladder: %t-binary/11 %t-unary2/10
	# %t-unary/9" is three findings -- so a line count called that one.
	_N=$(printf '%s\n' "$_OUT" | grep -E '^      (ladder|ladder-dict|shape):' \
		| sed 's/^ *[a-z-]*://' | wc -w | tr -d ' ')
	_WARNINGS=$((_WARNINGS + ${_N:-0}))
done

[ "$_STATUS" -eq 0 ] || { echo "lang-kit lint: FAILED" >&2; exit 1; }

# A warning line is indented under the file it belongs to; the verdict
# lines are not.  Strict mode fails when any appears.
if [ "$STRICT" -eq 1 ] && [ "$_WARNINGS" -gt 0 ]; then
	echo "lang-kit lint: $_WARNINGS structural finding(s) -- ladder/shape -- and --strict was asked" >&2
	exit 1
fi
echo "lang-kit lint: ok"
