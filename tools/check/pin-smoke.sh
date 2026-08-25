#!/bin/sh
# pin-smoke.sh -- the wrapper's pin.xon probe and the loader, end to end.
#
# Builds a throwaway project under $TMPDIR (a pin.xon manifest, overlay
# trees, a program) and runs the program THROUGH THE WRAPPER from the
# repo root -- the probe must find the manifest beside the PROGRAM, not
# the cwd.  Cases:
#   overlay    (import acme/util) resolves in the project's deps/ tree
#   order      two roots: the root listed FIRST wins
#   boot       an overlay copy of a boot module is a no-op -- the
#              pre-seeded set is the unpinnable core (GH #115 ruling)
#   notice     the wrapper announces the manifest on stderr
#   closed     an unknown manifest form is a loud error, nonzero exit
#   no-pin     --no-pin skips the probe (and the notice)
#   vendor     (Pin vendor) copies x/type/dict's closure into an overlay
#              (helium: dict is not boot-floor there), the boot floor is
#              skipped, and a pinned run loads the OVERLAY copy -- proven
#              by appending a drift marker the platform copy lacks
#   fetch      (Pin fetch) against a fake release over file:// -- curl,
#              manifest, pure-x digest, and the tamper refusal; hermetic,
#              no network
#   compose    (boot "FILE") + (root "DIR") in one manifest (GH #139):
#              the wrapper boots the project's own entry AND arms the
#              overlay, announcing both on stderr
#   boot-flag  --boot FILE overrides the manifest's (boot ...); the
#              overlay still arms
#   boot-gone  a manifest naming a missing boot entry fails loudly --
#              never a silent fallback to the platform entry
#   boot-bad   a malformed (boot ...) is rejected by the loader's
#              closed vocabulary (the wrapper's probe ignores it)
#   boot-quote a (boot ...) path carrying shell metacharacters stays a
#              PATH: the wrapper assembles its pipe as text and evals it,
#              so an unquoted value would make the manifest executable --
#              the manifest is documented inert (docs/modules.md)
#   release-guard  a pinned amalgam from another RELEASE is refused even
#              though the isa fingerprints match (#435), --allow-release-skew
#              and (allow-release-skew) waive it loudly, and a lock or an
#              engine with nothing to compare says so
#   pin-quote  a manifest DIRECTORY carrying a double quote is refused:
#              the path is emitted as an x-lang string literal, and a
#              quote would close it and inject forms into the boot stream
# (The pinned REPL path is tty-side -- the fd-3 class check-examples.sh
# documents -- and is not smokeable here; it shares every pipe stage but
# the final launch.x with the -f path exercised below.)
set -u

cd "$(dirname "$0")/../.." || exit 1
WRAPPER=./x.sh

# Wall-time guard, same detection as spec-runner.sh (macOS: gtimeout).
_TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then
  _TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  _TIMEOUT_BIN="gtimeout"
fi
TIMEOUT_CMD=""
if [ -n "$_TIMEOUT_BIN" ]; then
  TIMEOUT_CMD="$_TIMEOUT_BIN ${TIMEOUT_PIN_SECS:-120}"
fi

_TMP="${TMPDIR:-/tmp}/pin-smoke.$$"
trap 'rm -rf "$_TMP"' EXIT
mkdir -p "$_TMP/proj/deps/acme" "$_TMP/proj/alt/acme" "$_TMP/proj/deps/x/core"

fail() {
  echo "pin-smoke: FAIL: $1" >&2
  shift
  for f in "$@"; do
    sed 's/^/  /' "$f" | head -10 >&2
  done
  exit 1
}

cat > "$_TMP/proj/deps/acme/util.x" <<'EOF'
(def acme-marker "deps")
(provide acme/util acme-marker)
EOF
cat > "$_TMP/proj/alt/acme/util.x" <<'EOF'
(def acme-marker "alt")
(provide acme/util acme-marker)
EOF
# An overlay copy of a boot module: loading it would be fatal; the
# pre-seed makes the import below a no-op, so the program must succeed.
cat > "$_TMP/proj/deps/x/core/list.x" <<'EOF'
(error "pin-smoke: the unpinnable core was overlaid")
EOF
cat > "$_TMP/proj/main.x" <<'EOF'
(alloc-limit! 300000000)
(import acme/util)
(import x/core/list)
(display acme-marker)
(newline)
EOF

# overlay + order (deps listed first wins) + boot no-op + notice, one run
cat > "$_TMP/proj/pin.xon" <<'EOF'
; pin-smoke manifest
(root "deps")
(root "alt")
EOF
$TIMEOUT_CMD sh "$WRAPPER" -f "$_TMP/proj/main.x" >"$_TMP/out" 2>"$_TMP/err"
status=$?
[ "$status" -eq 0 ] || fail "pinned run exited $status" "$_TMP/err" "$_TMP/out"
grep -qx "deps" "$_TMP/out" || fail "overlay/order: expected first root's marker 'deps'" "$_TMP/out"
grep -q "^pinned: " "$_TMP/err" || fail "notice: no 'pinned:' line on stderr" "$_TMP/err"

# order, the other way: alt listed first must win
cat > "$_TMP/proj/pin.xon" <<'EOF'
(root "alt")
(root "deps")
EOF
$TIMEOUT_CMD sh "$WRAPPER" -f "$_TMP/proj/main.x" >"$_TMP/out" 2>"$_TMP/err"
status=$?
[ "$status" -eq 0 ] || fail "reordered run exited $status" "$_TMP/err" "$_TMP/out"
grep -qx "alt" "$_TMP/out" || fail "order: expected first root's marker 'alt'" "$_TMP/out"

# closed vocabulary: an unknown form fails the run loudly
cat > "$_TMP/proj/pin.xon" <<'EOF'
(evil "form")
EOF
$TIMEOUT_CMD sh "$WRAPPER" -f "$_TMP/proj/main.x" >"$_TMP/out" 2>"$_TMP/err"
status=$?
[ "$status" -ne 0 ] || fail "closed: unknown manifest form did not fail the run" "$_TMP/out" "$_TMP/err"

# --no-pin: probe skipped, no notice; a program with no overlay imports runs
cat > "$_TMP/proj/pin.xon" <<'EOF'
(evil "form")
EOF
cat > "$_TMP/proj/plain.x" <<'EOF'
(alloc-limit! 300000000)
(display "unpinned")
(newline)
EOF
$TIMEOUT_CMD sh "$WRAPPER" --no-pin -f "$_TMP/proj/plain.x" >"$_TMP/out" 2>"$_TMP/err"
status=$?
[ "$status" -eq 0 ] || fail "--no-pin run exited $status" "$_TMP/err" "$_TMP/out"
grep -qx "unpinned" "$_TMP/out" || fail "--no-pin: program output missing" "$_TMP/out"
grep -q "^pinned: " "$_TMP/err" && fail "--no-pin: probe still announced a manifest" "$_TMP/err"

