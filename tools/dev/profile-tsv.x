; tools/dev/profile-tsv.x -- every profile row, for a script to merge
;
; Appended by tools/dev/profile.sh --tsv after the program it profiles.  One
; line for each row of (profile-rows), tab-separated and led by PROF so that
; the program's own output can be told from it:
;
;   PROF file line calls evals pairs saturated
;
; saturated is 1 when a count in the body was at its maximum, and 0 otherwise.

((fn (self rows)
   (if (null? rows)
     ()
     ((fn (_ row)
        (display "PROF\t" (first row)
                 "\t" (first (rest row))
                 "\t" (first (rest (rest row)))
                 "\t" (first (rest (rest (rest row))))
                 "\t" (first (rest (rest (rest (rest row)))))
                 "\t" (if (first (rest (rest (rest (rest (rest row)))))) 1 0)
                 "\n")
        (self (rest rows)))
      (first rows))))
 (profile-rows))
