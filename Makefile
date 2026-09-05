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
# The engine is a SEPARATE PROJECT, not a subdirectory of this one.  It was
# carved out on 2026-08-21 and consumed as a submodule until this repository
# learned to acquire a released one; the submodule is gone now, and what stays
# is the CONTRACT between the two repos, which is three things.
#
# 1. WHERE THE BINARY LANDS.  At this repo's root, where it has always been.
#    That is not tidiness: tests/spec-runner.sh derives its awk harness path
#    from the directory holding the engine, so the binary must physically sit
#    beside tests/ or the runner cannot find its own harness.  Keeping it here
#    is what leaves x.sh, the spec runners, tools/dev/lint.sh and the ~15
#    tools/check/*.sh scripts untouched by the split.  That derivation is the
#    DEFAULT now rather than the only way: SPEC_RUNNER_DIR overrides it, which
#    is how a caller outside this tree -- a lang bundle sourcing the
#    INSTALLED runner, where the engine is under libexec/x/ and the harness
#    under share/x/tests/ -- finds a harness that does not sit beside its
#    engine.  The default is unchanged, so this layout constraint still holds.
#
# 2. WHOSE RELEASE IT REPORTS.  ITS OWN, since the engine got a version line.
#    This repo used to pass X_RELEASE down, so the engine reported the LANGUAGE
#    release it was built for -- correct while one tag was the only identity
#    either of them had, and a lie the moment x-engine-c cut v0.1.0.  Two
#    subjects, two stamps: $(LIBDIR)/contract/release is this repo's, and the
#    engine's own is read from the (param release ...) row it declares beside
#    its binary.
#
# 3. WHERE THE ENGINE IS.  `engine` -- one path, in this repo's root, for every
#    consumer: the boot's contract includes, the JIT's -I flags, the gates, the
#    conformance runner.  It is a SYMLINK to whatever engine this tree is
#    building against, and ENGINE_SRC is what it points at.
#
#    WHY A FIXED PATH AND NOT A VARIABLE.  lib/x/boot/engine.x must include the
#    contract manifests TEXTUALLY: it loads before anything that could build a
#    path, and tools/release/amalgamate.sh inlines includes by matching a
#    literal root at the start of a line -- a computed form travels into the
#    amalgam unresolved, and an installed tree has no way to find it later.
#    That bug shipped once during the engine split.  So the indirection lives
#    in the filesystem, where a path can be one thing and mean another.
#
#    WHAT IT POINTS AT: X_ENGINE_DIR when given, otherwise WHATEVER THE LINK
#    ALREADY POINTS AT.  There is no third case any more -- this repository does
#    not carry an engine, so a tree that has never acquired one has nothing to
#    fall back to and says so.  `make engine` is the step that gets one.
#
#    THE MIDDLE RULE IS NOT COSMETIC.  Re-pointing unconditionally looked
#    right -- a stale link is a real hazard -- but it meant every `make` reset
#    the tree to the submodule.  Pointed at an artifact and then asked for the
#    spec suite, the link flipped back mid-run and the suite reported 2624
#    green tests for an engine it was no longer using.  A default that
#    silently overrides an explicit choice is worse than a stale link, which
#    at least stays where someone put it.
#
#    A DANGLING link falls back rather than failing: whatever it named is
#    gone, so it is not a choice any more.
ENGINE_SRC?=$(if $(X_ENGINE_DIR),$(X_ENGINE_DIR),$(shell if [ -L $(ENGINE_DIR) ] && [ -e $(ENGINE_DIR) ]; then readlink $(ENGINE_DIR); fi))
ENGINE_DIR=engine

