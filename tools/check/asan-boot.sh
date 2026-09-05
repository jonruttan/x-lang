#!/bin/sh
# asan-boot.sh -- boot every dialect on an AddressSanitizer engine.
#
# THE FAILURE IT EXISTS FOR reaches CI and nowhere else.  The engine has no
# auto-GC and a precise collector: an object referenced only from a C frame is
# garbage the moment anything collects, and nothing notices until the freed
# cell is REUSED.  glibc reuses a freed cell at once; macOS's allocator mostly
# leaves it intact for a while.  So a use-after-free that the tower's boot
# commits on every machine crashed only on x86-64 Linux, and only when the
# heap happened to land so that the cell was recycled in time -- green on the
# desk, red in CI, and which PR went red depended on what the engine release
# had shuffled (x-lang#614, x-engine-c fix/load-roots).  Every one of those
# runs had been "verified locally".  The local verification could not have
# seen it.
#
# ADDRESSSANITIZER MAKES THE LUCK IRRELEVANT.  It quarantines freed memory
# and traps the read, on any allocator, on any OS, with a stack.  The unfixed
# engine aborts under ASan on this machine the first time a boot collects
# inside an include.  So this gate boots each dialect on an ASan build of the
# PINNED engine -- the sources fetch.sh clones at the pin's release tag -- and
# asks only that the boot finishes and the probe prints.  It is the one
# check here that turns "layout luck" into a verdict before push.
#
# WHAT IT COSTS.  First run clones the pinned sources and builds x-bin-asan
# (~1 min); after that the build is reused for as long as the pin stands.  The
# boots are COLD by construction (see below), so the tower compiles every unit
# under ASan each time: a few minutes for the three dialects, not seconds.  Too
# slow for gates-fast's sub-minute budget, so it rides test-fast and gates,
# where the pre-push hook and CI already spend minutes.
#
# X_ASAN_DIALECTS narrows the run (default: he xe rn).  X_ASAN_BIN points at
# an ASan engine already built elsewhere, skipping the clone and build.
set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

DIALECTS="${X_ASAN_DIALECTS:-he xe rn}"

# --- the engine ----------------------------------------------------------------
if [ -n "${X_ASAN_BIN:-}" ]; then
	ASAN_BIN="$X_ASAN_BIN"
	[ -x "$ASAN_BIN" ] || { echo "asan-boot: X_ASAN_BIN names no executable: $ASAN_BIN" >&2; exit 2; }
else
	# The pinned release's SOURCES, not its artifact: a release ships one
	# stripped binary per platform and no sanitizer build.  fetch.sh's source
	# arm clones the tag once into deps/engine-src/ and answers the path.
	#
	# But first, a build that already exists.  The pre-push hook tests a
	# detached worktree when the tree differs from the pushed commit, and hands
	# it this checkout's acquired engine through X_ENGINE_DIR so it needs no
	# network; the sanitizer build lives beside that engine, under the same
	# deps/, at a path the pin determines.  Reusing it keeps the hook offline
	# and keeps the build to one per pin, not one per worktree.
	PIN="${PIN:-tools/engine/engine.pin.xon}"
	name=$(sed -n 's/^(engine "\([^"]*\)").*/\1/p' "$PIN" | head -1)
	release=$(sed -n 's/^(release "\([^"]*\)").*/\1/p' "$PIN" | head -1)
	SRC="deps/engine-src/$name-$release"
	if [ ! -x "$SRC/x-bin-asan" ] && [ -n "${X_ENGINE_DIR:-}" ]; then
		alt="$(dirname "$X_ENGINE_DIR")/../engine-src/$name-$release"
		[ -x "$alt/x-bin-asan" ] && SRC="$alt"
	fi
	if [ ! -d "$SRC" ]; then
		SRC=$(FROM_SOURCE=1 sh tools/engine/fetch.sh) || {
			echo "asan-boot: could not acquire the pinned engine's sources" >&2; exit 2; }
	fi
	ASAN_BIN="$SRC/x-bin-asan"
	if [ ! -x "$ASAN_BIN" ]; then
		echo "asan-boot: building x-bin-asan in $SRC" >&2
		# A tag is immutable, so the build never goes stale and is never
		# rebuilt -- which also keeps clear of GNU make 3.81's one-second
		# mtime granularity, the thing that makes an incremental rebuild
		# after a quick edit silently reuse the old object.
		make -C "$SRC" -s x-bin-asan >&2 || {
			echo "asan-boot: x-bin-asan failed to build in $SRC" >&2; exit 2; }
	fi
fi

