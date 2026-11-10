; help-examples.x -- the ceiling on doc entries that show the reader no
; example: (entries-without-example COUNT).
;
; An entry shows an example when its doc form carries an (example "in"
; "out") or a (sample "in" "prose"); help renders the two alike.  The
; count is of the entries with neither, over every module under lib/x, as
; tools/check/doctest.x walks them and tools/check/help-examples.sh reads
; the tally.  The row may only go down: a count over it fails, and the
; check prints the number to lower it to once an area's examples land.
;
; Measured 2026-11-04 on the registry as the doctest walk sees it.  The
; 2026-10-26 audit's figure, 1072 of 1747, came from a form parser over
; the sources; the walk counts what help reads.

(entries-without-example 886)
