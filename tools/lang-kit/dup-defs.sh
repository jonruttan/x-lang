#!/bin/sh
# # x-lang -- the lang kit
#
# ## tools/lang-kit/dup-defs.sh -- one global name, one meaning
#
# @description Fails when two files that load into one root define the same
#   global name differently.  The platform's own sources and every bundle's
#   are held to it by this one scanner.
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2026 Jon Ruttan
# @license MIT No Attribution (MIT-0)
#
#     ., .,
#     {O,O}
#     (   )
#      " "
#
# Top-level redefinition updates the shared binding in place, so two files
# defining the same global name with different meanings is a real collision:
# whichever loads last rewires every caller.  Nothing at run time says so.
# x-coreutils carried %ts-verbose as tar's accessor and as tcpsvd's counter,
# and each applet worked only because it ran in a process of its own.
#
# Rule, per global name defined at top level in more than one file:
#   - catalogue fetches -- a body that is (prim-ref ...) -- must all fetch
#     the same catalogue entry (normalized-identical args);
#   - one non-fetch definition (the registrar/owner) plus any number of
#     fetches is fine: the fetches return the registered object;
#   - the same definition, text for text, in several files is fine: it
#     binds the same value whichever loads last;
#   - several distinct non-fetch definitions fail, unless the name is in
#     DUP_DEFS_ALLOW or every definition lives under DUP_DEFS_ONE_LOADS.
#
# A scoped module, whose first form is (module NAME), is checked only for the
# names it binds in the root (x-lang#719).  Its other top-level defs bind in
# the module's own environment, so two scoped modules may use the same
# private name, and a scoped module may reuse a global's, both by design.
# Its provide binds in the root the exports it marks (global NAME) and the
# exports that are classes (lib/x/boot/module.x); there a plain def of the
# same name in an unscoped file is exactly the collision this check is for.
# Any other export stays the module's own, reached with a selective import.
# A pre-pass over the scoped files' provide lists, fed in as the first input,
# says which exports are marked (G) and which are plain (E); of the plain
# ones, a (def-class NAME ...) and a (def NAME Class) alias count as classes.
#
# Extraction is a form scanner (paren depth outside strings, char literals and
# ; comments), not a line grep.  Recognized definers: (def NAME ...),
# (def-class NAME ...) and their (doc ...) wrappers.  A top-level (do ...) is
# descended into, because do evaluates its forms in the caller's env, so
# defs directly inside it bind globally.  (let ...) is not descended: its
# bindings are scoped.
#
# Usage: dup-defs.sh [FILE...], run from the tree the FILEs are relative to.
# With no FILEs it runs from BUNDLE (default: the current directory) over
# every .x there but the generated harness (tests/lib/) and .git.
#
#   BUNDLE              the tree to scan when no FILEs are given
#   DUP_DEFS_ALLOW      names allowed several distinct definitions, space
#                       separated; each needs its same-value argument written
#                       where the caller sets it
#   DUP_DEFS_ONE_LOADS  a directory prefix whose files never load together
#                       (one per host), so their defs never collide
#   DUP_DEFS_SCRIPTS    a directory prefix of scripts, default tools/: each
#                       loads beside the other files but never beside another
#                       script, so a script's def is checked against the
#                       other files' only
set -e

DUP_DEFS_SCRIPTS="${DUP_DEFS_SCRIPTS-tools/}"

if [ $# -eq 0 ]; then
	cd "${BUNDLE:-.}" || exit 2
	# shellcheck disable=SC2046
	set -- $(find . -name '*.x' -not -path './tests/lib/*' -not -path './.git/*' \
		| sed 's|^\./||' | sort)
fi

# Scripts go last: their defs are checked against an owner already recorded.
_FILES=""
_SCRIPTS=""
for _f in "$@"; do
	case "$_f" in
		"$DUP_DEFS_SCRIPTS"*) [ -n "$DUP_DEFS_SCRIPTS" ] && { _SCRIPTS="$_SCRIPTS $_f"; continue; } ;;
	esac
	_FILES="$_FILES $_f"
done
_FILES="$_FILES $_SCRIPTS"

[ -n "${_FILES# }" ] || { echo "dup-defs: ok (no .x files)"; exit 0; }

# One S line per scoped file, then a G line per export it marks (global NAME)
# and an E line per plain export.  The marks are folded to @NAME first, so a
# provide list runs to its first `)`; comments are stripped a line at a time.
_scoped_provides() {
	# shellcheck disable=SC2086
	for _f in $(grep -l '^(module ' $_FILES /dev/null); do
		printf 'S\t%s\n' "$_f"
		sed 's/;.*$//' "$_f" | tr '\n' ' ' | sed 's/(global \([^()]*\))/@\1/g' \
			| grep -o '(provide [^)]*' \
			| awk -v f="$_f" '{ for (i = 3; i <= NF; i++)
				if ($i ~ /^@/) printf "G\t%s\t%s\n", f, substr($i, 2)
				else printf "E\t%s\t%s\n", f, $i }'
	done
}

# shellcheck disable=SC2086
_scoped_provides | awk -v allowed="$DUP_DEFS_ALLOW" -v one_loads="$DUP_DEFS_ONE_LOADS" \
	-v scripts="$DUP_DEFS_SCRIPTS" '
BEGIN {
  split(allowed, aw, " ")
  for (i in aw) allow[aw[i]] = 1
}

