#!/bin/sh
# # Computational Expressions in C
#
# ## x.sh -- Shell Wrapper
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
# ABSOLUTE, not as spelled: every path the wrapper derives (install root,
# entry, engine) hangs off this, and the install root reaches the
# interpreter as DATA that import resolution consumes.  A `./x/bin/x`
# invocation made that root start with `./`, which is the marker for
# resolve-against-the-INCLUDING-FILE -- so the root got re-based and the
# boot's first include failed with `include: cannot open` (x-lang#188).
# Only the `./` spelling broke; bare and deeper relative paths happened
# to work, which is exactly the kind of accident normalising removes.
SCRIPT_PATH=$(cd "$(dirname "$0")" && pwd)
X_EXT=.x
X_LIB=x
# One definition per name the wrapper embeds; every use below reads these.
X_PIN=pin.xon            # pin manifest (docs/modules.md "Pinning")
X_PIN_MOD=x/tool/pin     # platform-side pin loader, imported by pin_arm
X_LAUNCH=x/repl/launch.x # interactive launcher, cat'd after -F / pinned REPL
                         # (a platform file: deliberately not -e/X_EXT-aware)
X_RUN=run                # app entry basename: apps/NAME/run.x (#35)
X_SHARE=share/x          # installed runtime tree, beside the bin dir
X_ENGINE_DIR=libexec/x   # installed engine directory (binary + its declaration)
X_ENGINE=x-bin           # default engine binary NAME (see engine discovery below)

# Repo mode: a lib tree at the CURRENT directory (the boot includes are
# cwd-relative "lib/..." literals, so cwd must be the repo root anyway),
# entries loaded live.  Probe for the entry file, not a bare lib/
# directory -- any unrelated project's lib/ used to hijack the path here.
# Installed mode: the runtime tree sits beside the wrapper's bin dir
# (share/x); entries are the amalgamated boot files under share/x/boot
# (zero path literals), and the import root reaches the interpreter as
# DATA -- one (def %install-root ...) form emitted at the top of the pipe
# (module.x consumes it; def is a C prim so no library is needed to
# evaluate it).
LIB_PATH=lib/
APPS_PATH=apps/
ENTRY_DIR=lib/
INSTALL_ROOT=
# Where acquired lang bundles live (docs/lang-contract.md).
#
# deps/, NOT beside lib/ and apps/, and the distinction is the point: lib/ and
# apps/ are this project's own committed source, while a bundle is a verified
# tarball fetched from somebody else's repository.  They resemble each other
# only in that -l searches all three.  Nor build/ -- a bundle was not BUILT
# here, and filing acquired things under output is how the engine came to need
# a symlink to be findable at all.  X_LANG_DIR moves it.
LANGS_PATH="${X_LANG_DIR:-deps/langs/}"
if [ ! -e "${LIB_PATH}${X_LIB}${X_EXT}" ]; then
	INSTALL_ROOT="$SCRIPT_PATH/../${X_SHARE}"
	LIB_PATH="$INSTALL_ROOT/lib/"
	APPS_PATH="$INSTALL_ROOT/apps/"
	ENTRY_DIR="$INSTALL_ROOT/boot/"
	[ -n "${X_LANG_DIR:-}" ] || LANGS_PATH="$INSTALL_ROOT/langs/"
fi

# Both forms below emit a path as an x-lang STRING LITERAL ahead of the
# boot entry.  A path holding a double quote or a backslash would close
# that literal and inject forms into the boot stream -- the shell hole
# shquote closes, one evaluator further in.  Refuse the path instead of
# picking an escaping scheme the reader may not share: these are install
# and project directories, and a quote in one is a mistake, not a need.
path_form_safe() {
	case "$1" in
		*\"* | *\\*)
			echo "Error: $2 path contains a quote or backslash: $1" >&2
			echo "  the path is emitted as an x-lang string; rename the directory" >&2
			exit 1
			;;
	esac
}

# --- lang bundles ------------------------------------------------
# A bundle is a DIFFERENT SURFACE LANGUAGE acquired as a pinned artifact
# (Pin bundle; docs/lang-contract.md).  Unlike a dialect entry it
# does not boot itself: the wrapper boots the dialect the bundle DECLARES,
# then loads the bundle on top -- exactly the shape -F already has (entry
# in --batch so its own launcher stays quiet, the file next, the launcher
# last).  That is why a bundle's entry needs no root-relative literals at
# all: the platform is already up when it is read, and its own modules
# resolve through the root emitted below.
#
# Read TEXTUALLY, one form per line, nothing evaluated -- the discipline
# every other manifest read in this file follows.  The wrapper must choose
# an entry before the pipe exists, so it cannot ask x to parse this.
BUNDLE_DIR=
BUNDLE_ENTRY=
BUNDLE_DIALECT=
BUNDLE_DEPS=

# The directory of the bundle calling itself $1, or empty.  Factored out
# because dependency resolution needs exactly the same lookup, including the
# duplicate-name refusal: a bundle reached as a dependency is no more allowed
# to be ambiguous than one named on the command line.
bundle_dir_of() {
	_found=
	for _d in "$LANGS_PATH"*/; do
		[ -f "$_d/lang.xon" ] || continue
		_n=$(sed -n 's/^(lang "\([^"]*\)").*/\1/p' "$_d/lang.xon" | head -1)
		[ "$_n" = "$1" ] || continue
		# TWO BUNDLES CLAIMING ONE NAME IS A MISCONFIGURATION, not a race to
		# be won by directory order: a project pins ONE release, and picking
		# silently would make which one you got depend on the filesystem.
		if [ -n "$_found" ]; then
			echo "Error: two bundles both call themselves '$1':" >&2
			echo "    $_found" >&2
			echo "    $_d" >&2
			echo "  remove the one you are not pinning" >&2
			exit 1
		fi
		_found="$_d"
	done
	[ -n "$_found" ] || return 1
	(cd "$_found" && pwd)
}

# The (requires-lang ...) rows of $1's lang.xon, as NAME|VERSION tokens with
# VERSION empty when the row names none.  Two expressions rather than one
# optional group, because BRE has no optional group worth relying on.
bundle_reqs_of() {
	sed -n 's/^(requires-lang "\([^"]*\)"[^"]*"\([^"]*\)").*/\1|\2/p' "$1/lang.xon"
	sed -n 's/^(requires-lang "\([^"]*\)")[[:space:]]*$/\1|/p' "$1/lang.xon"
}

# What an INSTALLED lang says it is.  Written by its `make install` from git
# describe, never committed -- a version in lang.xon could only be true at the
# one commit that gets tagged, and would lie on every other.  Absent in a
# checkout, which is a fact worth reporting rather than papering over.
bundle_version_of() {
	[ -f "$1/version" ] && head -1 "$1/version"
}

# Every root $1's bundle needs armed, deepest dependency first, in
# BUNDLE_DEPS.
#
# A lang may be written on top of another -- R7RS is R5RS plus about 700 lines
# -- and before this row that dependency had nowhere to live.  The dependent
# probed for its sibling from its own entry, which meant a missing dependency
# was a runtime message rather than a refusal, nothing recorded WHICH lang was
# needed, and every dependent re-derived the same path.  The same argument
# (dialect ...) already makes: a requirement belongs in the manifest, where it
# can be refused before anything boots.
#
# DEPTH-FIRST, and the ORDER IS THE POINT.  import-path! prepends, so the root
# armed last is searched first; emitting dependencies before the bundle's own
# root leaves the bundle itself winning any name it shares with something it
# depends on.
#
# $2 is the chain so far, used both to break cycles and to say where a missing
# lang was asked for.
bundle_deps_collect() {
	_dir=$(bundle_dir_of "$1") || {
		echo "Error: lang '$1' is required but not installed" >&2
		echo "  required by: $2" >&2
		echo "  searched ${LANGS_PATH}*/lang.xon" >&2
		echo "  install it, or set X_LANG_DIR to where it lives" >&2
		exit 1
	}
	case " $2 " in
		*" $1 "*)
			echo "Error: langs require each other in a cycle: $2 $1" >&2
			exit 1
			;;
	esac
	# $3 is the version the requirer named, empty when it named none.
	#
	# COMPARED FOR EQUALITY, NEVER PARSED -- the platform's existing rule for
	# release strings, and the reason there is no resolver here.  Ordering and
	# ranges would need a version algebra this tree has avoided everywhere
	# else; equality plus a declared waiver is smaller and says what it means.
	if [ -n "$3" ] && [ -z "$allow_lang_skew" ]; then
		_have=$(bundle_version_of "$_dir")
		if [ -z "$_have" ]; then
			echo "Error: lang '$1' is required at $3 but reports no version" >&2
			echo "  required by: $2" >&2
			echo "  $_dir carries no version stamp -- it is a checkout, not an install" >&2
			echo "  run 'make install' in it, or pass --allow-lang-skew" >&2
			exit 1
		fi
		if [ "$_have" != "$3" ]; then
			echo "Error: lang '$1' is $_have, but $3 is required" >&2
			echo "  required by: $2" >&2
			echo "  found in $_dir" >&2
			echo "  install the version asked for, or pass --allow-lang-skew" >&2
			exit 1
		fi
	fi
	for _row in $(bundle_reqs_of "$_dir"); do
		bundle_deps_collect "${_row%%|*}" "$2 $1" "${_row#*|}"
	done
	# Append after our own dependencies, so a diamond arms the shared one
	# once and earliest.
	case " $BUNDLE_DEPS " in
		*" $_dir "*) ;;
		*) BUNDLE_DEPS="$BUNDLE_DEPS $_dir" ;;
	esac
}

