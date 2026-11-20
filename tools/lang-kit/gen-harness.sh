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
# Libraries are armed as x.sh arms them, after the platform's own root: each
# one a (requires-lib ...) row names, found as a required lang is (X_LIBS_DIR,
# the bundle's siblings, the acquired libs), then every installed one.  A
# library is armed once by name, so a sibling checkout answers ahead of an
# installed copy.
#
# The bundle's tests/harness.x comes last: its imports and REPL printer, the
# part of its entry that sets the lang up without starting it.
#
# A LIBRARY's suite is generated the same way, from its lib.xon.  It has no
# dialect to declare, so it boots helium, or the dialect DIALECT names; its
# own root is the first library armed; and it has no lang root, no lang to
# lead, and a tests/harness.x only if it wants one.
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

# The name the declaration in $1 gives itself; $2 is the kind, lang or lib,
# which names both the file and the form.
_gh_decl_name() {
	sed -n 's/^('"$2"' "\([^"]*\)").*/\1/p' "$1/$2.xon" | head -1
}

# What the bundle in $1, of kind $2, requires, as KIND:NAME rows, version or
# not.  A lang may require langs and libraries; a library, libraries.
_gh_reqs() {
	[ "$2" != lang ] || sed -n 's/^(requires-lang "\([^"]*\)".*/lang:\1/p' "$1/lang.xon"
	sed -n 's/^(requires-lib "\([^"]*\)".*/lib:\1/p' "$1/$2.xon"
}

