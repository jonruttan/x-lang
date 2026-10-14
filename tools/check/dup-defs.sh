#!/bin/sh
# dup-defs.sh -- cross-module duplicate-global-def ratchet (#47)
#
# The platform's sources, held to tools/lang-kit/dup-defs.sh, the scanner
# every bundle's spec gate runs too.  Its header gives the rule; this file
# gives the platform's scope and its adjudicated names.
#
# Out of scope: lib/img.x, the state-image loader's dialect.  It is a
# runtime of its own -- it loads nothing of lib/x, nothing of lib/x loads
# into it, and its loader replaces the whole env at install -- so its
# function-only `do`, `prim-ref`, `newline` and the rest never share a base
# with the boot's.  Same rule as the per-arch backends: it cannot co-load.
#
# Scope: lib/ + apps/ + tools/ -- everything that can co-load into one base
# env.  The driver scripts load x-core and then their tool file, so tools/
# globals land in the same env; they are the scanner's scripts.  The per-arch
# backend directory, lib/x/tool/asm/, loads one file per host.
#
# Adjudicated same-name multi-definition names:
#   let            -- staged bootstrap upgrade: core/control.x defines the
#                     basic form, core/syntax.x redefines with named-let;
#                     last-loaded wins is the intent.
#   compile-asm    -- tool/compile.x installs a lazy stub that
#                     include-onces tool/asm-compile.x (the real one) and
#                     re-dispatches; the overwrite is the mechanism.
#   %c-read %c-malloc %c-free %c-close
#                  -- libc symbols re-resolved per module through
#                     different FFI helpers (%resolve/%sk/%dlsym); same
#                     pointer by construction.
#   %obj-set! %ptr %ptr-ref %int->ptr
#                  -- same value re-derived from different doors
#                     (data.x raw path vs prim-ref-composed).
# New entries need the same-value argument written here.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_DIR" || exit 1

DUP_DEFS_ALLOW="let compile-asm %c-read %c-malloc %c-free %c-close %obj-set! %ptr %ptr-ref %int->ptr" \
DUP_DEFS_ONE_LOADS="lib/x/tool/asm/" \
DUP_DEFS_SCRIPTS="tools/" \
	exec sh tools/lang-kit/dup-defs.sh $(find lib apps tools -name '*.x' ! -path 'lib/img.x' 2>/dev/null | sort)
