#!/bin/sh
# # x-lang -- the lang kit
#
# ## tools/lang-kit/gen-harness.sh -- a bundle's spec harness, booted as `x -l` boots it
#
# @description Writes tests/lib/harness.gen.x: the dialect the bundle's
#   lang.xon declares, the roots of the langs it requires and its own, then
#   the bundle's tests/harness.x.
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2026 Jon Ruttan
# @license MIT No Attribution (MIT-0)
#
#     ., .,
#     {O,O}
#     (   )
#      " "
#
# The platform ships this generator; a bundle runs it rather than keeping its
# own, so the dialect a suite boots is the one lang.xon names and nothing else.
#
# The dialect boots as its BODY: the file its entry includes before starting a
# REPL (lib/he.x includes lib/x/boot/helium.x).  The body is found by reading
# that include out of the entry, so a new dialect needs no row here, and it is
# loaded from its amalgam -- boot/ in an install, build/boot/ in a checkout,
# where `make boot` writes it.  The entry itself cannot be loaded: its REPL
# would start underneath the suite.
#
# What follows the boot is what x.sh emits between a dialect and a bundle's
# entry: an import root for each required lang, deepest first, then the
# bundle's own, %lang-root and %lang-lead.  A required lang is found by the name
# its lang.xon declares, as x.sh finds it, in X_LANG_DIR, then beside the bundle
# (a checkout's siblings), then among the acquired langs.  Versions are not
# compared: a checkout carries no version stamp, and a suite runs against
# working trees.
#
# The bundle's tests/harness.x comes last: its imports and REPL printer, the
# part of its entry that sets the lang up without starting it.
#
# BUNDLE is the bundle root and X the x to ask; the shim that sources this sets
# both.  The generated file embeds absolute paths, so it is written, never
# committed.
set -e

BUNDLE="${BUNDLE:-$(pwd)}"
X="${X:-x}"

_gh_die() {
	echo "gen-harness: $*" >&2
	exit 1
}

# Every path lands in an x-lang string literal, which cannot carry these;
# x.sh refuses the same two.
_gh_path_ok() {
	case "$1" in
		*\"* | *\\*) _gh_die "$2 path contains a quote or backslash: $1" ;;
	esac
}

# The name a lang.xon declares.
_gh_lang_name() {
	sed -n 's/^(lang "\([^"]*\)").*/\1/p' "$1/lang.xon" | head -1
}

# The names in a lang.xon's (requires-lang ...) rows, version or not.
_gh_reqs() {
	sed -n 's/^(requires-lang "\([^"]*\)".*/\1/p' "$1/lang.xon"
}

