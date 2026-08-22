# # Computational Expressions in C
#
# ## Makefile
#
# @description Computational Expressions in C
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2021 Jon Ruttan
# @license MIT No Attribution (MIT-0)
#
#     ., .,
#     {O,O}
#     (   )
#      " "
# Info on portable Makefiles:
# - [A Tutorial on Portable Makefiles « null program](http://nullprogram.com/blog/2017/08/20/)
# - [Makefile Assignments are Turing-Complete « null program](http://nullprogram.com/blog/2016/04/30/)
# - [os agnostic - OS detecting makefile - Stack Overflow](https://stackoverflow.com/questions/714100/os-detecting-makefile)
# - [Gagallium : Portable conditionals in makefiles](http://gallium.inria.fr/blog/portable-conditionals-in-makefiles/)
# - [make](http://pubs.opengroup.org/onlinepubs/009695399/utilities/make.html)

.POSIX:

# The install prefix
PREFIX?=/usr/local

# The engine's RELEASE IDENTITY (#435).  Derived, never written down: a tag
# build reports the tag, any other build reports its distance from one, and
# a dirty tree says so.  Overridable, and the release pipeline does override
# it -- tools/release/package.sh passes the tag it was handed, so a published
# tarball's engine is stamped with exactly the tag it ships under instead of
# whatever a shallow checkout's `git describe` could reconstruct.
#
# This is what the ISA fingerprint could never be.  isa.x is byte-identical
# across v0.3.1-rc10, v0.4.0 and v0.5.0 -- correctly, it is the C surface --
# so an amalgam from one release booted on another's engine passed the
# pairing guard and segfaulted.  The tag is the one key that cannot silently
# under-approximate, so the engine now carries it.
X_RELEASE?=$(shell git describe --tags --always --dirty 2>/dev/null || echo dev)

# ---------------------------------------------------------------------------
# The engine binary is built from the x-engine-c submodule (the 2026-08-21
# split).  Everything that used to live here -- CFLAGS, the compiler probe,
# the object rules, the variant builds -- moved with the C it compiles.  What
# stays is the CONTRACT between the two repos, and it is exactly two things.
#
# 1. WHERE THE BINARY LANDS.  At this repo's root, where it has always been.
#    That is not tidiness: tests/spec-runner.sh derives its awk harness path
#    from the directory holding the engine, so the binary must physically sit
#    beside tests/ or the runner cannot find its own harness.  Keeping it here
#    is what leaves x.sh, the spec runners, tools/dev/lint.sh and the ~15
#    tools/check/*.sh scripts untouched by the split.
#
# 2. WHOSE RELEASE IT REPORTS.  This repo's (#435).  The pin lock records the
#    LANGUAGE release and lib/x/tool/pin.x refuses at boot when a pinned
#    amalgam's release differs from the engine's, so an engine stamped with
#    the submodule's own `git describe` would fail every pinned project on
#    sight.  X_RELEASE is passed down on every engine build below -- the same
#    override tools/release/package.sh already uses for tarballs.
ENGINE_DIR=ext/x-engine-c

# Fail with a sentence instead of a screenful of missing-file errors: a clone
# without --recursive has an empty submodule, and the first symptom would
# otherwise be make(1) complaining it has no rule to make the engine.
ENGINE_MAKE=@if [ ! -f $(ENGINE_DIR)/Makefile ]; then \
		echo "The engine submodule is empty. Run: git submodule update --init --recursive" >&2; \
		exit 1; \
	fi; $(MAKE) --no-print-directory -C $(ENGINE_DIR) X_RELEASE="$(X_RELEASE)"

# NAME is the PROJECT name: the wrapper's installed command (bin/x) and the
# install-tree dirs (share/x, libexec/x) -- x.sh's X_SHARE/X_ENGINE and the
# bootstrap tarball layout depend on it.  EXECUTABLE is the ENGINE BINARY's
# filename, deliberately distinct from the repo root, the wrapper, and the
# .x extension so tooling can match it precisely.
NAME=x
EXECUTABLE=x-bin

# Where to install the stuff.  The user-facing command is the WRAPPER,
# installed as bin/x; the engine binary hides in libexec (without the
# library on its stdin pipe it cannot even print, so it is not a user
# command).  MANDIR is the man HIERARCHY ROOT, not a section dir: the pages
# `make install-man` ships are Doxygen's C reference (section 3), and its
# alias pages are `.so man3/<page>` -- a source directive resolved against
# the hierarchy root, so it only works if the pages land in $(MANDIR)/man3.
BINDIR?=$(PREFIX)/bin
LIBDIR?=$(PREFIX)/share/$(NAME)
LIBEXECDIR?=$(PREFIX)/libexec/$(NAME)
MANDIR?=$(PREFIX)/share/man

# Coverage
COVERAGE_DIR=.coverage

# ============================================================================
# Build
# ============================================================================

default: $(EXECUTABLE) ## Build the engine

all: $(EXECUTABLE) ## Build all
.PHONY: all

# The engine, built in the submodule and copied up to this root.  Two rules,
# not one, so the copy is timestamp-guarded: the inner make no-ops in
# milliseconds when nothing changed, and cp only runs when it actually
# produced a newer binary.  FORCE on the inner rule because only the
# submodule's own makefile knows whether its sources are stale.
$(EXECUTABLE): $(ENGINE_DIR)/$(EXECUTABLE)
	cp $< $@

$(ENGINE_DIR)/$(EXECUTABLE): FORCE
	$(ENGINE_MAKE)

# The variants, same shape.  Each is PHONY-free for the same reason as the
# plain engine: the copy must compare timestamps, not run unconditionally.
x-bin-asan x-bin-cov x-bin-profile x-bin-debug: %: $(ENGINE_DIR)/%
	cp $< $@

$(ENGINE_DIR)/x-bin-asan $(ENGINE_DIR)/x-bin-cov $(ENGINE_DIR)/x-bin-profile $(ENGINE_DIR)/x-bin-debug: $(ENGINE_DIR)/%: FORCE
	$(ENGINE_MAKE) $*

