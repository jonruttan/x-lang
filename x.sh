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
if [ ! -e "${LIB_PATH}${X_LIB}${X_EXT}" ]; then
	INSTALL_ROOT="$SCRIPT_PATH/../${X_SHARE}"
	LIB_PATH="$INSTALL_ROOT/lib/"
	APPS_PATH="$INSTALL_ROOT/apps/"
	ENTRY_DIR="$INSTALL_ROOT/boot/"
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

# The install-root form, emitted ahead of the entry in installed mode; a
# no-op command in repo mode (nothing defines %install-root there).
root_form() {
	if [ -n "$INSTALL_ROOT" ]; then
		printf '(def %%install-root "%s")\n' "$INSTALL_ROOT"
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
#      from the directory holding it.
#
# Probe order between 2 and 3 was load-bearing when the engine was also named
# `x`: installed, the wrapper takes the bin/x name, and $SCRIPT_PATH/x re-ran
# this script forever.  A named engine cannot collide with the wrapper, but the
# order stays.
if [ -n "${X_BIN:-}" ]; then
	# An explicit engine that is not there is a mistake worth naming, not a
	# reason to quietly run a different one: a silent fallback here is the
	# shape the pinning guards exist to prevent.
	if [ ! -x "$X_BIN" ]; then
		echo "Error: X_BIN names no executable engine: $X_BIN" >&2
		exit 1
	fi
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
	# Name what was actually looked for.  Without this the failure surfaced as
	# `x-bin: No such file or directory` naming the FALLBACK path -- so a tree
	# whose declared engine was missing sent the reader hunting for a file that
	# was never supposed to be there.
	if [ ! -e "$X_BIN" ]; then
		echo "Error: no engine found" >&2
		if [ -n "${_edeclared:-}" ]; then
			echo "  $_edir/x-engine.xon declares its binary as '$_ename', which is not at:" >&2
			echo "    $_edeclared" >&2
		fi
		echo "  and no '$X_ENGINE' beside the wrapper at:" >&2
		echo "    $SCRIPT_PATH/$X_ENGINE" >&2
		echo "  set X_BIN to an engine, or reinstall" >&2
		exit 1
	fi
fi

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
no_pin=""
allow_skew=""
boot_file=""
verbose=""
xflags=""
# Appended after the -F file so the interactive launcher runs once the
# file has been evaluated (see lib/x/repl/launch.x).
post=""

display_help() {
	echo "Usage: $0 [OPTION]... "
	echo
	echo "Computational Expressions in C."
	echo
	echo "Options"
	echo "  -h, --help      display this help and exit"
	echo "  -e, --ext EXT   file extension (default: \"$X_EXT\")"
	echo "  -f, --file FILE evaluate file and exit"
	echo "  -F, --load FILE evaluate file then continue"
	echo "  -l, --lib NAME  library name (default: \"$X_LIB\")"
	echo "      --boot FILE boot from FILE (a pinned amalgam) instead of -l's entry"
	echo "  -q, --quiet     suppress the startup banner"
	echo "      --no-color  disable ANSI colour in the REPL"
	echo "      --no-pin    ignore any $X_PIN manifest"
	echo "      --allow-release-skew  boot a pinned amalgam whose release"
	echo "                  differs from this engine's (it may crash)"
	echo "  -v, --verbose   display extra output"
	echo "  -V, --version   display version and exit"
}

while :
do
	case "$1" in
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
		--boot)
			boot_file="$2"
			shift 2
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
			# layer's, and x-release which RELEASE this engine is -- the
			# only one of the three that distinguishes two releases whose
			# C never changed (#435), and the key the pairing guard below
			# compares.
			{ root_form; cat "${ENTRY_DIR}${X_LIB}${X_EXT}"; \
				printf '(display %%lang-name)(display " ")(display x-lib-version)(display " (release ")(display x-release)(display ", engine ")(display x-version)(display ")")(newline)\n'; } \
				| "$X_BIN" "--batch"
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

	# RELEASE CHECK (#435).  The isa comparison above is a compatibility
	# test, and a correct one -- but it cannot answer THIS question.
	# ext/x-engine-c/tools/contract/isa.x is the C surface, deliberately fixed: it is
	# byte-identical across v0.3.1-rc10, v0.4.0 and v0.5.0, as are
	# obj-layout.x, base-paths.x and base-layout.x.  Meanwhile lib/ moved
	# 83 files between the first two.  An amalgam binds against far more
	# than the C surface -- boot structure, object-model conventions, the
	# library it will import from -- and none of that is in the
	# fingerprint, so the guard passed a v0.3.1-rc10 amalgam onto a v0.4.0
	# engine and the boot died on `KERN_INVALID_ADDRESS at 0x696200646e696245`:
	# a string dereferenced as an object pointer, no diagnosis, the exact
	# silent SIGSEGV #187 was closed to prevent.
	#
	# The release TAG is the key that cannot under-approximate: two
	# releases are different releases, whatever their C surface did.  The
	# lock has recorded it since the boot verb was written ((release
	# "vX.Y.Z")), so this guard also protects projects pinned long before
	# it existed; `make install` now stamps the engine's own beside the
	# library.  Both sides are recorded strings again -- a compare before
	# the amalgam reaches the engine, the only place a refusal can still
	# be one.
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
				echo "x.sh: release skew allowed -- amalgam is $_wantr, engine is $_haver; a crash here is this pairing, not your program" >&2
			else
				echo "Error: pinned boot amalgam is from a different release than this engine" >&2
				echo "  amalgam: $ENTRY" >&2
				echo "  its release:  $_wantr" >&2
				echo "  this engine:  $_haver" >&2
				echo "  the isa fingerprint cannot catch this -- it is the C surface, and" >&2
				echo "  it is identical across these releases; the amalgam binds against" >&2
				echo "  more than that, so a mismatched pair segfaults mid-boot." >&2
				# "Move the pin to this engine" is only advice when this
				# engine IS a release: `Pin boot` fetches the tag it is
				# given, and no release is published for a locally built
				# engine's `git describe` answer (v0.4.0-29-gbcb10a9,
				# -dirty, or a bare "dev" outside a git tree).  Naming a
				# remedy that cannot work sends the reader in a circle.
				_looks_released=
				case "$_haver" in
					*-dirty | *-g[0-9a-f]*) ;;
					v[0-9]*) _looks_released=1 ;;
				esac
				if [ -n "$_looks_released" ]; then
					echo "  Fix by moving the pin:  (Pin boot \"$_haver\")" >&2
					echo "  or install the $_wantr engine; --allow-release-skew overrides." >&2
				else
					echo "  This engine is a local build, not a published release, so there" >&2
					echo "  is no pin to move it to: install the $_wantr engine to run this" >&2
					echo "  project, or pass --allow-release-skew to try anyway." >&2
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
	echo "Error: no library or app named '$X_LIB'" >&2
	echo "  searched ${ENTRY_DIR}${X_LIB}${X_EXT} and ${APPS_PATH}${X_LIB}/${X_RUN}${X_EXT}" >&2
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
	exit 1
fi

# A supplied file suppresses the dialect entry's interactive launcher, so
# the read-eval loop reaches the file instead of the launcher reclaiming
# stdin and discarding it.  -F re-launches afterwards via $post.  A pinned
# REPL rides the same -F shape: --batch suppresses the entry's own
# launcher so the arming import lands before the prompt, then launch.x
# hands over the session.
if [ "$file" ]; then
	xflags="$xflags \"--batch\""
elif [ -n "$PIN_FILE" ]; then
	xflags="$xflags \"--batch\""
	post="$(shquote "${LIB_PATH}${X_LAUNCH}")"
fi

# An empty tail must vanish entirely -- a bare `cat` would read stdin.
TAIL=
if [ -n "${file}${post}" ]; then
	TAIL="cat ${file} ${post}; "
fi

CMD="{ root_form; pin_form; cat $(shquote "$ENTRY"); pin_arm; ${TAIL}} | $(shquote "$X_BIN")$xflags$args"

if [ "$verbose" ]; then
	echo "$CMD"
fi

if [ -n "$PIN_FILE" ]; then
	echo "pinned: $PIN_FILE" >&2
fi
if [ -n "$boot_file" ]; then
	echo "pinned boot: $ENTRY" >&2
fi

eval "$CMD"
