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
# The platform ships this linter; a bundle runs it rather than vendoring a
# copy.  `make lint-x` sweeps lib/ and apps/, which does not reach a bundle
# under languages/.
#
# The linter reports advisory rules as warnings and exits 0.  --strict fails
# the run on them instead, for a bundle that wants them gated.
#
# --strict fails on the structural rules only -- ladder, dispatch and
# depth, which say a definition is built wrong, and the two rules of the
# lang contract's "Modules, names and classes" this shim checks itself: a
# file the lang loads is a scoped module, and a provide list names no
# %-private.  Not `unused`, which an applet protocol trips by design (every
# applet takes stdin-thunk and most never read it), and not `shadow` or
# `display-chain`, which are style.
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

# Targets are made absolute: the linter cd's to each file's directory to find
# its siblings, so a relative path would resolve against the wrong root.  Given
# none, the targets are every .x the bundle ships, minus its generated harness.
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
	# constructs.x is data the linter and formatter read, not code, and
	# the platform's driver skips its own the same way.
	set -- $(find "$BUNDLE" -name '*.x' \
		-not -path '*/tests/lib/*' -not -path '*/.git/*' \
		-not -name 'constructs.x' | sort)
fi

# One boot per directory rather than one per file.  The platform's --group
# path lints a set of files sharing a preload in a single engine, and the
# preload is a property of the directory: cu/*.x import the same siblings, the
# entry beside run.x imports the module namespace.  Mixing directories in one
# group lints every file against the first one's environment.
# A bundle's constructs.x declares the lang's own binding forms -- Kernel's
# $lambda and $define!, Scheme's define -- so the linter reads a parameter
# they bind as bound.  The linter takes it through X_LINT_CONSTRUCTS.
_CONSTRUCTS=$(find "$BUNDLE" -name constructs.x -not -path '*/tests/*' -not -path '*/.git/*' 2>/dev/null | head -1)
[ -z "$_CONSTRUCTS" ] || { X_LINT_CONSTRUCTS="$_CONSTRUCTS"; export X_LINT_CONSTRUCTS; }
# The langs the bundle requires, found as the harness generator finds them:
# beside the bundle, named after the lang or after its repository.  Their
# roots go to the linter so a module's import from a required lang resolves.
_DEPS=""
for _req in $(sed -n 's/^(requires-lang "\([^"]*\)".*/\1/p' "$BUNDLE/lang.xon" 2>/dev/null); do
	for _c in "$BUNDLE/../$_req" "$BUNDLE/../x-$_req"; do
		if [ -f "$_c/lang.xon" ]; then _DEPS="$_DEPS $(cd "$_c" && pwd)"; break; fi
	done
done
[ -z "$_DEPS" ] || { X_LINT_MODULE_DEPS="$_DEPS"; export X_LINT_MODULE_DEPS; }
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
	# Findings are counted, not lines: the linter prints one line per rule
	# with every definition on it, so "ladder: %t-binary/11 %t-unary2/10
	# %t-unary/9" is three findings on one line.
	_N=$(printf '%s\n' "$_OUT" | grep -E '^      (ladder|dispatch|depth):' \
		| sed 's/^ *[a-z-]*://' | wc -w | tr -d ' ')
	_WARNINGS=$((_WARNINGS + ${_N:-0}))
done

# The lang contract's rules on a bundle's files (docs/lang-contract.md,
# "Modules, names and classes"), read textually the way the manifests are.
#
# Every file the lang loads is a scoped module: its first form is
# (module NAME).  A file is loaded when it is the entry lang.xon names, a
# module some file imports, or a file some file includes by a ./-relative
# path; a file nothing loads -- a data file a tool reads, a script -- is not
# held to the rule, and the entry is the one loaded file exempt from it.  A
# file headed with a module's name that is not the module's own file is one
# of its files: the module's file includes it, and it provides nothing.  A
# provide list names no %-private; the scan is the kit's own
# provide-names.sh.  All are findings like the linter's, indented under a
# heading, counted into the strict verdict.
_ENTRY=$(sed -n 's/^(entry "\([^"]*\)")$/\1/p' "$BUNDLE/lang.xon" 2>/dev/null | head -1)
_ENTRY="$BUNDLE/${_ENTRY:-run.x}"
_LOADED=" $_ENTRY "
for _g in "$@"; do
	_gd=$(dirname "$_g")
	for _m in $(sed -n 's/^[[:space:]]*(import \([^ )]*\).*/\1/p' "$_g"); do
		_LOADED="$_LOADED$BUNDLE/$_m.x "
	done
	for _i in $(sed -n 's/^[[:space:]]*(include\(-once\)\{0,1\} "\.\/\([^"]*\)".*/\2/p' "$_g"); do
		_LOADED="$_LOADED$_gd/$_i "
	done
done
_MODS=""
for _t in "$@"; do
	[ "$_t" = "$_ENTRY" ] && continue
	case "$_LOADED" in *" $_t "*) _MODS="$_MODS $_t" ;; esac
done
_BUNDLE_OUT=""
for _t in $_MODS; do
	# The first form: the first line that is not blank and not a comment.
	_first=$(awk '/^[[:space:]]*$/ { next } /^[[:space:]]*;/ { next } { print; exit }' "$_t")
	case "$_first" in
		"(module "*) ;;
		*) _BUNDLE_OUT="$_BUNDLE_OUT
      module: ${_t#"$BUNDLE"/} has no (module ...) header"; continue ;;
	esac
	_name=${_first#"(module "}; _name=${_name%%[ )]*}
	_own="$BUNDLE/$_name.x"
	[ "$_t" = "$_own" ] && continue
	_included=0
	if [ -f "$_own" ]; then
		for _i in $(sed -n 's/^[[:space:]]*(include\(-once\)\{0,1\} "\.\/\([^"]*\)".*/\2/p' "$_own"); do
			[ "$(dirname "$_own")/$_i" = "$_t" ] && _included=1
		done
	fi
	[ "$_included" = 1 ] || _BUNDLE_OUT="$_BUNDLE_OUT
      module: ${_t#"$BUNDLE"/} is headed (module $_name), and ${_own#"$BUNDLE"/} does not include it"
	grep -q '^[[:space:]]*(provide ' "$_t" && _BUNDLE_OUT="$_BUNDLE_OUT
      provide: ${_t#"$BUNDLE"/} provides, and it is a file of $_name"
done
# Every file's provide list, loaded or not: a provide is a claim on a name.
_PROV=$(sh "$(dirname "$0")/provide-names.sh" "$@" 2>&1 \
	| sed -n "s|^provide-names: $BUNDLE/\(.*\) -- .*|      provide: \1|p")
[ -z "$_PROV" ] || _BUNDLE_OUT="$_BUNDLE_OUT
$_PROV"
if [ -n "$_BUNDLE_OUT" ]; then
	printf '%s (the bundle)%s\n' "$BUNDLE" "$_BUNDLE_OUT"
	_N=$(printf '%s\n' "$_BUNDLE_OUT" | grep -cE '^      (module|provide):')
	_WARNINGS=$((_WARNINGS + _N))
fi

[ "$_STATUS" -eq 0 ] || { echo "lang-kit lint: FAILED" >&2; exit 1; }

# A warning line is indented under the file it belongs to; the verdict
# lines are not.  Strict mode fails when any appears.
if [ "$STRICT" -eq 1 ] && [ "$_WARNINGS" -gt 0 ]; then
	echo "lang-kit lint: $_WARNINGS structural finding(s) -- ladder/dispatch/depth/module/provide -- and --strict was asked" >&2
	exit 1
fi
echo "lang-kit lint: ok"