# --- a COLD boot, or nothing is being tested ----------------------------------
# compile-asm caches its emitted bytes under /tmp/x-asm-* (lib/x/tool/asm-cache.x)
# and a warm cache never runs the compiler at all -- so on a developer's machine
# the tower boots without one collect from the JIT, and the exact use-after-free
# this gate exists for cannot happen.  The first version of this script passed
# green on a library that CI had just crashed on, for precisely that reason.
# The prefix is hard-coded and shared, so the cache is set aside for the run
# and put back after: the boots below repopulate it with identical bytes (the
# key is the source text).  Not concurrency-safe: two of these at once, or an
# engine booting alongside, can leave the cache short some entries -- a miss
# costs one recompile, nothing else -- because the cache has no directory to
# point elsewhere.  The gate runs alone in test-fast and gates, which is
# where it belongs.
W="${TMPDIR:-/tmp}/asan-boot.$$"
mkdir -p "$W/cache"
restore_cache() {
	# Restore what was set aside; a fresh entry of the same name IS the same
	# bytes, so either order of precedence is right.
	for f in "$W"/cache/x-asm-*; do
		[ -e "$f" ] && mv -f "$f" /tmp/ 2>/dev/null
	done
	rm -rf "$W"
}
trap 'restore_cache' EXIT INT TERM
for f in /tmp/x-asm-*; do
	[ -e "$f" ] && mv -f "$f" "$W/cache/" 2>/dev/null
done

# --- the probe -------------------------------------------------------------------
PROBE="$W/probe.x"
printf '(display "asan-boot=ok")\n(newline)\n' > "$PROBE"

# A boot that is still running after ten minutes is not a boot; without a
# ceiling a hang here would hold the push connection open until GitHub dropped
# it, which reads as a network fault (the SIGPIPE class).
TIMEOUT=""
if command -v timeout >/dev/null 2>&1; then TIMEOUT="timeout 600"
elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT="gtimeout 600"; fi

# ASan's own exit status is what fails the boot.  Leak detection is off: a
# batch process that exits without freeing its heap is the engine's normal
# shape, not a finding.  THE QUARANTINE IS THE GATE'S MEMORY.  ASan catches a
# freed read only while the freed chunk is still quarantined; its default
# quarantine is 256M and a tower boot frees gigabytes, so a cell freed early
# in the boot can be recycled before the includer resumes to read it, and
# what ASan then sees is a valid read of someone else's object -- or an
# overflow past a smaller one, which is how the first trap here reported
# itself.  A 2G quarantine keeps every boot-time free poisoned until the
# boot is over, so the class reports as what it is.
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0:quarantine_size_mb=2048}"

fail=0
trapped=0
for d in $DIALECTS; do
	out="$W/$d.out"; err="$W/$d.err"
	# --no-pin: the sources carry no x-engine-build.xon and the pin guards
	# would refuse the pairing before the engine ever ran; the seam gate boots
	# the same way.  X_BIN is the wrapper's documented override.
	if X_BIN="$ASAN_BIN" $TIMEOUT sh x.sh --no-pin -q -l "$d" -f "$PROBE" > "$out" 2> "$err" \
		&& grep -qx "asan-boot=ok" "$out"; then
		printf '  %-3s ok\n' "$d"
		continue
	fi
	fail=1
	echo "asan-boot: $d failed to boot on the AddressSanitizer engine" >&2
	# The report's headline and its first frames are the finding; the rest
	# is shadow-byte tables nobody reads in a gate.
	if grep -q "ERROR: AddressSanitizer" "$err"; then
		trapped=1
		grep -E "ERROR: AddressSanitizer|SUMMARY:|^    #[0-9] " "$err" | head -14 | sed 's/^/  /' >&2
	else
		sed 's/^/  /' "$err" | head -8 >&2
	fi
done

if [ "$fail" -ne 0 ]; then
	# Say only what was seen.  A sanitizer report is the finding this gate
	# exists for; any other failure is a boot that did not happen, and the
	# stderr above is the whole story.
	if [ "$trapped" -ne 0 ]; then
		echo "asan-boot: FAIL -- a boot reads freed memory; the collector cannot see what holds it" >&2
	else
		echo "asan-boot: FAIL -- a dialect did not boot (no sanitizer report; see above)" >&2
	fi
	exit 1
fi
# $DIALECTS is a word list; splitting it is the point.
# shellcheck disable=SC2086
echo "asan-boot: ok ($(printf '%s\n' $DIALECTS | wc -l | tr -d ' ') dialects boot clean on $(basename "$ASAN_BIN"))"