bundle_resolve() {
	[ -d "$LANGS_PATH" ] || return 0
	_found=$(bundle_dir_of "$1") || return 0
	BUNDLE_DIR="$_found"
	BUNDLE_DIALECT=$(sed -n 's/^(dialect \([a-z0-9-]*\)).*/\1/p' "$BUNDLE_DIR/lang.xon" | head -1)
	BUNDLE_ENTRY=$(sed -n 's/^(entry "\([^"]*\)").*/\1/p' "$BUNDLE_DIR/lang.xon" | head -1)
	: "${BUNDLE_DIALECT:=he}"
	: "${BUNDLE_ENTRY:=run.x}"
	if [ ! -f "$BUNDLE_DIR/$BUNDLE_ENTRY" ]; then
		echo "Error: bundle '$1' names an entry that is not there: $BUNDLE_ENTRY" >&2
		echo "  looked in $BUNDLE_DIR" >&2
		exit 1
	fi
	path_form_safe "$BUNDLE_DIR" "bundle root"
	# Dependencies of the bundle itself, not the bundle -- it is armed by
	# bundle_form, after these and therefore ahead of them in the search.
	for _row in $(bundle_reqs_of "$BUNDLE_DIR"); do
		bundle_deps_collect "${_row%%|*}" "$1" "${_row#*|}"
	done
	for _d in $BUNDLE_DEPS; do
		path_form_safe "$_d" "required lang root"
	done
}

# The bundle's module root, emitted after the dialect has booted (import-path!
# is module.x's, so it does not exist before that) and before the bundle's own
# entry is read.  Same route %install-root takes, and for the same reason.
#
# %lang-root IS THE SAME FACT AS A VALUE, and it exists because a bundle may
# ship DATA as well as modules.  import-path! answers "where do my modules
# come from" for the module system; it answers nothing for a file the bundle
# reads itself -- x-logo's serve.x hands viewer.html to a browser, and no
# `import` can express that.  Without this row such a bundle has three bad
# options: a cwd-relative literal (broken in every installed tree -- the exact
# defect x-lang#467 fixed in the in-tree Logo app), a root re-derived from
# %install-root (wrong, a bundle is not under the platform's tree), or reading
# %import-roots-cell, which is a platform internal the seam does not cover.
#
# ONE DEFINITION, EMITTED WHERE THE FACT IS KNOWN.  The wrapper is the only
# thing that ever knows where a bundle sits -- it is what searched for it --
# so it says, once, rather than every bundle guessing.  Only for the bundle
# itself, never for its dependencies: a required lang reached through
# (requires-lang ...) is a library to the bundle that needs it, and a second
# %lang-root would overwrite the one whose entry is about to run.
bundle_form() {
	if [ -n "$BUNDLE_DIR" ]; then
		# Required langs first: import-path! prepends, so the bundle's own
		# root ends up searched ahead of everything it depends on.
		for _d in $BUNDLE_DEPS; do
			printf '(import-path! "%s")\n' "$_d"
		done
		printf '(import-path! "%s")\n' "$BUNDLE_DIR"
		printf '(def %%lang-root "%s")\n' "$BUNDLE_DIR"
		# %batch? MEANS "A FILE WAS SUPPLIED", and for a bundle it had stopped
		# meaning that.  --batch is passed unconditionally down there (the
		# `if [ "$file" ]` below is always true once the bundle entry joins
		# $file), because it is what keeps the DIALECT entry's own launcher
		# quiet -- and banner.x derives %batch? from argv, so every bundle saw
		# `true` whether or not the user named a file.
		#
		# The two questions were the same question until bundles existed.  They
		# are not: what --batch suppresses is the dialect's launcher, and what
		# a lang asks %batch? is whether there is a session to hand over.  x-
		# sweet's `(unless %batch? (%banner))` has silently never fired for want
		# of this line, and x-logo's entry has to choose between its REPL and
		# its batch reader on exactly this fact -- with the wrong answer it
		# reads the launcher x.sh appended as a Logo program.
		#
		# Restored HERE rather than by not passing --batch, because the flag is
		# still doing its other job.  The dialect has booted by this point, so
		# banner.x's def exists to be set!.
		#
		# Not when the boot comes from a STATE IMAGE ($1 = image): the pipe
		# emits the reset after the loader, since a def made before the
		# install is replaced with it.
		[ -n "$file1" ] || [ "$1" = image ] || printf '(set! %%batch? ())\n'
	fi
}

# The engine's BUILD PARAMETERS, emitted ahead of the entry as data -- the same
# route %install-root takes, and for the same reason: the platform layer needs
# them before any file I/O exists.
#
# These are facts of the BINARY (word size, byte order, os, arch), generated by
# the engine's own build from the COMPILER producing it, so a cross-compiled
# engine reports its target rather than the machine that built it.  x-engine.xon
# carries no param rows on purpose -- it is generated from source, and a 32-bit
# and a 64-bit build of one tree differ here and nowhere else in the contract.
#
# Emitted as SYMBOLS, not strings: the platform layer loads mid-x-core where the
# string protocol does not exist yet, and eq? on interned symbols works from the
# first form.  Textual extraction, nothing evaluated, like every other manifest
# read in this file.  A row reading `unknown` is deliberately NOT emitted -- the
# generator writes that when a fact could not be established, and x-lang falling
# back to its own detection beats believing a value nobody knows.
param_forms() {
	_pf="$(dirname "$X_BIN")/x-engine-build.xon"
	[ -f "$_pf" ] || return 0
	# The quoted rows first: `machine` and `release` are STRINGS, because their
	# values are free-form -- a triple, a tag, a describe -- and the bare-atom
	# sed below would mangle them.  A release reaches the library as a string
	# for the same reason nothing parses it anywhere else.
	_rel=$(sed -n 's/^(param release "\(.*\)")[[:space:]]*$/\1/p' "$_pf" | head -1)
	[ -n "$_rel" ] && [ "$_rel" != "unknown" ] && printf '(def %%param-release "%s")\n' "$_rel"
	sed -n 's/^(param \([a-z-]*\) \([a-z0-9_-]*\))[[:space:]]*$/\1 \2/p' "$_pf" \
	| while read -r _k _v; do
		[ "$_v" = "unknown" ] && continue
		case "$_k" in
			word-size) printf '(def %%param-word-size %s)\n' "$_v" ;;
			endian|os|arch) printf '(def %%param-%s (lit %s))\n' "$_k" "$_v" ;;
		esac
	done
}

# The install-root form, emitted ahead of the entry in installed mode; a
# no-op command in repo mode (nothing defines %install-root there).
root_form() {
	if [ -n "$INSTALL_ROOT" ]; then
		printf '(def %%install-root "%s")\n' "$INSTALL_ROOT"
		# The platform's own release, as DATA, the way %param-release already
		# carries the engine's: make install writes contract/release beside the
		# library, and a banner that can say WHICH x-lang answered saves the
		# next which-install-am-I-running investigation (a lang REPL cannot
		# read the file itself without an FFI excursion; the shell is already
		# here).  A checkout has no contract/ and emits nothing -- absence
		# says checkout, which is also information.
		if [ -f "$INSTALL_ROOT/contract/release" ]; then
			_prel=$(head -1 "$INSTALL_ROOT/contract/release")
			[ -n "$_prel" ] && printf '(def %%platform-release "%s")\n' "$_prel"
		fi
	fi
}

# The pin forms (docs/modules.md "Pinning"): the manifest's path ahead of
# the entry as DATA (def is a C prim, like the install root above), the
# loader import after it -- post-boot, before any user form.  The loader
# (lib/x/tool/pin.x) resolves platform-side, before any overlay root is
# armed, and READS the manifest; nothing in it is evaluated.  Both
# functions are no-ops when no manifest was found.
pin_form() {
	if [ -n "$PIN_FILE" ]; then
		printf '(def %%pin-file "%s")\n' "$PIN_FILE"
	fi
}
pin_arm() {
	if [ -n "$PIN_FILE" ]; then
		printf '(import %s)\n' "$X_PIN_MOD"
	fi
}
# -c/--eval source, emitted onto the pipe after the library and after any
# -F file, so an expression can use what those defined.  printf '%s' and
# not echo: an expression starting with -n or containing a backslash is
# DATA, and echo would eat it.
eval_form() {
	if [ -n "$have_eval" ]; then
		printf '%s' "$eval_src"
	fi
}

