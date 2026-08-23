#!/bin/sh
# engine-fetch.sh -- tools/engine/fetch.sh, end to end, over file:// .
#
# The acquisition path is the one part of the build that reaches the network,
# and the one nobody exercises: once a tree has an engine it never runs again.
# So it is gated here, hermetically, against a tarball this script builds --
# the same technique tools/check/pin-smoke.sh uses for (Pin fetch), and for the
# same reason: a release fixture proves the mechanism without needing a release.
#
# WHAT IT PINS DOWN, and each is a rule the mechanism would be wrong without:
#
#   verify    a good digest fetches, unpacks and lands
#   reuse     a second run does no work and touches nothing
#   tamper    a bad digest REFUSES, and quarantines the bytes as evidence
#   missing   a DECLARED artifact that will not fetch is an ERROR -- it must not
#             fall back to a source build.  The fallback is for platforms nobody
#             publishes for; firing it on a broken release would turn a bad
#             release into a slow build and hide it.
#   unknown   a form the pin does not define is refused, not ignored
set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

T="${TMPDIR:-/tmp}/engine-fetch.$$"
mkdir -p "$T"
trap 'rm -rf "$T"; rm -rf "$ROOT/build/engine/fixture-"* 2>/dev/null || true' EXIT INT TERM

fail() { echo "engine-fetch: FAIL: $1" >&2; shift; [ $# -gt 0 ] && sed 's/^/  /' "$@" >&2; exit 1; }

digest() {
	if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
	else sha256sum "$1" | cut -d' ' -f1; fi
}

# --- a release fixture: the smallest thing shaped like an engine directory ----
# Not a real engine: fetch.sh verifies bytes and publishes a directory, and
# knows nothing about what is in it.  Building a real engine here would test the
# engine's Makefile a second time and make this gate minutes long.
mkdir -p "$T/src/fixture-engine-v9.9.9-$(uname -s)/tools/contract"
echo 'fixture' > "$T/src/fixture-engine-v9.9.9-$(uname -s)/x-bin"
( cd "$T/src" && tar -czf "$T/fixture.tar.gz" . )
DG=$(digest "$T/fixture.tar.gz")

case "$(uname -s)" in Darwin) OS=darwin ;; Linux) OS=linux ;; *) OS=unknown ;; esac
case "$(uname -m)" in
	arm64|aarch64) ARCH=arm64 ;; x86_64|amd64) ARCH=x86-64 ;; i[3456]86) ARCH=i386 ;;
	*) ARCH=unknown ;;
esac

pin() {  # pin <digest> <url>
	{ printf '(engine "fixture")\n(release "v9.9.9")\n'
	  printf '(artifact %s %s "sha256:%s" "%s")\n' "$OS" "$ARCH" "$1" "$2"
	} > "$T/pin.xon"
}

# --- verify: a good digest lands ---------------------------------------------
pin "$DG" "file://$T/fixture.tar.gz"
out=$(PIN="$T/pin.xon" sh tools/engine/fetch.sh 2>"$T/err") \
	|| fail "a well-formed artifact did not fetch" "$T/err"
[ -f "$out/x-bin" ] || fail "fetched tree has no x-bin at $out" "$T/err"
[ "$(cat "$out/.digest")" = "$DG" ] || fail "fetched tree carries the wrong digest stamp"

# --- reuse: the second run does not fetch ------------------------------------
# Proven by taking the URL away: a run that still succeeds cannot have used it.
pin "$DG" "file://$T/gone.tar.gz"
out2=$(PIN="$T/pin.xon" sh tools/engine/fetch.sh 2>"$T/err") \
	|| fail "an already-verified tree was re-fetched instead of reused" "$T/err"
[ "$out2" = "$out" ] || fail "reuse landed somewhere else: $out2 vs $out"

# --- tamper: a bad digest refuses, and keeps the evidence --------------------
rm -rf "$out"
pin "0000000000000000000000000000000000000000000000000000000000000000" "file://$T/fixture.tar.gz"
if PIN="$T/pin.xon" sh tools/engine/fetch.sh >"$T/out" 2>"$T/err"; then
	fail "a MISMATCHED digest was accepted" "$T/out"
fi
grep -q "DIGEST MISMATCH" "$T/err" || fail "tamper: refused without naming the reason" "$T/err"
[ -d "$out.rejected" ] || fail "tamper: the bytes were not quarantined at $out.rejected"
rm -rf "$out.rejected"

# --- missing: a declared artifact that will not fetch is an ERROR ------------
# THE RULE THIS GATE EXISTS FOR.  Falling back to source here would make a
# broken release indistinguishable from a slow machine.
pin "$DG" "file://$T/not-there.tar.gz"
if PIN="$T/pin.xon" sh tools/engine/fetch.sh >"$T/out" 2>"$T/err"; then
	fail "a declared artifact that could not be fetched fell back instead of failing" "$T/out"
fi
grep -q "fetch failed" "$T/err" || fail "missing: wrong diagnosis" "$T/err"
grep -q "source" "$T/out" 2>/dev/null && fail "missing: it fell back to a source build" "$T/out"

# --- unknown: the vocabulary is closed ---------------------------------------
printf '(engine "fixture")\n(nonsense "x")\n' > "$T/pin.xon"
if PIN="$T/pin.xon" sh tools/engine/fetch.sh >"$T/out" 2>"$T/err"; then
	fail "an unknown pin form was ignored" "$T/out"
fi
grep -q "unknown form" "$T/err" || fail "unknown: refused without saying why" "$T/err"

echo "engine-fetch: ok (verify, reuse, tamper, missing, unknown)"