# Fail with a sentence instead of a screenful of missing-file errors: a clone
# without --recursive has an empty submodule, and the first symptom would
# otherwise be make(1) complaining it has no rule to make the engine.
# ONE IMPLEMENTATION OF "POINT THE LINK", used by the phony target below and by
# every delegating recipe.  Listing `engine-link` as a prerequisite on each of
# them was the first attempt and it shipped a red main: `make test-asan` is a
# valid entry point, CI calls it directly on a fresh checkout, and the variant
# rule was one of the six places that had no such prerequisite.  A macro that
# ensures what it is about to use cannot be forgotten at a call site.
#
# Re-pointing here is a no-op in the normal case: ENGINE_SRC defaults to
# whatever the link already names, so this only does work when the link is
# missing or someone passed X_ENGINE_DIR.
ENGINE_ENSURE=if [ ! -e "$(ENGINE_SRC)" ]; then \
		echo "No engine. This repository is the LANGUAGE; the engine is a" >&2; \
		echo "separate project, acquired rather than carried:" >&2; \
		echo "" >&2; \
		echo "  make engine         fetch the release engine.pin.xon names" >&2; \
		echo "  make engine-source  clone that release and build it here" >&2; \
		echo "  make X_ENGINE_DIR=DIR   use an engine you already have" >&2; \
		exit 1; \
	fi; ln -sfn "$(ENGINE_SRC)" $(ENGINE_DIR)

# TWO WAYS TO HAVE NO SOURCES, and they want different advice.  A release
# artifact ships a working engine and no Makefile ON PURPOSE -- telling its user
# to initialise a submodule sends them after a problem they do not have.  An
# empty directory is the fresh-clone case and does.
ENGINE_MAKE=@$(ENGINE_ENSURE); if [ ! -f $(ENGINE_DIR)/Makefile ]; then \
		if [ -x $(ENGINE_DIR)/$(EXECUTABLE) ]; then \
			echo "$(ENGINE_DIR) -> $(ENGINE_SRC) is a released engine: it ships a" >&2; \
			echo "binary and no sources, so this target has nothing to build." >&2; \
			echo "For a target that needs the C: make X_ENGINE_DIR=/path/to/a/checkout" >&2; \
		else \
			echo "No engine sources at $(ENGINE_DIR) -> $(ENGINE_SRC)." >&2; \
			echo "  make engine-source      clone the pinned release and build it" >&2; \
			echo "  make X_ENGINE_DIR=DIR   use a checkout you already have" >&2; \
		fi; \
		exit 1; \
	fi; $(MAKE) --no-print-directory -C $(ENGINE_DIR)

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
# CONTENT, NOT TIMESTAMP.  `cp` guarded by make's own freshness rule was right
# while there was one engine: the only way $< changed was by being rebuilt, so
# newer meant different.  With the link switchable, the SOURCE identity changes
# without the mtime moving -- point `engine` at a release built last week and
# the copy here is newer, make calls the target up to date, and the tree keeps
# running the engine it built yesterday while every gate reports on the one it
# was pointed at.  That is the "2624 green tests for an engine it was not using"
# failure again, one rule further in.
#
# cmp instead: copy when the bytes differ, which is the question actually being
# asked, and leave the mtime alone when they do not so nothing downstream
# rebuilds for nothing.
# FORCE, so the question is always ASKED.  A content check inside the recipe is
# no use if make never runs the recipe: with the link switchable, pointing at a
# release built last week leaves the copy here newer, make calls the target up
# to date, and the tree keeps running yesterday's engine while every gate
# reports on the one it was pointed at.  Measured, not imagined -- the banner
# said v0.4.0-146-g083685e2 with `engine` pointing at the v0.1.0 release.
#
# cmp keeps FORCE cheap: copy when the bytes differ, which is the question
# actually being asked, and leave the mtime alone when they do not so nothing
# downstream rebuilds for nothing.
$(EXECUTABLE): $(ENGINE_DIR)/$(EXECUTABLE) FORCE
	@cmp -s $< $@ || cp $< $@
	# The build's param declaration travels WITH the binary, so `dirname $$X_BIN`
	# finds it in repo mode exactly as it does in an install tree.  Without this
	# the wrapper would need two ways to locate the same fact.
	@if [ -f $(ENGINE_DIR)/x-engine-build.xon ]; then cp $(ENGINE_DIR)/x-engine-build.xon x-engine-build.xon; fi

