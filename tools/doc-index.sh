#!/bin/sh
# doc-index.sh -- Generate master index for x-lang reference docs
#
# Scans the docs/ref/x/ directory structure directly rather than
# querying the module registry, so all generated docs appear.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOCDIR="${ROOT}/docs/ref/x"

echo "# x-lang Reference"
echo
echo "Generated from source by \`make doc-x\`."
echo

# Group labels in display order
for group in boot:Bootstrap core:Core type:Types sys:System num:"Numeric Tower" doc:Documentation tool:Tools platform:Platform; do
    dir="${group%%:*}"
    label="${group#*:}"

    if [ -d "${DOCDIR}/${dir}" ]; then
        echo "## ${label}"
        echo

        for f in "${DOCDIR}/${dir}"/*.md; do
            [ -f "$f" ] || continue
            base=$(basename "$f" .md)
            [ "$base" = "index" ] && continue

            # Extract title from first heading
            title=$(head -5 "$f" | grep '^# ' | head -1 | sed 's/^# //')
            [ -z "$title" ] && title="x/${dir}/${base}"

            # Extract description from first non-empty line after heading
            desc=$(awk '/^# /{found=1; next} found && /^[^#\[]/ && !/^$/{print; exit}' "$f")

            printf -- "- [%s](%s/%s.md)" "$title" "$dir" "$base"
            [ -n "$desc" ] && printf " — %s" "$desc"
            echo
        done

        echo
    fi
done

# Top-level files (and.x, or.x, constructs.x, x-core.x)
has_toplevel=0
for f in "${DOCDIR}"/*.md; do
    [ -f "$f" ] || continue
    base=$(basename "$f" .md)
    [ "$base" = "index" ] && continue

    if [ "$has_toplevel" -eq 0 ]; then
        echo "## Top-level"
        echo
        has_toplevel=1
    fi

    title=$(head -5 "$f" | grep '^# ' | head -1 | sed 's/^# //')
    [ -z "$title" ] && title="$base"
    desc=$(awk '/^# /{found=1; next} found && /^[^#\[]/ && !/^$/{print; exit}' "$f")

    printf -- "- [%s](%s.md)" "$title" "$base"
    [ -n "$desc" ] && printf " — %s" "$desc"
    echo
done

[ "$has_toplevel" -eq 1 ] && echo