# The bundle under directory $2 that declares the lang or lib $1, of kind $3,
# printed as an absolute path; nothing when there is none.  Two claiming the
# name is a misconfiguration, as it is to x.sh, and exits.
_gh_decl_in() {
	[ -d "$2" ] || return 0
	_gh_found=
	for _gh_d in "$2"/*/; do
		[ -f "$_gh_d/$3.xon" ] || continue
		[ "$(_gh_decl_name "$_gh_d" "$3")" = "$1" ] || continue
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

# Where the lang or lib $1 lives, searched in order; $2 is the chain that
# required it and $3 the kind.  Installed langs are under langs/ in an install
# and deps/langs/ in a checkout, and libraries under libs/ and deps/libs/.
_gh_decl_dir() {
	if [ "$3" = lang ]; then
		set -- "$1" "$2" "$3" "${X_LANG_DIR:-}" X_LANG_DIR
	else
		set -- "$1" "$2" "$3" "${X_LIBS_DIR:-}" X_LIBS_DIR
	fi
	for _gh_where in ${4:+"$4"} "$BUNDLE/.." "$_gh_root/${3}s" "$_gh_root/deps/${3}s"; do
		_gh_at=$(_gh_decl_in "$1" "$_gh_where" "$3") || exit 1
		if [ -n "$_gh_at" ]; then
			echo "$_gh_at"
			return 0
		fi
	done
	echo "gen-harness: $3 '$1' is required but was not found" >&2
	echo "  required by: $2" >&2
	echo "  looked in ${4:+$5 ($4), }the bundle's siblings, $_gh_root/${3}s and $_gh_root/deps/${3}s" >&2
	exit 1
}

# The roots the row $1 (KIND:NAME) needs armed, deepest first: a lang's into
# _gh_deps, a library's into _gh_libs.  $2 is the chain that led here.
# Arguments rather than variables carry the state across the recursion, since
# a shell function's variables are not its own.
_gh_collect() {
	set -- "${1#*:}" "$2" "${1%%:*}"
	case " $2 " in
		*" $1 "*) _gh_die "${3}s require each other in a cycle: $2 $1" ;;
	esac
	set -- "$1" "$2" "$3" "$(_gh_decl_dir "$1" "$2" "$3")"
	[ -n "$4" ] || exit 1
	for _gh_r in $(_gh_reqs "$4" "$3"); do
		_gh_collect "$_gh_r" "$2 $1"
	done
	if [ "$3" = lang ]; then
		case " $_gh_deps " in
			*" $4 "*) ;;
			*) _gh_deps="$_gh_deps $4" ;;
		esac
	else
		_gh_lib_add "$1" "$4"
	fi
}

# The library $1 at $2, armed once: by path, and by name, so an installed copy
# of a library a sibling checkout already answers for is passed over.
_gh_lib_add() {
	case " $_gh_libnames " in
		*" $1 "*) return 0 ;;
	esac
	_gh_libnames="$_gh_libnames $1"
	_gh_libs="$_gh_libs $2"
}

# The bundle is a lang or a library, and its declaration says which.
if [ -f "$BUNDLE/lang.xon" ]; then
	_gh_kind=lang
elif [ -f "$BUNDLE/lib.xon" ]; then
	_gh_kind=lib
else
	_gh_die "no lang.xon or lib.xon in $BUNDLE"
fi
_gh_tail="$BUNDLE/tests/harness.x"
# A lang's harness.x is what sets the lang up, and it must be there.  A
# library has nothing to set up: its suite imports what it tests, so the file
# is read when present and not asked for.
if [ "$_gh_kind" = lang ]; then
	[ -f "$_gh_tail" ] || _gh_die "no $_gh_tail -- it holds what follows the boot: the bundle's imports and REPL printer"
fi

_gh_root="$("$X" --share-dir)"
[ -n "$_gh_root" ] || _gh_die "$X --share-dir answered nothing"

_gh_name=$(_gh_decl_name "$BUNDLE" "$_gh_kind")
[ -n "$_gh_name" ] || _gh_die "$BUNDLE/$_gh_kind.xon declares no ($_gh_kind \"...\")"
# A lang declares its dialect.  A library declares none, since any session
# may import it: its suite boots helium, or the dialect DIALECT names.
if [ "$_gh_kind" = lang ]; then
	_gh_dialect=$(sed -n 's/^(dialect \([a-z0-9-]*\)).*/\1/p' "$BUNDLE/lang.xon" | head -1)
	_gh_said="lang.xon declares"
else
	_gh_dialect="${DIALECT:-}"
	_gh_said="DIALECT names"
fi
: "${_gh_dialect:=he}"

_gh_entry="$_gh_root/lib/$_gh_dialect.x"
[ -f "$_gh_entry" ] || _gh_die "$_gh_said dialect '$_gh_dialect', which has no entry at $_gh_entry"
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
_gh_libs=
_gh_libnames=
# A library under test is the first library armed: its own working tree
# answers for its name, ahead of any installed copy.
[ "$_gh_kind" != lib ] || _gh_lib_add "$_gh_name" "$BUNDLE"
for _gh_r in $(_gh_reqs "$BUNDLE" "$_gh_kind"); do
	_gh_collect "$_gh_r" "$_gh_name"
done
# Every installed library, as x.sh arms them on every launch: X_LIBS_DIR
# when it is set, else the install's libs/ and the checkout's deps/libs/.
# In a function: this file may be sourced, and the positional parameters at
# its top level are the caller's.
_gh_libs_in() {
	[ -d "$1" ] || return 0
	for _gh_d in "$1"/*/; do
		[ -f "$_gh_d/lib.xon" ] || continue
		_gh_d=$(cd "$_gh_d" && pwd)
		_gh_lib_add "$(_gh_decl_name "$_gh_d" lib)" "$_gh_d"
	done
}
if [ -n "${X_LIBS_DIR:-}" ]; then
	_gh_libs_in "$X_LIBS_DIR"
else
	_gh_libs_in "$_gh_root/libs"
	_gh_libs_in "$_gh_root/deps/libs"
fi

_gh_path_ok "$_gh_root" "platform root"
_gh_path_ok "$BUNDLE" "bundle root"
for _gh_d in $_gh_deps; do
	_gh_path_ok "$_gh_d" "required lang root"
done
for _gh_d in $_gh_libs; do
	_gh_path_ok "$_gh_d" "library root"
done

mkdir -p "$BUNDLE/tests/lib"
{
	printf '; harness.gen.x -- GENERATED by x-lang tools/lang-kit/gen-harness.sh from\n'
	printf '; %s.xon and tests/harness.x.  Do not edit, do not commit: the paths are\n' "$_gh_kind"
	printf '; facts of this machine.\n'
	printf '(def %%install-root "%s")\n' "$_gh_root"
	printf '(include "%s")\n' "$_gh_amalgam"
	for _gh_d in $_gh_libs; do
		printf '(import-path! "%s" (lit after))\n' "$_gh_d"
	done
	for _gh_d in $_gh_deps; do
		printf '(import-path! "%s")\n' "$_gh_d"
	done
	if [ "$_gh_kind" = lang ]; then
		printf '(import-path! "%s")\n' "$BUNDLE"
		printf '(def %%lang-root "%s")\n' "$BUNDLE"
		printf '(def %%lang-lead "%s")\n' "$_gh_name"
	fi
	[ ! -f "$_gh_tail" ] || cat "$_gh_tail"
} > "$BUNDLE/tests/lib/harness.gen.x"
