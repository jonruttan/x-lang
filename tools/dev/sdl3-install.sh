#!/bin/sh
# sdl3-install.sh -- put libSDL3 where x/sys/sdl's dlopen finds it, for CI.
#
#   sh tools/dev/sdl3-install.sh
#
# macOS: Homebrew's sdl3 (/opt/homebrew/lib, one of the module's candidates).
# Linux: no Ubuntu 24.04 package carries SDL3, so the tag below is built from
# source into $SDL3_PREFIX (default ~/.sdl3, which CI caches) and its shared
# library copied into /usr/local/lib for the loader.  The build leaves out
# X11 and Wayland: the spec draws through the dummy video driver.

set -eu

SDL3_TAG=release-3.4.20
SDL3_PREFIX=${SDL3_PREFIX:-$HOME/.sdl3}

case "$(uname -s)" in
Darwin)
	brew list sdl3 >/dev/null 2>&1 || brew install sdl3
	;;
Linux)
	if [ ! -f "$SDL3_PREFIX/lib/libSDL3.so.0" ]; then
		src=$(mktemp -d)
		git clone -q --depth 1 --branch "$SDL3_TAG" https://github.com/libsdl-org/SDL.git "$src"
		cmake -S "$src" -B "$src/build" -DCMAKE_BUILD_TYPE=Release \
			-DCMAKE_INSTALL_PREFIX="$SDL3_PREFIX" -DCMAKE_INSTALL_LIBDIR=lib \
			-DSDL_SHARED=ON -DSDL_STATIC=OFF \
			-DSDL_TEST_LIBRARY=OFF -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF \
			-DSDL_UNIX_CONSOLE_BUILD=ON >/dev/null
		cmake --build "$src/build" -j "$(nproc)" >/dev/null
		cmake --install "$src/build" >/dev/null
		rm -rf "$src"
	fi
	sudo cp -P "$SDL3_PREFIX"/lib/libSDL3.so* /usr/local/lib/
	sudo ldconfig
	;;
*)
	echo "sdl3-install: no recipe for $(uname -s)" >&2
	exit 1
	;;
esac
echo "sdl3-install: $SDL3_TAG ready"
