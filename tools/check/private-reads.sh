#!/bin/sh
# private-reads.sh -- the cross-file PRIVATE READ ratchet (x-lang#719).
#
# A % name is private by convention, and until its module is scoped it is a
# global like any other: a second file can read it, and does.  Every such
# read is a coupling that scoping the owner will break, so step 4 of #719 is
# spent turning them into doors -- a class static, a catalog entry, an export
# the reader imports.  This check keeps the count from growing meanwhile.
#
# What counts, per READER file: the distinct % names it mentions that some
# OTHER unscoped file defines at its top level, and that the reader does not
# define itself, at any depth.  A file's own definition of a name -- the
# per-file catalog alias, `(def %cvt (prim-ref ...))` -- is not a read of
# anyone else's.  A scoped module's top-level defs are not in the root, so a
# scoped file is never an owner; it can still be a reader of an unscoped
# file's names, and those reads count.
#
# The count is per reader rather than per owner because a name several
# unscoped files bind (`%cvt`, `%type-of`) has no one owner to charge, while
# a read is a read whoever bound the name.  Every row may only shrink: a file
# over its budget fails, and a file under it fails until the row is lowered,
# so a door once built stays built.  A file absent from the manifest has a
# budget of 0.
#
# Scope: lib/ + apps/ + tools/, the files that can co-load into one base, as
# dup-defs.sh has it, and for its reason.  lib/img.x is a dialect of its own
# and is out of scope entirely.  Specs are prose with fences and are not
# scanned; the loader's own doors are what they exercise.
#
# The scan strips comments, strings and #\ character literals the way
# dup-defs.sh does, and reads names between the reader's delimiters; the
# definitions come from tools/check/defs.awk, which is form-accurate.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_DIR" || exit 1

MANIFEST=tools/contract/private-reads.x
_FILES=$(find lib apps tools -name '*.x' ! -path 'lib/img.x' 2>/dev/null | sort)

# The owners: every % name an UNSCOPED file defines at its top level.
_owners() {
  for _f in $_FILES; do
    grep -q '^(module ' "$_f" && continue
    awk -f tools/check/defs.awk "$_f"
  done | awk -F'\t' '$2 ~ /^%/ { print "O", $2 }' | sort -u
}

# One line per reader file: "C FILE COUNT NAMES...".
_counts() {
  { _owners; for _f in $_FILES; do printf 'F\t%s\n' "$_f"; cat "$_f"; done; } | awk '
  # Strip a line to its code: no comment, no string bytes, no #\ char.
  function code(line,    n, i, c, out) {
    n = length(line); out = ""; i = 1
    while (i <= n) {
      c = substr(line, i, 1)
      if (instr) {
        if (c == "\\") i++
        else if (c == "\"") { instr = 0; out = out " " }
      } else if (c == ";") {
        break
      } else if (c == "#" && substr(line, i, 2) == "#\\") {
        out = out " "; i += 2
      } else if (c == "\"") {
        instr = 1
      } else {
        out = out c
      }
      i++
    }
    return out
  }
  function flush(    n, i, k, line) {
    if (file == "") return
    n = 0
    for (k in reads) if (!(k in owndef)) names[++n] = k
    line = "C " file " " n
    for (i = 1; i <= n; i++) line = line " " names[i]
    print line
    delete reads; delete owndef; delete names
  }
  $1 == "O" && NF == 2 && file == "" { owner[$2] = 1; next }
  $1 == "F" { flush(); file = $2; instr = 0; next }
  {
    line = code($0)
    gsub(/[()\[\]{}`,]/, " ", line)
    gsub(/\047/, " ", line)
    n = split(line, tok, /[ \t]+/)
    for (i = 1; i <= n; i++) {
      if (tok[i] == "def" && i < n && tok[i+1] ~ /^%/) owndef[tok[i+1]] = 1
      if (tok[i] ~ /^%/ && (tok[i] in owner)) reads[tok[i]] = 1
    }
  }
  END { flush() }'
}

if [ "${1:-}" = "--list" ]; then
  _counts | awk '$3 > 0 { printf "(file \"%s\" %d)\n", $2, $3 }'
  exit 0
fi

{
  _counts
  sed -n 's/^(file "\(.*\)" \([0-9][0-9]*\)).*/B \1 \2/p' "$MANIFEST"
} | awk '
  $1 == "C" { count[$2] = $3; names[$2] = ""; for (i = 4; i <= NF; i++) names[$2] = names[$2] " " $i }
  $1 == "B" { budget[$2] = $3 }
  END {
    bad = 0
    for (f in count) {
      b = (f in budget) ? budget[f] : 0
      if (count[f] > b) {
        printf "private-reads: %s reads %d private names of other files, budget %d -- give the name a door instead (see tools/check/private-reads.sh):%s\n", f, count[f], b, names[f] > "/dev/stderr"
        bad = 1
      }
    }
    for (f in budget) {
      n = (f in count) ? count[f] : 0
      if (n < budget[f]) {
        printf "private-reads: %s is under budget (%d < %d) -- ratchet the row down in tools/contract/private-reads.x\n", f, n, budget[f] > "/dev/stderr"
        bad = 1
      }
    }
    if (bad) exit 1
    print "private-reads: every file within its shrinking budget."
  }'