# The C spec suite belongs to the engine repo and its CI runs it.  This is
# the local door to it, so `make test` here can still be the whole verdict.
test-c: ## Run the engine's C unit tests (delegates to the submodule)
	$(ENGINE_MAKE) test-c
.PHONY: test-c

# The C reference is Doxygen over the engine's sources, so it generates
# INSIDE the submodule (ext/x-engine-c/docs/ref/c/).  pages.yml copies from
# there; this target exists so `make doc` is still both halves.
doc-c: ## Generate C reference documentation (delegates to the submodule)
	$(ENGINE_MAKE) doc-c
.PHONY: doc-c

install-man-c uninstall-man-c: ## The C reference man pages (delegates to the submodule)
	$(ENGINE_MAKE) $@ DESTDIR="$(DESTDIR)" MANDIR="$(MANDIR)"
.PHONY: install-man-c uninstall-man-c

# ============================================================================
# Test
# ============================================================================

test-x: $(EXECUTABLE) ## Run x-lang tests
	sh tests/x/spec-runner.sh
.PHONY: test-x

# The applicative stress lane rides test-x only when STRESS=1 (CI's
# native specs jobs set it; see #300).  This target is the local
# spelling -- SERIAL, because the lane's files peak ~4.7GB each.
test-stress: $(EXECUTABLE) ## Run x-lang tests including the stress lane
	STRESS=1 PARALLEL=1 sh tests/x/spec-runner.sh
.PHONY: test-stress

# The tools' own spec suite (tools/tests), repaired from the post-overhaul
# rot (#180).  Two runners: spec-runner.sh takes the top-level specs on the
# plain engine; cov-spec-runner.sh takes specs/cov/ on x-bin-cov, because
# coverage marking only exists under -DX_COV.
test-tools: $(EXECUTABLE) x-bin-cov ## Run the tool suite's specs (tools/tests)
	sh tools/tests/spec-runner.sh
	sh tools/tests/cov-spec-runner.sh
.PHONY: test-tools

# The doctest ratchet (#16): every (example "in" "out") in the doc registry
# is an executable contract -- "out" must be the true echo.  tools/check/doctest.sh
# extracts them into a generated spec; the personality runner executes it.
# Illustrations that must not run are (sample ...) forms (see doc.x).
doctest: $(EXECUTABLE) ## Extract (example ...) forms and run them as doctests
	mkdir -p build/doctest-specs
	sh tools/check/doctest.sh > build/doctest-specs/doctests.spec.md
	sh tests/x/doctest-runner.sh
.PHONY: doctest

# The contract gates, ONE definition: `make test` runs them first and
# CI's "Contract gates" step runs exactly this target.  They must not
# drift -- ci.yml once hand-listed a subset, and check-pin's first run
# on Linux happened in the RELEASE job (where it promptly died).
gates: check-isa check-prim-coverage check-obj-layout check-base-paths check-boot-order check-path-literals check-boot-amalgam check-pin check-release-manifest check-bootstrap check-package check-doc-vocab check-dup-defs check-bare-globals check-percent-globals check-constraints check-engine-contract check-compliance check-conformance-coverage check-engine-seam check-platform-seam check-dialect-cover check-highlight-roundtrip ## Run the contract gates
.PHONY: gates

# The local-latency split (2026-08-03 audit): `make test` grew past ten
# minutes (build/install/package smokes, amalgam boots, doctest walk,
# example programs) and the pre-push hook ran ALL of it inside the open
# push connection -- long enough for GitHub to hang up the idle SSH
# channel mid-hook.  gates-fast is the sub-minute subset: every scan
# ratchet, none of the targets that build or boot artifacts.  The hook
# runs test-fast; CI still runs the FULL `make test` on every push/PR
# (ci.yml unchanged -- it stays the enforcing gate for the heavy surface).
gates-fast: check-isa check-prim-coverage check-obj-layout check-base-paths check-boot-order check-path-literals check-doc-vocab check-dup-defs check-bare-globals check-percent-globals check-constraints check-engine-contract check-conformance-coverage check-engine-seam check-platform-seam check-dialect-cover ## The fast contract gates (pre-push subset)
.PHONY: gates-fast

test-fast: gates-fast test-c test-x ## Pre-push gate: fast gates + both spec suites (CI runs full `make test`)
.PHONY: test-fast

# bootstrap.sh's build+install path (its coupling to the install layout);
# the clone path is exercised by the release workflow on a clean checkout.
# The smoke stages a tracked-files copy and builds THERE (#326): the
# script's own `make clean` used to wipe this repo's x-bin and objects
# mid-gate, and the next $(EXECUTABLE)-dependent target silently re-paid
# the whole C build.  The repo's artifacts now survive the gate.
check-bootstrap: $(EXECUTABLE) ## Smoke the one-command bootstrap install
	sh tools/check/bootstrap-smoke.sh
.PHONY: check-bootstrap

test: gates conformance test-c test-x doctest spec-examples doc-examples check-examples lint-x test-tools doc-x ## Run all tests
.PHONY: test

# The release manifest (SHASUMS + pin.release.xon over the amalgams;
# .github/workflows/release.yml publishes it on a version tag) -- gated
# here with a throwaway tag so the self-checking script cannot rot
# between releases.
check-release-manifest: boot ## Generate + self-check the release manifest
	sh tools/release/release-manifest.sh local
.PHONY: check-release-manifest

# The relocatable binary tarball (release.yml ships one per platform on a
# tag) -- gated so the packaging cannot rot between releases: package.sh
# stages the install tree, tars it, and self-proves relocation (unpack
# elsewhere, run).  Output lands under build/.
#
# The tag it is handed is THIS BUILD'S $(X_RELEASE), not a throwaway
# literal.  package.sh passes its tag through to `make install`, which
# stamps the engine with it -- so a literal would rebuild x-cli.o and
# relink the repo's own binary under a fake release, then relink it back
# on the next make.  Handing it the value the tree already has keeps the
# gate a no-op on the build while still exercising the whole path,
# stamp assertions included.
check-package: $(EXECUTABLE) ## Build + self-check a relocatable binary tarball
	sh tools/release/package.sh "$(X_RELEASE)" build/dist-check
