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
# What does not count: a name tools/contract/shared-privates.x lists, and a
# % name tools/contract/seam.x promises to a lang.  Those are read across
# files by decision (docs/namespaces.md), so the count is of the reads that
# still want a door.  The same manifest names the boot files, which cannot
# take a module header.  A read of a boot file's % name that has no row is
# refused whatever the reader's budget, so what the boot layer shares grows
# only by an edit to the manifest.  The rows are held to the tree in turn:
# a row's file has to define its name, some other file has to read a
# `shared` name, and the document of a `promised` name has to mention it.
#
# Scope: the readers are the files of lib/ + apps/ + tools/, and the owners
# those of lib/ + apps/.  A script under tools/ wraps library functions, and
# what one script shares with another is its own affair: no library file
# loads a tool, which this check holds.  lib/img.x is a dialect of its own
# and is out of scope entirely.  The two manifests of names are lists and
# not readers.  Specs are prose with fences and are not scanned; the
# loader's own doors are what they exercise.
#
# The scan strips comments, strings and #\ character literals the way
# dup-defs.sh does, and reads names between the reader's delimiters; the
# definitions come from tools/check/defs.awk, which is form-accurate.  A
# name in the selector's place of a send, after `self`, `super` or a class at
# the head of a form, or declared by `method`, is a message and not a read.
# A member a class body declares, (%size 8192), is known by the file sending
# the same name as a selector and using it nowhere else but at a form's head.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_DIR" || exit 1

MANIFEST=tools/contract/private-reads.x
SHARED=tools/contract/shared-privates.x
SEAM=tools/contract/seam.x
for _m in "$MANIFEST" "$SHARED" "$SEAM"; do
  [ -f "$_m" ] || { echo "private-reads: no manifest at $_m" >&2; exit 2; }
done
_FILES=$(find lib apps tools -name '*.x' ! -path 'lib/img.x' \
  ! -path "$SHARED" ! -path "$SEAM" 2>/dev/null | sort)

# The shared names are a closed vocabulary in a rigid format: a line is
# blank, a comment, or one row exactly as the manifest's header gives it.
_bad=$(grep -n -v -E '^(;.*|[[:space:]]*|\(boot "[^" ]+" "[^"]*"\)|\(shared "[^" ]+" %[^" ()]+ "[^"]*"\)|\(promised "[^" ]+" %[^" ()]+ "[^" ]+" "[^"]*"\))$' "$SHARED")
if [ -n "$_bad" ]; then
  echo "private-reads: $SHARED has a line that is not a row in the format its header gives:" >&2
  printf '%s\n' "$_bad" | sed 's/^/  /' >&2
  exit 2
fi

# The rows: "K FILE" a boot file, "S NAME FILE" a shared name, "P NAME FILE
# DOC" a promised one, "M NAME" a % name of the seam.
_rows() {
  sed -n \
    -e 's/^(boot "\([^"]*\)" .*/K \1/p' \
    -e 's/^(shared "\([^"]*\)" \(%[^ ]*\) .*/S \2 \1/p' \
    -e 's/^(promised "\([^"]*\)" \(%[^ ]*\) "\([^"]*\)" .*/P \2 \1 \3/p' \
    "$SHARED"
  sed -n 's/^(seam [a-z-]* \(%[^ ]*\) .*/M \1/p' "$SEAM"
}

for _f in $(_rows | sed -n 's/^K //p'); do
  if [ ! -f "$_f" ]; then
    echo "private-reads: $SHARED names $_f as a boot file, and there is no such file" >&2
    exit 2
  fi
  if grep -q '^(module ' "$_f"; then
    echo "private-reads: $SHARED names $_f as a boot file, and it has a module header -- delete its rows" >&2
    exit 2
  fi
done

# A promised name's document has to be there and has to mention it.
_docs() {
  _rows | sed -n 's/^P //p' | while read -r _n _f _d; do
    if [ ! -f "$_d" ]; then
      echo "X nodoc $_n $_d"
    elif ! grep -qF -- "$_n" "$_d"; then
      echo "X unmentioned $_n $_d"
    fi
  done
}

# A tool script is a wrapper around library functions, so nothing in lib/ or
# apps/ loads one.  That is what lets the scripts stay out of the owners
# below, and it is held here.  The engine's contract files, reached through
# the engine link, are not this tree's tools.
_loads=$(grep -nE '^[[:space:]]*\((include|include-once|import)[[:space:]]+"?tools/' \
  $(find lib apps -name '*.x' 2>/dev/null | sort) /dev/null)
if [ -n "$_loads" ]; then
  echo "private-reads: a file under lib/ or apps/ loads a file under tools/ -- move what it needs into the library:" >&2
  printf '%s\n' "$_loads" | sed 's/^/  /' >&2
  exit 1
fi