# The bundle under directory $2 that declares the lang $1, printed as an
# absolute path; nothing when there is none.  Two claiming the name is a
# misconfiguration, as it is to x.sh, and exits.
_gh_lang_in() {
	[ -d "$2" ] || return 0
	_gh_found=
	for _gh_d in "$2"/*/; do
		[ -f "$_gh_d/lang.xon" ] || continue
		[ "$(_gh_lang_name "$_gh_d")" = "$1" ] || continue
		_gh_d=$(cd "$_gh_d" && pwd)
		[ "$_gh_d" != "$BUNDLE" ] || continue
		if [ -n "$_gh_found" ]; then
			echo "gen-harness: two bundles both call themselves '$1':" >&2
			echo "    $_gh_found" >&2
			echo "    $_gh_d" >&2
			exit 1
		fi
		_gh_found="$_gh_d"
	done
	[ -z "$_gh_found" ] || echo "$_gh_found"
}

# Where the lang $1 lives, searched in order; $2 is the chain that required it.
# Installed langs are under langs/ in an install and deps/langs/ in a checkout.
_gh_lang_dir() {
	for _gh_where in ${X_LANG_DIR:+"$X_LANG_DIR"} "$BUNDLE/.." "$_gh_root/langs" "$_gh_root/deps/langs"; do
		_gh_at=$(_gh_lang_in "$1" "$_gh_where") || exit 1
		if [ -n "$_gh_at" ]; then
			echo "$_gh_at"
			return 0
		fi
	done
	echo "gen-harness: lang '$1' is required but was not found" >&2
	echo "  required by: $2" >&2
	echo "  looked in ${X_LANG_DIR:+X_LANG_DIR ($X_LANG_DIR), }the bundle's siblings, $_gh_root/langs and $_gh_root/deps/langs" >&2
	exit 1
}

# The roots the lang $1 needs armed, into _gh_deps, deepest first; $2 is the
# chain that led here.  Arguments rather than variables carry the state across
# the recursion, since a shell function's variables are not its own.
_gh_collect() {
	case " $2 " in
		*" $1 "*) _gh_die "langs require each other in a cycle: $2 $1" ;;
	esac
	set -- "$1" "$2" "$(_gh_lang_dir "$1" "$2")"
	[ -n "$3" ] || exit 1
	for _gh_r in $(_gh_reqs "$3"); do
		_gh_collect "$_gh_r" "$2 $1"
	done
	case " $_gh_deps " in
		*" $3 "*) ;;
		*) _gh_deps="$_gh_deps $3" ;;
	esac
}

[ -f "$BUNDLE/lang.xon" ] || _gh_die "no lang.xon in $BUNDLE"
_gh_tail="$BUNDLE/tests/harness.x"
[ -f "$_gh_tail" ] || _gh_die "no $_gh_tail -- it holds what follows the boot: the bundle's imports and REPL printer"

_gh_root="$("$X" --share-dir)"
[ -n "$_gh_root" ] || _gh_die "$X --share-dir answered nothing"

_gh_name=$(_gh_lang_name "$BUNDLE")
[ -n "$_gh_name" ] || _gh_die "$BUNDLE/lang.xon declares no (lang \"...\")"
_gh_dialect=$(sed -n 's/^(dialect \([a-z0-9-]*\)).*/\1/p' "$BUNDLE/lang.xon" | head -1)
: "${_gh_dialect:=he}"

_gh_entry="$_gh_root/lib/$_gh_dialect.x"
[ -f "$_gh_entry" ] || _gh_die "lang.xon declares dialect '$_gh_dialect', which has no entry at $_gh_entry"
_gh_body=$(sed -n 's|^(include "lib/x/boot/\([a-z0-9-]*\)\.x")$|\1|p' "$_gh_entry" | head -1)
[ -n "$_gh_body" ] || _gh_die "the $_gh_dialect entry includes no body from lib/x/boot/: $_gh_entry"

_gh_amalgam=
for _gh_c in "$_gh_root/boot/$_gh_body.x" "$_gh_root/build/boot/$_gh_body.x"; do
	if [ -f "$_gh_c" ]; then
		_gh_amalgam="$_gh_c"
		break
	fi
done
[ -n "$_gh_amalgam" ] || _gh_die "no amalgam of the $_gh_body body at $_gh_root/boot/ or $_gh_root/build/boot/ -- in a checkout, run 'make boot'"

_gh_deps=
for _gh_r in $(_gh_reqs "$BUNDLE"); do
	_gh_collect "$_gh_r" "$_gh_name"
done

_gh_path_ok "$_gh_root" "platform root"
_gh_path_ok "$BUNDLE" "bundle root"
for _gh_d in $_gh_deps; do
	_gh_path_ok "$_gh_d" "required lang root"
done

mkdir -p "$BUNDLE/tests/lib"
{
	printf '; harness.gen.x -- GENERATED by x-lang tools/lang-kit/gen-harness.sh from\n'
	printf '; lang.xon and tests/harness.x.  Do not edit, do not commit: the paths are\n'
	printf '; facts of this machine.\n'
	printf '(def %%install-root "%s")\n' "$_gh_root"
	printf '(include "%s")\n' "$_gh_amalgam"
	for _gh_d in $_gh_deps; do
		printf '(import-path! "%s")\n' "$_gh_d"
	done
	printf '(import-path! "%s")\n' "$BUNDLE"
	printf '(def %%lang-root "%s")\n' "$BUNDLE"
	printf '(def %%lang-lead "%s")\n' "$_gh_name"
	cat "$_gh_tail"
} > "$BUNDLE/tests/lib/harness.gen.x"