[ -z "$INSTALL_ROOT" ] || path_form_safe "$INSTALL_ROOT" "install root"

# ENGINE DISCOVERY.  x-lang is not tied to one engine (docs/engine-contract.md),
# so the wrapper resolves WHICH engine to run rather than assuming a filename.
# Three sources, most specific first:
#
#   1. $X_BIN in the environment -- an explicit choice, used by the conformance
#      and compliance runners to aim the same library at another engine.  Several
#      tools/check scripts already read X_BIN this way, so honouring it here is
#      the existing convention rather than a new one.
#   2. The installed engine directory.  Its x-engine.xon names the binary in a
#      (binary "...") row, so an engine that does not build something called
#      x-bin still installs and runs.  Read TEXTUALLY, one line, nothing
#      evaluated -- the same discipline every other manifest read in this file
#      follows.
#   3. Beside this script, under the default name -- repo mode, where the
#      Makefile copies the built engine to the repository root.  The engine must
#      physically sit there: tests/spec-runner.sh derives its awk harness path
#      from the directory holding it, unless the caller sets SPEC_RUNNER_DIR
#      (which is how an installed tree's runner is sourced from outside it).
#
#   `--engine-path` prints what this order settles on, so a caller needing the
#   RAW engine -- a spec runner pipes a library and a spec straight into it,
#   and going through this wrapper would boot the library twice -- does not
#   reimplement any of the above.
#
# Probe order between 2 and 3 was load-bearing when the engine was also named
# `x`: installed, the wrapper takes the bin/x name, and $SCRIPT_PATH/x re-ran
# this script forever.  A named engine cannot collide with the wrapper, but the
# order stays.
# VALIDATION IS DEFERRED to just before the engine is invoked, not done here.
# The pin guards refuse a mismatched pair BEFORE any engine boots -- that is the
# whole point of them -- and tools/check/pin-smoke.sh exercises those refusals in
# a fake install tree with no engine in it at all.  Reporting a missing engine
# during discovery preempted the refusal, turning an informative "this amalgam
# was built for a different engine" into "no engine found".  The more specific
# diagnosis wins.
_x_explicit=""
if [ -n "${X_BIN:-}" ]; then
	_x_explicit=1
else
	_edir="$SCRIPT_PATH/../${X_ENGINE_DIR}"
	_ename="$X_ENGINE"
	if [ -f "$_edir/x-engine.xon" ]; then
		_n=$(sed -n 's/^(binary "\(.*\)")[[:space:]]*$/\1/p' "$_edir/x-engine.xon" | head -n 1)
		[ -n "$_n" ] && _ename="$_n"
	fi
	X_BIN="$_edir/$_ename"
	if [ ! -e "$X_BIN" ]; then
		_edeclared="$X_BIN"
		X_BIN="$SCRIPT_PATH/$X_ENGINE"
	fi
fi

# THE ENGINE MUST EXIST -- checked at each point of use, not at discovery, so the
# pin guards keep their first refusal.  Those guards deliberately run BEFORE any
# engine boots, and tools/check/pin-smoke.sh exercises them in a fake install tree
# with no engine in it at all: validating during discovery turned an informative
# "this amalgam was built for a different engine" into "no engine found".
#
# There are two points of use -- the -V handler and the final invocation -- so
# this is a function rather than a line.  The message names what was actually
# looked for: before it, a missing engine surfaced as `x-bin: No such file or
# directory` naming the FALLBACK path, sending the reader after a file that was
# never supposed to be there.
require_engine() {
	[ -x "$X_BIN" ] && return 0
	if [ -n "$_x_explicit" ]; then
		echo "Error: X_BIN names no executable engine: $X_BIN" >&2
	else
		echo "Error: no engine found" >&2
		if [ -n "${_edeclared:-}" ]; then
			echo "  ${_edir}/x-engine.xon declares its binary as '$_ename', which is not at:" >&2
			echo "    $_edeclared" >&2
		fi
		echo "  and no '$X_ENGINE' beside the wrapper at:" >&2
		echo "    $SCRIPT_PATH/$X_ENGINE" >&2
	fi
	echo "  set X_BIN to an engine, or reinstall" >&2
	exit 1
}

# Every value that reaches $CMD below is re-parsed by the shell (it is
# assembled as text and run through `eval`), so a value carrying a quote,
# `$` or a backtick would stop being a path and start being code.  Single
# quotes are the only airtight shell quoting -- nothing inside them is
# special -- so wrap in them and rewrite an embedded ' as the standard
# '\'' escape.  Data reaching CMD unquoted is the pin.xon manifest hole:
# the manifest is documented as inert (docs/modules.md "Pinning"), and
# `eval` on an unquoted (boot "FILE") string made it executable.
shquote() {
	printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# Pipe carries only library content — the REPL reclaims terminal
# stdin from fd 3 (saved below) before its first read
file=""
file1=""
# -c/--eval expressions, accumulated in order and emitted onto the pipe
# after the library (see eval_form).  Kept separate from $file because
# they are TEXT, not a path: nothing to shquote into a `cat`.
eval_src=""
have_eval=""
# Set when stdin is not a terminal: the caller piped a program in, and it
# rides the tail of the library pipe (see the batch decision below).
stdin_prog=""
no_pin=""
allow_skew=""
fetch_release=""
boot_file=""
verbose=""
xflags=""
# Appended after the -F file so the interactive launcher runs once the
# file has been evaluated (see lib/x/repl/launch.x).
post=""

# The original invocation, kept verbatim before the loop below consumes
# it: the release handover (#499) gives the whole command line to another
# install's wrapper, which must see exactly what this one was asked.
ORIG_ARGS=""
for _arg in "$@"; do
	# --fetch-release is THIS wrapper's instruction, and its work is done
	# by handover time; a release's wrapper that predates the flag would
	# refuse it as unknown (found live: v0.5.1's did).
	[ "$_arg" = "--fetch-release" ] && continue
	ORIG_ARGS="$ORIG_ARGS $(shquote "$_arg")"
done

display_help() {
	echo "Usage: $0 [OPTION]... "
	echo
	echo "Computational Expressions in C."
	echo
	echo "Options"
	echo "  -h, --help      display this help and exit"
	echo "  -c, --eval EXPR evaluate EXPR and exit (repeatable)"
	echo "  -e, --ext EXT   file extension (default: \"$X_EXT\")"
	echo "  -f, --file FILE evaluate file and exit"
	echo "  -F, --load FILE evaluate file then continue"
	echo "  -l, --lib NAME  library name (default: \"$X_LIB\")"
	echo "      --boot FILE boot from FILE (a pinned amalgam) instead of -l's entry"
	echo "      --image     write the state image -l's boot loads from, and exit"
	echo "      --no-image  boot from source even when a state image is current"
	echo "  -q, --quiet     suppress the startup banner"
	echo "      --no-color  disable ANSI colour in the REPL"
	echo "      --no-pin    ignore any $X_PIN manifest"
	echo "      --allow-lang-skew  load a required lang whose version"
	echo "                  differs from the one asked for"
	echo "      --allow-release-skew  boot a pinned amalgam whose release"
	echo "                  differs from this engine's (it may crash)"
	echo "      --fetch-release  fetch the release a pinned project names"
	echo "                  into the per-user cache without asking first"
	echo "  -v, --verbose   display extra output"
	echo "  -V, --version   display version and exit"
}

while :
do
	case "$1" in
		-c | --eval)
			# Repeatable, and each expression arrives as its own line so a
			# trailing comment in one cannot swallow the next.  -e is taken
			# (--ext), so the flag letter is -c, as in `sh -c` / `python -c`.
			eval_src="$eval_src$2
