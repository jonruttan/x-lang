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
	INSTALL_ROOT="$SCRIPT_PATH/../share/x"
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

# The engine binary sits beside this script in-repo (x.sh + x at the
# root); installed it lives in libexec -- and the wrapper takes the bin/x
# name there, so probe libexec FIRST or $SCRIPT_PATH/x re-runs this
# script forever.
X_BIN="$SCRIPT_PATH/../libexec/x/x"
if [ ! -e "$X_BIN" ]; then
	X_BIN="$SCRIPT_PATH/x"
fi

# Pipe carries only library content — the REPL reclaims terminal
# stdin from fd 3 (saved below) before its first read
file=""
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
	echo "  -v, --verbose   display extra output"
	echo "  -V, --version   display version and exit"
}

while :
do
	case "$1" in
		-f | --file)
			file="\"$2\""
			post=""
			shift 2
			;;
		-F | --load)
			file="\"$2\" $file"
			post="\"${LIB_PATH}x/repl/launch.x\""
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

# Save terminal stdin as fd 3 so x-lang can reclaim it after the pipe
# (the pipe dies on ctrl-c; fd 3 survives for the REPL)
exec 3<&0

# Library entries live in lib/ (repo) or share/x/boot/ (installed, where
# app entries are amalgamated alongside the dialects); applications live
# in apps/NAME/run.x (#35 -- the Logo app left the stdlib). -l resolves
# the entry dir first, then apps.
ENTRY="${ENTRY_DIR}${X_LIB}${X_EXT}"
if [ ! -e "$ENTRY" ] && [ -e "${APPS_PATH}${X_LIB}/run${X_EXT}" ]; then
	ENTRY="${APPS_PATH}${X_LIB}/run${X_EXT}"
fi

# A wrong name used to fail as `cat: lib/nope.x: No such file` with EXIT 0
# -- a bare cat diagnostic, no mention of x-lang, and a success status.
# Name the request, the searched paths, and the real inventory instead.
if [ ! -e "$ENTRY" ]; then
	echo "Error: no library or app named '$X_LIB'" >&2
	echo "  searched ${ENTRY_DIR}${X_LIB}${X_EXT} and ${APPS_PATH}${X_LIB}/run${X_EXT}" >&2
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
	for _a in "${APPS_PATH}"*/run"$X_EXT"; do
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
# stdin and discarding it.  -F re-launches afterwards via $post.
if [ "$file" ]; then
	xflags="$xflags \"--batch\""
fi

CMD="{ root_form; cat \"${ENTRY}\" ${file} ${post}; } | \"$X_BIN\"$xflags$args"

if [ "$verbose" ]; then
	echo "$CMD"
fi

eval "$CMD"
