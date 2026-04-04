#!/bin/sh
# doc-index.sh -- Generate master index for x-lang reference docs
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
X="${ROOT}/x"
LIB="${ROOT}/lib/x-core.x"

TMPINPUT=$(mktemp)
cat > "$TMPINPUT" <<'XEOF'
(do
  (display "# x-lang Reference\n\n")
  (display "Generated from source by `make doc-x`.\n\n")

  (def %modules (first %module-registry-cell))

  (def %groups (list
    (pair "x/boot" "Bootstrap")
    (pair "x/core" "Core")
    (pair "x/type" "Types")
    (pair "x/sys"  "System")
    (pair "x/num"  "Numeric Tower")
    (pair "x/doc"  "Documentation")
    (pair "x/tool" "Tools")
    (pair "x/platform" "Platform")))

  (for-each
    (fn (_ group)
      (def %prefix (first group))
      (def %label (rest group))
      (def %found
        (filter
          (fn (_ mod)
            (def %name (symbol->str (first mod)))
            (def %plen (str-length %prefix))
            (if (< (str-length %name) %plen) #f
              (str=? (substring %name 0 %plen) %prefix)))
          %modules))
      (if (not (null? %found))
        (do
          (display "## ") (display %label) (newline) (newline)
          (for-each
            (fn (_ mod)
              (def %name (first mod))
              (def %name-str (symbol->str %name))
              (def %rel (str-append (substring %name-str 2 (str-length %name-str)) ".md"))
              (display "- [") (display %name) (display "](") (display %rel) (display ")")
              (def %doc-entry (%doc-lookup %name))
              (if (not (null? %doc-entry))
                (if (not (str=? (%doc-entry-desc %doc-entry) ""))
                  (do (display " — ") (display (%doc-entry-desc %doc-entry)))))
              (newline))
            %found)
          (newline))))
    %groups))
XEOF

cat "$LIB" "$TMPINPUT" | "$X" 2>/dev/null
rm -f "$TMPINPUT"