"
			have_eval=1
			shift 2
			;;
		-f | --file)
			file="$(shquote "$2")"
			[ -z "$file1" ] && file1="$2"
			post=""
			shift 2
			;;
		-F | --load)
			file="$(shquote "$2") $file"
			[ -z "$file1" ] && file1="$2"
			post="$(shquote "${LIB_PATH}${X_LAUNCH}")"
			shift 2
			;;
		-h | --help)
			display_help
			exit 0
			;;
		-e | --ext)
			X_EXT="$2"
			shift 2
			;;
		-l | --lib)
			X_LIB="$2"
			shift 2
			;;
		-q | --quiet)
			xflags="$xflags \"--quiet\""
			shift
			;;
		--no-color)
			# Consumed by repl/ansi.x's args fold.  Without this case the
			# wrapper rejected its own documented flag as unknown; it only
			# ever worked spelled `-- --no-color`.
			xflags="$xflags \"--no-color\""
			shift
			;;
		--no-pin)
			no_pin=1
			shift
			;;
		--allow-release-skew)
			allow_skew=1
			shift
			;;
		--allow-lang-skew)
			allow_lang_skew=1
			shift
			;;
		--fetch-release)
			fetch_release=1
			shift
			;;
		--boot)
			boot_file="$2"
			shift 2
			;;
		--image)
			image_write=1
			shift
			;;
		--no-image)
			no_image=1
			shift
			;;
		-v | --verbose)
			verbose="verbose"
			shift
			;;
		-V | --version)
			# The old `echo 'x-version' | x` printed NOTHING (#79): with no
			# library on the pipe the bare C loop evaluates but cannot
			# print -- display/write are library code (the printer is
			# x-level, boot/printer.x).  So boot the entry in batch mode
			# and let IT print.  THREE numbers on purpose, and they
			# answer different questions: x-lib-version is the library's
			# (what the banner shows), x-version the x-expr expression
			# layer's, and x-release which RELEASE THIS ENGINE is.
			#
			# THAT LAST ONE IS THE ENGINE'S, NOT THE LANGUAGE'S, and the
			# two are no longer the same string.  They were while x-lang
			# built its own engine and passed its `git describe` down;
			# an engine that arrives as a release carries its own.  The
			# key the pairing guard compares is neither of these -- it is
			# the LIBRARY's stamp, $INSTALL_ROOT/contract/release, printed
			# below when there is an install tree to read it from.  A
			# banner that showed one release and a guard that compared
			# another would be a trap for exactly the person reading it
			# to diagnose a refusal.
			require_engine
			{ root_form; cat "${ENTRY_DIR}${X_LIB}${X_EXT}"; \
				printf '(display %%lang-name)(display " ")(display x-lib-version)(display " (engine release ")(display x-release)(display ", expr ")(display x-version)(display ")")(newline)\n'; } \
				| "$X_BIN" "--batch"
			if [ -n "$INSTALL_ROOT" ] && [ -f "$INSTALL_ROOT/contract/release" ]; then
				echo "library release $(cat "$INSTALL_ROOT/contract/release") -- what a pinned boot is checked against"
			fi
			exit 0
			;;
		--share-dir)
			# WHERE THIS x READS ITS TREE FROM, so a tool outside this
			# repository can ASK instead of guessing.  A lang bundle
			# needs the shared spec runner under <root>/tests/, and the only
			# alternative is re-deriving the root from `command -v x` --
			# path-guessing, which is the failure class the engine contract
			# already avoids by preferring an engine's own (param os ...)
			# declaration to sniffing the host (docs/lang-contract.md).
			#
			# ONE RELATIVE PATH WORKS IN BOTH MODES, which is the point of
			# answering with a root rather than a full path: <root>/tests/ is
			# the repo's tests/ in a checkout and share/x/tests/ in an install.
			# Repo mode is DETECTED by lib/x.x existing under the cwd, so a
			# checkout's root is the cwd by construction, not by assumption.
			#
			# No engine needed: this is a question about paths, and it must
			# answer on a tree whose engine is missing -- that is one of the
			# states a caller uses it to diagnose.
			if [ -z "$INSTALL_ROOT" ]; then
				# Repo mode: the cwd IS the tree, by the detection above.
				pwd
			elif [ -d "$INSTALL_ROOT" ]; then
				# NORMALISED, not printf'd raw: INSTALL_ROOT is built as
				# "$SCRIPT_PATH/../share/x" and carries the /bin/.. segment.
				cd "$INSTALL_ROOT" && pwd
			elif [ -e "$SCRIPT_PATH/lib/x${X_EXT}" ]; then
				# A CHECKOUT'S WRAPPER, ASKED FROM OUTSIDE THE CHECKOUT.
				#
				# Mode detection is cwd-based, deliberately: it decides which
				# tree x will READ, and running an installed x inside a
				# checkout reads the checkout.  But this flag exists so a tool
				# outside the tree can ask instead of guessing, and outside a
				# checkout that detection takes the installed branch and
				# computes a share/x that a checkout does not have -- so the
				# one question the flag was added to answer was the one it
				# refused.  x-krn hit this on day one and worked around it by
				# cd'ing to the wrapper's directory first, which is precisely
				# the guessing the flag is meant to end.
				#
				# So: fall back to the tree this WRAPPER belongs to.  Beside
				# it is lib/x.x, which only a checkout has -- an installed
				# wrapper sits in bin/ with no lib/ under it, so this branch
				# cannot fire there.  --engine-path has always resolved from
				# $SCRIPT_PATH and has always worked from anywhere; this makes
				# the pair consistent.
				printf '%s\n' "$SCRIPT_PATH"
			else
				echo "Error: no x tree found for this wrapper" >&2
				echo "  not an install ($INSTALL_ROOT is absent)" >&2
				echo "  and no lib/x${X_EXT} beside $SCRIPT_PATH" >&2
				exit 1
			fi
			exit 0
			;;
		--install-lang)
			# INSTALL A LANG WITHOUT CLONING IT.  The argument is the URL of a
			# published lang.pin.xon; x fetches that, then the tarball it
			# names, verifies the digest and installs to <install-root>/langs.
			# A thin front for (Pin install ...) -- the work is there, because
			# verification is x's job and not the shell's.
			[ -n "$2" ] || {
				echo "Error: --install-lang needs the URL of a lang.pin.xon" >&2
				echo "  e.g. x --install-lang https://host/x-krn/releases/latest/download/lang.pin.xon" >&2
				exit 1; }
			require_engine
			{ root_form; param_forms; cat "${ENTRY_DIR}${X_LIB}${X_EXT}"; \
			  printf '(import x/tool/pin)\n'; \
			  printf '(Pin install "%s")\n' "$(printf '%s' "$2" | sed 's/[\\"]/\\&/g')"; } \
				| "$X_BIN" "--batch"
			exit $?
			;;
		--engine-path)
			# The ENGINE this wrapper would run, after the whole discovery
			# order above (X_BIN, the installed engine's (binary "...") row,
			# then beside the wrapper).  A spec runner pipes a library and a
			# spec into the raw engine rather than through this wrapper -- the
			# harness boots x-core itself, so the wrapper would boot it twice
			# -- and without this the caller would have to reimplement the
			# discovery it is standing next to.
			require_engine
			printf '%s/%s\n' "$(cd "$(dirname "$X_BIN")" && pwd)" "$(basename "$X_BIN")"
			exit 0
			;;
		--) # End of all options
			shift
			break
			;;
		-*)
			echo "Error: Unknown option: $1" >&2
			exit 1
			;;
		*)  # No more options
			break
			;;
	esac
done

