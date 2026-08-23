#!/bin/sh
# bootstrap.sh -- get a working x from source in one command.
#
#   curl -fsSL https://raw.githubusercontent.com/jonruttan/x-lang/main/bootstrap.sh | sh
#
# with flags through a pipe:
#
#   curl -fsSL .../bootstrap.sh | sh -s -- --install
#
# or, from inside a checkout:
#
#   sh bootstrap.sh
#
# It clones x-lang (unless already in a checkout), acquires the engine that
# clone names,
# builds the engine (a ~4-second C89 compile), and prints how to run
# and how to install.  With --install (or X_INSTALL=1) it also installs
# to a user prefix -- no sudo, nothing written outside the prefix.
#
# Knobs (all optional):
#   X_REPO     clone URL         (default: the public GitHub repo)
#   X_REF      branch/tag/commit (default: main)
#   X_SRC      where to clone    (default: ./x-lang)
#   X_PREFIX   install prefix    (default: $HOME/.local)
#   X_INSTALL  1 => install      (default: build only)
# Flags: --install, --ref REF, --prefix DIR, --src DIR, --help
#
# No compiler, no clone -- deliberately: this is the setup step the
# 4-second build never needed help with; it removes the toolchain and
# submodule dance, not a slow compile.
set -eu

X_REPO="${X_REPO:-https://github.com/jonruttan/x-lang.git}"
X_REF="${X_REF:-main}"
X_SRC="${X_SRC:-}"
X_PREFIX="${X_PREFIX:-$HOME/.local}"
X_INSTALL="${X_INSTALL:-}"

while [ $# -gt 0 ]; do
	case "$1" in
		--install) X_INSTALL=1; shift ;;
		--ref) X_REF="$2"; shift 2 ;;
		--prefix) X_PREFIX="$2"; shift 2 ;;
		--src) X_SRC="$2"; shift 2 ;;
		--help|-h)
			sed -n '2,26p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//'
			exit 0 ;;
		*) echo "bootstrap: unknown argument: $1" >&2; exit 1 ;;
	esac
done

say()  { printf '\033[1;32m==>\033[0m %s\n' "$1"; }
die()  { printf '\033[1;31mbootstrap: %s\033[0m\n' "$1" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# A checkout is identifiable by the wrapper + the Makefile + the library
# together -- not one of them alone (a stray Makefile in some cwd must not
# read as "already here").
#
# NOT BY THE ENGINE.  This probe used to require ext/x-engine-c, which made
# "am I in a checkout?" depend on a directory a checkout can legitimately be
# without: the submodule is uninitialised on a plain clone, and once the
# engine arrives as a pinned artifact it is not in the tree at all until it
# is fetched.  The library is the thing this repo IS.  (The probe has been
# wrong this way before: it asked for ext/x-expr, which the split moved a
# level down, and answered "not a checkout" in a checkout.)
in_checkout() {
	[ -f Makefile ] && [ -f x.sh ] && [ -f lib/x-core.x ]
}

# --- Preflight: a C compiler and make are always needed; git only to clone.
CC_BIN="${CC:-}"
if [ -z "$CC_BIN" ]; then
	for c in cc gcc clang tcc; do have "$c" && { CC_BIN="$c"; break; }; done
fi
[ -n "$CC_BIN" ] || die "no C compiler found (set CC, or install cc/gcc/clang)"
have make || die "make not found"

# --- Locate or fetch the source tree.  An explicit --src/X_SRC always
# means "clone/use there" and wins over build-in-place: standing inside a
# checkout must not hijack a run that named a different location.
if [ -z "$X_SRC" ] && in_checkout; then
	SRC="$(pwd)"
	say "building in place: $SRC"
else
	have git || die "git not found (needed to clone; or run this from a checkout)"
	SRC="${X_SRC:-$(pwd)/x-lang}"
	if [ -e "$SRC/.git" ]; then
		say "updating existing clone: $SRC"
		git -C "$SRC" fetch --quiet origin
		git -C "$SRC" checkout --quiet "$X_REF"
		git -C "$SRC" submodule update --init --recursive --quiet
	elif [ -e "$SRC" ]; then
		die "$SRC exists and is not a git clone -- move it or set X_SRC/--src"
	else
		say "cloning $X_REPO @ $X_REF -> $SRC"
		git clone --quiet --branch "$X_REF" "$X_REPO" "$SRC" 2>/dev/null \
			|| git clone --quiet "$X_REPO" "$SRC"
		# --branch does not accept a raw commit; fall back to an explicit checkout.
		git -C "$SRC" checkout --quiet "$X_REF" 2>/dev/null || true
		git -C "$SRC" submodule update --init --recursive --quiet
	fi
fi

# --- Build (the 4-second part).
say "building the engine (CC=$CC_BIN)"
( cd "$SRC" && make --no-print-directory clean >/dev/null 2>&1 || true )

# ACQUIRE THE ENGINE.  x-lang is the language; the engine is a separate project
# and this tree carries none, so there is a step between "clone" and "build"
# that did not exist while a submodule came along for the ride.  `make engine`
# reads tools/engine/engine.pin.xon, fetches the release it names for this
# platform, verifies it against the pinned digest, and links it -- or clones and
# builds the sources where nothing is published.
#
# X_ENGINE_DIR SKIPS IT, which is how the smoke stays offline: pointed at an
# engine that is already here, there is nothing to acquire.
if [ -z "${X_ENGINE_DIR:-}" ]; then
	say "acquiring the engine"
	( cd "$SRC" && make --no-print-directory engine >/dev/null ) || die "could not acquire an engine"
fi
( cd "$SRC" && CC="$CC_BIN" make --no-print-directory ) || die "build failed"
[ -x "$SRC/x-bin" ] || die "build reported success but no engine at $SRC/x-bin"

# --- Verify the freshly built engine answers.
VER="$( ( cd "$SRC" && sh ./x.sh -V ) 2>/dev/null | head -1 || true )"
[ -n "$VER" ] || die "the built engine did not answer -V"
say "built: $VER"

# --- Optionally install to a user prefix (no sudo).
if [ -n "$X_INSTALL" ]; then
	say "installing to $X_PREFIX (no sudo)"
	( cd "$SRC" && CC="$CC_BIN" make --no-print-directory install PREFIX="$X_PREFIX" >/dev/null ) \
		|| die "install failed"
	BIN="$X_PREFIX/bin/x"
	say "installed: $BIN"
	if have x && [ "$(command -v x)" = "$BIN" ]; then
		printf '    x is on your PATH -- run: x\n'
	else
		printf '    add it to PATH:  export PATH="%s/bin:$PATH"\n' "$X_PREFIX"
		printf '    then run:        x\n'
	fi
else
	say "done -- run it from the checkout:"
	printf '    cd %s && sh x.sh          # REPL\n' "$SRC"
	printf '    sh %s/x.sh -f program.x   # run a file\n' "$SRC"
	printf '    re-run with --install to put x on your PATH\n'
fi
