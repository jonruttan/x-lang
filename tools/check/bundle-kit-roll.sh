#!/bin/sh
# bundle-kit-roll.sh -- the bundle kit's roll writes a release a consumer can
# install.
#
# tools/bundle-kit/roll.sh archives a bundle at a tag and writes its pin.
# Held here, on a fixture repository:
#
#   - the tarball holds bundle.xon, lib/, LICENSE, README.md and the version
#     stamp under one directory, and nothing else the repository has;
#   - a file that is not committed at the tag is not in it;
#   - the payload bundle.xon declares is in it, and a payload the tag
#     lacks, or one outside the bundle, is refused;
#   - the pin names the bundle, the tag, the tarball's digest and its URL;
#   - the same tag rolls the same bytes;
#   - the files are named for the repository, read from BUNDLE_REPO or the
#     origin remote, never from the bundle's name;
#   - (Pin install ...) takes the pin and lands the bundle;
#   - a tag that does not exist, a tree with no (name ...) row, and one with
#     no lib/NAME are refused.
#
# The install boots this tree's x once.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_DIR" || exit 1
ROLL="$PROJECT_DIR/tools/bundle-kit/roll.sh"

# Run from a git hook, this inherits the hook's repository in the
# environment, and the fixture's git would act on that one.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX

TMP=$(mktemp -d)
TMP=$(cd "$TMP" && pwd)
trap 'rm -rf "$TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fails=0
ok() { printf '  %s: ok\n' "$1"; }
bad() { printf 'bundle-kit-roll: %s\n' "$1" >&2; [ -z "${2:-}" ] || sed 's/^/  /' "$2" >&2; fails=$((fails + 1)); }

g() { git -C "$R" -c user.name=roll -c user.email=roll@example.invalid -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }

# A library named rl, kept in a repository named otherwise.
R="$TMP/repo"
mkdir -p "$R/lib/rl" "$R/tests/specs" "$R/tools" "$R/.github/workflows"
git init -q "$R"
printf '(name "rl")\n(dialect he)\n(requires-release "v0.0.0")\n' > "$R/bundle.xon"
printf '(module rl/m)\n(def one (fn (_) 1))\n(provide rl/m one)\n' > "$R/lib/rl/m.x"
printf 'data\n' > "$R/lib/rl/table.txt"
printf 'MIT-0\n' > "$R/LICENSE"
printf '# rl\n' > "$R/README.md"
printf '# a spec\n' > "$R/tests/specs/m.spec.md"
printf 'echo tool\n' > "$R/tools/t.sh"
printf 'name: CI\n' > "$R/.github/workflows/ci.yml"
g add -A
g commit -q -m "rl"
g tag v1.2.3
printf 'not committed\n' > "$R/lib/rl/later.x"

# roll ARGS... -- output in $TMP/out, status in $st
roll() {
	BUNDLE="$R" BUNDLE_REPO="${REPO-someone/x-lib-rl}" BUNDLE_URL_BASE="${URLBASE-file://$TMP/dist}" \
		GITHUB_REPOSITORY= sh "$ROLL" "$@" > "$TMP/out" 2>&1 && st=0 || st=$?
}

roll v1.2.3 "$TMP/dist"
T="$TMP/dist/x-lib-rl-v1.2.3.tar.gz"
if [ "$st" = 0 ] && [ -f "$T" ]; then
	ok "the files are named for the repository, not the bundle"
else
	bad "no tarball named for the repository" "$TMP/out"
fi

want="x-lib-rl-v1.2.3/LICENSE
x-lib-rl-v1.2.3/README.md
x-lib-rl-v1.2.3/bundle.xon
x-lib-rl-v1.2.3/lib/rl/m.x
x-lib-rl-v1.2.3/lib/rl/table.txt
x-lib-rl-v1.2.3/version"
got=$(tar -tzf "$T" 2>/dev/null | grep -v '/$' | LC_ALL=C sort)
if [ "$got" = "$want" ]; then
	ok "the tarball holds what runs and the stamp, and nothing else"
else
	printf '%s\n' "$got" > "$TMP/got"
	bad "the tarball's contents are not the payload" "$TMP/got"
fi