# ACQUIRE the engine the pin names, then point the link at whatever arrived.
# One linking implementation, reached with X_ENGINE_DIR -- the same door engine
# hacking uses, because a fetched release is not a special mode.
#
# Not a prerequisite of anything.  Acquisition touches the network and the pin
# is a deliberate choice; a build that silently re-pointed the engine because
# someone edited a manifest would be the "default overrides an explicit choice"
# mistake in a new place.  `make engine` is a thing you ask for.
# X_ENGINE_DIR SHORT-CIRCUITS IT.  Naming an engine explicitly and then being
# handed a downloaded one instead is the override losing to the default, which
# is the mistake this Makefile already made once with the link.  `PIN=` selects
# a different manifest, which is how the fetch gate drives this.
# THE SOURCE ARM, ON PURPOSE.  `make engine` prefers a published artifact, which
# is right for building the language and wrong for the three things that need
# the C: the sanitizer and coverage builds, and hacking on the engine itself.
# Those ask for sources rather than discovering they have none.
engine-source: ## Acquire the engine's SOURCES (clone the pinned release) and link them
	@$(MAKE) --no-print-directory engine-link \
		X_ENGINE_DIR="$$(FROM_SOURCE=1 PIN="$(PIN)" sh tools/engine/fetch.sh)"
	@echo "engine -> $$(readlink $(ENGINE_DIR))"
.PHONY: engine-source

engine: ## Acquire the engine tools/engine/engine.pin.xon names (release, or source)
	@if [ -n "$(X_ENGINE_DIR)" ]; then \
		echo "engine: X_ENGINE_DIR names $(X_ENGINE_DIR) -- linking that, not acquiring" >&2; \
		$(MAKE) --no-print-directory engine-link; \
	else \
		$(MAKE) --no-print-directory engine-link \
			X_ENGINE_DIR="$$(PIN="$(PIN)" sh tools/engine/fetch.sh)"; \
	fi
	@echo "engine -> $$(readlink $(ENGINE_DIR))"
.PHONY: engine

# NOT ABOVE `default:`.  A rule placed before it becomes the default goal --
# `make` then built the symlink, reported success, and produced no engine.
# check-bootstrap caught it; nothing else did, because every other tree
# already had a binary.
# The link is re-pointed on every build, not created once: X_ENGINE_DIR is a
# per-invocation choice, and a stale link would silently build the last
# engine someone named.  `ln -sfn` is idempotent and costs nothing.
#
# It REFUSES a real directory rather than replacing it (that is what -n buys):
# if `engine` is ever a directory of its own -- an unpacked release put there
# by hand, a botched checkout -- clobbering it would be the wrong move, and
# the error names the path.
engine-link:
	@$(ENGINE_ENSURE)
.PHONY: engine-link

# AN ENGINE DIRECTORY EITHER HAS SOURCES OR SHIPS A BINARY.  A checkout has a
# Makefile and gets built; an unpacked release has none and is already built,
# so there is nothing to do but use it.  Trying to build the second is how
# artifact mode announced itself: `make test-x` died with "no engine sources"
# while a working binary sat in the directory it had been pointed at.
#
# Failing only when BOTH are missing keeps the empty-submodule diagnostic that
# a fresh clone needs, without extending it to engines that were never going
# to be compiled here.
$(ENGINE_DIR)/$(EXECUTABLE): engine-link FORCE
	@$(ENGINE_ENSURE)
	@if [ -f $(ENGINE_DIR)/Makefile ]; then \
		$(MAKE) --no-print-directory -C $(ENGINE_DIR); \
	elif [ ! -x $(ENGINE_DIR)/$(EXECUTABLE) ]; then \
		echo "$(ENGINE_DIR) -> $(ENGINE_SRC) has neither sources to build nor an engine to use." >&2; \
		echo "For the bundled engine: git submodule update --init --recursive" >&2; \
		echo "For your own: make X_ENGINE_DIR=/path/to/engine" >&2; \
		exit 1; \
	fi