args=
while [ $# -gt 0 ]
do
	args="$args $(shquote "$1")"
	shift
done

# Project pinning: probe for the pin manifest ($X_PIN) from the PROGRAM's
# directory (-f/-F; the first file named), or the cwd for a REPL, walking
# up git-style.  Found means announced, never silent: the path is printed
# to stderr below, and the manifest reaches the interpreter as data only
# (see pin_form/pin_arm above).  --no-pin skips the probe entirely.
PIN_FILE=
if [ -z "$no_pin" ]; then
	if [ -n "$file1" ]; then
		_pd=$(dirname -- "$file1")
	else
		_pd=.
	fi
	_pd=$(cd "$_pd" 2>/dev/null && pwd)
	while [ -n "$_pd" ]; do
		if [ -e "$_pd/$X_PIN" ]; then
			PIN_FILE="$_pd/$X_PIN"
			path_form_safe "$PIN_FILE" "manifest"
			break
		fi
		[ "$_pd" = / ] && break
		_pd=$(dirname "$_pd")
	done
fi

# A corrupt manifest used to surface as a bare mid-boot reader error
# ("Unterminated input") with nothing naming the file -- the manifest
# streams into the boot pipe, so its syntax errors wore the stream's
# face.  A cheap paren balance over the MANIFEST GRAMMAR (strings and
# ; comments respected; manifests carry no char literals) names it
# before anything boots.  An empty manifest arms nothing -- say so
# rather than announcing "pinned:" over a blank file.
if [ -n "$PIN_FILE" ]; then
	if ! awk 'BEGIN{b=0;instr=0;esc=0}
		{
			n=length($0)
			for(i=1;i<=n;i++){
				c=substr($0,i,1)
				if(instr){ if(esc){esc=0} else if(c=="\\"){esc=1} else if(c=="\""){instr=0}; continue }
				if(c=="\""){instr=1;continue}
				if(c==";"){break}
				if(c=="(")b++
				if(c==")")b--
				if(b<0)exit 1
			}
		}
		END{ if(b!=0||instr)exit 1 }' "$PIN_FILE"; then
		echo "Error: unreadable manifest (unbalanced parens or unterminated string): $PIN_FILE" >&2
		echo "  fix the manifest, or run with --no-pin to bypass it" >&2
		exit 1
	fi
	if ! grep -q '^[[:space:]]*(' "$PIN_FILE"; then
		echo "x.sh: manifest is empty -- nothing armed: $PIN_FILE" >&2
	fi
fi

# Boot pinning (GH #139): the ONE manifest form the wrapper itself
# consumes.  (boot "FILE") names the boot entry -- a fetched amalgam --
# and the entry must be chosen HERE, before the pipe exists: the loader
# import lands after the entry has already booted, too late to pick it.
# Textual extraction of data, nothing evaluated; the form must sit alone
# on its line (the loader still checks its shape).  A relative FILE
# resolves against the manifest's directory, like (root ...).  An
# explicit --boot wins over the manifest.
if [ -z "$boot_file" ] && [ -n "$PIN_FILE" ]; then
	_bt=$(sed -n 's/^(boot "\(.*\)")[[:space:]]*$/\1/p' "$PIN_FILE" | head -n 1)
	if [ -n "$_bt" ]; then
		case "$_bt" in
			/*) boot_file="$_bt" ;;
			*)  boot_file="$(dirname "$PIN_FILE")/$_bt" ;;
		esac
	fi
fi

# The project's CHOICE of engine, a wrapper-consumed manifest form.  x-lang runs
# on any engine meeting the contract (docs/engine-contract.md); a project that
# needs a particular one says (engine "NAME") and the wrapper holds it to that.
# Textual extraction, alone on its line, like (boot ...) -- and the loader still
# shape-checks it under the closed vocabulary.
#
# This is INTENT, not safety.  The pairing that can corrupt is the layout, and
# (engine-layout ...) refuses that by equality below.  Refusing on the NAME would
# repeat the isa mistake in a new spelling: two engines with the same layout are
# interchangeable, and a name compare would reject a pairing that is provably
# fine.  So this fires only when a project asked for something specific and got
# something else.
if [ -n "$PIN_FILE" ] && [ -f "$PIN_FILE" ]; then
	_wanted_engine=$(sed -n 's/^(engine "\(.*\)")[[:space:]]*$/\1/p' "$PIN_FILE" | head -n 1)
	if [ -n "$_wanted_engine" ]; then
		_have_engine=""
		if [ -f "${_edir:-}/x-engine.xon" ]; then
			_have_engine=$(sed -n 's/^(engine-name "\(.*\)")[[:space:]]*$/\1/p' "${_edir}/x-engine.xon" | head -n 1)
		fi
		if [ -z "$_have_engine" ]; then
			# Unknown is not wrong: a repo checkout has no installed declaration.
			# Say so rather than passing silently -- a guard that disappears
			# without a word is worse than none (#313).
			echo "x.sh: manifest asks for engine '$_wanted_engine' but this tree carries no engine declaration -- choice unchecked" >&2
		elif [ "$_wanted_engine" != "$_have_engine" ]; then
			echo "Error: this project asks for a different engine" >&2
			echo "  manifest: $PIN_FILE" >&2
			echo "  it asks for: $_wanted_engine" >&2
			echo "  this one is: $_have_engine" >&2
			echo "  install that engine, or drop the (engine ...) row -- any" >&2
			echo "  contract-meeting engine will do" >&2
			exit 1
		fi
	fi
fi

# The release-skew opt-out, the manifest's second wrapper-consumed form
# (#435).  A project that KNOWINGLY runs a pinned amalgam against another
# release's engine says so once, in the manifest, instead of every runner
# remembering the flag; --allow-release-skew is the same decision made per
# invocation.  Zero arguments, alone on its line, textual like (boot ...) --
# and the loader still shape-checks it under the closed vocabulary.
if [ -z "$allow_skew" ] && [ -n "$PIN_FILE" ] && [ -f "$PIN_FILE" ]; then
	if grep -q '^[[:space:]]*(allow-release-skew)[[:space:]]*$' "$PIN_FILE"; then
		allow_skew=1
	fi
fi

# Save terminal stdin as fd 3 so x-lang can reclaim it after the pipe
# (the pipe dies on ctrl-c; fd 3 survives for the REPL)
exec 3<&0

# Library entries live in lib/ (repo) or share/x/boot/ (installed, where
# app entries are amalgamated alongside the dialects); applications live
# in apps/NAME/run.x (#35 -- the Logo app left the stdlib). -l resolves
# the entry dir first, then apps.
ENTRY="${ENTRY_DIR}${X_LIB}${X_EXT}"
if [ ! -e "$ENTRY" ] && [ -e "${APPS_PATH}${X_LIB}/${X_RUN}${X_EXT}" ]; then
	ENTRY="${APPS_PATH}${X_LIB}/${X_RUN}${X_EXT}"
fi
# THIRD STEP: an acquired lang bundle.  Unlike the first two this
# does not make the NAMED file the entry -- the entry becomes the DIALECT
# the bundle declares, and the bundle rides after it as a -F-shaped load.
if [ ! -e "$ENTRY" ]; then
	bundle_resolve "$X_LIB"
	if [ -n "$BUNDLE_DIR" ]; then
		ENTRY="${ENTRY_DIR}${BUNDLE_DIALECT}${X_EXT}"
		if [ ! -e "$ENTRY" ]; then
			echo "Error: bundle '$X_LIB' declares dialect '$BUNDLE_DIALECT', which this tree has no entry for:" >&2
			echo "    $ENTRY" >&2
			exit 1
		fi
		# BEFORE any -f/-F file: the lang must exist before a program
		# written in it is read.  file1 is the USER's file, so an untouched
		# file1 is how we know to hand back a prompt rather than exit.
		file="$(shquote "$BUNDLE_DIR/$BUNDLE_ENTRY") $file"
		[ -n "$file1" ] || post="$(shquote "${LIB_PATH}${X_LAUNCH}")"
	fi
fi

# A pinned boot replaces the entry outright (-l is not consulted).  A
# missing file is a broken project pin -- fail loudly, never fall back
# to the platform entry: a silent fallback is the very shape #139 closes.
if [ -n "$boot_file" ]; then
	ENTRY="$boot_file"
	if [ ! -e "$ENTRY" ]; then
		echo "Error: pinned boot entry does not exist: $ENTRY" >&2
		exit 1
	fi

	# PAIRING CHECK.  An amalgam is built against one engine's C surface;
	# run it on a drifted engine and the boot walks a base layout that no
	# longer matches -- a SIGSEGV mid-boot, with the pinned lines already
	# printed and nothing to say what went wrong (x-lang#187; the crash
	# that started the 2026-08-03 investigation was exactly this).
	#
	# Both sides are RECORDED strings, so this is a compare, not a digest:
	# `Pin boot` lifts the release's ISA fingerprint into the overlay's
	# lock (<root>.lock.xon beside the manifest -- the lock is NAMED FOR
	# its root: two overlays sharing a parent must not share a lock), the
	# older `Pin fetch` layout leaves pin.release.xon beside the amalgam,
	# and `make install` puts this engine's fingerprint beside the
	# library.  Try EVERY manifest root's lock, first hit wins (#313: the
	# guard once read only the FIRST root, so an unrelated root reorder
	# orphaned the lock and the guard skipped without a word), then the
	# fetch layout: both are in the wild, and a guard that reads neither
	# is a silent regression to the mid-boot SIGSEGV this check exists to
	# prevent (the exact bug shipped in v0.3.1-rc7, caught by running the
	# released artifact).
	# No sha tool needed at boot, and the check happens BEFORE the amalgam
	# reaches the engine -- the only place a refusal can still be one.
	#
	# Silent when the ENGINE side is absent (a repo checkout with no
	# installed fingerprint is unknown-not-wrong), but an armed boot pin
	# whose lock cannot be FOUND says so (#313): a protection that
	# disappears without a word is worse than none.
	# --no-pin leaves PIN_FILE empty while --boot still lands here; sed
	# on "" printed a spurious "sed: : No such file or directory" on
	# every such invocation (#331).  No manifest to consult means no
	# root -- the ENTRY-relative fallback below is the derivation.
	_rel=
	if [ -n "$PIN_FILE" ] && [ -f "$PIN_FILE" ]; then
		for _root in $(sed -n 's/^(root "\(.*\)")[[:space:]]*$/\1/p' "$PIN_FILE"); do
			case "$_root" in
				/*) _cand="${_root}.lock.xon" ;;
				*)  _cand="$(dirname "$PIN_FILE")/${_root}.lock.xon" ;;
			esac
			if [ -f "$_cand" ]; then
				_rel="$_cand"
				break
			fi
		done
	fi
	if [ -z "$_rel" ] || [ ! -f "$_rel" ]; then
		_rel="$(dirname "$ENTRY")/pin.release.xon"
	fi
	# REACH FOR THE RELEASE THE LOCK NAMES (#499).  The refusals below can
	# name every fact needed to fix what they refuse: the tag is in the
	# lock, the artifact name is convention, the digest is in the sidecar.
	# Reporting that as an errand for the human makes the pin a blocker
	# instead of a guarantee.  So before any refusal, a pinned project
	# whose installed library is not the release it names hands the WHOLE
	# invocation to a cached copy of that release -- fetching it, verified,
	# when the cache is empty and someone consents (the --fetch-release
	# flag, or one question on the terminal).  Nothing global changes: the
	# cache is per-user, the install on PATH is never touched, and the
	# re-exec'd wrapper runs its own guards against its own matched tree.
	#   X_RELEASE_CACHE  cache root (default $XDG_CACHE_HOME/x/releases)
	#   X_RELEASE_BASE   artifact base URL (tests point it at file://)
	#   X_PIN_REEXEC     loop guard, set by the exec below: a cached tree
	#                    that still mismatches must refuse, not recurse.
	# --allow-release-skew means "run THIS install"; it skips the reach.
	if [ -n "$INSTALL_ROOT" ] && [ -f "$_rel" ] \
		&& [ -f "$INSTALL_ROOT/contract/release" ] \
		&& [ -z "$allow_skew" ] && [ -z "${X_PIN_REEXEC:-}" ]; then
		_reach_want=$(sed -n 's/^[[:space:]]*(release "\([^"]*\)").*/\1/p' "$_rel" | head -1)
		_reach_have=$(cat "$INSTALL_ROOT/contract/release")
		if [ -n "$_reach_want" ] && [ "$_reach_want" != "$_reach_have" ]; then
			_croot="${X_RELEASE_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/x/releases}"
			_cname="x-${_reach_want}-$(uname -s | tr 'A-Z' 'a-z')-$(uname -m)"
			_cx="$_croot/$_cname/x-${_reach_want}/bin/x"
			if [ ! -x "$_cx" ]; then
				# Consent: the flag says yes ahead of time; a terminal is
				# asked once; a script gets the refusal below, which names
				# the flag.  Verified BEFORE unpacked, staged on the same
				# filesystem, published by one mv -- rejected bytes never
				# land where a boot would find them (#145).
				_go="$fetch_release"
				if [ -z "$_go" ] && [ -t 0 ] && [ -r /dev/tty ] && [ -w /dev/tty ]; then
					printf 'x.sh: this project pins %s; fetch it to %s? [y/N] ' \
						"$_reach_want" "$_croot" > /dev/tty
					read -r _ans < /dev/tty || _ans=""
					case "$_ans" in y | Y | yes | YES) _go=1 ;; esac
				fi
				if [ -n "$_go" ]; then
					_base="${X_RELEASE_BASE:-https://github.com/jonruttan/x-lang/releases/download}"
					if ! command -v curl >/dev/null 2>&1; then
						echo "x.sh: no curl on PATH -- fetch these, verify, and unpack under $_croot/$_cname/:" >&2
						echo "  $_base/$_reach_want/$_cname.tar.gz" >&2
						echo "  $_base/$_reach_want/$_cname.tar.gz.sha256" >&2
					else
						_stage="$_croot/.fetch.$$"
						mkdir -p "$_stage" && (
							cd "$_stage" || exit 1
							curl -fsSL -o "$_cname.tar.gz" "$_base/$_reach_want/$_cname.tar.gz" \
								&& curl -fsSL -o "$_cname.tar.gz.sha256" "$_base/$_reach_want/$_cname.tar.gz.sha256" \
								|| { echo "x.sh: fetch failed: $_base/$_reach_want/$_cname.tar.gz" >&2; exit 1; }
							if command -v sha256sum >/dev/null 2>&1; then
								sha256sum -c "$_cname.tar.gz.sha256" >/dev/null 2>&1
							else
								shasum -a 256 -c "$_cname.tar.gz.sha256" >/dev/null 2>&1
							fi || { echo "x.sh: digest mismatch on $_cname.tar.gz -- refusing to unpack; distrust the transport" >&2; exit 1; }
							tar -xzf "$_cname.tar.gz"
						) && [ -x "$_stage/x-${_reach_want}/bin/x" ] \
							&& mkdir -p "$_croot/$_cname" \
							&& rm -rf "$_croot/$_cname/x-${_reach_want}" \
							&& mv "$_stage/x-${_reach_want}" "$_croot/$_cname/x-${_reach_want}"
						rm -rf "$_stage"
					fi
				fi
			fi
			if [ -x "$_cx" ]; then
				echo "x.sh: this install is $_reach_have; handing over to the pinned $_reach_want release (cached)" >&2
				export X_PIN_REEXEC=1
				eval "exec $(shquote "$_cx")$ORIG_ARGS"
			fi
		fi
	fi
	# THE LAYOUT KEY (the arc's phase 5).  The isa comparison below is a
	# compatibility hint and a poor one: isa.x is the C SURFACE, byte-identical
	# across v0.3.1-rc10, v0.4.0 and v0.5.0, so it cannot distinguish an engine
	# whose object layout moved from one whose layout did not.  It is also too
	# STRICT in the other direction -- a different engine with the same
	# capabilities has a different digest and would be refused, which is exactly
	# backwards once more than one engine exists.
	#
	# This key is MECHANICAL, not forensic: no crash in the wild has been traced
	# to a moved layout (#435 looked like one and was not -- see the release
	# check below).  It guards a failure that cannot be diagnosed if it happens,
	# which is why it refuses rather than warns.
	#
	# What an amalgam actually binds against is the LAYOUT: lib/x/boot/reflect.x
	# reads object header words at committed offsets, so a layout that moved is a
	# segfault, not a diagnosable error.  That makes it an EQUALITY key, unlike
	# capabilities, which compare by superset and are checked post-boot where set
	# algebra is possible.  Compared here as recorded strings, before the amalgam
	# reaches the engine -- the only place a refusal can still be one.
	_mine_lay="$INSTALL_ROOT/contract/layout.sha256"
	if [ -n "$INSTALL_ROOT" ] && [ -f "$_rel" ] && [ -f "$_mine_lay" ]; then
		_wantl=$(sed -n 's/^[[:space:]]*(engine-layout "sha256:\([0-9a-f]*\)").*/\1/p' "$_rel" | head -1)
		_havel=$(cat "$_mine_lay")
		if [ -n "$_wantl" ] && [ "$_wantl" != "$_havel" ]; then
			echo "Error: pinned boot amalgam was built against a different object layout" >&2
			echo "  amalgam: $ENTRY" >&2
			echo "  its engine's layout fingerprint: $_wantl" >&2
			echo "  this engine's:                   $_havel" >&2
			echo "  the amalgam walks object header words at committed offsets; a" >&2
			echo "  layout that moved is a crash in field access, not an error." >&2
			exit 1
		fi
	fi
	# THE ENGINE'S RELEASE (the arc's phase 5).  A third subject, and the last
	# one that had no key: the layout row above refuses an engine whose object
	# model moved, and the release row below refuses a library from another
	# release, but nothing named WHICH ENGINE BUILD a project was verified
	# against.  While x-lang stamped its own tag onto the engine it built, that
	# was invisible -- one string stood for both.  x-engine-c has its own
	# version line now, so the two are different strings and each needs its own
	# comparison.
	#
	# WHAT THIS IS NOT.  It is not the #435 key: that crash was a LIBRARY
	# pairing, reproduced with the engine held constant, and the release row
	# below is what catches it.  No engine-pairing corruption has been observed
	# at all -- the layout key guards the one that is mechanically possible.
	# This row records the engine a project was verified against and refuses a
	# different one because equality is the only claim the evidence supports,
	# and `Pin boot` makes re-pinning one call.  Waived by --allow-release-skew
	# like the library row, and for the same reason: someone who knows their
	# pairing is fine should be able to say so.
	_mine_erel="$INSTALL_ROOT/contract/engine-release"
	if [ -n "$INSTALL_ROOT" ] && [ -f "$_rel" ]; then
		_wante=$(sed -n 's/^[[:space:]]*(engine-release "\([^"]*\)").*/\1/p' "$_rel" | head -1)
		if [ -n "$_wante" ] && [ ! -f "$_mine_erel" ]; then
			echo "x.sh: the lock names an engine release but this install tree carries no engine stamp -- engine pairing unchecked; reinstall to stamp it" >&2
		fi
		if [ -n "$_wante" ] && [ -f "$_mine_erel" ]; then
			_havee=$(cat "$_mine_erel")
			if [ "$_wante" != "$_havee" ]; then
				if [ -n "$allow_skew" ]; then
					echo "x.sh: engine skew allowed -- amalgam was verified against $_wante, this engine is $_havee" >&2
				else
					echo "Error: pinned boot amalgam was verified against a different engine build" >&2
					echo "  amalgam: $ENTRY" >&2
					echo "  verified against:  $_wante" >&2
					echo "  this engine:       $_havee" >&2
					echo "  Re-pin to this engine with (Pin boot \"<tag>\"), install the engine" >&2
					echo "  the lock names, or pass --allow-release-skew to proceed anyway." >&2
					exit 1
				fi
			fi
		fi
	fi

	_mine="$INSTALL_ROOT/contract/isa.sha256"
	_mine_rel="$INSTALL_ROOT/contract/release"
	if [ -n "$INSTALL_ROOT" ] && [ ! -f "$_rel" ]; then
		echo "x.sh: boot pin armed but no lock found (no <root>.lock.xon for any manifest root, no pin.release.xon) -- engine pairing unchecked; run (Pin boot) to write the lock" >&2
	fi
	if [ -n "$INSTALL_ROOT" ] && [ -f "$_rel" ] && [ -f "$_mine" ]; then
		_want=$(sed -n 's/.*isa "sha256:\([0-9a-f]*\)".*/\1/p' "$_rel" | head -1)
		_have=$(cat "$_mine")
		# A lock that EXISTS but yields no fingerprint is a corrupt or
		# truncated lock -- skipping it silently is the same
		# disappearing-guard shape #313 closed for a MISSING lock.
		if [ -z "$_want" ]; then
			echo "x.sh: boot pin armed but no isa fingerprint readable in $_rel -- engine pairing unchecked; re-run (Pin boot <tag>) to rewrite the lock" >&2
		fi
		if [ -n "$_want" ] && [ "$_want" != "$_have" ]; then
			echo "Error: pinned boot amalgam was built for a different engine" >&2
			echo "  amalgam: $ENTRY" >&2
			echo "  its engine's isa fingerprint: $_want" >&2
			echo "  this engine's:                $_have" >&2
			echo "  pair the amalgam with its own release's engine (same tag)" >&2
			exit 1
		fi
	fi

	# RELEASE CHECK (#435).  THE SUBJECT HERE IS THE LIBRARY, NOT THE ENGINE.
	# The two checks above are engine facts -- the object layout an amalgam
	# walks, and the C surface it calls.  This one compares the amalgam's
	# release against $INSTALL_ROOT/contract/release, the stamp `make install`
	# writes for the LIBRARY it installed.  For most of this guard's life the
	# distinction was invisible, because one tag was stamped on both.
	#
	# WHY A LIBRARY PAIRING NEEDS A GUARD AT ALL: an amalgam is self-contained
	# only over its `include` closure.  Its `import` forms resolve at RUNTIME
	# against this install's lib/ and apps/ (#467), so a pinned boot always
	# runs MIXED -- the project's amalgam plus whichever version of those
	# modules the platform happens to carry.  Move share/x/lib/x/codec/utf8.x
	# aside and any dialect amalgam dies with `include: cannot open`; the
	# amalgam never contained it.
	#
	# That mixture is what crashed in #435: a v0.3.1-rc10 amalgam on a v0.4.0
	# install died on `KERN_INVALID_ADDRESS at 0x696200646e696245`, a string
	# dereferenced as an object pointer -- the silent SIGSEGV #187 was closed
	# to prevent.  Reproduced 2026-08-22 with the ENGINE HELD CONSTANT:
	# swapping the engine between the two releases changed nothing, swapping
	# lib/ + apps/ decided everything, and the minimal delta was one file --
	# v0.4.0's x/num/float.x calls (Str8 includes? ...) where the rc10 amalgam
	# had baked in a Str8 carrying only `contains?`.  An ordinary vocabulary
	# rename, met by a stale boot.  No engine pairing was involved, and the
	# original report's "different engine" framing was wrong.
	#
	# So this is the guard the isa and layout keys cannot stand in for: they
	# describe the engine, and nothing in either moves when the library
	# renames a method.  The release TAG cannot under-approximate it -- two
	# releases are different releases, whatever the C surface did.  The lock
	# has recorded it since the boot verb was written ((release "vX.Y.Z")),
	# so this also protects projects pinned long before the guard existed.
	# Both sides are recorded strings -- a compare before the amalgam reaches
	# the engine, the only place a refusal can still be one.
	if [ -n "$INSTALL_ROOT" ] && [ -f "$_rel" ] && [ ! -f "$_mine_rel" ]; then
		# Wrapper new, install tree old: the tree predates the stamp, so
		# the check cannot run.  Say so -- a guard that disappears without
		# a word is worse than none (#313).
		echo "x.sh: boot pin armed but this install tree carries no release stamp -- release pairing unchecked; reinstall to stamp it" >&2
	fi
	if [ -n "$INSTALL_ROOT" ] && [ -f "$_rel" ] && [ -f "$_mine_rel" ]; then
		_wantr=$(sed -n 's/^[[:space:]]*(release "\([^"]*\)").*/\1/p' "$_rel" | head -1)
		_haver=$(cat "$_mine_rel")
		if [ -z "$_wantr" ]; then
			echo "x.sh: boot pin armed but no release tag readable in $_rel -- release pairing unchecked; re-run (Pin boot <tag>) to rewrite the lock" >&2
		fi
		if [ -n "$_wantr" ] && [ "$_wantr" != "$_haver" ]; then
			if [ -n "$allow_skew" ]; then
				echo "x.sh: release skew allowed -- amalgam is $_wantr, installed library is $_haver; a crash here is this pairing, not your program" >&2
			else
				echo "Error: pinned boot amalgam is from a different release than this installed library" >&2
				echo "  amalgam: $ENTRY" >&2
				echo "  its release:        $_wantr" >&2
				echo "  installed library:  $_haver" >&2
				echo "  the amalgam is not import-closed: it loads modules from this" >&2
				echo "  install's lib/ and apps/ as it boots, so a release mismatch runs" >&2
				echo "  one release's boot against another's modules and can segfault." >&2
				# "Move the pin to this library" is only advice when the
				# installed tree IS a release: `Pin boot` fetches the tag it
				# is given, and no release is published for a locally built
				# tree's `git describe` answer (v0.4.0-29-gbcb10a9, -dirty,
				# or a bare "dev" outside a git tree).  Naming a remedy that
				# cannot work sends the reader in a circle.
				_looks_released=
				case "$_haver" in
					*-dirty | *-g[0-9a-f]*) ;;
					v[0-9]*) _looks_released=1 ;;
				esac
				if [ -n "$_looks_released" ]; then
					echo "  Fix by moving the pin:  (Pin boot \"$_haver\")" >&2
					echo "  or run the $_wantr release from the cache with --fetch-release;" >&2
					echo "  --allow-release-skew overrides." >&2
				else
					echo "  This install is a local build, not a published release, so there" >&2
					echo "  is no pin to move it to: rerun with --fetch-release to run the" >&2
					echo "  $_wantr release from the cache, or --allow-release-skew to try anyway." >&2
				fi
				exit 1
			fi
		fi
	fi