# The owners: every % name an UNSCOPED file of lib/ or apps/ defines at its
# top level, with the file, so that a row can be held to its file and a boot
# name known.  A file under tools/ is a reader and never an owner.
_owners() {
  for _f in $_FILES; do
    case "$_f" in tools/*) continue ;; esac
    grep -q '^(module ' "$_f" && continue
    awk -f tools/check/defs.awk "$_f"
  done | awk -F'\t' '$2 ~ /^%/ { print "O", $2, $1 }' | sort -u
}

# One line per reader file, "C FILE COUNT NAMES...", and beside them:
#   V FILE NAME OWNER   a read of a boot file's name that has no row
#   X WHAT NAME FILE    a row the tree no longer bears out
#   T SHARED SEAM       how many names are not counted
_counts() {
  { _rows; _owners; for _f in $_FILES; do printf 'F\t%s\n' "$_f"; cat "$_f"; done; } | awk '
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
    # A name met only at the head of a form, in a file that also sends it as
    # a selector, is a member that file declares.  Anywhere else the head of
    # a form is a call, and a read.
    for (k in heads) if (!(k in sent)) reads[k] = 1
    for (k in reads) {
      if (k in owndef) continue
      if ((k in label) || (k in seam)) { used[k] = 1; continue }
      if (k in bootname) { print "V " file " " k " " bootname[k]; continue }
      names[++n] = k
    }
    line = "C " file " " n
    for (i = 1; i <= n; i++) line = line " " names[i]
    print line
    delete reads; delete owndef; delete names; delete heads; delete sent
  }
  file == "" && $1 == "K" && NF == 2 { boot[$2] = 1; next }
  file == "" && $1 == "S" && NF == 3 { label[$2] = "shared"; home[$2] = $3; rows[$2]++; next }
  file == "" && $1 == "P" && NF == 4 { label[$2] = "promised"; home[$2] = $3; rows[$2]++; next }
  file == "" && $1 == "M" && NF == 2 { seam[$2] = 1; next }
  file == "" && $1 == "O" && NF == 3 {
    owner[$2] = 1; defines[$2, $3] = 1
    if ($3 in boot) bootname[$2] = $3
    next
  }
  $1 == "F" { flush(); file = $2; instr = 0; next }
  {
    line = code($0)
    gsub(/\(/, " ( ", line)
    gsub(/[)\[\]{}`,]/, " ", line)
    gsub(/\047/, " ", line)
    n = split(line, tok, /[ \t]+/)
    for (i = 1; i <= n; i++) {
      if (tok[i] == "def" && i < n && tok[i+1] ~ /^%/) owndef[tok[i+1]] = 1
      # A selector is not a read: (self %walk ...) and (Lint %lint-class ...)
      # send a message, and (method %walk ...) declares one.  The name
      # belongs to the receiver, whatever the root binds under that spelling.
      if (i > 2 && tok[i-2] == "(" && tok[i-1] ~ /^(self|super|method|[A-Z][A-Za-z0-9-]*)$/) { sent[tok[i]] = 1; continue }
      if (tok[i] ~ /^%/ && (tok[i] in owner)) {
        # At the head of a form the name is a call, or the declaration of a
        # member: (%size 8192) in a class body.  Which, flush decides.
        if (i > 1 && tok[i-1] == "(") heads[tok[i]] = 1
        else reads[tok[i]] = 1
      }
    }
  }
  END {
    flush()
    for (k in label) {
      ns++
      if (rows[k] > 1) print "X twice " k " " home[k]
      if (k in seam) print "X seam " k " " home[k]
      if (!((k, home[k]) in defines)) print "X undefined " k " " home[k]
      else if (label[k] == "shared" && !(k in used)) print "X unread " k " " home[k]
    }
    for (k in seam) if (k in owner) nm++
    print "T " (ns + 0) " " (nm + 0)
  }'
  _docs
}

if [ "${1:-}" = "--list" ]; then
  _counts | awk '$1 == "C" && $3 > 0 { printf "(file \"%s\" %d)\n", $2, $3 }'
  exit 0
fi

{
  _counts
  sed -n 's/^(file "\(.*\)" \([0-9][0-9]*\)).*/B \1 \2/p' "$MANIFEST"
} | awk -v shared="$SHARED" -v seam="$SEAM" '
  $1 == "C" { count[$2] = $3; names[$2] = ""; for (i = 4; i <= NF; i++) names[$2] = names[$2] " " $i }
  $1 == "B" { budget[$2] = $3 }
  $1 == "T" { nshared = $2; nseam = $3 }
  $1 == "V" {
    printf "private-reads: %s reads %s, a private name of the boot file %s that %s does not list -- give the name a door, or add its row\n", $2, $3, $4, shared > "/dev/stderr"
    bad = 1
  }
  $1 == "X" && $2 == "twice" { printf "private-reads: %s lists %s more than once\n", shared, $3 > "/dev/stderr"; bad = 1 }
  $1 == "X" && $2 == "seam" { printf "private-reads: %s lists %s, which %s lists already -- delete the row\n", shared, $3, seam > "/dev/stderr"; bad = 1 }
  $1 == "X" && $2 == "undefined" { printf "private-reads: %s lists %s, which %s does not define at its top level -- delete the row\n", shared, $3, $4 > "/dev/stderr"; bad = 1 }
  $1 == "X" && $2 == "unread" { printf "private-reads: %s lists %s, which no file other than its own reads any more -- delete the row\n", shared, $3 > "/dev/stderr"; bad = 1 }
  $1 == "X" && $2 == "nodoc" { printf "private-reads: %s says %s describes %s, and there is no such file\n", shared, $4, $3 > "/dev/stderr"; bad = 1 }
  $1 == "X" && $2 == "unmentioned" { printf "private-reads: %s says %s describes %s, and the document does not mention it\n", shared, $4, $3 > "/dev/stderr"; bad = 1 }
  END {
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
    printf "private-reads: every file within its shrinking budget; %d shared names and %d names of the seam are not counted.\n", nshared, nseam
  }'