.PHONY: check-package

# Project pinning (docs/modules.md "Pinning"): the wrapper's pin.xon probe
# and lib/x/tool/pin.x, end to end -- overlay resolution, root precedence,
# the unpinnable boot core, the closed manifest vocabulary, --no-pin.
check-pin: $(EXECUTABLE) ## Smoke the pin.xon probe + loader end to end
	sh tools/check/pin-smoke.sh
.PHONY: check-pin

# The examples ratchet: every file under examples/*/ runs under its documented
# dialect in batch mode; output-pinned where portable (sidecars in
# tests/examples/).  The examples are the first code a newcomer runs and were
# previously the only code with no gate.  UPDATE=1 regenerates sidecars.
check-examples: $(EXECUTABLE) ## Run every example under its documented dialect
	sh tools/check/examples.sh
.PHONY: check-examples

# The logo tty contract (#152/#157): expect-driven pty sessions pinning the
# interactive behaviors (ctrl-c cancel, exit paths, hooks, execute-once)
# that isatty guards hide from every batch suite.  Not part of `make test`
# (tty environments flake); CI runs it explicitly on both OSes.  Skips
# with a note when expect(1) is absent.  known-fail.txt entries pin the
# post-#157 ruling; a listed test PASSING is red (delete its line).
check-logo-tty: $(EXECUTABLE) ## Run the logo interactive-contract pty tests
	sh tools/check/logo-tty.sh
.PHONY: check-logo-tty

# The three SELF-CONTAINED contract ratchets moved to the engine repo with
# the manifests they diff against (2026-08-21).  They are delegated, not
# deleted: `make check-isa` still works from here, CI's gate list does not
# have to know which side of the boundary each ratchet lives on, and a C
# change that skips its manifest edit is refused by the same `make gates`
# it always was.
#
# Their RUNTIME halves stay here and run under test-x, because only a booted
# engine can answer them: tests/x/specs/meta/{isa,obj-layout,base-paths}.spec.md
# walk the live catalog, the live object header and the live base spine.
check-isa check-obj-layout check-base-paths: ## Engine contract ratchets (delegated)
	$(ENGINE_MAKE) $@
.PHONY: check-isa check-obj-layout check-base-paths

# The fourth ratchet, and the one that CANNOT move: it asks whether every
# primitive the C registers is EXERCISED by a spec, and most primitives are
# reachable only through the library, so the honest answer needs BOTH spec
# suites at once.  Only the repo holding both trees can ask it -- this one,
# while the engine is a submodule.  When x-lang stops vendoring the engine's
# source this gate is the thing that has no home yet; see the split notes.
#
# Sixteen primitives had no test and nobody knew -- found by accident,
# because nothing enumerated the C surface and asked which parts of it run.
# This asks.  An untestable primitive has to say so in prose next to the
# subject rather than being quietly absent, and a reason cannot outlive its
# subject.
check-prim-coverage: ## Assert every C primitive is exercised by a spec, or says why not
	sh tools/check/prim-coverage.sh
.PHONY: check-prim-coverage

# The boot-order lint: derives the effective load order from each boot entry
# (lib/x-core.x + the three dialect entries; include forms, the
# %include-list-cell pre-seed, import expansion) and flags (a) load-time
# class-calls whose def-class comes later in the order -- the silent
# class-call trap -- and (b) pre-seed drift: double loads and raw-included
# lib paths never registered (see tools/check/boot-order.x).
check-boot-order: $(EXECUTABLE) ## Lint the boot load order: class-call order + pre-seed drift
	sh tools/check/boot-order.sh
.PHONY: check-boot-order

# Doc-type vocabulary ratchet: the adjudicated losers (INTEGER/BOOLEAN/
# FUNCTION -- see contributing.md) must not reappear in (param ...)/
# (returns ...) forms; INT/BOOL/CALLABLE are the one-name-per-concept picks.
# The duplicate-global-def ratchet (#47): top-level redefinition updates the
# shared binding in place, so two modules defining one name with different
# meanings is a real collision (the %alist-find segfault).  tools/check/dup-defs.sh
# holds the rule + the adjudicated allowlist.
check-dup-defs: ## Lint lib+apps for cross-module duplicate global defs
	sh tools/check/dup-defs.sh
.PHONY: check-dup-defs

check-path-literals: ## Lint for root-relative load literals outside the boot closure
	sh tools/check/path-literals.sh
.PHONY: check-path-literals

