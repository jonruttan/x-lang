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

file="\"-\""
verbose=""
xflags=""

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
			shift 2
			;;
		-F | --load)
			file="\"$2\" $file"
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

# Save original stdin as fd 3 before the pipe replaces it.
# After library load, x-lang can dup2 fd 3 onto fd 0 to restore
# the real terminal input (survives ctrl-c, unlike the pipe).
exec 3<&0

CMD="cat \"${LIB_PATH}${X_LIB}${X_EXT}\" ${file} | \"$SCRIPT_PATH/x\"$xflags$args"

if [ "$verbose" ]; then
	echo "$CMD"
fi

eval "$CMD"
