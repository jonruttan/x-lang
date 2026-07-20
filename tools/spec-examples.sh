#!/bin/sh
# spec-examples.sh -- extract docs/spec.md's worked examples as runnable tests.
#
# spec.md:5-6 promises "Each section maps 1:1 to a test file in tests/x/specs/".
# That promise is what keeps the normative spec honest, and it had no
# enforcement -- so where the mapping quietly lapsed, the document drifted from
# the implementation (#55: `and`/`or` return values, `def` shadowing vs
# redef-in-place, `and`/`or` TCO). Note a mapping gate that only checked FILE
# EXISTENCE would have stayed green through every one of those: the sections
# exist and so do the files. Only running the examples catches it.
#
# Format in spec.md: inside a fence, a line `EXPR -> EXPECTED` is an assertion,
# and any line without ` -> ` is setup evaluated before it (e.g. `(def x 10)`
# preceding `x -> 10`). Same idea as the doctest ratchet (#16), pointed at the
# spec instead of the doc registry.
#
# Writes ONE generated spec file PER SECTION into $1 (default
# build/spec-example-specs). Per-section files matter: the harness batches a
# file into one interpreter process, so a single segfault reports every later
# test in that file as "died mid-batch" -- with one big file, one crash at
# section 5 masked 288 results.
set -e

OUT="${1:-build/spec-example-specs}"
export OUT   # awk reads it via ENVIRON
mkdir -p "$OUT"
rm -f "$OUT"/*.spec.md

awk '
function flush_setup() { setup = "" }

# Section headings become spec groups.
/^## / {
  section = $0
  sub(/^## /, "", section)
  gsub(/"/, "", section)
  next
}

/^```/ {
  in_fence = !in_fence
  if (in_fence) flush_setup()
  next
}

!in_fence { next }

# Assertion line: EXPR -> EXPECTED
/ -> / {
  line_no = NR
  expr = $0
  expected = $0
  sub(/ -> .*$/, "", expr)
  sub(/^.* -> /, "", expected)

  # Skip what cannot be a mechanical assertion:
  #   TBD/... placeholders, prose arrows, error demos (the harness renders
  #   errors differently), and anything with an unbalanced fence artifact.
  if (expected ~ /TBD/ || expr ~ /TBD/) next
  if (expr ~ /\.\.\./ || expected ~ /\.\.\./) next
  if (expected ~ /^[Ee]rror/) next
  # <symbol>, <instance>, <fn> etc. are prose placeholders, not literal values.
  if (expected ~ /^</) next
  # display/write examples assert on a RETURN value while also printing, so the
  # harness (which compares stdout) sees both -- not drift, just unassertable.
  if (expr ~ /display|write|print/) next
  if (expr == "" || expected == "") next

  if (!section) section = "spec"
  if (section != last_section) {
    slug = section
    gsub(/[^A-Za-z0-9]+/, "-", slug)
    sub(/^-+/, "", slug); sub(/-+$/, "", slug)
    outfile = ENVIRON["OUT"] "/" slug ".spec.md"
    printf "## %s\n", section > outfile
    last_section = section
  }

  printf "\n### spec.md:%d %s\n\n", line_no, expr >> outfile
  printf "```scheme\n" >> outfile
  if (setup != "") printf "(do %s %s)\n", setup, expr >> outfile
  else printf "%s\n", expr >> outfile
  printf "```\n---\n" >> outfile
  # nil prints as an empty line in the harness, so an expected () is blank.
  if (expected == "()") printf "\n" >> outfile
  else printf "    %s\n", expected >> outfile
  next
}

# Setup line: accumulate for subsequent assertions in this fence.
{
  gsub(/^[ \t]+|[ \t]+$/, "")
  if ($0 != "") setup = setup " " $0
}
' docs/spec.md
