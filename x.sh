# # Computational Expressions in C
#
# ## x.sh -- Shell Script
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
X_EXT=.l
X_LIB_EXT="$X_EXT"
X_LIB=x-lib
if [ ! -e "$LIB_PATH" ]; then
	LIB_PATH=/usr/local/share/x/
fi

file=\"-\"
verbose=""

display_help() {
	echo "Usage: $0 [OPTION]... "
	echo
	echo "A Minimal Lisp Implementation in Ansi C."
	echo
	echo "Options"
	echo "  -h, --help      display this help and exit"
	echo "  -e, --ext file  extention (default: \"$X_EXT\")"
	echo "  -E, --lib-ext   library file extention (default: \"$X_LIB_EXT\")"
	echo "  -f, --file      evaluate file and exit"
	echo "  -F, --load      evaluate file"
	echo "  -l, --lib       library path (default: \"$X_LIB\")"
	echo "  -L, --lib-path  library path (default: \"$LIB_PATH\")"
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
		-F | --file-list)
			file="\"$2\" $file"
			shift 2
			;;
		-h | --help)
			display_help
			exit 0
			;;
		-E | --lib-ext)
			X_LIB_EXT="$2"
			shift 2
			;;
		-e | --ext)
			X_EXT="$2"
			shift 2
			;;
		-L | --lib-path)
			LIB_PATH="$2"
			shift 2
			;;
		-l | --lib)
			X_LIB="$2"
			shift 2
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

CMD="""cat \"${LIB_PATH}${X_LIB}${X_LIB_EXT}\" ${file} | \"$SCRIPT_PATH/x\"$args"""

if [ "$verbose" ]; then
	echo "$CMD"
fi

eval "$CMD"
