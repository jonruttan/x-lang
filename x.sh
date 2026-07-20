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
LIB_PATH=lib/
X_EXT=.x
X_LIB=x

if [ ! -e "$LIB_PATH" ]; then
	LIB_PATH=/usr/local/share/x/lib/
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
		-v | --verbose)
			verbose="verbose"
			shift
			;;
		-V | --version)
			echo 'x-version' | "$SCRIPT_PATH/x"
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

# Library entries live in lib/; applications live in apps/NAME/run.x
# (#35 -- the Logo app left the stdlib). -l resolves lib first, then apps.
ENTRY="${LIB_PATH}${X_LIB}${X_EXT}"
if [ ! -e "$ENTRY" ] && [ -e "apps/${X_LIB}/run${X_EXT}" ]; then
	ENTRY="apps/${X_LIB}/run${X_EXT}"
fi

# A supplied file suppresses the dialect entry's interactive launcher, so
# the read-eval loop reaches the file instead of the launcher reclaiming
# stdin and discarding it.  -F re-launches afterwards via $post.
if [ "$file" ]; then
	xflags="$xflags \"--batch\""
fi

CMD="cat \"${ENTRY}\" ${file} ${post} | \"$SCRIPT_PATH/x\"$xflags$args"

if [ "$verbose" ]; then
	echo "$CMD"
fi

eval "$CMD"
