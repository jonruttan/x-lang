#!/bin/sh
# bootstrap-smoke.sh -- gate bootstrap.sh's build+install path.
#
# bootstrap.sh's one fragile coupling is to the Makefile's install layout
# (BINDIR/LIBEXECDIR/LIBDIR): if those move, the script's PATH hint and
# its "did it install?" checks rot.  This smoke drives the script in
# build-in-place mode and installs to a throwaway prefix, then runs the
# INSTALLED x from an unrelated cwd -- the same end-to-end assertion a new
# user makes, minus the clone.
#
# The CLONE path (git, submodules, --ref) is deliberately NOT gated here:
# a hermetic clone would need the submodules available offline.  It is
# covered indirectly -- every CI run is itself a recursive checkout +
# build, the same chain the clone path drives -- and directly by the
# manual local-clone test.  This gate covers what a Makefile install-layout
# edit can silently break, which is bootstrap.sh's one fragile coupling.
set -eu

cd "$(dirname "$0")/../.."
REPO="$(pwd)"

sh -n bootstrap.sh || { echo "bootstrap-smoke: bootstrap.sh has a syntax error" >&2; exit 1; }

T="${TMPDIR:-/tmp}/bootstrap-smoke.$$"
mkdir -p "$T"
trap 'rm -rf "$T"' EXIT
fail() { echo "bootstrap-smoke: FAIL: $1" >&2; [ -f "$T/log" ] && sed 's/^/  /' "$T/log" >&2; exit 1; }

# Build-in-place (no X_SRC) + install to the temp prefix, run from $T so
# the in-checkout detection triggers on the repo.
( cd "$REPO" && X_PREFIX="$T/prefix" sh bootstrap.sh --install ) > "$T/log" 2>&1 \
	|| fail "bootstrap --install exited nonzero"

[ -x "$T/prefix/bin/x" ]        || fail "wrapper not installed at the expected path"
[ -x "$T/prefix/libexec/x/x-bin" ]  || fail "engine not installed at the expected path"
[ -d "$T/prefix/share/x/boot" ] || fail "boot amalgams not installed"

echo '(display (+ 40 2))(newline)' > "$T/p.x"
out=$( cd "$T" && "$T/prefix/bin/x" -f "$T/p.x" 2>/dev/null | tail -1 )
[ "$out" = "42" ] || fail "the installed x did not run a program (got: '$out')"

echo "bootstrap-smoke: ok"
