#!/bin/sh
# asan-boot.sh -- boot every dialect on an AddressSanitizer engine.
#
# The failure this gate exists for depends on allocator luck.  The engine has
# no auto-GC and a precise collector: an object referenced only from a C frame
# is garbage the moment anything collects, and nothing notices until the freed
# cell is reused.  glibc reuses a freed cell at once; macOS's allocator mostly
# leaves it intact for a while.  So a use-after-free the tower's boot commits
# on every machine surfaces only where the heap lands such that the cell is
# recycled in time -- green on one box, red on another, with no difference in
# the code.
#
# AddressSanitizer removes the luck: it quarantines freed memory and traps the
# read, on any allocator and any OS, with a stack.  This gate boots each
# dialect on an ASan build of the pinned engine -- the sources fetch.sh clones
# at the pin's release tag -- and asks that the boot finishes and the probe
# prints.
#
# Cost: the first run clones the pinned sources and builds x-bin-asan (~1 min),
# and the build is then reused for as long as the pin stands.  The boots are
# cold by construction (see below), so the tower compiles every unit under
# ASan each time -- a few minutes for the three dialects.  That is past
# gates-fast's sub-minute budget, so it rides test-fast and gates instead.
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
	# INT and TERM are ignored from here on.  Their traps exit, and an exit
	# from inside this trap would leave the entries not yet moved in $W.
	trap '' INT TERM
	# Restore what was set aside; a fresh entry of the same name IS the same
	# bytes, so either order of precedence is right.
	for f in "$W"/cache/x-asm-*; do
		[ -e "$f" ] && mv -f "$f" /tmp/ 2>/dev/null
	done
	rm -rf "$W"
}
# A boot runs under timeout, which puts itself in a process group of its own,
# so an INT or TERM sent to the gate's group does not reach the boot.
# stop_boot sends TERM to the boot's group, and to the timeout itself in case
# it has not made its group yet, then waits for it.  TERM rather than INT: a
# command started in the background may have INT ignored.
boot=""
stop_boot() {
	trap '' INT TERM
	if [ -n "$boot" ]; then
		kill -s TERM -- "-$boot" "$boot" 2>/dev/null || :
		wait "$boot" 2>/dev/null || :
	fi
}
trap 'restore_cache' EXIT
trap 'stop_boot; exit 130' INT
trap 'stop_boot; exit 143' TERM
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
# shape, not a finding.
#
# The quarantine is the gate's memory.  ASan catches a freed read only while
# the freed chunk is still quarantined, and its default quarantine is 256M
# against a tower boot that frees gigabytes.  A cell freed early in the boot
# is then recycled before the includer resumes to read it, and ASan sees a
# valid read of someone else's object, or an overflow past a smaller one.  A
# 2G quarantine keeps every boot-time free poisoned until the boot is over.
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0:quarantine_size_mb=2048}"

fail=0
trapped=0
for d in $DIALECTS; do
	out="$W/$d.out"; err="$W/$d.err"
	# --no-pin: the sources carry no x-engine-build.xon and the pin guards
	# would refuse the pairing before the engine ever ran; the seam gate boots
	# the same way.  X_BIN is the wrapper's documented override.
	#
	# Under timeout the boot runs in the background and the gate waits for it.
	# A trapped signal interrupts `wait`, so stop_boot can end the boot; with
	# the boot in the foreground the trap would run only after it finished.
	# Without timeout the boot stays in the foreground, in the gate's process
	# group, where the signal reaches it directly.
	status=0
	if [ -n "$TIMEOUT" ]; then
		X_BIN="$ASAN_BIN" $TIMEOUT sh x.sh --no-pin -q -l "$d" -f "$PROBE" > "$out" 2> "$err" &
		boot=$!
		wait "$boot" || status=$?
		boot=""
	else
		X_BIN="$ASAN_BIN" sh x.sh --no-pin -q -l "$d" -f "$PROBE" > "$out" 2> "$err" || status=$?
	fi
	if [ "$status" -eq 0 ] && grep -qx "asan-boot=ok" "$out"; then
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