fi

# A wrong name used to fail as `cat: lib/nope.x: No such file` with EXIT 0
# -- a bare cat diagnostic, no mention of x-lang, and a success status.
# Name the request, the searched paths, and the real inventory instead.
if [ ! -e "$ENTRY" ]; then
	echo "Error: no library, app or lang named '$X_LIB'" >&2
	echo "  searched ${ENTRY_DIR}${X_LIB}${X_EXT}, ${APPS_PATH}${X_LIB}/${X_RUN}${X_EXT}" >&2
	echo "      and ${LANGS_PATH}*/lang.xon" >&2
	# Inventory by discovery, not by hand: entries are ${ENTRY_DIR}*.x
	# files, apps are ${APPS_PATH}*/run.x -- the same rule the resolution
	# above follows.  (An empty listing also means ENTRY_DIR itself is
	# wrong: in repo mode it resolves against the CURRENT DIRECTORY, so
	# run from the repository root.)
	libs=""
	for _e in "${ENTRY_DIR}"*"${X_EXT}"; do
		[ -e "$_e" ] && libs="$libs $(basename "$_e" "$X_EXT")"
	done
	apps=""
	for _a in "${APPS_PATH}"*/"${X_RUN}${X_EXT}"; do
		[ -e "$_a" ] && apps="$apps $(basename "$(dirname "$_a")")"
	done
	if [ -n "$libs" ]; then
		echo "  libraries:$libs" >&2
	else
		echo "  no entries found under '$ENTRY_DIR' -- run from the repository root" >&2
	fi
	[ -n "$apps" ] && echo "  apps:$apps" >&2
	# Langs are listed by the name they DECLARE, not by directory:
	# a bundle unpacks as <name>-<release>/, so the directory is not what
	# -l takes, and printing it would be an inventory of wrong answers.
	pers=""
	for _p in "${LANGS_PATH}"*/; do
		[ -f "$_p/lang.xon" ] || continue
		_pn=$(sed -n 's/^(lang "\([^"]*\)").*/\1/p' "$_p/lang.xon" | head -1)
		[ -n "$_pn" ] && pers="$pers $_pn"
	done
	[ -n "$pers" ] && echo "  langs:$pers" >&2
	exit 1