# vendor: closure copied, floor skipped, overlay copy is the one that loads
mkdir -p "$_TMP/proj2"
cat > "$_TMP/vendor.x" <<EOF
(alloc-limit! 300000000)
(import x/tool/pin)
(Pin vendor "$_TMP/proj2/deps" 'x/type/dict)
(display "vendored")
(newline)
EOF
$TIMEOUT_CMD sh "$WRAPPER" --no-pin -f "$_TMP/vendor.x" >"$_TMP/out" 2>"$_TMP/err"
status=$?
[ "$status" -eq 0 ] || fail "vendor run exited $status" "$_TMP/err" "$_TMP/out"
grep -qx "vendored" "$_TMP/out" || fail "vendor: no completion marker" "$_TMP/out" "$_TMP/err"
[ -e "$_TMP/proj2/deps/x/type/dict.x" ] || fail "vendor: dict.x not copied"
[ -d "$_TMP/proj2/deps/x/core" ] && fail "vendor: boot floor leaked into the overlay"
# verify plumbing end to end, on a TINY closure (pure-x hashing of the
# dict closure would cost ~25s per pass; the acme fixture costs nothing
# and exercises the identical wrapper->loader->lock->hash path)
mkdir -p "$_TMP/proj3"
cat > "$_TMP/verify.x" <<EOF
(alloc-limit! 300000000)
(import x/tool/pin)
(import-path! "$_TMP/proj/deps")
(Pin vendor "$_TMP/proj3/deps" 'acme/util)
(display (Pin verify "$_TMP/proj3/deps"))
(newline)
EOF
$TIMEOUT_CMD sh "$WRAPPER" --no-pin -f "$_TMP/verify.x" >"$_TMP/out" 2>"$_TMP/err"
status=$?
[ "$status" -eq 0 ] || fail "verify-clean run exited $status" "$_TMP/err" "$_TMP/out"
grep -qx "1" "$_TMP/out" || fail "verify-clean: expected count 1" "$_TMP/out"

cat > "$_TMP/verify2.x" <<EOF
(alloc-limit! 300000000)
(import x/tool/pin)
(display (Pin verify "$_TMP/proj3/deps"))
EOF
printf '; tampered\n' >> "$_TMP/proj3/deps/acme/util.x"
$TIMEOUT_CMD sh "$WRAPPER" --no-pin -f "$_TMP/verify2.x" >"$_TMP/out" 2>"$_TMP/err"
status=$?
[ "$status" -ne 0 ] || fail "verify-tamper: tampered overlay verified clean" "$_TMP/out" "$_TMP/err"

# drift simulation: the vendored copy grows a marker the platform lacks
printf '(def %%pin-smoke-vendored "yes")\n' >> "$_TMP/proj2/deps/x/type/dict.x"
cat > "$_TMP/proj2/pin.xon" <<'EOF'
(root "deps")
EOF
cat > "$_TMP/proj2/main.x" <<'EOF'
(alloc-limit! 300000000)
(import x/type/dict)
(display %pin-smoke-vendored)
(newline)
EOF
$TIMEOUT_CMD sh "$WRAPPER" -f "$_TMP/proj2/main.x" >"$_TMP/out" 2>"$_TMP/err"
status=$?
[ "$status" -eq 0 ] || fail "vendored-pin run exited $status" "$_TMP/err" "$_TMP/out"
grep -qx "yes" "$_TMP/out" || fail "vendored-pin: the platform copy loaded, not the overlay" "$_TMP/out"

# stale (GH #147): a dependency dropped upstream must LEAVE the lock on
# re-vendor.  It used to stay in both tree and lock -- still shadowing
# the platform -- with verify calling the pair clean because both had
# gone stale together.  Runs through the wrapper, on the acme fixture.
mkdir -p "$_TMP/proj7/lib0/acme"
cat > "$_TMP/proj7/lib0/acme/head.x" <<'EOF'
(import acme/tail)
(provide acme/head)
EOF
cat > "$_TMP/proj7/lib0/acme/tail.x" <<'EOF'
(provide acme/tail)
EOF
cat > "$_TMP/stale1.x" <<EOF
(alloc-limit! 300000000)
(import x/tool/pin)
(import-path! "$_TMP/proj7/lib0")
(Pin vendor "$_TMP/proj7/deps" 'acme/head)
(display (Pin verify "$_TMP/proj7/deps"))
(newline)
EOF
$TIMEOUT_CMD sh "$WRAPPER" --no-pin -f "$_TMP/stale1.x" >"$_TMP/out" 2>"$_TMP/err"
status=$?
[ "$status" -eq 0 ] || fail "stale-vendor1 exited $status" "$_TMP/err" "$_TMP/out"
grep -qx "2" "$_TMP/out" || fail "stale: expected 2 files vendored" "$_TMP/out"
# upstream drops the dependency; re-vendor must name it and drop it
printf '(provide acme/head)\n' > "$_TMP/proj7/lib0/acme/head.x"
cat > "$_TMP/stale2.x" <<EOF
(alloc-limit! 300000000)
(import x/tool/pin)
(import-path! "$_TMP/proj7/lib0")
(Pin vendor "$_TMP/proj7/deps" 'acme/head)
EOF
$TIMEOUT_CMD sh "$WRAPPER" --no-pin -f "$_TMP/stale2.x" >"$_TMP/out" 2>"$_TMP/err"
status=$?
[ "$status" -eq 0 ] || fail "stale-vendor2 exited $status" "$_TMP/err" "$_TMP/out"
grep -q "no longer in the closure" "$_TMP/out" || fail "stale: dropped file not reported" "$_TMP/out"
grep -q "acme/tail.x" "$_TMP/out" || fail "stale: dropped file not named" "$_TMP/out"
# and the orphan is now unlisted, so verify refuses it
cat > "$_TMP/stale3.x" <<EOF
(alloc-limit! 300000000)
(import x/tool/pin)
(display (Pin verify "$_TMP/proj7/deps"))
EOF
$TIMEOUT_CMD sh "$WRAPPER" --no-pin -f "$_TMP/stale3.x" >"$_TMP/out" 2>"$_TMP/err"
status=$?
[ "$status" -ne 0 ] || fail "stale: orphan left in the overlay verified clean" "$_TMP/out" "$_TMP/err"
grep -q "unlisted: acme/tail.x" "$_TMP/out" "$_TMP/err" \
  || fail "stale: orphan not reported as unlisted" "$_TMP/out" "$_TMP/err"

# fetch: a fake release over file:// -- verified or nothing.  The tiny
# artifact keeps the pure-x digest instant; the layout and vocabulary
# are exactly tools/release/release-manifest.sh's.
if command -v sha256sum >/dev/null 2>&1; then
  _dg() { sha256sum "$1" | awk '{print $1}'; }
else
  _dg() { shasum -a 256 "$1" | awk '{print $1}'; }
fi
mkdir -p "$_TMP/rel/v9.9.9-smoke"
printf '(def %%pin-smoke-fetched "tiny")\n' > "$_TMP/rel/v9.9.9-smoke/tiny.x"
{
  printf '(release "v9.9.9-smoke")\n'
  printf '(isa "sha256:%s")\n' "$(_dg engine/tools/contract/isa.x)"
  printf '(file "tiny.x" "sha256:%s")\n' "$(_dg "$_TMP/rel/v9.9.9-smoke/tiny.x")"
} > "$_TMP/rel/v9.9.9-smoke/pin.release.xon"
cat > "$_TMP/fetch.x" <<EOF
(alloc-limit! 300000000)
(import x/tool/pin)
(display (Pin fetch "$_TMP/fetched" "v9.9.9-smoke" 'tiny "file://$_TMP/rel"))
(newline)
EOF
$TIMEOUT_CMD sh "$WRAPPER" --no-pin -f "$_TMP/fetch.x" >"$_TMP/out" 2>"$_TMP/err"
status=$?
[ "$status" -eq 0 ] || fail "fetch run exited $status" "$_TMP/err" "$_TMP/out"
grep -q "fetched/tiny.x" "$_TMP/out" || fail "fetch: no verified-amalgam path in output" "$_TMP/out"
grep -q "isa fingerprint matches" "$_TMP/out" || fail "fetch: isa fingerprint report missing" "$_TMP/out"
cmp -s "$_TMP/rel/v9.9.9-smoke/tiny.x" "$_TMP/fetched/tiny.x" || fail "fetch: fetched bytes differ"

# fetch refuses a tampered artifact: bad digest in the manifest
mkdir -p "$_TMP/rel/v9.9.8-bad"
cp "$_TMP/rel/v9.9.9-smoke/tiny.x" "$_TMP/rel/v9.9.8-bad/tiny.x"
{
  printf '(release "v9.9.8-bad")\n'
  printf '(file "tiny.x" "sha256:%s")\n' "$(printf 'not-these-bytes' | _dg /dev/stdin)"
} > "$_TMP/rel/v9.9.8-bad/pin.release.xon"
cat > "$_TMP/fetch2.x" <<EOF
(alloc-limit! 300000000)
(import x/tool/pin)
(Pin fetch "$_TMP/fetched2" "v9.9.8-bad" 'tiny "file://$_TMP/rel")
EOF
$TIMEOUT_CMD sh "$WRAPPER" --no-pin -f "$_TMP/fetch2.x" >"$_TMP/out" 2>"$_TMP/err"
status=$?
[ "$status" -ne 0 ] || fail "fetch-tamper: mismatched digest fetched clean" "$_TMP/out" "$_TMP/err"
grep -q "digest mismatch" "$_TMP/out" "$_TMP/err" || fail "fetch-tamper: no digest-mismatch error" "$_TMP/out" "$_TMP/err"

# fetch survives a manifest with no (isa ...): the parser requires only the
# tag, so %pin-assoc hands back nil, and the fingerprint report used to
# compare against it -- dying AFTER the amalgam had verified clean.  Drift
# is information, not an error, and so is an absent fingerprint.
mkdir -p "$_TMP/rel/v9.9.7-noisa"
cp "$_TMP/rel/v9.9.9-smoke/tiny.x" "$_TMP/rel/v9.9.7-noisa/tiny.x"
{
  printf '(release "v9.9.7-noisa")\n'
  printf '(file "tiny.x" "sha256:%s")\n' "$(_dg "$_TMP/rel/v9.9.7-noisa/tiny.x")"
} > "$_TMP/rel/v9.9.7-noisa/pin.release.xon"
cat > "$_TMP/fetch3.x" <<EOF
(alloc-limit! 300000000)
(import x/tool/pin)
(display (Pin fetch "$_TMP/fetched3" "v9.9.7-noisa" 'tiny "file://$_TMP/rel"))
(newline)
EOF
$TIMEOUT_CMD sh "$WRAPPER" --no-pin -f "$_TMP/fetch3.x" >"$_TMP/out" 2>"$_TMP/err"
status=$?
[ "$status" -eq 0 ] || fail "fetch-noisa exited $status" "$_TMP/err" "$_TMP/out"
grep -q "fetched3/tiny.x" "$_TMP/out" || fail "fetch-noisa: no verified-amalgam path in output" "$_TMP/out"
grep -q "no isa fingerprint" "$_TMP/out" || fail "fetch-noisa: absent fingerprint not reported" "$_TMP/out"

# compose (GH #139): boot pin + overlay pin in ONE manifest, one run.
# The "amalgam" fixture is the repo entry copied out of the tree plus a
# marker def the real entry lacks -- its includes are cwd-relative, and
# the smoke runs from the repo root, so the copy boots; the marker
# proves the COPY booted, the overlay marker proves deps/ armed.
mkdir -p "$_TMP/proj4/boot" "$_TMP/proj4/deps/acme"
cp lib/x.x "$_TMP/proj4/boot/entry.x"
printf '(def %%pin-smoke-boot "custom")\n' >> "$_TMP/proj4/boot/entry.x"
cp "$_TMP/proj/deps/acme/util.x" "$_TMP/proj4/deps/acme/util.x"
cat > "$_TMP/proj4/pin.xon" <<'EOF'
; both tiers, one declaration
(root "deps")
(boot "boot/entry.x")
EOF
cat > "$_TMP/proj4/main.x" <<'EOF'
(alloc-limit! 300000000)
(import acme/util)
(display %pin-smoke-boot)
(newline)
(display acme-marker)
(newline)
EOF
$TIMEOUT_CMD sh "$WRAPPER" -f "$_TMP/proj4/main.x" >"$_TMP/out" 2>"$_TMP/err"
status=$?
[ "$status" -eq 0 ] || fail "compose run exited $status" "$_TMP/err" "$_TMP/out"
grep -qx "custom" "$_TMP/out" || fail "compose: the platform entry booted, not the pinned one" "$_TMP/out"
grep -qx "deps" "$_TMP/out" || fail "compose: overlay did not arm under the pinned boot" "$_TMP/out"
grep -q "^pinned: " "$_TMP/err" || fail "compose: no 'pinned:' notice" "$_TMP/err"
grep -q "^pinned boot: " "$_TMP/err" || fail "compose: no 'pinned boot:' notice" "$_TMP/err"

# --boot flag: overrides the manifest's (boot ...); overlay still arms
cp lib/x.x "$_TMP/proj4/boot/entry2.x"
printf '(def %%pin-smoke-boot "flag")\n' >> "$_TMP/proj4/boot/entry2.x"
$TIMEOUT_CMD sh "$WRAPPER" --boot "$_TMP/proj4/boot/entry2.x" -f "$_TMP/proj4/main.x" >"$_TMP/out" 2>"$_TMP/err"
status=$?
[ "$status" -eq 0 ] || fail "boot-flag run exited $status" "$_TMP/err" "$_TMP/out"
grep -qx "flag" "$_TMP/out" || fail "boot-flag: --boot did not override the manifest" "$_TMP/out"
grep -qx "deps" "$_TMP/out" || fail "boot-flag: overlay did not arm under --boot" "$_TMP/out"

# a missing boot entry fails loudly, never a silent platform fallback
mkdir -p "$_TMP/proj5"
cat > "$_TMP/proj5/pin.xon" <<'EOF'
(boot "boot/nope.x")
EOF
cat > "$_TMP/proj5/main.x" <<'EOF'
(display "should not run")
EOF
$TIMEOUT_CMD sh "$WRAPPER" -f "$_TMP/proj5/main.x" >"$_TMP/out" 2>"$_TMP/err"
status=$?
[ "$status" -ne 0 ] || fail "boot-gone: missing boot entry fell back silently" "$_TMP/out" "$_TMP/err"
grep -q "boot entry does not exist" "$_TMP/err" || fail "boot-gone: no boot-entry error" "$_TMP/err"

# a malformed (boot ...) never selects an entry (the probe wants one
# string on its own line); the LOADER's closed vocabulary rejects it
cat > "$_TMP/proj5/pin.xon" <<'EOF'
(boot 42)
EOF
$TIMEOUT_CMD sh "$WRAPPER" -f "$_TMP/proj5/main.x" >"$_TMP/out" 2>"$_TMP/err"
status=$?
[ "$status" -ne 0 ] || fail "boot-bad: malformed boot form was accepted" "$_TMP/out" "$_TMP/err"

# boot-quote: a boot path carrying shell metacharacters must stay a PATH.
# The wrapper builds its pipe as text and evals it, so an unquoted value
# here used to reach the shell as code -- with pin.xon documented as inert
# data (docs/modules.md "Pinning"), that made a manifest executable.  The
# marker file exists so the wrapper's -e gate passes and the value reaches
# the eval; a leaked metacharacter runs the payload, a quoted one does not.
# The payload has to be a FILENAME, so it can hold no slash -- it prints
# instead of writing a file.  Its output must also differ from its own
# source text, because the wrapper's `pinned boot:` notice echoes the path
# verbatim: `printf %s%s LE AK` emits LEAK while the path only ever reads
# "LE AK", so a grep for LEAK matches execution and nothing else.
mkdir -p "$_TMP/proj6"
_evil='q";printf %s%s LE AK >&2;"'
: > "$_TMP/proj6/$_evil"
printf '(boot "%s")\n' "$_evil" > "$_TMP/proj6/pin.xon"
printf '(display "ran")\n' > "$_TMP/proj6/main.x"
_no_exec() {
	grep -q "LEAK" "$_TMP/out" "$_TMP/err" \
		&& fail "boot-quote: $1" "$_TMP/err" "$_TMP/out"
	return 0
}
$TIMEOUT_CMD sh "$WRAPPER" -f "$_TMP/proj6/main.x" >"$_TMP/out" 2>"$_TMP/err"
_no_exec "manifest metacharacters reached the shell"
# Same through the flag, which bypasses the manifest entirely.
$TIMEOUT_CMD sh "$WRAPPER" --boot "$_TMP/proj6/$_evil" -f "$_TMP/proj6/main.x" \
	>"$_TMP/out" 2>"$_TMP/err"
_no_exec "--boot metacharacters reached the shell"
# And through a program path, which has no existence gate at all.
$TIMEOUT_CMD sh "$WRAPPER" --no-pin -f "$_TMP/proj6/$_evil" >"$_TMP/out" 2>"$_TMP/err"
_no_exec "-f metacharacters reached the shell"

# pin-quote: a manifest whose DIRECTORY holds a double quote is refused.
# pin_form emits that path as an x-lang string literal ahead of the boot
# entry, where a quote closes the literal and the rest becomes forms.
_qdir="$_TMP/pq\"dir"
mkdir -p "$_qdir"
printf '(root "deps")\n' > "$_qdir/pin.xon"
printf '(display "ran")\n' > "$_qdir/main.x"
$TIMEOUT_CMD sh "$WRAPPER" -f "$_qdir/main.x" >"$_TMP/out" 2>"$_TMP/err"
status=$?
[ "$status" -ne 0 ] || fail "pin-quote: a quoted manifest path was accepted" "$_TMP/out" "$_TMP/err"
grep -q "quote or backslash" "$_TMP/err" || fail "pin-quote: no refusal message" "$_TMP/err"

# pairing-guard: the wrapper's boot-time ISA refusal, both layouts.
# The guard arms only in INSTALLED mode (INSTALL_ROOT set), so no other
# in-repo gate exercises it -- which is exactly how v0.3.1-rc7 shipped a
# wrapper whose guard read a lockfile name that no longer exists and
# silently never fired.  A fake install tree suffices: the refusal runs
# BEFORE any engine boots, so no working library is needed.
_fake="$_TMP/fakeinstall"
mkdir -p "$_fake/bin" "$_fake/share/x/contract" "$_fake/share/x/lib" "$_fake/share/x/boot"
cp "$WRAPPER" "$_fake/bin/x"
printf 'aaaa1111\n' | tr -d '\n' > "$_fake/share/x/contract/isa.sha256"

# New layout: the lock is named for the root, beside the manifest.
mkdir -p "$_TMP/pair1/boot" "$_TMP/pair1/deps"
printf '(root "deps")\n(boot "boot/he.x")\n' > "$_TMP/pair1/pin.xon"
printf '; not a real amalgam -- never reached\n' > "$_TMP/pair1/boot/he.x"
printf '(isa "sha256:bbbb2222")\n' > "$_TMP/pair1/deps.lock.xon"
printf '(display "ran")\n' > "$_TMP/pair1/main.x"
(cd "$_TMP" && $TIMEOUT_CMD sh "$_fake/bin/x" -f "$_TMP/pair1/main.x") >"$_TMP/out" 2>"$_TMP/err"
status=$?
[ "$status" -ne 0 ] || fail "pairing-guard: a mismatched lock fingerprint was accepted (new layout)" "$_TMP/out" "$_TMP/err"
grep -q "different engine" "$_TMP/err" || fail "pairing-guard: no refusal message (new layout)" "$_TMP/err"

# Old layout: pin.release.xon beside the amalgam (bare Pin fetch keeps it).
mkdir -p "$_TMP/pair2/boot"
printf '(boot "boot/he.x")\n' > "$_TMP/pair2/pin.xon"
printf '; not a real amalgam -- never reached\n' > "$_TMP/pair2/boot/he.x"
printf '(release "v9.9.9")\n(isa "sha256:cccc3333")\n' > "$_TMP/pair2/boot/pin.release.xon"
printf '(display "ran")\n' > "$_TMP/pair2/main.x"
(cd "$_TMP" && $TIMEOUT_CMD sh "$_fake/bin/x" -f "$_TMP/pair2/main.x") >"$_TMP/out" 2>"$_TMP/err"
status=$?
[ "$status" -ne 0 ] || fail "pairing-guard: a mismatched release fingerprint was accepted (old layout)" "$_TMP/out" "$_TMP/err"
grep -q "different engine" "$_TMP/err" || fail "pairing-guard: no refusal message (old layout)" "$_TMP/err"

# Matched fingerprints must NOT refuse (the boot then fails later on the
# fake tree, which is fine -- the assertion is only about the guard).
printf '(isa "sha256:aaaa1111")\n' > "$_TMP/pair1/deps.lock.xon"
(cd "$_TMP" && $TIMEOUT_CMD sh "$_fake/bin/x" -f "$_TMP/pair1/main.x") >"$_TMP/out" 2>"$_TMP/err" || true
grep -q "different engine" "$_TMP/err" && fail "pairing-guard: matched fingerprints were refused" "$_TMP/err"

# Root order must not matter (#313): the lock is named for ITS root, and
# the guard tries every manifest root -- reading only the first meant an
# unrelated reorder orphaned the lock and the guard skipped silently.
mkdir -p "$_TMP/pair3/boot" "$_TMP/pair3/deps"
printf '(root ".")\n(root "deps")\n(boot "boot/he.x")\n' > "$_TMP/pair3/pin.xon"
printf '; not a real amalgam -- never reached\n' > "$_TMP/pair3/boot/he.x"
printf '(isa "sha256:bbbb2222")\n' > "$_TMP/pair3/deps.lock.xon"
printf '(display "ran")\n' > "$_TMP/pair3/main.x"
(cd "$_TMP" && $TIMEOUT_CMD sh "$_fake/bin/x" -f "$_TMP/pair3/main.x") >"$_TMP/out" 2>"$_TMP/err"
status=$?
[ "$status" -ne 0 ] || fail "pairing-guard: a reordered root orphaned the lock (#313)" "$_TMP/out" "$_TMP/err"
grep -q "different engine" "$_TMP/err" || fail "pairing-guard: no refusal after root reorder (#313)" "$_TMP/err"

# An armed boot pin with NO findable lock says so (#313): the guard must
# never disappear without a word.
mkdir -p "$_TMP/pair4/boot"
printf '(root "deps")\n(boot "boot/he.x")\n' > "$_TMP/pair4/pin.xon"
printf '; not a real amalgam -- never reached\n' > "$_TMP/pair4/boot/he.x"
printf '(display "ran")\n' > "$_TMP/pair4/main.x"
(cd "$_TMP" && $TIMEOUT_CMD sh "$_fake/bin/x" -f "$_TMP/pair4/main.x") >"$_TMP/out" 2>"$_TMP/err" || true
grep -q "engine pairing unchecked" "$_TMP/err" || fail "pairing-guard: lockless armed pin skipped WITHOUT the unchecked notice (#313)" "$_TMP/err"

# A lock that EXISTS but yields no fingerprint (corrupt, truncated) is
# the same disappearing-guard shape -- it must say so too.
mkdir -p "$_TMP/pair5/boot"
printf '(root "deps")\n(boot "boot/he.x")\n' > "$_TMP/pair5/pin.xon"
printf '; not a real amalgam -- never reached\n' > "$_TMP/pair5/boot/he.x"
printf 'total garbage, no isa line\n' > "$_TMP/pair5/deps.lock.xon"
printf '(display "ran")\n' > "$_TMP/pair5/main.x"
(cd "$_TMP" && $TIMEOUT_CMD sh "$_fake/bin/x" -f "$_TMP/pair5/main.x") >"$_TMP/out" 2>"$_TMP/err" || true
grep -q "no isa fingerprint readable" "$_TMP/err" || fail "pairing-guard: corrupt lock skipped WITHOUT the unchecked notice" "$_TMP/err"

# release-guard (#435): the pairing refusal the ISA fingerprint cannot
# make.  isa.x is the C surface and is byte-identical across v0.3.1-rc10,
# v0.4.0 and v0.5.0 -- so the guard above passed an rc10 amalgam onto a
# v0.4.0 engine and the boot died on a dereferenced string, no diagnosis.
# The release TAG is the key that cannot under-approximate, and every leg
# below keeps the isa fingerprints MATCHED so the refusal under test is
# unambiguously the release one.
_fake2="$_TMP/fakeinstall2"
mkdir -p "$_fake2/bin" "$_fake2/share/x/contract" "$_fake2/share/x/lib" "$_fake2/share/x/boot"
cp "$WRAPPER" "$_fake2/bin/x"
printf 'aaaa1111\n' | tr -d '\n' > "$_fake2/share/x/contract/isa.sha256"
printf 'v9.9.9-rel\n' > "$_fake2/share/x/contract/release"

# dir, the lock's release tag ("" for a lock that predates #435), and
# "skew" to put the manifest's own waiver in.  The isa row is always the
# fake engine's, so nothing here can be refused for the older reason.
_rel_proj() {
	mkdir -p "$_TMP/$1/boot" "$_TMP/$1/deps"
	printf '(root "deps")\n(boot "boot/he.x")\n' > "$_TMP/$1/pin.xon"
	[ "${3:-}" = skew ] && printf '(allow-release-skew)\n' >> "$_TMP/$1/pin.xon"
	printf '; not a real amalgam -- never reached\n' > "$_TMP/$1/boot/he.x"
	: > "$_TMP/$1/deps.lock.xon"
	[ -n "$2" ] && printf '(release "%s")\n' "$2" >> "$_TMP/$1/deps.lock.xon"
	printf '(isa "sha256:aaaa1111")\n' >> "$_TMP/$1/deps.lock.xon"
	printf '(display "ran")\n' > "$_TMP/$1/main.x"
	return 0
}

# Different release, matching isa: refused, and the message names both.
_rel_proj rel1 v9.9.8-old
(cd "$_TMP" && $TIMEOUT_CMD sh "$_fake2/bin/x" -f "$_TMP/rel1/main.x") >"$_TMP/out" 2>"$_TMP/err"
status=$?
[ "$status" -ne 0 ] || fail "release-guard: a skewed release was accepted" "$_TMP/out" "$_TMP/err"
grep -q "different release" "$_TMP/err" || fail "release-guard: no refusal message" "$_TMP/err"
grep -q "v9.9.8-old" "$_TMP/err" || fail "release-guard: refusal does not name the amalgam's release" "$_TMP/err"
grep -q "v9.9.9-rel" "$_TMP/err" || fail "release-guard: refusal does not name the engine's release" "$_TMP/err"

# --allow-release-skew waives it -- loudly.  A silent waiver would be a
# guard that can be turned off without leaving a trace in the output.
(cd "$_TMP" && $TIMEOUT_CMD sh "$_fake2/bin/x" --allow-release-skew -f "$_TMP/rel1/main.x") >"$_TMP/out" 2>"$_TMP/err" || true
grep -q "different release" "$_TMP/err" && fail "release-guard: --allow-release-skew did not waive the refusal" "$_TMP/err"
grep -q "release skew allowed" "$_TMP/err" || fail "release-guard: --allow-release-skew waived SILENTLY" "$_TMP/err"

# A LOCALLY BUILT engine must not be told to move the pin onto itself:
# `Pin boot` fetches the tag it is given, and `git describe` answers for
# a local build name no published release.  The remedy has to differ.
printf 'v9.9.9-12-gabcdef1\n' > "$_fake2/share/x/contract/release"
(cd "$_TMP" && $TIMEOUT_CMD sh "$_fake2/bin/x" -f "$_TMP/rel1/main.x") >"$_TMP/out" 2>"$_TMP/err"
status=$?
[ "$status" -ne 0 ] || fail "release-guard: a skewed local build was accepted" "$_TMP/out" "$_TMP/err"
grep -q "local build" "$_TMP/err" || fail "release-guard: a local build was told to move the pin onto itself" "$_TMP/err"
grep -q "Pin boot" "$_TMP/err" && fail "release-guard: a local build was offered an unfetchable (Pin boot) remedy" "$_TMP/err"
printf 'v9.9.9-rel\n' > "$_fake2/share/x/contract/release"

# The manifest form is the same waiver, made once for the project.
_rel_proj rel2 v9.9.8-old skew
(cd "$_TMP" && $TIMEOUT_CMD sh "$_fake2/bin/x" -f "$_TMP/rel2/main.x") >"$_TMP/out" 2>"$_TMP/err" || true
grep -q "different release" "$_TMP/err" && fail "release-guard: (allow-release-skew) did not waive the refusal" "$_TMP/err"
grep -q "release skew allowed" "$_TMP/err" || fail "release-guard: (allow-release-skew) waived SILENTLY" "$_TMP/err"

# Same release: no refusal (the fake tree fails to boot afterwards, which
# is fine -- the assertion is only about the guard).
_rel_proj rel3 v9.9.9-rel
(cd "$_TMP" && $TIMEOUT_CMD sh "$_fake2/bin/x" -f "$_TMP/rel3/main.x") >"$_TMP/out" 2>"$_TMP/err" || true
grep -q "different release" "$_TMP/err" && fail "release-guard: a matched release was refused" "$_TMP/err"

# --- THE ENGINE'S RELEASE, a separate subject (the arc's phase 5) -----------
# The rows above are the LIBRARY's release.  This one names the engine build a
# project was verified against, and the two have been different strings since
# x-engine-c got a version line of its own.  The fake tree stamps both, so a
# skew in one cannot be mistaken for a skew in the other.
printf 'eng-v0.1.0\n' > "$_fake2/share/x/contract/engine-release"

_eng_proj() {  # _eng_proj <dir> <engine-release in the lock>
	_rel_proj "$1" v9.9.9-rel
	[ -n "$2" ] && printf '(engine-release "%s")\n' "$2" >> "$_TMP/$1/deps.lock.xon"
	return 0
}

# A different engine build: refused, naming both sides.
_eng_proj eng1 eng-v0.0.9
(cd "$_TMP" && $TIMEOUT_CMD sh "$_fake2/bin/x" -f "$_TMP/eng1/main.x") >"$_TMP/out" 2>"$_TMP/err"
status=$?
[ "$status" -ne 0 ] || fail "engine-guard: a skewed engine release was accepted" "$_TMP/out" "$_TMP/err"
grep -q "different engine build" "$_TMP/err" || fail "engine-guard: no refusal message" "$_TMP/err"
grep -q "eng-v0.0.9" "$_TMP/err" || fail "engine-guard: refusal does not name what the amalgam was verified against" "$_TMP/err"
grep -q "eng-v0.1.0" "$_TMP/err" || fail "engine-guard: refusal does not name the installed engine" "$_TMP/err"

# It is the ENGINE's row that refused, not the library's -- the two subjects
# must not be reachable through each other's message.
grep -q "different release" "$_TMP/err" && fail "engine-guard: an engine skew was reported as a library skew" "$_TMP/err"

# Waived like the library's, and just as loudly.
(cd "$_TMP" && $TIMEOUT_CMD sh "$_fake2/bin/x" --allow-release-skew -f "$_TMP/eng1/main.x") >"$_TMP/out" 2>"$_TMP/err" || true
grep -q "different engine build" "$_TMP/err" && fail "engine-guard: --allow-release-skew did not waive it" "$_TMP/err"
grep -q "engine skew allowed" "$_TMP/err" || fail "engine-guard: the waiver was SILENT" "$_TMP/err"

# Matching engine: no refusal.
_eng_proj eng2 eng-v0.1.0
(cd "$_TMP" && $TIMEOUT_CMD sh "$_fake2/bin/x" -f "$_TMP/eng2/main.x") >"$_TMP/out" 2>"$_TMP/err" || true
grep -q "different engine build" "$_TMP/err" && fail "engine-guard: a matched engine was refused" "$_TMP/err"

# A lock with no engine-release row -- every lock written before phase 5 --
# must still boot.  Older locks state no such fact and inventing one would
# unpin every project in the wild.
_eng_proj eng3 ""
(cd "$_TMP" && $TIMEOUT_CMD sh "$_fake2/bin/x" -f "$_TMP/eng3/main.x") >"$_TMP/out" 2>"$_TMP/err" || true
grep -q "different engine build" "$_TMP/err" && fail "engine-guard: a lock predating the row was refused" "$_TMP/err"

# A lock that NAMES an engine against a tree that cannot answer: announce,
# never assume.  A guard that disappears without a word is the #313 shape.
mv "$_fake2/share/x/contract/engine-release" "$_fake2/share/x/contract/engine-release.away"
(cd "$_TMP" && $TIMEOUT_CMD sh "$_fake2/bin/x" -f "$_TMP/eng2/main.x") >"$_TMP/out" 2>"$_TMP/err" || true
grep -q "no engine stamp" "$_TMP/err" || fail "engine-guard: an unanswerable pairing passed in silence" "$_TMP/err"
mv "$_fake2/share/x/contract/engine-release.away" "$_fake2/share/x/contract/engine-release"

# --- REACH FOR THE RELEASE (#499): before refusing a library skew, the
# --- wrapper hands the invocation to a cached copy of the release the
# --- lock names -- fetching it, verified, when told to.  The pin knows
# --- what it needs and where to get it; blocking was the bug.  Every
# --- leg passes </dev/null so the consent prompt can never engage.
_cos=$(uname -s | tr 'A-Z' 'a-z')
_carch=$(uname -m)
_cacheroot="$_TMP/cache"
_cname="x-v9.9.8-old-${_cos}-${_carch}"

# A fake cached release: its bin/x only proves it was handed the call.
mkdir -p "$_cacheroot/$_cname/x-v9.9.8-old/bin"
cat > "$_cacheroot/$_cname/x-v9.9.8-old/bin/x" <<'EOF'
#!/bin/sh
echo "CACHED-RELEASE-RAN $@"
exit 0
EOF
chmod +x "$_cacheroot/$_cname/x-v9.9.8-old/bin/x"

# Cache hit: the skewed install hands over instead of refusing, announces
# the handover, and the original argv arrives intact.
_rel_proj reach1 v9.9.8-old
(cd "$_TMP" && $TIMEOUT_CMD env X_RELEASE_CACHE="$_cacheroot" sh "$_fake2/bin/x" -f "$_TMP/reach1/main.x" </dev/null) >"$_TMP/out" 2>"$_TMP/err"
status=$?
[ "$status" -eq 0 ] || fail "reach: cache hit still failed" "$_TMP/err" "$_TMP/out"
grep -q "CACHED-RELEASE-RAN" "$_TMP/out" || fail "reach: cached release was not handed the call" "$_TMP/out" "$_TMP/err"
grep -q "reach1/main.x" "$_TMP/out" || fail "reach: original argv did not arrive" "$_TMP/out"
grep -q "handing over to the pinned v9.9.8-old release" "$_TMP/err" || fail "reach: the handover was silent" "$_TMP/err"

# Loop guard: a cached tree that still mismatches refuses, never recurses.
(cd "$_TMP" && $TIMEOUT_CMD env X_RELEASE_CACHE="$_cacheroot" X_PIN_REEXEC=1 sh "$_fake2/bin/x" -f "$_TMP/reach1/main.x" </dev/null) >"$_TMP/out" 2>"$_TMP/err"
status=$?
[ "$status" -ne 0 ] || fail "reach: re-entry did not fall back to the refusal" "$_TMP/out" "$_TMP/err"
grep -q "different release" "$_TMP/err" || fail "reach: re-entry lost the refusal" "$_TMP/err"

# --allow-release-skew means "run THIS install": no handover, loud waiver.
(cd "$_TMP" && $TIMEOUT_CMD env X_RELEASE_CACHE="$_cacheroot" sh "$_fake2/bin/x" --allow-release-skew -f "$_TMP/reach1/main.x" </dev/null) >"$_TMP/out" 2>"$_TMP/err" || true
grep -q "CACHED-RELEASE-RAN" "$_TMP/out" && fail "reach: --allow-release-skew still handed over" "$_TMP/out"
grep -q "release skew allowed" "$_TMP/err" || fail "reach: skew waiver lost" "$_TMP/err"

# Empty cache, no consent possible (no tty): the refusal stands and now
# names the flag that would have resolved it.
(cd "$_TMP" && $TIMEOUT_CMD env X_RELEASE_CACHE="$_TMP/cache-empty" sh "$_fake2/bin/x" -f "$_TMP/reach1/main.x" </dev/null) >"$_TMP/out" 2>"$_TMP/err"
status=$?
[ "$status" -ne 0 ] || fail "reach: empty cache was accepted" "$_TMP/out" "$_TMP/err"
grep -q "fetch-release" "$_TMP/err" || fail "reach: refusal does not name --fetch-release" "$_TMP/err"

# --fetch-release against a local mirror (file://, fetch's sanctioned
# override): verified, unpacked, handed over -- and the cache survives.
_mirror="$_TMP/mirror/v9.9.7-mir"
mkdir -p "$_mirror" "$_TMP/mirror-stage/x-v9.9.7-mir/bin"
cat > "$_TMP/mirror-stage/x-v9.9.7-mir/bin/x" <<'EOF'
#!/bin/sh
# A released wrapper predating the flag refuses it -- the handover must
# not forward its own instruction (found live against v0.5.1).
for _a in "$@"; do
	[ "$_a" = "--fetch-release" ] && { echo "Error: Unknown option: $_a" >&2; exit 1; }
done
echo "FETCHED-RELEASE-RAN"
exit 0
EOF
chmod +x "$_TMP/mirror-stage/x-v9.9.7-mir/bin/x"
_mname="x-v9.9.7-mir-${_cos}-${_carch}"
(cd "$_TMP/mirror-stage" && tar -czf "$_mirror/$_mname.tar.gz" "x-v9.9.7-mir")
(cd "$_mirror" && { command -v sha256sum >/dev/null 2>&1 && sha256sum "$_mname.tar.gz" || shasum -a 256 "$_mname.tar.gz"; } > "$_mname.tar.gz.sha256")
_rel_proj reach2 v9.9.7-mir
(cd "$_TMP" && $TIMEOUT_CMD env X_RELEASE_CACHE="$_TMP/cache2" X_RELEASE_BASE="file://$_TMP/mirror" sh "$_fake2/bin/x" --fetch-release -f "$_TMP/reach2/main.x" </dev/null) >"$_TMP/out" 2>"$_TMP/err"
status=$?
[ "$status" -eq 0 ] || fail "reach: fetch-release failed" "$_TMP/err" "$_TMP/out"
grep -q "FETCHED-RELEASE-RAN" "$_TMP/out" || fail "reach: fetched release was not handed the call" "$_TMP/out" "$_TMP/err"
[ -x "$_TMP/cache2/$_mname/x-v9.9.7-mir/bin/x" ] || fail "reach: fetch did not populate the cache" "$_TMP/err"

# A tampered artifact publishes NOTHING: refusal, and no bytes land in
# the cache where a later boot would trust them (#145).
_mirror2="$_TMP/mirror/v9.9.6-bad"
mkdir -p "$_mirror2"
_bname="x-v9.9.6-bad-${_cos}-${_carch}"
cp "$_mirror/$_mname.tar.gz" "$_mirror2/$_bname.tar.gz"
printf 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef  %s\n' "$_bname.tar.gz" > "$_mirror2/$_bname.tar.gz.sha256"
_rel_proj reach3 v9.9.6-bad
(cd "$_TMP" && $TIMEOUT_CMD env X_RELEASE_CACHE="$_TMP/cache3" X_RELEASE_BASE="file://$_TMP/mirror" sh "$_fake2/bin/x" --fetch-release -f "$_TMP/reach3/main.x" </dev/null) >"$_TMP/out" 2>"$_TMP/err"
status=$?
[ "$status" -ne 0 ] || fail "reach: a tampered artifact was accepted" "$_TMP/out" "$_TMP/err"
grep -q "digest mismatch" "$_TMP/err" || fail "reach: tamper refusal not named" "$_TMP/err"
[ ! -e "$_TMP/cache3/$_bname/x-v9.9.6-bad/bin/x" ] || fail "reach: rejected bytes landed in the cache (#145)" "$_TMP/err"

# A lock with no (release ...) row -- every lock written before #435 --
# cannot be checked, and says so rather than passing quietly.
_rel_proj rel4 ""
(cd "$_TMP" && $TIMEOUT_CMD sh "$_fake2/bin/x" -f "$_TMP/rel4/main.x") >"$_TMP/out" 2>"$_TMP/err" || true
grep -q "no release tag readable" "$_TMP/err" || fail "release-guard: a release-less lock skipped WITHOUT the unchecked notice" "$_TMP/err"

# An install tree with no stamp -- an engine older than #435 under a newer
# wrapper -- is the same disappearing guard, and says so too.
_rel_proj rel5 v9.9.8-old
(cd "$_TMP" && $TIMEOUT_CMD sh "$_fake/bin/x" -f "$_TMP/rel5/main.x") >"$_TMP/out" 2>"$_TMP/err" || true
grep -q "carries no release stamp" "$_TMP/err" || fail "release-guard: an unstamped engine skipped WITHOUT the unchecked notice" "$_TMP/err"

# A corrupt MANIFEST names itself before anything boots -- it used to
# surface as a bare mid-boot "Unterminated input" naming nothing.
mkdir -p "$_TMP/badman"
printf 'this is (((not xon\n' > "$_TMP/badman/pin.xon"
printf '(display "ran")\n' > "$_TMP/badman/main.x"
$TIMEOUT_CMD sh "$WRAPPER" -f "$_TMP/badman/main.x" >"$_TMP/out" 2>"$_TMP/err"
status=$?
[ "$status" -ne 0 ] || fail "manifest: a corrupt manifest was accepted" "$_TMP/out" "$_TMP/err"
grep -q "unreadable manifest" "$_TMP/err" || fail "manifest: corrupt manifest not named" "$_TMP/err"

# An EMPTY manifest arms nothing and says so (instead of announcing
# "pinned:" over a blank file).
mkdir -p "$_TMP/emptyman"
: > "$_TMP/emptyman/pin.xon"
printf '(display "ran")\n' > "$_TMP/emptyman/main.x"
$TIMEOUT_CMD sh "$WRAPPER" -f "$_TMP/emptyman/main.x" >"$_TMP/out" 2>"$_TMP/err" || true
grep -q "nothing armed" "$_TMP/err" || fail "manifest: empty manifest armed silently" "$_TMP/err"

# --- The boot-pin lifecycle, offline (#145): fetch publishes verified
# --- bytes or nothing, upgrade preserves the pin on failure, and verify
# --- re-checks the platform half.  file:// is fetch's sanctioned
# --- mirror override; fixture amalgams are tiny, so digests are pure-x
# --- milliseconds (under the JIT threshold).
_sha() {
	if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
	else shasum -a 256 "$1" | awk '{print $1}'; fi
}
mkdir -p "$_TMP/rel/v9.9.9" "$_TMP/rel/v9.9.8" "$_TMP/proj/boot" "$_TMP/proj/deps"
printf '; v1 amalgam\n(display 1)\n' > "$_TMP/rel/v9.9.9/he.x"
printf '(release "v9.9.9")\n(isa "sha256:aaaa1111")\n(engine-release "eng-v9.1.2")\n(payload "sha256:eeee5555")\n(file "he.x" "sha256:%s")\n' \
	"$(_sha "$_TMP/rel/v9.9.9/he.x")" > "$_TMP/rel/v9.9.9/pin.release.xon"
printf '; v2 amalgam, manifest digest WRONG\n(display 2)\n' > "$_TMP/rel/v9.9.8/he.x"
printf '(release "v9.9.8")\n(isa "sha256:bbbb2222")\n(file "he.x" "sha256:%064d")\n' 0 \
	> "$_TMP/rel/v9.9.8/pin.release.xon"
printf '(root "deps")\n(src ".")\n(boot "boot/he.x")\n' > "$_TMP/proj/pin.xon"

# Good pin: amalgam installed, lock carries the tag, header names the
# lock's REAL file (#421).
cat > "$_TMP/boot1.x" <<EOF
(import x/tool/pin)
(Pin boot "v9.9.9" "$_TMP/proj" "file://$_TMP/rel")
EOF
$TIMEOUT_CMD sh "$WRAPPER" --no-pin -q -f "$_TMP/boot1.x" >"$_TMP/out" 2>"$_TMP/err" \
	|| fail "boot-pin: good offline pin failed" "$_TMP/out" "$_TMP/err"
grep -q '; v1 amalgam' "$_TMP/proj/boot/he.x" || fail "boot-pin: amalgam not installed" "$_TMP/out"
grep -q '(release "v9.9.9")' "$_TMP/proj/deps.lock.xon" || fail "boot-pin: lock has no release tag" "$_TMP/out"
head -1 "$_TMP/proj/deps.lock.xon" | grep -q 'deps.lock.xon' || fail "boot-pin: lock header does not name the lock (#421)" "$_TMP/proj/deps.lock.xon"
grep -q '(payload "sha256:eeee5555")' "$_TMP/proj/deps.lock.xon" || fail "boot-pin: lock did not lift the release's payload fingerprint (#435)" "$_TMP/proj/deps.lock.xon"
# The MANIFEST carried the engine row this time -- the row the v0.5.0
# release shipped and the parser refused as an unknown form.  Reaching
# here at all proves the parse; the grep proves the lift.
grep -q '(engine-release "eng-v9.1.2")' "$_TMP/proj/deps.lock.xon" || fail "boot-pin: lock did not lift the release's engine-release row" "$_TMP/proj/deps.lock.xon"

# ...and a release that published NO payload row -- every release before
# #435 -- must still pin, leaving no payload line rather than a nil one
# that would match nothing forever.
mkdir -p "$_TMP/rel/v9.9.6" "$_TMP/proj6/boot" "$_TMP/proj6/deps"
cp "$_TMP/rel/v9.9.9/he.x" "$_TMP/rel/v9.9.6/he.x"
printf '(release "v9.9.6")\n(isa "sha256:aaaa1111")\n(file "he.x" "sha256:%s")\n' \
	"$(_sha "$_TMP/rel/v9.9.6/he.x")" > "$_TMP/rel/v9.9.6/pin.release.xon"
printf '(root "deps")\n(src ".")\n(boot "boot/he.x")\n' > "$_TMP/proj6/pin.xon"
cat > "$_TMP/boot6.x" <<EOF
(import x/tool/pin)
(Pin boot "v9.9.6" "$_TMP/proj6" "file://$_TMP/rel")
EOF
$TIMEOUT_CMD sh "$WRAPPER" --no-pin -q -f "$_TMP/boot6.x" >"$_TMP/out" 2>"$_TMP/err" \
	|| fail "boot-pin: a payload-less release failed to pin (#435)" "$_TMP/out" "$_TMP/err"
grep -q '(release "v9.9.6")' "$_TMP/proj6/deps.lock.xon" || fail "boot-pin: payload-less pin wrote no release tag" "$_TMP/proj6/deps.lock.xon"
grep -q '(payload' "$_TMP/proj6/deps.lock.xon" && fail "boot-pin: payload-less release left a payload row in the lock" "$_TMP/proj6/deps.lock.xon"
grep -q '(engine-release' "$_TMP/proj6/deps.lock.xon" && fail "boot-pin: engine-less release left an engine-release row in the lock" "$_TMP/proj6/deps.lock.xon"

# Failed UPGRADE: loud, and NOTHING moves -- the pinned amalgam, the
# lock, both untouched; the rejected bytes are quarantined beside them.
cat > "$_TMP/boot2.x" <<EOF
(import x/tool/pin)
(Pin boot "v9.9.8" "$_TMP/proj" "file://$_TMP/rel")
EOF
$TIMEOUT_CMD sh "$WRAPPER" --no-pin -q -f "$_TMP/boot2.x" >"$_TMP/out" 2>"$_TMP/err"
grep -q "digest mismatch" "$_TMP/out" "$_TMP/err" || fail "boot-pin: bad upgrade did not refuse (#145)" "$_TMP/out" "$_TMP/err"
grep -q '; v1 amalgam' "$_TMP/proj/boot/he.x" || fail "boot-pin: bad upgrade CLOBBERED the pinned amalgam (#145)" "$_TMP/proj/boot/he.x"
grep -q '(release "v9.9.9")' "$_TMP/proj/deps.lock.xon" || fail "boot-pin: bad upgrade moved the lock (#145)" "$_TMP/proj/deps.lock.xon"
[ -f "$_TMP/proj/boot/he.x.rejected" ] || fail "boot-pin: rejected bytes not quarantined" "$_TMP/out"

# Verify covers the platform half: a tampered amalgam fails verify by
# name; restoring it passes again.
cat > "$_TMP/ver.x" <<EOF
(import x/tool/pin)
(display (Pin verify "$_TMP/proj/deps")) (newline)
EOF
printf '; TAMPER\n' >> "$_TMP/proj/boot/he.x"
$TIMEOUT_CMD sh "$WRAPPER" --no-pin -q -f "$_TMP/ver.x" >"$_TMP/out" 2>"$_TMP/err"
grep -q "pinned boot amalgam digest mismatch" "$_TMP/out" "$_TMP/err" || fail "verify: tampered amalgam not caught (#145)" "$_TMP/out" "$_TMP/err"
cp "$_TMP/rel/v9.9.9/he.x" "$_TMP/proj/boot/he.x"
$TIMEOUT_CMD sh "$WRAPPER" --no-pin -q -f "$_TMP/ver.x" >"$_TMP/out" 2>"$_TMP/err"
grep -q "digest mismatch" "$_TMP/out" "$_TMP/err" && fail "verify: restored amalgam still failing" "$_TMP/out" "$_TMP/err"


# The lock-root chooser (#313's WRITE side): a "."-first manifest must
# never produce "..lock.xon" -- boot picks the root whose lock already
# exists (an upgrade rewrites it), else the first directory-named root.
# Observed pre-fix: an upgrade against a "."-first manifest wrote
# ..lock.xon and left the real lock stale -- silent version skew.
mkdir -p "$_TMP/proj9/boot" "$_TMP/proj9/deps"
printf '(root ".")\n(root "deps")\n(src ".")\n(boot "boot/he.x")\n' > "$_TMP/proj9/pin.xon"
{
	echo '(import x/tool/pin)'
	echo "(Pin boot \"v9.9.9\" \"$_TMP/proj9\" \"file://$_TMP/rel\")"
} > "$_TMP/boot3.x"
$TIMEOUT_CMD sh "$WRAPPER" --no-pin -q -f "$_TMP/boot3.x" >"$_TMP/out" 2>"$_TMP/err" \
	|| fail "lock-root: dot-first pin failed" "$_TMP/out" "$_TMP/err"
[ ! -f "$_TMP/proj9/..lock.xon" ] || fail "lock-root: wrote ..lock.xon (#313 write side)" "$_TMP/out"
grep -q '(release "v9.9.9")' "$_TMP/proj9/deps.lock.xon" || fail "lock-root: lock not at the directory root" "$_TMP/out"
# Upgrade rewrites the EXISTING lock, wherever it is.
sed 's/v9.9.9/v9.9.7/' "$_TMP/proj9/deps.lock.xon" > "$_TMP/proj9/deps.lock.xon.new" \
	&& mv "$_TMP/proj9/deps.lock.xon.new" "$_TMP/proj9/deps.lock.xon"
$TIMEOUT_CMD sh "$WRAPPER" --no-pin -q -f "$_TMP/boot3.x" >"$_TMP/out" 2>"$_TMP/err" \
	|| fail "lock-root: re-pin failed" "$_TMP/out" "$_TMP/err"
grep -q '(release "v9.9.9")' "$_TMP/proj9/deps.lock.xon" || fail "lock-root: upgrade did not rewrite the existing lock" "$_TMP/proj9/deps.lock.xon"

echo "pin-smoke: ok"