# The variants, same shape.  Each is PHONY-free for the same reason as the
# plain engine: the copy must compare timestamps, not run unconditionally.
x-bin-asan x-bin-cov x-bin-profile x-bin-debug: %: $(ENGINE_DIR)/%
	cp $< $@

$(ENGINE_DIR)/x-bin-asan $(ENGINE_DIR)/x-bin-cov $(ENGINE_DIR)/x-bin-profile $(ENGINE_DIR)/x-bin-debug: $(ENGINE_DIR)/%: FORCE
	$(ENGINE_MAKE) $*

# The C spec suite belongs to the engine repo and its CI runs it.  This is
# the local door to it, so `make test` here can still be the whole verdict.
test-c: ## Run the engine's C unit tests (delegates to the engine)
	@$(ENGINE_ENSURE); if [ -f $(ENGINE_DIR)/Makefile ]; then \
		$(MAKE) --no-print-directory -C $(ENGINE_DIR) test-c; \
	else \
		echo "test-c: SKIPPED -- $(ENGINE_DIR) is a released engine and ships no C suite."; \
		echo "  A release is published only from a green run of it; this tree tests"; \
		echo "  the PAIR instead -- conformance, compliance and the spec suites."; \
	fi
.PHONY: test-c

# The C reference is Doxygen over the engine's sources, so it generates
# INSIDE the engine (engine/docs/ref/c/).  pages.yml copies from
# there; this target exists so `make doc` is still both halves.
doc-c: ## Generate C reference documentation (delegates to the submodule)
	$(ENGINE_MAKE) doc-c
.PHONY: doc-c

install-man-c uninstall-man-c: ## The C reference man pages (delegates to the engine)
	@$(ENGINE_ENSURE); if [ -f $(ENGINE_DIR)/Makefile ]; then \
		$(MAKE) --no-print-directory -C $(ENGINE_DIR) $@ DESTDIR="$(DESTDIR)" MANDIR="$(MANDIR)"; \
	else \
		echo "$@: SKIPPED -- the C reference is Doxygen over the engine's sources,"; \
		echo "  and $(ENGINE_DIR) is a release that ships none.  The engine publishes"; \
		echo "  its own; make engine-source to build them here."; \
	fi
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
# THE COV HALF NEEDS A COV ENGINE, and the rest of the suite does not.  Making
# the whole target depend on x-bin-cov meant a tree running a released engine
# could not run ANY tool spec: the variant has to be compiled, and a release
# ships no C.  Splitting it keeps the artifact path honest -- the tools are
# x-lang's, and only the coverage tool needs an instrumented engine under it.
test-tools: $(EXECUTABLE) ## Run the tool suite's specs (tools/tests)
	sh tools/tests/spec-runner.sh
	@$(ENGINE_ENSURE); if [ -f $(ENGINE_DIR)/Makefile ]; then \
		$(MAKE) --no-print-directory x-bin-cov && sh tools/tests/cov-spec-runner.sh; \
	else \
		echo "test-tools: cov specs SKIPPED -- the coverage engine is a BUILD of the"; \
		echo "  engine (-DX_COV), and $(ENGINE_DIR) is a release that ships no C."; \
		echo "  make engine-source, then make test-tools, to run them."; \
	fi
.PHONY: test-tools

# The doctest ratchet (#16): every (example "in" "out") in the doc registry
# is an executable contract -- "out" must be the true echo.  tools/check/doctest.sh
# extracts them into a generated spec; the lang runner executes it.
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
gates: engine-link check-engine-fetch check-boot-closed check-isa check-prim-coverage check-obj-layout check-base-paths check-boot-order check-path-literals check-boot-amalgam check-pin check-release-manifest check-bootstrap check-package check-doc-vocab check-dup-defs check-bare-globals check-percent-globals check-constraints check-engine-contract check-compliance check-conformance-coverage check-engine-seam check-platform-seam check-second-engine check-base-routes check-seam check-langs check-wrapper check-spec-weights check-spec-globals check-release-version check-dialect-cover check-highlight-roundtrip check-primitives-doc ## Run the contract gates
.PHONY: gates

