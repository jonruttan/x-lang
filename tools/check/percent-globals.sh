#!/bin/sh
# percent-globals.sh -- the %-GLOBAL BUDGET ratchet.
#
# The % prefix marks a def "private", but the language has no module
# scope: every top-level (def %name ...) binds globally, in every
# session that imports the file.  The bare-globals ratchet (#108)
# deliberately exempted %-names -- which let them grow unbounded (pin.x
# reached ONE HUNDRED before it was homed into its class).  This check
# closes the exemption: every file's count of top-level %-defs is
# budgeted in tools/contract/percent-globals.x, and the budget may only
# SHRINK.  The composed alternative is the classes-ARE-namespaces rule:
# home helpers as %-prefixed statics on the module's class (pin.x is the
# worked example -- one justified global remains).
#
# Both directions fail, mirroring bare-globals:
#   - a file over its budget fails (the pollution cannot grow);
#   - a file under its budget fails (ratchet DOWN: update the row, keep
#     the win); a file absent from the manifest has budget 0.
#
# Scope: lib/ + apps/ + tools/ -- dup-defs.sh's scope, for dup-defs.sh's
# reason: a tool script co-loads with the library (its driver loads
# x-core first), so its globals land in the same env.  Tools are not
# exempt from the rule; the check just could not see them (#304).
#
# Counting is FORM-ACCURATE (tools/check/defs.awk), not a line grep,
# because "binds globally" is not the same as "starts in column 0":
#   - (doc (def %name ...)) is a def -- the old ^(def % grep skipped
#     every DOCUMENTED helper, so the better a global was documented the
#     more invisible it was;
#   - a def directly inside a top-level (do ...) binds in the caller's
#     env, which is how the tool scripts write nearly everything.
#
# Hot-path files keep large budgets on MEASURED grounds (class dispatch
# costs 8-30x, so sha256/asm de-dispatched deliberately).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_DIR" || exit 1

MANIFEST=tools/contract/percent-globals.x

{
  find lib apps tools -name '*.x' 2>/dev/null | sort \
    | xargs awk -f tools/check/defs.awk \
    | awk -F'\t' '$2 ~ /^%/ { c[$1]++ } END { for (f in c) print "C", f, c[f] }'
  sed -n 's/^(file "\(.*\)" \([0-9][0-9]*\)).*/B \1 \2/p' "$MANIFEST"
} | awk '
  $1=="C" { count[$2]=$3 }
  $1=="B" { budget[$2]=$3 }
  END {
    bad=0
    for (f in count) {
      b = (f in budget) ? budget[f] : 0
      if (count[f] > b) {
        printf "percent-globals: %s has %d top-level %%-defs, budget %d -- home them in the file'\''s class (see lib/x/tool/pin.x)\n", f, count[f], b > "/dev/stderr"
        bad=1
      }
    }
    for (f in budget) {
      n = (f in count) ? count[f] : 0
      if (n < budget[f]) {
        printf "percent-globals: %s is under budget (%d < %d) -- ratchet the row down in tools/contract/percent-globals.x\n", f, n, budget[f] > "/dev/stderr"
        bad=1
      }
    }
    if (bad) exit 1
    print "percent-globals: every file within its shrinking budget."
  }'
