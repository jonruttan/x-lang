#!/bin/sh
# highlight-roundtrip.sh -- the highlighter must not alter what it renders
#
# THE CONTRACT: for every ```x and ```x-repl block in the documentation,
# stripping the span markup and unescaping the three entities returns the
# fence's original bytes, exactly.  A highlighter that quietly drops a
# character, reorders a token, or eats a brace is worse than none: the reader
# cannot tell, and the page is the reference.
#
# Checked over the REAL corpus rather than a handful of cases in a spec, and
# through the real sweep, because that is the path the published site takes.
# The property held on a 2KB sample when the scanner was written; this is what
# keeps it holding.
#
# Not in gates-fast: it runs the sweep over every page (tens of seconds).
set -e

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

# The pages that carry tagged blocks, discovered rather than listed.
FILES=$(grep -rl --include='*.md' --exclude-dir=tests '^```x' docs README.md 2>/dev/null || true)
if [ -z "$FILES" ]; then
  echo "highlight-roundtrip: no tagged blocks found -- did the fence pass regress?" >&2
  exit 1
fi

mkdir -p "$TMP/staged"
for f in $FILES; do
  mkdir -p "$TMP/staged/$(dirname "$f")"
  cp "$f" "$TMP/staged/$f"
done

# What went in: every tagged block's body, in file order.
awk '
  FNR == 1 { inb = 0 }
  /^```x$/ || /^```x-repl$/ { inb = 1; next }
  /^```/ { inb = 0; next }
  inb { print }
' $FILES > "$TMP/before"

( cd "$TMP/staged" && sh "$ROOT/tools/dev/highlight-sweep.sh" $FILES >/dev/null )

# What came out: the same blocks, stripped back to text.  Entity order
# matters -- &amp; last, or "&amp;lt;" in the source would decode twice.
# A block's markup spans as many lines as the source it renders, so this is a
# RANGE from the opening div to the line that closes it -- not a grep for the
# first line, which silently drops every line but the first.
( cd "$TMP/staged" && cat $FILES ) \
  | awk '/^<div class="highlight">/ { inb = 1 } inb { print } /<\/code><\/pre><\/div>$/ { inb = 0 }' \
  | sed -e 's|<div class="highlight"><pre class="highlight"><code>||' \
        -e 's|</code></pre></div>$||' \
        -e 's|<span class="[a-z0-9]*">||g' \
        -e 's|</span>||g' \
        -e 's|&lt;|<|g' -e 's|&gt;|>|g' -e 's|&amp;|\&|g' \
  > "$TMP/after"

if cmp -s "$TMP/before" "$TMP/after"; then
  printf 'highlight-roundtrip: ok (%s blocks, byte-identical)\n' \
    "$(grep -c '^```x' $FILES | awk -F: '{n += $2} END {print n}')"
else
  echo "highlight-roundtrip: FAIL -- the highlighter altered what it rendered" >&2
  diff "$TMP/before" "$TMP/after" | head -20 >&2
  exit 1
fi