. tools/lib/digest.sh
dg=$(x_sha256 "$T" | cut -d' ' -f1)
wantpin="(name \"rl\")
(release \"v1.2.3\")
(bundle \"sha256:$dg\" \"file://$TMP/dist/x-lib-rl-v1.2.3.tar.gz\")"
if [ "$(cat "$TMP/dist/bundle.pin.xon")" = "$wantpin" ]; then
	ok "the pin names the bundle, the tag, the digest and the URL"
else
	bad "the pin is not what was rolled" "$TMP/dist/bundle.pin.xon"
fi
if [ "$(cat "$T.sha256")" = "$dg  x-lib-rl-v1.2.3.tar.gz" ]; then
	ok "the digest file is the tarball's"
else
	bad "the .sha256 file does not hold the tarball's digest" "$T.sha256"
fi

roll v1.2.3 "$TMP/again"
if [ "$(x_sha256 "$TMP/again/x-lib-rl-v1.2.3.tar.gz" | cut -d' ' -f1)" = "$dg" ]; then
	ok "the same tag rolls the same bytes"
else
	bad "a second roll of the tag gave other bytes"
fi

# Published on GitHub: the URL is the repository's release, and the pin says
# where the source is.
URLBASE='' roll v1.2.3 "$TMP/gh"
if grep -q '"https://github.com/someone/x-lib-rl/releases/download/v1.2.3/x-lib-rl-v1.2.3.tar.gz")' "$TMP/gh/bundle.pin.xon" \
	&& grep -q '^(source "https://github.com/someone/x-lib-rl.git")$' "$TMP/gh/bundle.pin.xon"; then
	ok "the default URL is the repository's release for the tag"
else
	bad "the default pin does not name the repository's release" "$TMP/gh/bundle.pin.xon"
fi

# The repository from the origin remote, in the form ssh gives it.
g remote add origin git@github.com:alice/crypto-things.git
REPO='' roll v1.2.3 "$TMP/remote"
if [ -f "$TMP/remote/crypto-things-v1.2.3.tar.gz" ]; then
	ok "the repository is read from the origin remote"
else
	bad "the origin remote was not read" "$TMP/out"
fi

# A consumer installs from the pin.
mkdir -p "$TMP/dest"
printf '(alloc-limit! 300000000)\n(import x/tool/pin)\n(Pin install "file://%s/dist/bundle.pin.xon" "%s/dest")\n' \
	"$TMP" "$TMP" > "$TMP/install.x"
if sh x.sh --no-pin -q -f "$TMP/install.x" > "$TMP/out" 2>&1 \
	&& [ -f "$TMP/dest/rl/lib/rl/m.x" ] && [ "$(cat "$TMP/dest/rl/version" 2>/dev/null)" = v1.2.3 ]; then
	ok "(Pin install ...) takes the pin and lands the bundle with its stamp"
else
	bad "the rolled bundle did not install from its pin" "$TMP/out"
fi

roll v9.9.9 "$TMP/none"
case "$st:$(cat "$TMP/out")" in
	0:*) bad "a tag that does not exist was rolled" ;;
	*"no such tag"*) ok "a tag that does not exist is refused" ;;
	*) bad "the refusal did not name the missing tag" "$TMP/out" ;;
esac

printf '(dialect he)\n' > "$R/bundle.xon"
g commit -q -am "no name"
g tag noname
roll noname "$TMP/none"
case "$st:$(cat "$TMP/out")" in
	0:*) bad "a bundle.xon with no name was rolled" ;;
	*"no (name"*) ok "a bundle.xon with no (name ...) row is refused" ;;
	*) bad "the refusal did not name the missing row" "$TMP/out" ;;
esac

printf '(name "other")\n' > "$R/bundle.xon"
g commit -q -am "other"
g tag other
roll other "$TMP/none"
case "$st:$(cat "$TMP/out")" in
	0:*) bad "a bundle with no lib/NAME was rolled" ;;
	*"no lib/other"*) ok "a bundle with no lib/NAME is refused" ;;
	*) bad "the refusal did not name the missing directory" "$TMP/out" ;;
esac

# What a bundle ships beside lib/: a directory and a file, declared.
mkdir -p "$R/lib/pay" "$R/data/deep" "$R/art"
printf '(module pay/m)\n' > "$R/lib/pay/m.x"
printf '(d)\n' > "$R/data/deep/d.xon"
printf 'pixels\n' > "$R/art/a.txt"
printf 'notice\n' > "$R/NOTICE"
printf '(name "pay")\n(payload "data" "NOTICE")\n' > "$R/bundle.xon"
g add -A
g commit -q -m "pay"
g tag pay
REPO=someone/x-lib-rl roll pay "$TMP/pay"
want="x-lib-rl-pay/LICENSE
x-lib-rl-pay/NOTICE
x-lib-rl-pay/README.md
x-lib-rl-pay/bundle.xon
x-lib-rl-pay/data/deep/d.xon
x-lib-rl-pay/version"
got=$(tar -tzf "$TMP/pay/x-lib-rl-pay.tar.gz" 2>/dev/null | grep -v '/$' | grep -v '/lib/' | LC_ALL=C sort)
if [ "$st" = 0 ] && [ "$got" = "$want" ]; then
	ok "the payload bundle.xon declares is in the tarball, and no more"
else
	printf '%s\n' "$got" > "$TMP/got"
	bad "the declared payload is not what was rolled" "$TMP/got"
fi

printf '(name "pay")\n(payload "sound")\n' > "$R/bundle.xon"
g commit -q -am "payload the tag lacks"
g tag lacks
roll lacks "$TMP/none"
case "$st:$(cat "$TMP/out")" in
	0:*) bad "a payload the tag does not have was rolled" ;;
	*"declares payload sound"*) ok "a payload the tag does not have is refused" ;;
	*) bad "the refusal did not name the missing payload" "$TMP/out" ;;
esac

printf '(name "pay")\n(payload "../x")\n' > "$R/bundle.xon"
g commit -q -am "payload outside"
g tag outside
roll outside "$TMP/none"
case "$st:$(cat "$TMP/out")" in
	0:*) bad "a payload outside the bundle was rolled" ;;
	*"not a path at the bundle's top"*) ok "a payload outside the bundle is refused" ;;
	*) bad "the refusal did not name the path" "$TMP/out" ;;
esac

[ "$fails" = 0 ] || { echo "bundle-kit-roll: $fails failed" >&2; exit 1; }
echo "bundle-kit-roll: ok"