fi

# A supplied file suppresses the dialect entry's interactive launcher, so
# the read-eval loop reaches the file instead of the launcher reclaiming
# stdin and discarding it.  -F re-launches afterwards via $post.  A pinned
# REPL rides the same -F shape: --batch suppresses the entry's own
# launcher so the arming import lands before the prompt, then launch.x
# hands over the session.
#
# -c/--eval is the same bargain as -f: expressions to evaluate, then exit,
# so it suppresses the launcher the same way.
#
# A NON-TERMINAL stdin is the third case, and it used to be a silent
# no-op: `echo '(write 1)' | x` printed a prompt and exited having
# evaluated nothing.  The pipe the wrapper builds IS the engine's stdin,
# so the REPL reaches the caller's stdin only by reclaiming fd 3 -- and
# lib/x/repl/loop.x reclaims it only `(when (Sys isatty 3))`, which a
# pipe is not.  Nothing consumed the program and nothing said so.  The
# fix is the form README documents for direct invocation -- `cat lib/x.x -
# | x-bin` -- put back where the wrapper can reach it: piped stdin is
# program text, appended after the library, in batch.  A terminal keeps
# the REPL, and -f/-c win over the pipe (they named their source).
if [ "$file" ] || [ -n "$have_eval" ]; then
	xflags="$xflags \"--batch\""
