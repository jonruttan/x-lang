#!/bin/sh
# boot-closed.sh -- a boot amalgam loads nothing from the platform (#467).
#
# THE CLAIM AN AMALGAM MAKES is that it is a whole boot: hand it to an engine
# and the language stands up.  It was true of everything the entry `include`s
# and false of everything the entry `import`s -- those resolved at RUNTIME
# against whatever library the machine happened to have, so a pinned project
# ran its own boot mixed with the platform's modules, and the overlay could not
# intercept them because the pin arms AFTER the amalgam has already run.
#
# That mixture is what crashed #435: a v0.3.1-rc10 amalgam on a v0.4.0 install,
# reproduced with the engine held constant.
#
# WHAT THIS CHECKS.  Every top-level `(import NAME)` left in a generated
# amalgam must name a module the boot has ALREADY loaded -- that is, one in
# x-core.x's pre-seeded loaded-set, where `import` is a no-op.  Any other
# top-level import is a file read from the platform at boot.
#
# STATIC, on purpose.  The end-to-end proof is to install a tree, delete its
# lib/ and apps/, and boot each amalgam -- which is minutes, and is how this
# was verified when it was written.  This is the ratchet that keeps it true:
# seconds, and it fails on the commit that reintroduces the leak rather than
# on the release that ships it.
set -e

cd "$(dirname "$0")/../.." || exit 1

[ -d build/boot ] || { echo "boot-closed: no build/boot -- run 'make boot' first" >&2; exit 2; }

W="${TMPDIR:-/tmp}/boot-closed.$$"
mkdir -p "$W"
trap 'rm -rf "$W"' EXIT INT TERM

# The pre-seeded set: the modules x-core.x marks loaded because it raw-includes
# them.  `include` does not register, so without that list a later import would
# reload the file mid-boot; check-boot-order holds the list against the tree.
sed -n 's/^[[:space:]]*(pair (lit \([a-z0-9_/.-]*\)).*/\1/p' lib/x-core.x | sort -u > "$W/seeded"

bad=0
for f in build/boot/*.x; do
	# Top-level only.  An indented import is inside a body -- lib/x/boot/module.x
	# imports the syscall layer inside `module list-dir`, a cold method -- and a
	# cold import is not a boot-time load.
	sed -n 's/^(import \([a-z0-9_/.-]*\))[[:space:]]*$/\1/p' "$f" | sort -u > "$W/imports"
	leaks=$(comm -23 "$W/imports" "$W/seeded")
	if [ -n "$leaks" ]; then
		bad=1
		echo "$(basename "$f"): loads these from the platform at boot:"
		printf '%s\n' "$leaks" | sed 's/^/    /'
	fi
done

if [ "$bad" != 0 ]; then
	echo "boot-closed: FAIL -- an amalgam is not a whole boot." >&2
	echo "  tools/release/amalgamate.sh splices a top-level import and marks it" >&2
	echo "  loaded; an import it leaves behind is one it could not resolve, or one" >&2
	echo "  its matcher did not recognise." >&2
	exit 1
fi
echo "boot-closed: ok ($(ls build/boot/*.x | wc -l | tr -d ' ') amalgams load nothing from the platform)"
