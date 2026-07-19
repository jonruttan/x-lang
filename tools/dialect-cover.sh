#!/bin/sh
# dialect-cover.sh -- the dialect coverage ratchet (#70).
#
# Every shipped entry point under lib/*.x must be exercised end-to-end by a
# `# @lib <file>` group in tests/x/specs/dialects/. The dialects had ZERO such
# coverage until #70, which is how #49 shipped: both tower launchers crashed at
# the exact invocation the README documents, while every numeric spec passed
# against its own bespoke harness.
#
# The point is that a NEW dialect cannot ship untested -- add lib/x-foo.x and
# this fails until a smoke group exists for it. Same shape as check-isa and the
# other contract ratchets: mechanical, not a habit anyone has to remember.
set -e

SPEC_DIR=tests/x/specs/dialects
status=0

for f in lib/*.x; do
  name=$(basename "$f")
  if ! grep -qr "^# @lib $name\$" "$SPEC_DIR" 2>/dev/null; then
    echo "dialect-cover: FAIL $f has no '# @lib $name' group in $SPEC_DIR/"
    status=1
  fi
done

# The reverse direction: a group naming a dialect that no longer exists is
# stale coverage, and would otherwise sit green forever against nothing.
for g in $(grep -hr "^# @lib " "$SPEC_DIR" 2>/dev/null | sed 's/^# @lib //'); do
  case "$g" in
    */*) continue ;;   # harness libs (e.g. ../tests/x/lib/float.x), not dialects
  esac
  if [ ! -f "lib/$g" ]; then
    echo "dialect-cover: FAIL $SPEC_DIR/ covers lib/$g, which does not exist"
    status=1
  fi
done

[ $status -eq 0 ] && echo "dialect-cover: ok"
exit $status
