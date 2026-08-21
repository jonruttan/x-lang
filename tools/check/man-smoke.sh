#!/bin/sh
# man-smoke.sh -- gate the man-page generation and install path.
#
# doc-man and install-man had no target in the gate: doc-man sits outside
# `doc` deliberately (it is a second full library sweep, and only install-man
# consumes it), so nothing in CI ever ran either one.  This drives both
# against a throwaway prefix and checks the properties that actually break.
#
# WHAT IT CHECKS, and why each one is here rather than assumed:
#
#   pages exist          a sweep that emits nothing still exits 0.
#   .TH on every page    a page without it is not a man page; roff renders it
#                        as running text and `man` shows no header.
#   every stub resolves  the alias pass writes `.so man3x/<page>` stubs and
#                        REFUSES to overwrite, so a bug in the naming or the
#                        collision rule leaves stubs pointing at nothing.
#                        This is the one that would have caught the `/` in
#                        `Bigint-/` and the non-idempotent sweep.
#   no unsafe names      a `/` in a page name is a path separator, and a
#                        leading `-` parses as an option at every command
#                        that reads the name.
#   install round-trips  install-man-x then uninstall-man-x must leave the
#                        section empty -- a stub the uninstall cannot name
#                        would be left behind on every upgrade.
#
# The C half needs Doxygen, so it is opt-in: pass --with-c where Doxygen is
# installed.  It is REPORTED either way; a skipped half never passes quietly.
#
# Deliberately no `man`/`groff` dependency: the checks are structural, so the
# gate does not turn on which roff toolchain a runner happens to ship.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_DIR"

WITH_C=no
[ "$1" = "--with-c" ] && WITH_C=yes

MAN3X="docs/ref/man/man3x"
PREFIX_DIR=$(mktemp -d)
trap 'rm -rf "$PREFIX_DIR"' EXIT

fail() { printf '  \033[1;31mman-smoke FAIL\033[0m %s\n' "$1" >&2; exit 1; }

# x-lang names are legal file names but not safe shell WORDS: the library
# documents `*`, so the alias pass writes a page literally called `*.3x`.  An
# unquoted $(grep -l ...) re-globbed that name back into every file in the
# directory, and this gate's first run blamed a real page for having no .so
# line.  Hence the file lists below: a quoted glob expands once, and the
# result is read back with IFS= read -r, which neither splits nor re-globs.
# (`set -f` would also fix it, and would break the quoted globs that build
# the lists in the first place.)

# --- generate ---------------------------------------------------------------
make doc-man >/dev/null || fail "make doc-man exited nonzero"

pages=$(grep -L '^\.so ' "$MAN3X"/*.3x 2>/dev/null | wc -l | tr -d ' ')
stubs=$(grep -l '^\.so ' "$MAN3X"/*.3x 2>/dev/null | wc -l | tr -d ' ')
[ "$pages" -gt 0 ] || fail "no module pages generated"
[ "$stubs" -gt 0 ] || fail "no alias stubs generated"

# --- every real page is a man page ------------------------------------------
grep -L '^\.so ' "$MAN3X"/*.3x > "$PREFIX_DIR/pages.lst"
while IFS= read -r page; do
	head -n 1 "$page" | grep -q '^\.TH ' \
		|| fail "$(basename "$page") has no .TH header"
done < "$PREFIX_DIR/pages.lst"

# --- every stub resolves to a page that exists ------------------------------
dangling=0
grep -l '^\.so ' "$MAN3X"/*.3x > "$PREFIX_DIR/stubs.lst"
while IFS= read -r stub; do
	target=$(sed -n 's|^\.so man3x/||p' "$stub" | head -1)
	[ -n "$target" ] || fail "$(basename "$stub") has an unparseable .so line"
	if [ ! -f "$MAN3X/$target" ]; then
		printf '  dangling: %s -> %s\n' "$(basename "$stub")" "$target" >&2
		dangling=$((dangling + 1))
	fi
done < "$PREFIX_DIR/stubs.lst"
[ "$dangling" -eq 0 ] || fail "$dangling alias stub(s) point at a missing page"

# --- no name that is not a file name ----------------------------------------
for page in "$MAN3X"/*.3x; do
	case "$(basename "$page")" in
		-*) fail "page name starts with '-': $(basename "$page")" ;;
	esac
done

# --- install / uninstall round-trip -----------------------------------------
make install-man-x DESTDIR="$PREFIX_DIR" >/dev/null \
	|| fail "make install-man-x exited nonzero"
installed=$(ls "$PREFIX_DIR/usr/local/share/man/man3x" 2>/dev/null | wc -l | tr -d ' ')
[ "$installed" -eq $((pages + stubs)) ] \
	|| fail "installed $installed pages, generated $((pages + stubs))"

make uninstall-man-x DESTDIR="$PREFIX_DIR" >/dev/null \
	|| fail "make uninstall-man-x exited nonzero"
left=$(ls "$PREFIX_DIR/usr/local/share/man/man3x" 2>/dev/null | wc -l | tr -d ' ')
[ "$left" -eq 0 ] || fail "uninstall-man-x left $left file(s) behind"

# --- the C half, where Doxygen exists ---------------------------------------
if [ "$WITH_C" = yes ]; then
	command -v doxygen >/dev/null 2>&1 || fail "--with-c given but doxygen is not installed"
	make install-man-c DESTDIR="$PREFIX_DIR" >/dev/null \
		|| fail "make install-man-c exited nonzero"
	c_installed=$(ls "$PREFIX_DIR/usr/local/share/man/man3" 2>/dev/null | wc -l | tr -d ' ')
	[ "$c_installed" -gt 0 ] || fail "install-man-c installed nothing"
	# Test what install-man-c actually filters on -- the page TITLE -- not
	# the file name.  A leading underscore is not the marker: _GNU_SOURCE.3
	# is a legitimate macro page, and keying on `^_` failed the gate on it.
	# Doxygen's directory pages are the ones carrying this checkout's
	# absolute path in their name, and "Directory Reference" is what
	# identifies them on any machine.
	if head -qn 1 "$PREFIX_DIR/usr/local/share/man/man3"/*.3 2>/dev/null \
		| grep -q 'Directory Reference" 3'; then
		fail "a Doxygen directory page reached the install tree"
	fi
	make uninstall-man-c DESTDIR="$PREFIX_DIR" >/dev/null \
		|| fail "make uninstall-man-c exited nonzero"
	c_left=$(ls "$PREFIX_DIR/usr/local/share/man/man3" 2>/dev/null | wc -l | tr -d ' ')
	[ "$c_left" -eq 0 ] || fail "uninstall-man-c left $c_left file(s) behind"
	printf 'man-smoke: ok (%s pages, %s aliases, C reference %s pages)\n' \
		"$pages" "$stubs" "$c_installed"
else
	printf 'man-smoke: ok (%s pages, %s aliases; C half NOT checked -- pass --with-c where doxygen is installed)\n' \
		"$pages" "$stubs"
fi
