#!/bin/sh
# dup-defs.sh -- cross-module duplicate-global-def ratchet (#47)
#
# Top-level redefinition updates the shared binding IN PLACE since the
# env-model fix (53b84b0), so two modules defining the same global name
# with different meanings is a real collision: whichever loads last
# rewires every caller (the %alist-find segfault -- sys/convert.x's
# dispatcher helper clobbered by logo/types.x's case-insensitive one).
#
# Rule, per global name defined at top level in MORE THAN ONE module:
#   - catalog fetches -- a body that is (prim-ref ...) -- must all fetch
#     the SAME catalog entry (normalized-identical args);
#   - one non-fetch definition (the registrar/owner) plus any number of
#     fetches is fine: the fetches return the registered object;
#   - several DISTINCT non-fetch definitions fail, unless the name is in
#     the adjudicated allowlist below or every definition lives in the
#     per-arch backend directory (lib/x/tool/asm/ -- one loads per host).
#
# Scope: lib/ + apps/ + tools/ (everything that can co-load into one
# base env -- the driver scripts load x-core and then their tool file, so
# tools/ globals land in the same env; the %lookup rebind fixed in #252
# lived exactly there, invisible to the pre-tools scan).
# Extraction is a real form scanner (paren depth outside strings, char
# literals, and ; comments), not a line grep.  Recognized definers:
# (def NAME ...), (def-class NAME ...), and their (doc ...) wrappers.
# A top-level (do ...) is descended into: %do-seq tail-evals children in
# the caller's env, so defs directly inside it bind globally -- treating
# them as top-level is what makes the cov.x/lint.x (do ...) bodies
# visible.  (let ...) is NOT descended: its bindings are scoped.
#
# Adjudicated same-name multi-definition names (2026-07-19, #47 wrap-up):
#   let            -- staged bootstrap upgrade: core/control.x defines the
#                     basic form, core/syntax.x redefines with named-let;
#                     last-loaded wins IS the intent.
#   compile-asm    -- tool/compile.x installs a lazy stub that
#                     include-onces tool/asm-compile.x (the real one) and
#                     re-dispatches; the overwrite is the mechanism.
#   %deg->rad      -- logo math.x/state.x each derive the same converter.
#   %c-read %c-malloc %c-free %c-close
#                  -- libc symbols re-resolved per module through
#                     different FFI helpers (%resolve/%sk/%dlsym); same
#                     pointer by construction.
#   %obj-set! %list-type %ptr %ptr-ref %int->ptr
#                  -- same value re-derived from different doors
#                     (data.x raw path vs prim-ref-composed).
# New entries need the same-value argument written here.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_DIR" || exit 1

_FILES=$(find lib apps tools -name '*.x' 2>/dev/null | sort)

awk '
BEGIN {
  split("let compile-asm %deg->rad %c-read %c-malloc %c-free %c-close " \
        "%obj-set! %list-type %ptr %ptr-ref %int->ptr", aw, " ")
  for (i in aw) allow[aw[i]] = 1
}

# Split the children of a top-level (do ...) body into kids[1..n],
# tracking strings and #\X char literals so their parens do not count.
# Only list-shaped children are collected (defs are lists; atoms cannot
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
# descended: %do-seq tail-evals its children in the CALLER env, so a
# def directly inside binds globally, same as a bare top-level def.
function handle(f,    tmp, name, body, key, kids, nk, j) {
  if (f ~ /^\(do[ \t(]/) {
    nk = split_children(f, kids)
    for (j = 1; j <= nk; j++) handle(kids[j])
    return
  }
  tmp = f
  if (tmp ~ /^\(doc[ \t]*\(def(-class)?[ \t]/) sub(/^\(doc[ \t]*/, "", tmp)
  if (tmp ~ /^\(def(-class)?[ \t]/) {
    sub(/^\(def(-class)?[ \t]+/, "", tmp)
    name = tmp
    sub(/[ \t)].*$/, "", name)
    body = tmp
    sub(/^[^ \t]+[ \t]*/, "", body)
    if (name != "") {
      key = name SUBSEP FILENAME
      if (!(key in seen)) {
        seen[key] = 1
        nfiles[name]++
        if (body ~ /^\(prim-ref /) {
          if (!(name in fetch_body)) fetch_body[name] = body
          else if (fetch_body[name] != body) fetch_diverge[name] = 1
        } else if (FILENAME ~ /^tools\//) {
          # A tool script co-loads with lib/apps (its driver loads x-core
          # first) but never with a sibling tool script -- each driver is
          # its own engine run.  So a tools/ def is checked against the
          # lib/apps owner only; tools-vs-tools same-name defs are fine.
          # lib/apps sort before tools/, so the owner is already recorded.
          if ((name in own_body) && own_body[name] != body) {
            own_diverge[name] = 1
            own_file2[name] = FILENAME
            own_outside_arch[name] = 1
          }
        } else {
          if (!(name in own_body)) { own_body[name] = body; own_file[name] = FILENAME }
          else if (own_body[name] != body) {
            own_diverge[name] = 1
            own_file2[name] = FILENAME
          } else if (own_file[name] != FILENAME) {
            # identical text in a second file: harmless duplicate
          }
          if (FILENAME !~ /^lib\/x\/tool\/asm\//) own_outside_arch[name] = 1
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
      printf "dup-def: %s -- modules fetch DIFFERENT catalog entries under one name\n", name
      bad = 1
    }
    if ((name in own_diverge) && !(name in allow) && (name in own_outside_arch)) {
      printf "dup-def: %s -- distinct definitions in %s and %s (adjudicate or consolidate; see header)\n", \
        name, own_file[name], own_file2[name]
      bad = 1
    }
  }
  if (bad) exit 1
  print "dup-defs: ok"
}
' $_FILES
