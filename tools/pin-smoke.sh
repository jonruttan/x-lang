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
# (The pinned REPL path is tty-side -- the fd-3 class check-examples.sh
# documents -- and is not smokeable here; it shares every pipe stage but
# the final launch.x with the -f path exercised below.)
set -u

cd "$(dirname "$0")/.." || exit 1
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

# fetch: a fake release over file:// -- verified or nothing.  The tiny
# artifact keeps the pure-x digest instant; the layout and vocabulary
# are exactly tools/release-manifest.sh's.
if command -v sha256sum >/dev/null 2>&1; then
  _dg() { sha256sum "$1" | awk '{print $1}'; }
else
  _dg() { shasum -a 256 "$1" | awk '{print $1}'; }
fi
mkdir -p "$_TMP/rel/v9.9.9-smoke"
printf '(def %%pin-smoke-fetched "tiny")\n' > "$_TMP/rel/v9.9.9-smoke/tiny.x"
{
  printf '(release "v9.9.9-smoke")\n'
  printf '(isa "sha256:%s")\n' "$(_dg tools/isa.x)"
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

echo "pin-smoke: ok"
