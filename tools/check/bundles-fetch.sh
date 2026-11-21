#!/bin/sh
# bundles-fetch.sh -- tools/bundles/fetch.sh and install.sh, end to end, over
# file:// .
#
# The official bundles are acquired once a tree and copied once an install,
# so the path is run rarely and is gated here, against a fixture bundle this
# script builds.  The pin tool's own rules (the digest before tar, the
# refusals of a wrong name or an unknown form) are tools/check/pin-smoke.sh's;
# what is held here is what the two scripts add:
#
#   none      with no pin, nothing is fetched and the run says so
#   acquire   a pinned bundle lands at DEST/NAME, with the pin it was
#             acquired at recorded beside it
#   reuse     a second run leaves the bundle alone
#   repin     a pin that changed is fetched again
#   tamper    a bad digest fails the run, keeps the copy that was there, and
#             leaves no record that says the bundle is as pinned
#   misnamed  a pin file not named for the bundle it pins is refused
#   install   the pinned bundles are copied and nothing else is; a bundle
#             not acquired at its pin fails the install
#
# The fixtures boot this tree's x, once an acquisition.
set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

T=$(mktemp -d)
T=$(cd "$T" && pwd)
trap 'rm -rf "$T"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fail() { echo "bundles-fetch: FAIL: $1" >&2; shift; [ $# -gt 0 ] && sed 's/^/  /' "$@" >&2; exit 1; }

. tools/lib/digest.sh
digest() { x_sha256 "$1" | cut -d' ' -f1; }

# fixture TAG -- a library bundle "bf" whose one module says which TAG it is
fixture() {
	mkdir -p "$T/src-$1/lib/bf"
	printf '(name "bf")\n(dialect he)\n(requires-release "v0.0.0")\n' > "$T/src-$1/bundle.xon"
	printf '(module bf/tag)\n(def tag (fn (_) "%s"))\n(provide bf/tag tag)\n' "$1" > "$T/src-$1/lib/bf/tag.x"
	( cd "$T/src-$1" && tar -czf "$T/bf-$1.tar.gz" . )
}

# pin FILE TAG DIGEST
pin() {
	{ printf '(name "bf")\n(release "%s")\n' "$2"
	  printf '(bundle "sha256:%s" "file://%s/bf-%s.tar.gz")\n' "$3" "$T" "$2"
	} > "$1"
}

# fetch -- the script's output in $T/out and its status in $st
fetch() {
	BUNDLE_PINS="$T/pins" BUNDLE_DEST="$T/dest" sh tools/bundles/fetch.sh > "$T/out" 2>&1 && st=0 || st=$?
}

fixture v1
fixture v2
mkdir -p "$T/pins"

# --- none ----------------------------------------------------------------------
fetch
[ "$st" = 0 ] || fail "none: a tree with no pin failed" "$T/out"
grep -q 'no official bundle is pinned' "$T/out" || fail "none: the run did not say nothing is pinned" "$T/out"
echo "  none: ok"

# --- acquire -------------------------------------------------------------------
pin "$T/pins/bf.pin.xon" v1 "$(digest "$T/bf-v1.tar.gz")"
fetch
[ "$st" = 0 ] || fail "acquire: a good pin was not acquired" "$T/out"
grep -q '"v1"' "$T/dest/bf/lib/bf/tag.x" 2>/dev/null || fail "acquire: the bundle did not land at DEST/bf" "$T/out"
cmp -s "$T/pins/bf.pin.xon" "$T/dest/bf.pin" || fail "acquire: the pin was not recorded beside the bundle" "$T/out"
echo "  acquire: ok"

# --- reuse ---------------------------------------------------------------------
# A file the acquisition did not write: a second acquisition would replace
# the tree and it would be gone.
echo kept > "$T/dest/bf/marker"
fetch
[ "$st" = 0 ] || fail "reuse: the second run failed" "$T/out"
grep -q 'bf is as pinned' "$T/out" || fail "reuse: the run did not say the bundle is as pinned" "$T/out"
[ -f "$T/dest/bf/marker" ] || fail "reuse: a bundle at its pin was fetched again" "$T/out"
echo "  reuse: ok"

# --- repin ---------------------------------------------------------------------
pin "$T/pins/bf.pin.xon" v2 "$(digest "$T/bf-v2.tar.gz")"
fetch
[ "$st" = 0 ] || fail "repin: a changed pin was not acquired" "$T/out"
grep -q '"v2"' "$T/dest/bf/lib/bf/tag.x" 2>/dev/null || fail "repin: the bundle is not the one the new pin names" "$T/out"
cmp -s "$T/pins/bf.pin.xon" "$T/dest/bf.pin" || fail "repin: the record is not the new pin" "$T/out"
echo "  repin: ok"

# --- tamper --------------------------------------------------------------------
pin "$T/pins/bf.pin.xon" v1 0000000000000000000000000000000000000000000000000000000000000000
fetch
[ "$st" != 0 ] || fail "tamper: a bad digest was acquired" "$T/out"
grep -q '"v2"' "$T/dest/bf/lib/bf/tag.x" 2>/dev/null || fail "tamper: the copy that was there did not survive" "$T/out"
[ ! -f "$T/dest/bf.pin" ] || fail "tamper: a record still says the bundle is as pinned" "$T/out"
echo "  tamper: ok"

# --- install: not at its pin ---------------------------------------------------
pin "$T/pins/bf.pin.xon" v2 "$(digest "$T/bf-v2.tar.gz")"
BUNDLE_PINS="$T/pins" BUNDLE_SRC="$T/dest" sh tools/bundles/install.sh "$T/inst" > "$T/out" 2>&1 && st=0 || st=$?
[ "$st" != 0 ] || fail "install: a bundle with no record of its pin was installed" "$T/out"
grep -q "make bundles" "$T/out" || fail "install: the refusal did not name 'make bundles'" "$T/out"
[ ! -e "$T/inst/bf" ] || fail "install: the refused bundle was copied" "$T/out"

# --- install -------------------------------------------------------------------
fetch
[ "$st" = 0 ] || fail "install: the pinned bundle was not acquired" "$T/out"
# Something a developer installed beside the official ones.
mkdir -p "$T/dest/other"
printf '(name "other")\n' > "$T/dest/other/bundle.xon"
BUNDLE_PINS="$T/pins" BUNDLE_SRC="$T/dest" sh tools/bundles/install.sh "$T/inst" > "$T/out" 2>&1 && st=0 || st=$?
[ "$st" = 0 ] || fail "install: the copy failed" "$T/out"
diff -r "$T/dest/bf" "$T/inst/bf" > "$T/out" 2>&1 || fail "install: the installed bundle differs from the acquired one" "$T/out"
[ ! -e "$T/inst/other" ] || fail "install: a bundle with no pin was copied"
[ ! -e "$T/inst/bf.pin" ] || fail "install: the acquisition record was copied"
echo "  install: ok"

# --- misnamed ------------------------------------------------------------------
mv "$T/pins/bf.pin.xon" "$T/pins/wrong.pin.xon"
fetch
[ "$st" != 0 ] || fail "misnamed: a pin file not named for its bundle was accepted" "$T/out"
grep -q 'bf.pin.xon' "$T/out" || fail "misnamed: the refusal did not name the file it should be" "$T/out"
echo "  misnamed: ok"

echo "bundles-fetch: ok"