.PHONY: check-spec-weights
# The spec suite talks to the ENGINE (cat lib | x-bin), by design, so x.sh's
# own argument surface is invisible to it -- which is how a piped program came
# to evaluate nothing, successfully, undetected.  This gate is the wrapper's
# only test.
check-wrapper: ## x.sh's entry points (-c, -f, -F, stdin, -l) evaluate what they are handed
	sh tools/check/wrapper.sh
.PHONY: check-wrapper

check-spec-weights: ## Every spec file declares a `# @weight N`
	sh tools/check/spec-weights.sh

# Glob mode buckets SPEC_BATCH files into one interpreter, and the harness
# evaluates top-level snippet forms with eval!, so a spec that defs a shared
# name takes it from every later file in its bucket.  The breakage surfaces in
# someone else's spec, at one batch size, looking like anything but its cause.
.PHONY: check-spec-globals
check-spec-globals: ## No spec rebinds a name the engine or library owns
	sh tools/check/spec-globals.sh

# The local-latency split (2026-08-03 audit): `make test` grew past ten
# minutes (build/install/package smokes, amalgam boots, doctest walk,
# example programs) and the pre-push hook ran ALL of it inside the open
# push connection -- long enough for GitHub to hang up the idle SSH
# channel mid-hook.  gates-fast is the sub-minute subset: every scan
# ratchet, none of the targets that build or boot artifacts.  The hook
# runs test-fast; CI still runs the FULL `make test` on every push/PR
# (ci.yml unchanged -- it stays the enforcing gate for the heavy surface).
gates-fast: engine-link check-engine-fetch check-isa check-prim-coverage check-obj-layout check-base-paths check-boot-order check-path-literals check-doc-vocab check-dup-defs check-bare-globals check-percent-globals check-constraints check-engine-contract check-conformance-coverage check-engine-seam check-platform-seam check-second-engine check-base-routes check-seam check-wrapper check-spec-weights check-spec-globals check-release-version check-dialect-cover check-primitives-doc ## The fast contract gates (pre-push subset)
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
# ANNOUNCE, DO NOT FAIL, when the engine ships no sources.  These three ask
# whether the engine's C agrees with the manifests it publishes -- a question
# with no subject in a released artifact, which carries the manifests and no C.
#
# SKIPPING IS THE DANGEROUS SHAPE, so it says so on every run and names what
# still covers the ground: the engine's own repository runs these three on
# every build of itself, and check-compliance here verifies that the digests
# its declaration states still describe the manifests shipped beside it.  A
# gate that goes quiet is indistinguishable from a gate that passed, which is
# the vacuous-pass family this project has now met five times.
check-isa check-obj-layout check-base-paths: ## Engine contract ratchets (delegated)
	@$(ENGINE_ENSURE); if [ -f $(ENGINE_DIR)/Makefile ]; then \
		$(MAKE) --no-print-directory -C $(ENGINE_DIR) $@; \
	else \
		echo "$@: SKIPPED -- $(ENGINE_DIR) is a released engine and ships no C."; \
		echo "  Its own repository ratchets this on every build; check-compliance"; \
		echo "  here holds the digests it declares against the manifests it ships."; \
	fi
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
# The acquisition path reaches the network and runs exactly once per machine,
# which makes it the least-exercised code in the build.  This drives it over
# file:// against a fixture tarball: verify, reuse, tamper, a declared artifact
# that will not fetch, and an unknown pin form.
check-engine-fetch: ## Smoke the engine acquisition path (hermetic, file://)
	sh tools/check/engine-fetch.sh
.PHONY: check-engine-fetch

# An amalgam claims to be a whole boot.  It was true of what the entry includes
# and false of what it imports -- those resolved against the platform at boot,
# which is the mixture #435 crashed on and the hole #467 named.  This holds the
# claim: seconds, on the commit that would break it.
check-boot-closed: boot ## Assert a boot amalgam loads nothing from the platform
	sh tools/check/boot-closed.sh
