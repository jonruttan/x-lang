#!/bin/sh
# spec-examples.sh -- extract a documentation file's worked examples as
# runnable tests.
#
# spec.md:5-6 promises "Each section maps 1:1 to a test file in tests/x/specs/".
# That promise is what keeps the normative spec honest, and it had no
# enforcement -- so where the mapping quietly lapsed, the document drifted from
# the implementation (#55: `and`/`or` return values, `def` shadowing vs
# redef-in-place, `and`/`or` TCO). Note a mapping gate that only checked FILE
# EXISTENCE would have stayed green through every one of those: the sections
# exist and so do the files. Only running the examples catches it.
#
# Format: inside a fence, a line `EXPR -> EXPECTED` is an assertion, and any
# line without ` -> ` is setup evaluated before it (e.g. `(def x 10)` preceding
# `x -> 10`). Same idea as the doctest ratchet (#16), pointed at prose instead
# of the doc registry.
#
# THE DOC IS A PARAMETER. This began hardcoded to docs/spec.md, but that format
# is not unique to the spec: docs/primitives.md and docs/standard-library.md
# write their examples the same way and had no gate at all -- 235 assertions
# that nothing had ever executed, hiding retired primitives and swapped
# argument orders (#452, #453). Which docs are actually GATED is
# tools/check/doc-examples.conf's business, not this script's; this one
# extracts whatever it is pointed at.
#
#   DOC=docs/primitives.md SECTION='### ' sh tools/check/spec-examples.sh out/
#
# Environment:
#   DOC          source document (default docs/spec.md)
#   SECTION      heading prefix that opens a spec group (default '## ').
#                primitives.md needs '### ': its whole body sits under a single
#                `## Primitives`, and one output file per doc re-creates exactly
#                the failure mode the per-section split exists to prevent.
#   DEFAULT_LIB  `# @lib` dialect for every generated file (default: none,
#                i.e. the runner's lib/x-core.x).
#
# Writes ONE generated spec file PER SECTION into $1 (default
# build/spec-example-specs). Per-section files matter: the harness batches a
# file into one interpreter process, so a single segfault reports every later
# test in that file as "died mid-batch" -- with one big file, one crash at
# section 5 masked 288 results.
set -e

DOC="${DOC:-docs/spec.md}"
OUT="${1:-build/spec-example-specs}"
SECTION="${SECTION:-## }"
DEFAULT_LIB="${DEFAULT_LIB:-}"
export OUT   # awk reads it via ENVIRON

[ -f "$DOC" ] || { echo "spec-examples: no such doc: $DOC" >&2; exit 1; }

mkdir -p "$OUT"
rm -f "$OUT"/*.spec.md "$OUT"/.spec.md   # the dotfile: cleanup for empty slugs written before the fix

awk -v section_mark="$SECTION" -v default_lib="$DEFAULT_LIB" \
    -v label="$(basename "$DOC")" '
function flush_setup() { setup = "" }

# An end-of-line comment on the EXPECTED value is prose, not part of the value:
# `(newline) -> ()  ; prints \n` asserts (), and the comment says what else
# happens. Quote-aware, and the `;` must follow whitespace, so a `;` inside a
# string literal or an identifier survives.
function strip_comment(s,   i, c, q) {
  q = 0
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c == "\"") q = !q
    else if (c == ";" && !q && i > 1 && substr(s, i - 1, 1) ~ /[ \t]/) {
      s = substr(s, 1, i - 1)
      break
    }
  }
  sub(/[ \t]+$/, "", s)
  return s
}

# Section headings become spec groups.
index($0, section_mark) == 1 {
  section = substr($0, length(section_mark) + 1)
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
  expected = strip_comment(expected)

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
    # A heading that is pure punctuation -- primitives.md heads a section per
    # primitive, so one for = and one for + -- slugs to the EMPTY string, and
    # every one of them then lands in a single hidden ".spec.md": invisible to
    # the glob here, missed by the rm above, and precisely the one-big-file
    # batching trap the per-section split exists to prevent. 36 of the 113
    # assertions in primitives.md disappeared this way.
    if (slug == "") slug = "op"
    # Two distinct sections can still slug alike. The @lib line opens the file
    # with a truncating redirect, so a collision EATS the tests written for the
    # earlier section -- silent, and only on docs that set DEFAULT_LIB.
    if (slug in slug_seen) { slug_seen[slug]++; slug = slug "-" slug_seen[slug] }
    slug_seen[slug] = 1
    outfile = ENVIRON["OUT"] "/" slug ".spec.md"
    # Per-section dialect. Most sections document x-core semantics -- notably
    # section 5, where spec.md means INTEGER division, so running it under a
    # tower dialect would be wrong. Two sections need readers that only exist
    # once a dialect has installed them at boot: #/.../ regex literals, which
    # x-base.x brings in via tower-compiled.x. Reader macros are boot-time
    # only, so this cannot be fixed by importing inside the example.
    lib = (slug == "20-Lib-Regex" || slug == "10-Reader-Syntax") ? "x-base.x" : default_lib
    if (lib != "") printf "# @lib %s\n", lib > outfile
    printf "## %s\n", section >> outfile
    last_section = section
  }

  printf "\n### %s:%d %s\n\n", label, line_no, expr >> outfile
  printf "```scheme\n" >> outfile
  # The wrap spans lines with the closing paren on its own: an end-of-line
  # comment in setup or expr must not be able to swallow the rest of the form.
  if (setup != "") printf "(do %s\n%s\n)\n", setup, expr >> outfile
  else printf "%s\n", expr >> outfile
  printf "```\n---\n" >> outfile
  # nil prints as an empty line in the harness, so an expected () is blank.
  if (expected == "()") printf "\n" >> outfile
  else printf "    %s\n", expected >> outfile
  next
}

# Setup line: accumulate for subsequent assertions in this fence.
# Comment-only lines are dropped: folded inline into the (do ...) wrap, a
# `;` comments to END OF LINE and swallows the expression and the closing
# paren -- the unterminated form then eats the following tests (found via
# the Comments example itself, which demonstrates exactly this syntax).
{
  gsub(/^[ \t]+|[ \t]+$/, "")
  if ($0 ~ /^;/) next
  if ($0 != "") setup = setup " " $0
}
' "$DOC"
