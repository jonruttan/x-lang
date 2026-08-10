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
X_ENGINE=libexec/x/x-bin # installed engine binary

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

# The engine binary sits beside this script in-repo (x.sh + x-bin at the
# root); installed it lives in libexec, so probe libexec FIRST.  (The
# order was load-bearing when the engine was also named `x`: installed,
# the wrapper takes the bin/x name, and $SCRIPT_PATH/x re-ran this script
# forever.  x-bin cannot collide with the wrapper, but the order stays.)
X_BIN="$SCRIPT_PATH/../${X_ENGINE}"
if [ ! -e "$X_BIN" ]; then
	X_BIN="$SCRIPT_PATH/x-bin"
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
			# and let IT print.  Two versions on purpose: x-lib-version is
			# the library (what the banner shows), x-version the x-expr
			# engine -- they are different numbers and drift independently.
			{ root_form; cat "${ENTRY_DIR}${X_LIB}${X_EXT}"; \
				printf '(display %%lang-name)(display " ")(display x-lib-version)(display " (engine ")(display x-version)(display ")")(newline)\n'; } \
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
	# `Pin boot` lifts the release's ISA fingerprint into pin.lock.xon
	# beside the manifest, and `make install` puts this engine's beside
	# the library.
	# No sha tool needed at boot, and the check happens BEFORE the amalgam
	# reaches the engine -- the only place a refusal can still be one.
	#
	# Silent when either side is absent: an amalgam with no manifest, or a
	# repo checkout with no installed fingerprint, is unknown-not-wrong,
	# and `fetch` already says so at the point where it matters.
	_rel="$(dirname "$PIN_FILE")/pin.lock.xon"
	_mine="$INSTALL_ROOT/contract/isa.sha256"
	if [ -n "$INSTALL_ROOT" ] && [ -f "$_rel" ] && [ -f "$_mine" ]; then
		_want=$(sed -n 's/.*isa "sha256:\([0-9a-f]*\)".*/\1/p' "$_rel" | head -1)
		_have=$(cat "$_mine")
		if [ -n "$_want" ] && [ "$_want" != "$_have" ]; then
			echo "Error: pinned boot amalgam was built for a different engine" >&2
			echo "  amalgam: $ENTRY" >&2
			echo "  its engine's isa fingerprint: $_want" >&2
			echo "  this engine's:                $_have" >&2
			echo "  pair the amalgam with its own release's engine (same tag)" >&2
			exit 1
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