.PHONY: check-boot-closed

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
	@# GUARDED, because apps/ is empty since Logo became a bundle and an
	@# unmatched glob is the literal pattern, which amalgamate.sh would then
	@# try to open.  The mechanism stays (see apps/README.md); the loop just
	@# has to survive having nothing to do.
	@for a in apps/*/run.x; do \
		[ -e "$$a" ] || continue; \
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

# Cheap, static, and the only thing standing between the re-partition (#486)
# and the undifferentiated list it replaced.  It reads the ENGINE's isa.x, so
# a second engine with a different surface re-files this document by being
# built against, not by anyone remembering to edit a table here.
check-primitives-doc: ## Assert docs/primitives.md files each form where it lives
	sh tools/check/primitives-doc.sh
.PHONY: check-primitives-doc

# The platform seam: the build triple is PARSED in lib/x/platform/syscall.x and
# nowhere else.  Three modules used to pick x-machine apart independently and only
# one knew Darwin spells A64 "arm64" where GNU triplets spell it "aarch64".  Using
# the whole triple as an opaque value -- a cache key, a diagnostic -- stays fine;
# what belongs to the platform layer is taking it apart.
check-platform-seam: ## Assert the build triple is parsed only in the platform layer
	sh tools/check/platform-seam.sh
.PHONY: check-platform-seam

# THE SECOND-ENGINE GATE.  The whole engine-contract arc rests on the claim that
# the vocabulary, the generator and the resolver describe ANY conforming engine --
# and nothing tested that while only one engine existed.  The first time the
# apparatus was pointed at a second one it gave two wrong answers: the contract
# gate could not be asked about another engine at all, and the generator wrote
# capability claims the engine had no rows for.  This runs the apparatus against a
# paper engine on every build so those cannot come back.
check-second-engine: ## Assert the contract apparatus is engine-agnostic
	sh tools/check/second-engine.sh
.PHONY: check-second-engine

check-base-routes: ## Assert the engine's base carries the routes lib/ walks
	sh tools/check/base-routes.sh
.PHONY: check-base-routes

# The LANG SEAM (docs/lang-contract.md).  A lang lives in its own repository,
# so a rename here that drops one of the names it is promised breaks it
# silently and this tree stays green -- one of the three ways the last
# generation of langs rotted, and the one no amount of testing over there can
# catch in time.  ~8s for all three dialects, which is why it rides the fast
# gates rather than the deep tier.
check-seam: $(EXECUTABLE) ## Assert the platform still provides what a lang is promised
	sh tools/check/seam.sh
.PHONY: check-seam

# EVERY LANG, AGAINST THIS WORKING TREE.  check-seam above catches a RENAME in
# eight seconds and cannot catch anything else -- a behaviour change, an arity
# change, a reader that scores a tie differently all leave this tree green while
# a bundle in its own repository breaks.  Each bundle's CI runs on its own
# schedule against a RELEASE, so the break surfaces weeks later as somebody
# else's mystery.  That is the same shape as the rot the five 2024-era
# personalities died of.
#
# Measured when this gate was written: x-lang green at 2590/0, and the six
# bundles carrying 175 failures between them with nothing here saying so.
#
# Minutes, not seconds (r5rs and r7rs are ~1300 specs together), which is why it
# rides the deep tier and check-seam rides the fast one.  Advisory about
# presence -- a bundle that is not on the disk is announced and skipped, because
# this tree must build for someone who cloned nothing else -- and strict about
# regression.  Budgets in tools/contract/langs.x, which may only shrink.
# LANGS='krn sweet' runs a subset; X_LANGS_DIR moves where bundles are found.
check-langs: $(EXECUTABLE) ## Run every lang bundle's suite against this tree
	sh tools/check/langs.sh
.PHONY: check-langs

# THE VERSION A RELEASE REPORTS.  v0.6.0 shipped saying `helium 0.5.2`, because
# the tag and the changelog moved and lib/x-core.x did not.  Only meaningful at
# a tag, where it is the difference between a release and a release that lies
# about itself; skips loudly anywhere else.
check-release-version: ## Assert the tag, x-lib-version and the CHANGELOG agree
	sh tools/check/release-version.sh
.PHONY: check-release-version

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
	@if [ ! -f $(ENGINE_DIR)/Makefile ] && [ -x $(ENGINE_DIR)/$(EXECUTABLE) ]; then \
		echo "retired-c-symbols: SKIPPED -- $(ENGINE_DIR) is a released engine and ships no C."; \
		exit 0; \
	fi; \
	if [ ! -d $(ENGINE_DIR)/src ] || [ ! -d $(ENGINE_DIR)/include ]; then \
		echo "retired-c-symbols: FAIL (no C tree at $(ENGINE_DIR); run 'git submodule update --init --recursive')" >&2; \
		exit 1; \
	fi; \
	if grep -rnw 'x_eval_filein_push\|x_eval_filein_pop\|x_eval_buffer_pop\|x_char_utf8_len\|x_char_utf8_encode\|x_type_alist_iter\|x_type_alist_iter_prim\|x_type_iter_isempty' $(ENGINE_DIR)/src $(ENGINE_DIR)/include; then \
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
	# And the BUILD's own facts beside it.  x-engine.xon is generated from source
	# and carries no (param ...) rows on purpose -- word size, byte order and
	# architecture belong to a BINARY, not a tree.  This is what lets the platform
	# layer read a declaration instead of sniffing the build triple at runtime, and
	# what a cross-compiled engine reports its TARGET through.
	@if [ -f $(ENGINE_DIR)/x-engine-build.xon ]; then \
		install $C -m 0644 $(ENGINE_DIR)/x-engine-build.xon $(DESTDIR)$(LIBEXECDIR)/x-engine-build.xon; \
	else \
		echo "install: WARNING -- $(ENGINE_DIR)/x-engine-build.xon is missing; the installed tree cannot say what platform its engine was built for" >&2; \
	fi
	@if [ -f $(ENGINE_DIR)/entitlements.plist ]; then codesign -s - --entitlements $(ENGINE_DIR)/entitlements.plist -f $(DESTDIR)$(LIBEXECDIR)/$(EXECUTABLE) 2>/dev/null || true; fi
	install $C -m 0755 $(NAME).sh $(DESTDIR)$(BINDIR)/$(NAME)
	rm -rf $(DESTDIR)$(LIBDIR)/lib $(DESTDIR)$(LIBDIR)/apps $(DESTDIR)$(LIBDIR)/boot $(DESTDIR)$(LIBDIR)/tests
	# The engine's ISA fingerprint travels WITH the engine -- literally so
	# since the split: the manifest is the engine's own
	# $(ENGINE_DIR)/tools/contract/isa.x, not a copy this repo keeps.  An installed
	# tree has no source checkout, so before this there was no way to ask
	# "which engine contract is this?" -- fetch could not compare (#186)
	# and a pinned boot could not refuse a mismatched amalgam (#187); it
	# just ran it and segfaulted.  One precomputed hex line: the wrapper
	# needs a STRING compare against a release manifest, not a digester.
	install -d -m 0755 $(DESTDIR)$(LIBDIR)/contract
	@# THE ENGINE'S RELEASE, beside the library's, because they are two facts
	@# now.  Read from the row the engine declares rather than asked of the
	@# binary: the wrapper compares this before deciding whether an engine may
	@# boot a pinned amalgam, and starting an engine to find out whether it is
	@# allowed to start is the wrong shape.  Absent (an engine that predates
	@# the row) leaves no file, and the guard announces rather than assumes.
	@sed -n 's/^(param release "\(.*\)")[[:space:]]*$$/\1/p' \
		$(ENGINE_DIR)/x-engine-build.xon 2>/dev/null | head -1 \
		> $(DESTDIR)$(LIBDIR)/contract/engine-release || true
	@[ -s $(DESTDIR)$(LIBDIR)/contract/engine-release ] \
		|| rm -f $(DESTDIR)$(LIBDIR)/contract/engine-release
	@# THROUGH $(ENGINE_DIR), like everything else.  This line held a literal
	@# ext/x-engine-c while the comment above it already said $(ENGINE_DIR) --
	@# harmless while there was one engine at one path, and wrong the moment
	@# there was not: it would stamp the SUBMODULE's fingerprint into a tree
	@# built against another engine, and the wrapper compares that stamp to
	@# decide whether a pinned amalgam may boot.
	@sh -c 'if command -v shasum >/dev/null 2>&1; then shasum -a 256 $(ENGINE_DIR)/tools/contract/isa.x | cut -d" " -f1; 		else sha256sum $(ENGINE_DIR)/tools/contract/isa.x | cut -d" " -f1; fi' 		> $(DESTDIR)$(LIBDIR)/contract/isa.sha256
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
	# THE SHARED SPEC RUNNER, and only it -- not tests/, which is this
	# repo's own suite and no business of an installed tree.  A lang
	# bundle keeps its specs in its own repository and runs them with this
	# runner, sourcing it as <root>/tests/spec-runner.sh where <root> is what
	# `x --share-dir` answers.  Shipping it is what stops every bundle
	# vendoring 865 lines of shell and awk and drifting into a spec-format
	# dialect apiece (docs/lang-contract.md).
	#
	# NOT IN THE PAYLOAD FINGERPRINT, deliberately: that digest is library
	# bytes -- lib, apps, boot -- and answers "which release is this".  The
	# wrapper and the engine already ship outside it; a tool belongs with
	# them, and tools/release/payload-digest.sh stays untouched.
	install -d -m 0755 $(DESTDIR)$(LIBDIR)/tests
	install $C -m 0644 tests/spec-runner.sh $(DESTDIR)$(LIBDIR)/tests/spec-runner.sh
	install $C -m 0644 tests/spec-runner.awk $(DESTDIR)$(LIBDIR)/tests/spec-runner.awk
	diff tests/spec-runner.sh $(DESTDIR)$(LIBDIR)/tests/spec-runner.sh
	diff tests/spec-runner.awk $(DESTDIR)$(LIBDIR)/tests/spec-runner.awk
	# THE LANG KIT, on exactly the argument above.  The spec runner was the
	# first thing every bundle would otherwise have vendored; it is not the
	# only one.  These checks are byte-identical in every bundle -- the same
	# file was written twice and needed three fixes backported to the second
	# copy the day it was written -- so they ship here and bundles carry a
	# shim, addressed as <root>/tools/lang-kit where <root> is what
	# `x --share-dir` answers.
	#
	# Outside the payload fingerprint, for the same reason the runner is.
	install -d -m 0755 $(DESTDIR)$(LIBDIR)/tools/lang-kit
	install $C -m 0644 tools/lang-kit/release-refs.sh $(DESTDIR)$(LIBDIR)/tools/lang-kit/release-refs.sh
	diff tools/lang-kit/release-refs.sh $(DESTDIR)$(LIBDIR)/tools/lang-kit/release-refs.sh
	install $C -m 0644 tools/lang-kit/spec-gate.sh $(DESTDIR)$(LIBDIR)/tools/lang-kit/spec-gate.sh
	diff tools/lang-kit/spec-gate.sh $(DESTDIR)$(LIBDIR)/tools/lang-kit/spec-gate.sh
	# The tree's RELEASE IDENTITY, beside the engine's ISA fingerprint and
	# for the same reason: an installed tree has no source checkout and no
	# git, so without these two lines it cannot answer "which release is
	# this?" -- and the wrapper's pairing guard, which must decide BEFORE
	# the amalgam reaches the engine, has nothing to compare (#435).
	#
	#   release           the tag THIS LIBRARY was installed from -- it lands
	#                     under $(LIBDIR)/contract for that reason.  The
	#                     wrapper compares it to the lock's (release "vX.Y.Z")
	#                     because a boot amalgam imports from this lib/ and
	#                     apps/ as it boots (#467), so the pairing that can
	#                     corrupt is amalgam-to-LIBRARY.  It currently equals
	#                     the engine's stamp only because one X_RELEASE is
	#                     passed to both.
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