elif [ ! -t 0 ]; then
	stdin_prog=1
	xflags="$xflags \"--batch\""
elif [ -n "$PIN_FILE" ]; then
	xflags="$xflags \"--batch\""
	post="$(shquote "${LIB_PATH}${X_LAUNCH}")"
fi

# -c says "and exit", so it drops any launcher -F asked for: the two
# together mean run the file, then the expressions, then stop.
[ -n "$have_eval" ] && post=""

# An empty tail must vanish entirely -- a bare `cat` would read stdin.
# When $stdin_prog is set that is exactly what it must do: the bare `cat`
# IS the program.
#
# ORDER IS THE CONTRACT: files first (they define), then piped stdin,
# then -c expressions, and the launcher LAST -- it hands over the session,
# so anything emitted after it is never reached.  Fold the four into one
# `cat` and that ordering stops being visible; keep them separate.
TAIL=
[ -n "$file" ]       && TAIL="cat ${file}; "
[ -n "$stdin_prog" ] && TAIL="${TAIL}cat; "
[ -n "$have_eval" ]  && TAIL="${TAIL}eval_form; "
[ -n "$post" ]       && TAIL="${TAIL}cat ${post}; "

# --- STATE IMAGES: the boot, saved once and loaded after -------------------
# Everything the pipe below feeds ahead of the user's program -- the root and
# param forms, the entry, the pin arming, the bundle's root and entry -- is a
# fixed traversal of the same source every time, and it costs seconds (a
# lang bundle's boot is six).  docs/state-images.md: a state image is that
# traversal's RESULT, and lib/img.x plus tools/dev/image-read.x load one in a
# fraction of a second.  So the wrapper writes that prefix to a file, asks
# tools/dev/image-build.sh for an image of it (keyed on the prefix, the
# library, the engine and -- for a bundle -- the bundle's own modules, so
# any change rewrites it), and when the image is current the loader stands
# in for the prefix.  The engine's own argv survives the install: the loader
# rebinds `args` after it.  What the image cannot stand in for is emitted
# after the loader: the %batch? reset and the launcher, both of which the
# prefix would have decided by evaluating.
#
# WHO WRITES IT.  A bundle's image is its installer's: `make install` runs
# `x --image NAME` into the bundle's own .images/, so a missing or stale one
# means boot from source, quietly -- the wrapper does not write into a
# bundle behind its installer's back.  Every other boot (a dialect, an app)
# is the user's own: on a miss the wrapper writes the image into the per-user
# cache, and says so on stderr, because the first run after a library or
# engine change pays a boot twice.  --no-image boots from source; a pinned
# boot (--boot, or a project manifest) is never imaged, since what a pin
# arms is per-directory state the key does not see.
IMAGE=
img_root() { if [ -n "$INSTALL_ROOT" ]; then printf '%s' "$INSTALL_ROOT"; else pwd; fi; }
img_loader() {
	printf '(def %%IMG-PATH "%s")\n' "$IMAGE"
	# The loader's includes are root-relative (engine/tools/contract/*.x,
	# lib/x/type/shape-rows.x), as everything under lib/ is; this process
	# runs wherever the user is, so they are rooted here, on the way in --
	# the same sed the spec runner uses.
	sed 's|^(include "\([^/]\)|(include "'"$_iroot"'/\1|' "$_iroot/lib/img.x" "$_iroot/tools/dev/image-read.x"
}
if [ -z "$no_image" ] && [ -z "$boot_file" ] && [ -z "$PIN_FILE" ]; then
	_iroot=$(img_root)
	_ibuild="$_iroot/tools/dev/image-build.sh"
	if [ -f "$_ibuild" ] && [ -f "$_iroot/lib/img.x" ]; then
		path_form_safe "$_iroot" "install root"
		if [ -n "$BUNDLE_DIR" ]; then
			_idir="$BUNDLE_DIR/.images"
			_ikeys="$BUNDLE_DIR $BUNDLE_DEPS"
		else
			_idir="${XDG_CACHE_HOME:-$HOME/.cache}/x/images/$(printf '%s' "$_iroot" | shasum | cut -c1-12)"
			_ikeys=""
		fi
		require_engine
		mkdir -p "$_idir" 2>/dev/null
		_ilib="$_idir/$X_LIB.boot.x"
		# The prefix, written where the builder can key it and the child
		# can load it: exactly what the source boot would feed.
		# A bundle's entry is in the prefix too: its imports are the bulk
		# of the boot.  It is still run after the loader (it sits in $file),
		# where its imports are no-ops and its CLI dispatch sees the real
		# args -- in the writer's child there were none.
		if { root_form; param_forms; pin_form; cat "$ENTRY"; pin_arm; bundle_form image; \
		     [ -z "$BUNDLE_DIR" ] || cat "$BUNDLE_DIR/$BUNDLE_ENTRY"; } > "$_ilib.new" 2>/dev/null \
			&& mv "$_ilib.new" "$_ilib"; then
			_ish="$SCRIPT_PATH/$(basename "$0")"
			[ -n "$INSTALL_ROOT" ] || _ish="$0"
			if [ -n "$image_write" ]; then
				X_BIN="$X_BIN" X_SH="$_ish" sh "$_ibuild" "$_ilib" "$_idir" $_ikeys 1>&2
				_irc=$?
				[ "$_irc" -eq 0 ] && echo "x: state image for $X_LIB written to $_idir" >&2
				exit "$_irc"
			elif [ -n "$BUNDLE_DIR" ]; then
				IMG_CHECK=1 X_BIN="$X_BIN" X_SH="$_ish" sh "$_ibuild" "$_ilib" "$_idir" $_ikeys > /dev/null 2>&1 \
					&& IMAGE="$_ilib.ximg"
			else
				if ! IMG_CHECK=1 X_BIN="$X_BIN" X_SH="$_ish" sh "$_ibuild" "$_ilib" "$_idir" > /dev/null 2>&1; then
					echo "x: no current state image for $X_LIB -- writing one to $_idir (once per change of the library or engine)" >&2
					X_BIN="$X_BIN" X_SH="$_ish" sh "$_ibuild" "$_ilib" "$_idir" > /dev/null 2>&1 || true
				fi
				[ -f "$_ilib.ximg" ] && IMAGE="$_ilib.ximg"
			fi
			[ -n "$IMAGE" ] && path_form_safe "$IMAGE" "state image"
		fi
	fi
fi
if [ -n "$image_write" ]; then
	echo "Error: --image: nothing to write for '$X_LIB'" >&2
	echo "  a pinned boot is not imaged, and the tree must carry tools/dev/image-build.sh" >&2
	exit 1
fi

if [ -n "$IMAGE" ]; then
	# A session with nothing to run gets the launcher the entry would have
	# started itself, and the %batch? the entry would have derived.
	_ipost=
	if [ -z "$file" ] && [ -z "$have_eval" ] && [ -z "$stdin_prog" ]; then
		_ipost="printf '(set! %%batch? ())\n'; "
		if [ -z "$post" ]; then
			post="$(shquote "${LIB_PATH}${X_LAUNCH}")"
			TAIL="${TAIL}cat ${post}; "
		fi
	fi
	[ "$verbose" ] && echo "x.sh: booting from state image $IMAGE" >&2
	CMD="{ img_loader; ${_ipost}${TAIL}} | $(shquote "$X_BIN")$xflags$args"
else
	CMD="{ root_form; param_forms; pin_form; cat $(shquote "$ENTRY"); pin_arm; bundle_form; ${TAIL}} | $(shquote "$X_BIN")$xflags$args"
fi

if [ "$verbose" ]; then
	echo "$CMD"
fi

require_engine

if [ -n "$PIN_FILE" ]; then
	echo "pinned: $PIN_FILE" >&2
fi
if [ -n "$boot_file" ]; then
	echo "pinned boot: $ENTRY" >&2
fi

eval "$CMD"
