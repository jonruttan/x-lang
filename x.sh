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
SCRIPT_PATH=$(dirname "$0")
X_EXT=.x
X_LIB=x
# One definition per name the wrapper embeds; every use below reads these.
X_PIN=pin.xon            # pin manifest (docs/modules.md "Pinning")
X_PIN_MOD=x/tool/pin     # platform-side pin loader, imported by pin_arm
X_LAUNCH=x/repl/launch.x # interactive launcher, cat'd after -F / pinned REPL
                         # (a platform file: deliberately not -e/X_EXT-aware)
X_RUN=run                # app entry basename: apps/NAME/run.x (#35)
X_SHARE=share/x          # installed runtime tree, beside the bin dir
X_ENGINE=libexec/x/x     # installed engine binary

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

# The engine binary sits beside this script in-repo (x.sh + x at the
# root); installed it lives in libexec -- and the wrapper takes the bin/x
# name there, so probe libexec FIRST or $SCRIPT_PATH/x re-runs this
# script forever.
X_BIN="$SCRIPT_PATH/../${X_ENGINE}"
if [ ! -e "$X_BIN" ]; then
	X_BIN="$SCRIPT_PATH/x"
fi

# Pipe carries only library content — the REPL reclaims terminal
# stdin from fd 3 (saved below) before its first read
file=""
file1=""
no_pin=""
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
			file="\"$2\""
			[ -z "$file1" ] && file1="$2"
			post=""
			shift 2
			;;
		-F | --load)
			file="\"$2\" $file"
			[ -z "$file1" ] && file1="$2"
			post="\"${LIB_PATH}${X_LAUNCH}\""
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
	args="$args \"$1\""
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
			break
		fi
		[ "$_pd" = / ] && break
		_pd=$(dirname "$_pd")
	done
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
	post="\"${LIB_PATH}${X_LAUNCH}\""
fi

# An empty tail must vanish entirely -- a bare `cat` would read stdin.
TAIL=
if [ -n "${file}${post}" ]; then
	TAIL="cat ${file} ${post}; "
fi

CMD="{ root_form; pin_form; cat \"${ENTRY}\"; pin_arm; ${TAIL}} | \"$X_BIN\"$xflags$args"

if [ "$verbose" ]; then
	echo "$CMD"
fi

if [ -n "$PIN_FILE" ]; then
	echo "pinned: $PIN_FILE" >&2
fi

eval "$CMD"