# Split the children of a top-level (do ...) body into kids[1..n],
# tracking strings and #\X char literals so their parens do not count.
# Only children recognised as lists are collected (defs are lists; atoms cannot
# define anything).
function split_children(f, kids,    s, i, n, c, depth, start, cnt, str) {
  s = f
  sub(/^\(do[ \t]*/, "", s)
  sub(/\)[ \t]*$/, "", s)
  n = length(s); depth = 0; str = 0; cnt = 0; start = 0
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (str) {
      if (c == "\\") i++
      else if (c == "\"") str = 0
      continue
    }
    if (c == "#" && substr(s, i, 2) == "#\\") { i += 2; continue }
    if (c == "\"") { str = 1; continue }
    if (c == "(") {
      if (depth == 0) start = i
      depth++
    } else if (c == ")") {
      depth--
      if (depth == 0 && start > 0) {
        kids[++cnt] = substr(s, start, i - start + 1)
        start = 0
      }
    }
  }
  return cnt
}

# Record one top-level form (already quote-normalized).  A (do ...) is
# descended: do evaluates its forms in the CALLER env, so a
# def directly inside binds globally, same as a bare top-level def.
function handle(f,    tmp, name, body, key, kids, nk, j, isclass) {
  if (f ~ /^\(do[ \t(]/) {
    nk = split_children(f, kids)
    for (j = 1; j <= nk; j++) handle(kids[j])
    return
  }
  tmp = f
  if (tmp ~ /^\(doc[ \t]*\(def(-class)?[ \t]/) sub(/^\(doc[ \t]*/, "", tmp)
  isclass = (tmp ~ /^\(def-class[ \t]/)
  if (tmp ~ /^\(def(-class)?[ \t]/) {
    sub(/^\(def(-class)?[ \t]+/, "", tmp)
    name = tmp
    sub(/[ \t)].*$/, "", name)
    body = tmp
    sub(/^[^ \t]+[ \t]*/, "", body)
    # A scoped module keeps what it does not bind in the root (see the
    # header): a marked export, or an exported class or class alias, is kept.
    if (FILENAME in scoped) {
      key = FILENAME SUBSEP name
      if (!((key in marked) || ((key in exported) && (isclass || body ~ /^[A-Z][^ \t()]*\)?$/)))) name = ""
    }
    if (name != "") {
      key = name SUBSEP FILENAME
      if (!(key in seen)) {
        seen[key] = 1
        nfiles[name]++
        if (body ~ /^\(prim-ref /) {
          if (!(name in fetch_body)) fetch_body[name] = body
          else if (fetch_body[name] != body) fetch_diverge[name] = 1
        } else if (scripts != "" && index(FILENAME, scripts) == 1) {
          # A script co-loads with the other files but never with a sibling
          # script -- each is its own engine run.  So a script def is checked
          # against the owner only; script-vs-script same-name defs are fine.
          # Scripts are read last, so the owner is already recorded.
          if ((name in own_body) && own_body[name] != body) {
            own_diverge[name] = 1
            own_file2[name] = FILENAME
            own_outside_one[name] = 1
          }
        } else {
          if (!(name in own_body)) { own_body[name] = body; own_file[name] = FILENAME }
          else if (own_body[name] != body) {
            own_diverge[name] = 1
            own_file2[name] = FILENAME
          }
          if (one_loads == "" || index(FILENAME, one_loads) != 1) own_outside_one[name] = 1
        }
      }
    }
  }
}

function flush_form(    tmp) {
  if (form == "") return
  # Normalize the quote idiom: (lit x)/(quote x) and bare quotes compare
  # equal (#45 R2 allows either spelling in boot-constrained files).
  while (match(form, /\((lit|quote) [^()]+\)/)) {
    tmp = substr(form, RSTART, RLENGTH)
    sub(/^\((lit|quote) /, "", tmp)
    sub(/\)$/, "", tmp)
    form = substr(form, 1, RSTART - 1) "Q:" tmp substr(form, RSTART + RLENGTH)
  }
  gsub(/'"'"'/, "Q:", form)
  handle(form)
  form = ""
}

# The pre-pass arrives first, on stdin: which files are scoped, and the names
# each of them provides.
FILENAME == "-" {
  split($0, pp, "\t")
  if (pp[1] == "S") scoped[pp[2]] = 1
  else if (pp[1] == "G") marked[pp[2] SUBSEP pp[3]] = 1
  else if (pp[1] == "E") exported[pp[2] SUBSEP pp[3]] = 1
  next
}

FNR == 1 { depth = 0; instr = 0; form = "" }

{
  line = $0
  n = length(line)
  out = ""
  i = 1
  while (i <= n) {
    c = substr(line, i, 1)
    if (instr) {
      out = out c
      if (c == "\\") { i++; if (i <= n) out = out substr(line, i, 1) }
      else if (c == "\"") instr = 0
    } else if (c == ";") {
      break
    } else if (c == "#" && substr(line, i, 2) == "#\\") {
      out = out substr(line, i, 3)
      i += 2
    } else {
      out = out c
      if (c == "\"") instr = 1
      else if (c == "(") depth++
      else if (c == ")") depth--
    }
    i++
  }
  if (out != "") {
    gsub(/[ \t]+/, " ", out)
    sub(/^ /, "", out)
    sub(/ $/, "", out)
    if (out != "") form = (form == "" ? out : form " " out)
  }
  if (depth == 0 && form != "") flush_form()
}

END {
  flush_form()
  for (name in nfiles) {
    if (nfiles[name] < 2) continue
    if (name in fetch_diverge) {
      printf "dup-def: %s -- files fetch DIFFERENT catalogue entries under one name\n", name
      bad = 1
    }
    if ((name in own_diverge) && !(name in allow) && (name in own_outside_one)) {
      printf "dup-def: %s -- distinct definitions in %s and %s (consolidate, or adjudicate in DUP_DEFS_ALLOW)\n", \
        name, own_file[name], own_file2[name]
      bad = 1
    }
  }
  if (bad) exit 1
  print "dup-defs: ok"
}
' - $_FILES