# Amalgamated boot entries: each dialect's raw-include
# chain flattened into one self-ordered stream, plus one per app entry.
# Build products only -- never committed; regenerated on every call, so the
# amalgams cannot drift from the sources they are made of.
boot: ## Generate amalgamated boot entries into build/boot
	@mkdir -p build/boot
	@for e in x he xe rn x-base; do \
		sh tools/release/amalgamate.sh "lib/$$e.x" > "build/boot/$$e.x" || exit 1; done
	@for a in apps/*/run.x; do \
		n=$$(basename "$$(dirname "$$a")"); \
		sh tools/release/amalgamate.sh "$$a" > "build/boot/$$n.x" || exit 1; done
	@echo "boot: generated $$(ls build/boot | wc -l | tr -d ' ') entries"
.PHONY: boot

check-boot-amalgam: $(EXECUTABLE) boot ## Boot every amalgam in batch mode and pin a smoke expression
	sh tools/check/amalgam-smoke.sh
.PHONY: check-boot-amalgam

# THE TOP LEVEL IS SACRED (#108): the runtime library may bind only the names
# tools/contract/bare-globals.x sanctions; the manifest can only shrink.
check-bare-globals: ## Diff the runtime library's bare top-level defs against tools/contract/bare-globals.x
	sh tools/check/bare-globals.sh
.PHONY: check-bare-globals

# The %-global budget (the bare ratchet's closed exemption): per-file
# counts in tools/contract/percent-globals.x, shrink-only.
check-percent-globals: ## Diff every lib file's %-global count against its shrinking budget
	sh tools/check/percent-globals.sh
.PHONY: check-percent-globals

# The platform-parameter ratchet: a module that only works at one word size or
# byte order declares it at the code AND in tools/contract/constraints.x, and the
# two must agree in both directions.  A parameter is NOT a capability -- a global
# `word-size = 8` requirement would lock out the 32-bit Pi and would be false
# besides, since obj-layout.x is in words and data.x probes the width at boot.
# The syscall/FFI layer is the part that genuinely binds, and it used to say so
# only in prose.
check-constraints: ## Diff source constraint markers against tools/contract/constraints.x
	sh tools/check/constraints.sh
.PHONY: check-constraints

# The engine-contract vocabulary: tools/contract/features.x is what an engine's
# x-engine.xon and this repo's requires.x both quote from, so it must stay in step
# with the surface it describes.  The gate holds the capability groups as a TOTAL,
# DISJOINT partition of the engine's isa.x -- a new C row cannot appear unclassified
# -- and re-derives requires.x from the tree rather than trusting it.  The partition
# is the load-bearing part: the `ffi` tag carries eleven rows that split three ways
# (pointer casts, foreign door, syscall door), and treating it as one group would
# make dlopen mandatory for every engine including a sandboxed one.
check-engine-contract: ## Hold features.x/requires.x against the engine's ISA
	sh tools/check/engine-contract.sh
.PHONY: check-engine-contract

# COMPLIANCE: does the engine DO what its x-engine.xon claims?  check-engine-contract
# compares provides against requires as text, so an engine that over-declares passes
# it, is chosen by the resolver, and fails in the field -- loudly for a capability,
# SILENTLY for a guarantee (an engine that claims gc/explicit-only while collecting
# on allocation corrupts the six library sites that hold raw pointers across
# allocating expressions, and says nothing).  This runs generated probes that try to
# falsify each declared row, BARE: with the library loaded, registry.x's prim-ref and
# reflect.x's refiled entries make an engine capability indistinguishable from a
# library one.  Needs the built engine, so it rides `gates`, not `gates-fast`.
check-compliance: $(EXECUTABLE) ## Falsify each row of the engine's x-engine.xon
	sh tools/check/compliance.sh
.PHONY: check-compliance

# CONFORMANCE: is this a correct x-lang evaluator?  The language's own definition of
# correct, which is why it lives here rather than in an engine -- an implementation
# that owned this suite would become the arbiter of the contract every other
# implementation is judged against.  Loads NOTHING: every other runner in tests/ cats
# a library onto stdin, so what it measures is the library's surface (variadic `+` is
# lib/x/core/arithmetic.x on top of a BINARY primitive).  X_BIN aims it at any engine.
conformance: $(EXECUTABLE) ## Run the conformance suite (X_BIN=... for another engine)
	sh tests/x/conformance/runner.sh
.PHONY: conformance

# The coverage ratchet.  The suite is early and will be for a while, so the gate is
# not "is it complete" but "did it just get smaller": a row that was defined and no
# longer is fails.  Uncovered rows are printed every run, because a suite silent
# about its gaps reads as finished.
check-conformance-coverage: ## Report ISA coverage; fail if the suite regressed
	sh tools/check/conformance-coverage.sh
.PHONY: check-conformance-coverage

# The implementation-agnostic ratchet: lib/ may name a specific engine only in
# lib/x/boot/engine.x, the seam that carries both boot contract includes and the
# engine root the JIT and pin tool read at runtime.  Without this the claim that a
# second engine needs no library edit is a wish rather than a property.
check-engine-seam: ## Assert lib/ names its engine only in the seam
	sh tools/check/engine-seam.sh
.PHONY: check-engine-seam

# The platform seam: the build triple is PARSED in lib/x/platform/syscall.x and
# nowhere else.  Three modules used to pick x-machine apart independently and only
# one knew Darwin spells A64 "arm64" where GNU triplets spell it "aarch64".  Using
# the whole triple as an opaque value -- a cache key, a diagnostic -- stays fine;
# what belongs to the platform layer is taking it apart.
check-platform-seam: ## Assert the build triple is parsed only in the platform layer
	sh tools/check/platform-seam.sh
.PHONY: check-platform-seam

# The dialect coverage ratchet (#70): every lib/*.x entry point needs an
# end-to-end smoke group, so a new dialect cannot ship untested the way the
# tower launchers did (#49 -- both crashed at the exact invocation the README
# documents, while every numeric spec passed against a bespoke harness).
# The highlighter must not alter what it renders: strip the span markup from
# every rendered block, unescape the three entities, and the fence's original
# bytes must come back.  A highlighter that drops a character or eats a brace
# is worse than none -- the reader cannot tell, and the page is the reference.
# Deep tier only: it sweeps every page, which is tens of seconds.
check-highlight-roundtrip: $(EXECUTABLE) ## Assert highlighting is byte-preserving
	@sh tools/check/highlight-roundtrip.sh
.PHONY: check-highlight-roundtrip

check-dialect-cover: $(EXECUTABLE) ## Assert every lib/*.x dialect has an end-to-end smoke group
	sh x.sh --no-pin -q -f tools/check/dialect-cover.x
.PHONY: check-dialect-cover

# spec.md's worked examples, extracted and executed -- the ratchet that keeps
# the normative spec honest (#70 seam 2, PROMOTED at 356/356 green).  It began
# report-only at 86 failures; the drift burned down through #72 #73 #76 the
# #31 order sweep, the regex-escaping fix, the reader-section repairs and
# depth-tracked quasi (#55), and on the stated criterion -- red would rot it
# like lint-x (#60) -- it joined `test` only once fully green.  A spec.md
# example that stops reproducing now fails the build with a file:line name.
spec-examples: $(EXECUTABLE) ## Run docs/spec.md's examples (gate: spec.md cannot drift silently)
	sh tools/check/spec-examples.sh
	sh tests/x/spec-example-runner.sh
.PHONY: spec-examples

# The same extraction pointed at the OTHER docs that write examples in the
# `EXPR -> EXPECTED` form.  spec.md was gated; primitives.md and
# standard-library.md were not, and 235 assertions had never been executed --
# retired primitives still documented as live, list functions documented as
# bare globals long after they moved onto classes, three swapped argument
# orders (#452, #453).  Report-only until those are fixed, on the same
# criterion spec-examples was promoted under: a red gate rots.  Which docs run
# and whether they are fatal is tools/check/doc-examples.conf.
doc-examples: $(EXECUTABLE) ## Run the prose docs' examples (see doc-examples.conf)
	sh tools/check/doc-examples.sh
.PHONY: doc-examples

check-doc-vocab: ## Lint doc forms for banned type-token aliases + retired names
	@if grep -rn 'INTEGER\|BOOLEAN\|FUNCTION' lib --include='*.x' \
		| grep '(param \|(returns '; then \
		echo "doc-vocab: FAIL (use INT/BOOL/CALLABLE; see contributing.md)" >&2; \
		exit 1; \
	else echo "doc-vocab: ok"; fi
	@# Retired/banned names from the #42/#44 adjudications (see contributing.md's
	@# adjudication block): shapes ride the name, synonyms stay dead.
	@if grep -rnw 'from-pairs\|->pairs' lib --include='*.x' \
		|| grep -rn '(method nth \|(method member? \|(method every? \|(method size ' lib --include='*.x'; then \
		echo "doc-vocab: FAIL (retired name; see contributing.md adjudications)" >&2; \
		exit 1; \
	else echo "retired-names: ok"; fi
	@# Retired dialect spellings (#95): the noble-gas names (he/xe/rn,
	@# modules x/xe, x/rn) replaced x-and/x-or; the compat shims are gone.
	@if grep -rnw 'x-and\|x-or\|x/and\|x/or' lib --include='*.x'; then \
		echo "doc-vocab: FAIL (retired dialect spelling; use he/xe/rn -- #95)" >&2; \
		exit 1; \
	else echo "retired-dialects: ok"; fi
	@# The quote-idiom ratchet (#45 R2/R8, added at the 2026-07-18 reopen):
	@# user-facing doc STRINGS -- (example ...), (sample ...), (note ...) --
	@# speak 'x, never the longhand (lit x), even inside boot-constrained
	@# files (strings never hit the boot reader).  Allowlist: doc-prims.x's
	@# definitional docs for lit itself.
	@if grep -rn '(example "\|(sample "\|(note "' lib --include='*.x' \
		| grep -v 'lib/x/doc/doc-prims\.x' \
		| grep '(lit '; then \
		echo "doc-vocab: FAIL (doc strings speak 'x, not (lit x); #45 R2/R8)" >&2; \
		exit 1; \
	else echo "doc-string-quotes: ok"; fi
	@# Retired C symbols (#249): dead exports deleted with the audit.  A
	@# grep-ratchet so they cannot quietly return -- if one is reintroduced,
	@# it is either genuinely needed (delete the name from this list with a
	@# caller) or the deletion is being undone by mistake.
	@#
	@# The SUBJECT-EXISTS GUARD is not decoration.  This ratchet greps the C
	@# tree, and when that tree moved to the engine submodule the grep began
	@# reporting "No such file or directory" on stderr and PASSING -- a scan
	@# over nothing finds nothing.  Caught by reading gate output, which is
	@# the only reason it did not rot silently.  A missing subject is now a
	@# failure, so the next move breaks the gate instead of hollowing it.
	@if [ ! -d $(ENGINE_DIR)/src ] || [ ! -d $(ENGINE_DIR)/include ]; then \
		echo "retired-c-symbols: FAIL (no C tree at $(ENGINE_DIR); run 'git submodule update --init --recursive')" >&2; \
		exit 1; \
	fi
	@if grep -rnw 'x_eval_filein_push\|x_eval_filein_pop\|x_eval_buffer_pop\|x_char_utf8_len\|x_char_utf8_encode\|x_type_alist_iter\|x_type_alist_iter_prim\|x_type_iter_isempty' $(ENGINE_DIR)/src $(ENGINE_DIR)/include; then \
		echo "retired-c-symbols: FAIL (dead export removed in #249 reintroduced)" >&2; \
		exit 1; \
	else echo "retired-c-symbols: ok"; fi
.PHONY: check-doc-vocab

# Memory-safety gate: run BOTH suites against an AddressSanitizer build (reuses
# the x-asan target). Catches the crash class we keep hitting -- e.g. an
# unchecked `first` reading past a non-pair, which is silently wrong on 64-bit
# but SIGSEGVs on 32-bit/Pi -- on the dev box, before a Pi run surfaces it.
#   - address only: UBSan is deferred until its baseline noise on the C89
#     stack-pair pointer tricks is assessed (it would flag intentional UB).
#   - detect_leaks=0: the interpreter is a GC that does not free at exit, so
#     LeakSanitizer reports are not bugs.
#   - detect_stack_use_after_return=0: stack-copying call/cc cannot coexist
#     with ASan's fake stack -- intermediate frames' locals live in heap-side
#     fake frames that are recycled on return, so a continuation reinvoked
#     later restores real-stack bytes pointing at dead fake frames (the same
#     limitation every fiber/coroutine library documents). Off on some
#     arch/compiler defaults already; pinned off so behavior matches.
#   - WRAPPER= disables the C runner's valgrind auto-wrap (ASan != valgrind).
#   - TIMEOUT_UNIT_SECS raised: instrumentation slows each spec ~2-3x.
ASAN_RUN_OPTIONS=detect_leaks=0:detect_stack_use_after_return=0
#   - SPEC_HEAVY_JOBS=1 (#366): the scheduler's heavy-set admission cap
#     of 2 is tuned at NORMAL resident sizes; sanitizer instrumentation
#     multiplies RSS ~2-3x, and two co-resident heavies OOM-killed the
#     7GB hosted runner on every merge after the #320 heaviest-first
#     ordering landed (exit 143, no failing test -- the runner dies).
#     One heavy at a time under ASan; light jobs still fill the
#     remaining slots.
test-asan: x-bin-asan ## Run both suites under AddressSanitizer (memory-safety gate)
	ASAN_OPTIONS=$(ASAN_RUN_OPTIONS) TIMEOUT_UNIT_SECS=180 SPEC_HEAVY_JOBS=1 X_BIN=./x-bin-asan sh tests/x/spec-runner.sh
	$(ENGINE_MAKE) test-asan
.PHONY: test-asan

# Install the local pre-push gate (first line of defence before the Actions
# CI gates). Points git at the tracked .githooks/ dir so `make test` runs
# before every push. RUN_ASAN=1 in the environment also runs `make test-asan`
# as a non-blocking advisory.
install-hooks: ## Install the pre-push test gate (core.hooksPath=.githooks)
	git config core.hooksPath .githooks
	@chmod +x .githooks/* 2>/dev/null || true
	@echo "pre-push gate active (core.hooksPath=.githooks). Bypass: git push --no-verify. Uninstall: git config --unset core.hooksPath."
.PHONY: install-hooks

# ============================================================================
# Coverage
# ============================================================================

test-x-cov: cov-clean $(EXECUTABLE) ## x-lang tests with coverage
	$(MAKE) clean
	$(ENGINE_MAKE) x-bin-cov && cp $(ENGINE_DIR)/x-bin-cov $(EXECUTABLE)
	sh tests/x/spec-runner.sh
	mkdir -p $(COVERAGE_DIR)
	gcovr -r . --filter 'src/' --print-summary --html-details $(COVERAGE_DIR)/index.html
.PHONY: test-x-cov

test-cov: cov-clean ## All tests with coverage
	$(MAKE) clean
	$(ENGINE_MAKE) x-bin-cov && cp $(ENGINE_DIR)/x-bin-cov $(EXECUTABLE)
	sh tests/x/spec-runner.sh
	$(ENGINE_MAKE) test-c-cov
	mkdir -p $(COVERAGE_DIR)
	gcovr -r . --filter 'src/' --print-summary --html-details $(COVERAGE_DIR)/index.html
.PHONY: test-cov

cov-clean: ## Clean coverage artifacts
	rm -rf $(COVERAGE_DIR)
	find . -name '*.gcov' -o -name '*.gcda' -o -name '*.gcno' | xargs rm -f
.PHONY: cov-clean

# ============================================================================
# Performance
# ============================================================================

bench: x-bin-profile ## Run benchmarks
	sh tools/dev/bench.sh --no-build

cov-x: x-bin-profile ## x-lang library coverage report
	sh tools/dev/cov-lib.sh
.PHONY: bench

# ============================================================================
# Dev tools
# ============================================================================

FORCE:
.PHONY: FORCE

# Promoted into `test` 2026-08-02 on the #60 criterion (red would rot it,
# so it joined only once fully green): lib AND apps both sweep clean since
# the sibling-preload / value-call linter round (#176).
lint-x: $(EXECUTABLE) ## Lint x-lang files
	PARALLEL=1 sh tools/dev/lint.sh
.PHONY: lint-x

# Both targets ride tools/dev/fmt-sweep.sh (#307): the whole library
# (the old loops visited lib's top level only -- 4 of 111 files),
# chunked batch runs behind %%FMT-X-PAGE%% sentinels, and the
# three-outcome contract -- ERROR (the formatter FAILED; never reported
# as a diff), F (a real formatting difference), '.' (byte-identical,
# cmp not command substitution).
fmt-x: $(EXECUTABLE) ## Format x-lang files (whole library)
	sh tools/dev/fmt-sweep.sh --write
.PHONY: fmt-x

fmt-check-x: $(EXECUTABLE) ## Check x-lang formatting (whole library)
	sh tools/dev/fmt-sweep.sh
.PHONY: fmt-check-x

# No stderr masking and fail on error/empty output: a 2>/dev/null here once
# hid a retired-constructor crash for weeks -- 77 of 79 ref files were 0
# bytes while the target reported success.
# The sweep lives in tools/dev/doc-sweep.sh (#321): chunked engine runs
# (~5 boots) instead of one boot per file (~98, ~70% of the old 287s CI
# step), and an explicit find for the file list -- the old `lib/x/**`
# glob was not recursive under sh, so depth-3 modules were silently
# never documented (#322).  Page semantics (FAIL/EMPTY/skip) unchanged.
doc-x: $(EXECUTABLE) ## Generate x-lang documentation
	@sh tools/dev/doc-sweep.sh
	@sh x.sh --no-pin -q -f tools/dev/doc-index.x > docs/ref/x/index.md
	@printf '  %s\n' "docs/ref/x/index.md"
	@sh tools/check/doc-forms.sh
.PHONY: doc-x

# The x-lang library as roff, section 3x -- the same sweep as doc-x behind
# its --man flag (one file list, one chunking policy, one set of per-file
# verdicts; only the emitter differs).  X_RELEASE rides the .TH date slot,
# exactly as doc-c hands it to Doxygen, so an installed page can say which
# build it came from.
#
# NOT part of `doc`: that target is what CI runs on every push, and a second
# full library sweep would double its cost for an artifact only install-man
# consumes.  install-man depends on this directly instead.
doc-man: $(EXECUTABLE) ## Generate x-lang man pages (section 3x)
	@X_RELEASE="$(X_RELEASE)" sh tools/dev/doc-sweep.sh --man
.PHONY: doc-man

# Neither doc-man nor install-man had any gate target, which is how both
# reached main unexercised by CI.  Structural checks only, against a
# throwaway prefix -- see the script header for what each one catches.
# CHECK_MAN_C=1 adds the Doxygen half where Doxygen is installed.
check-man: $(EXECUTABLE) ## Smoke man generation + install (CHECK_MAN_C=1 adds the C half)
	@sh tools/check/man-smoke.sh $${CHECK_MAN_C:+--with-c}
.PHONY: check-man

doc: doc-c doc-x ## Generate all documentation
.PHONY: doc

# The installed library is BYTE-IDENTICAL to the repo's:
# lib/ and apps/ copy verbatim -- diff -r inside the recipe is the proof, and
# it fails the install if anything diverges.  Only the boot/ entries are
# generated (the amalgams; build products, like the binary itself).  The
# import root reaches the installed tree as data: the wrapper emits one
# (def %install-root ...) form at the top of the pipe (see x.sh + module.x).
install: $(EXECUTABLE) $(NAME).sh boot ## Install to PREFIX (DESTDIR honoured)
	install -d -m 0755 $(DESTDIR)$(BINDIR) $(DESTDIR)$(LIBEXECDIR) $(DESTDIR)$(LIBDIR)
	install $C -m 0755 $(EXECUTABLE) $(DESTDIR)$(LIBEXECDIR)/$(EXECUTABLE)
	# strip -x, NOT bare strip: the JIT resolves its runtime helpers
	# (jit_mkint, jit_atomint, ...) through dlsym on the engine itself,
	# and those live in exports.sym.  Bare strip removes the exported
	# symbol table, every dlsym then answers nil, and compiled code
	# called address 0 -- a SIGSEGV inside jit_atomint on every INSTALLED
	# engine while the repo build (which already used -x, line ~158) was
	# clean (x-lang#201).  Release tarballs come from this same target.
	strip -x $(DESTDIR)$(LIBEXECDIR)/$(EXECUTABLE)
	# The engine's DECLARATION travels with the engine, beside it in libexec.
	# x.sh reads its (binary "...") row to learn what to run, so an engine that
	# does not build something called x-bin still installs and starts; and an
	# installed tree can be asked what it provides without a source checkout,
	# which is the same reason the ISA fingerprint has been installed since #186.
	@if [ -f $(ENGINE_DIR)/x-engine.xon ]; then \
		install $C -m 0644 $(ENGINE_DIR)/x-engine.xon $(DESTDIR)$(LIBEXECDIR)/x-engine.xon; \
	else \
		echo "install: WARNING -- $(ENGINE_DIR)/x-engine.xon is missing; the installed tree cannot say what its engine provides" >&2; \
	fi
	@if [ -f $(ENGINE_DIR)/entitlements.plist ]; then codesign -s - --entitlements $(ENGINE_DIR)/entitlements.plist -f $(DESTDIR)$(LIBEXECDIR)/$(EXECUTABLE) 2>/dev/null || true; fi
	install $C -m 0755 $(NAME).sh $(DESTDIR)$(BINDIR)/$(NAME)
	rm -rf $(DESTDIR)$(LIBDIR)/lib $(DESTDIR)$(LIBDIR)/apps $(DESTDIR)$(LIBDIR)/boot
	# The engine's ISA fingerprint travels WITH the engine -- literally so
	# since the split: the manifest is the engine's own
	# $(ENGINE_DIR)/tools/contract/isa.x, not a copy this repo keeps.  An installed
	# tree has no source checkout, so before this there was no way to ask
	# "which engine contract is this?" -- fetch could not compare (#186)
	# and a pinned boot could not refuse a mismatched amalgam (#187); it
	# just ran it and segfaulted.  One precomputed hex line: the wrapper
	# needs a STRING compare against a release manifest, not a digester.
	install -d -m 0755 $(DESTDIR)$(LIBDIR)/contract
	@sh -c 'if command -v shasum >/dev/null 2>&1; then shasum -a 256 ext/x-engine-c/tools/contract/isa.x | cut -d" " -f1; 		else sha256sum ext/x-engine-c/tools/contract/isa.x | cut -d" " -f1; fi' 		> $(DESTDIR)$(LIBDIR)/contract/isa.sha256
	# The LAYOUT fingerprint, and it is the one that matters for pairing.  The isa
	# digest above is the C SURFACE -- byte-identical across rc10, v0.4.0 and
	# v0.5.0, which is how a mismatched amalgam once passed the guard and
	# segfaulted (#435).  An amalgam binds against the LAYOUT: it walks object
	# header words through reflect.x, and a layout that moved is a crash in field
	# access rather than a diagnosable error.  All three descriptors digest as ONE
	# unit because an amalgam binds against all three or none -- the same
	# concatenation tools/release/release-manifest.sh and the x-engine.xon
	# generator use, so all three producers agree by construction.
	@cat $(ENGINE_DIR)/tools/contract/obj-layout.x $(ENGINE_DIR)/tools/contract/base-paths.x $(ENGINE_DIR)/tools/contract/base-layout.x > $(DESTDIR)$(LIBDIR)/contract/layout.cat
	@sh -c 'if command -v shasum >/dev/null 2>&1; then shasum -a 256 $(DESTDIR)$(LIBDIR)/contract/layout.cat | cut -d" " -f1; else sha256sum $(DESTDIR)$(LIBDIR)/contract/layout.cat | cut -d" " -f1; fi' > $(DESTDIR)$(LIBDIR)/contract/layout.sha256
	@rm -f $(DESTDIR)$(LIBDIR)/contract/layout.cat
	cp -R lib $(DESTDIR)$(LIBDIR)/lib
	cp -R apps $(DESTDIR)$(LIBDIR)/apps
	cp -R build/boot $(DESTDIR)$(LIBDIR)/boot
	diff -r lib $(DESTDIR)$(LIBDIR)/lib
	diff -r apps $(DESTDIR)$(LIBDIR)/apps
	diff -r build/boot $(DESTDIR)$(LIBDIR)/boot
	# The tree's RELEASE IDENTITY, beside the engine's ISA fingerprint and
	# for the same reason: an installed tree has no source checkout and no
	# git, so without these two lines it cannot answer "which release is
	# this?" -- and the wrapper's pairing guard, which must decide BEFORE
	# the amalgam reaches the engine, has nothing to compare (#435).
	#
	#   release           the tag this engine was built as; the guard's key,
	#                     compared against the lock's (release "vX.Y.Z")
	#   payload.sha256    the digest of what this tree actually ships, the
	#                     same value the release manifest records -- written
	#                     AFTER the copies above so it describes the
	#                     installed bytes, not the repo's
	printf '%s\n' '$(X_RELEASE)' > $(DESTDIR)$(LIBDIR)/contract/release
	sh tools/release/payload-digest.sh $(DESTDIR)$(LIBDIR) > $(DESTDIR)$(LIBDIR)/contract/payload.sha256
.PHONY: install

uninstall: ## Uninstall from PREFIX
	rm -rf $(DESTDIR)$(LIBDIR)
	rm -rf $(DESTDIR)$(LIBEXECDIR)
	rm -f $(DESTDIR)$(BINDIR)/$(NAME)
.PHONY: uninstall

# Doxygen's C reference as man pages, deliberately NOT wired into `install`
# and `uninstall`: they are a separate, opt-in pair.  Three reasons.  The
# pages are a build product of doc-c, so `install` would grow a hard Doxygen
# dependency it does not have today.  They are not part of the x-lang tree
# whose bytes contract/payload.sha256 attests, and `install` writes that
# digest AFTER its copies precisely so it describes the shipped payload --
# man pages under MANDIR are outside $(LIBDIR) and would not belong to it.
# And MANDIR is a SHARED hierarchy: an unconditional install would make
# `make install` scatter files outside the three dirs `uninstall` owns.
#
# Two classes of page come out of doc-c and both must ship:
#
#   real pages    112 of them -- one per file, group and struct.
#   alias pages   964 one-line `.so man3/<real>.3` stubs, one per documented
#                 entity (MAN_LINKS=YES in the Doxyfile).  Without these
#                 `man x_lib_strlen` finds nothing, because the symbol is
#                 documented INSIDE its file's page.  Their `.so` argument
#                 is resolved against the man hierarchy ROOT, which is why
#                 MANDIR is that root and the pages land in its man3/.
#
# What does NOT ship: Doxygen's 18 directory pages.  It builds those file
# names from the ABSOLUTE build path (`_Users_jon_Workspace_x_src_.3`), and
# STRIP_FROM_PATH does not reach them -- it rewrites titles, not man file
# names (A/B tested; blank and `.` produce identical output).  Installing
# them would publish this checkout's path into a shared man tree, and they
# hold nothing but a subdirectory listing.  The filter keys on the page
# TITLE, not the file name, so it stays right on whatever box ran Doxygen.
MANSRC_X=docs/ref/man/man3x

# The C half is generated and installed by the engine repo (this Makefile's
# install-man-c delegates there); the x-lang half is below.  They stay apart
# because the C pages need Doxygen and these need only the engine -- joining
# them would force a Doxygen dependency on anyone who wants the library pages.
install-man-x: doc-man ## Install the x-lang reference man pages (section 3x)
	install -d -m 0755 $(DESTDIR)$(MANDIR)/man3x
	@n=0; \
	for page in $(MANSRC_X)/*.3x; do \
		install -m 0644 "$$page" $(DESTDIR)$(MANDIR)/man3x/ || exit 1; \
		n=`expr $$n + 1`; \
	done; \
	echo "  $$n x-lang pages -> $(DESTDIR)$(MANDIR)/man3x"
	@echo "  NOTE: section 3x is not searched by default -- \`man 3x <name>\`, or set MANSECT."
.PHONY: install-man-x

install-man: install-man-c install-man-x ## Install both man references to MANDIR (needs Doxygen)
.PHONY: install-man

# Removal is BY NAME, from the same generated tree install-man read, so it
# needs doc-c output to exist -- it says so rather than silently removing
# nothing.  Note the shared-hierarchy hazard this inherits: Doxygen names
# the real pages after their source files (`atom.c.3`, `buffer.h.3`), so if
# another package owns a page of the same name, install-man overwrote it and
# this removes it.  Point MANDIR at a private tree (and add it to MANPATH)
# to keep both sides out of the shared namespace:
#
#   make install-man MANDIR=$(PREFIX)/share/$(NAME)/man
#
uninstall-man-x: ## Remove the x-lang man pages from MANDIR
	@if [ ! -d $(MANSRC_X) ]; then \
		echo "uninstall-man-x reads $(MANSRC_X) to know what install-man-x shipped; run 'make doc-man' first" >&2; \
		exit 1; \
	fi
	@n=0; \
	for page in $(MANSRC_X)/*.3x; do \
		installed=$(DESTDIR)$(MANDIR)/man3x/`basename "$$page"`; \
		if [ -f "$$installed" ]; then \
			rm -f "$$installed" || exit 1; \
			n=`expr $$n + 1`; \
		fi; \
	done; \
	echo "  removed $$n x-lang pages from $(DESTDIR)$(MANDIR)/man3x"
.PHONY: uninstall-man-x

uninstall-man: uninstall-man-c uninstall-man-x ## Remove both man references from MANDIR
.PHONY: uninstall-man

clean: cov-clean ## Clean build artifacts
	rm -f $(EXECUTABLE) x-bin-debug x-bin-profile x-bin-asan x-bin-cov *.out *.core core
	@if [ -f $(ENGINE_DIR)/Makefile ]; then $(MAKE) --no-print-directory -C $(ENGINE_DIR) clean; fi
	@# Pre-rename binary names (engine was `x` until the x-bin rename): a
	@# checkout that built before the rename has stale copies at the root.
	rm -f x x-debug x-profile x-asan x-cov
.PHONY: clean

help: ## Show targets
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "\033[32m%-38s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
.PHONY: help
