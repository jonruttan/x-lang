; date.x -- Date: civil dates over unix time (#21). Pure integer math
; (Howard Hinnant's days/civil algorithms), UTC only -- no timezone
; database, no locale. A date is an ALIST:
;   ((year . 2026) (month . 7) (day . 18)
;    (hour . 21) (minute . 30) (second . 0) (wday . 6))
; month 1-12, day 1-31, wday 0-6 with 0 = Sunday.

(import x/core/alist)
(import x/type/class)
(import x/type/list)   ; from-iso field work (length/ref/map)
(import x/protocol/str/str8)

; Tower-proof integer ops: under xenon or radon the ambient / promotes to
; RATIONAL (287787200/146097 is not a year). Civil math is INT math by
; definition -- fetch the raw C ops once and use them throughout.
(def %i/ (prim-ref 'int '/))
(def %i% (prim-ref 'int '%))

; Truncating / is C division; these need FLOOR division for pre-epoch
; times. %fdiv rounds toward negative infinity.
(def %fdiv
  (fn (_ a b)
    (let ((q (%i/ a b)))
      (if (and (< a 0) (not (= (* q b) a))) (- q 1) q))))

; days since 1970-01-01 -> (year month day), proleptic Gregorian.
(def %civil-from-days
  (fn (_ z0)
    (let ((z (+ z0 719468)))
      (let ((era (%fdiv z 146097)))
        (let ((doe (- z (* era 146097))))
          ; yoe = (doe - doe/1460 + doe/36524 - doe/146096) / 365 -- Hinnant's
          ; exact terms (leap every 4y, minus centuries, plus the 400y leap).
          ; Two mis-transcriptions died here: a sign-flip decoded the epoch as
          ; 1968-12-29, and a doe/365 term passed spot checks but shifted
          ; year-boundary days (2023-03-01 decoded as Feb 29) -- the 4000-day
          ; roundtrip sweep in date.spec.md is the pin that holds the law.
          (let ((yoe (%i/ (- (+ (- doe (%i/ doe 1460)) (%i/ doe 36524)) (%i/ doe 146096)) 365)))
            (let ((doy (- doe (+ (* 365 yoe) (- (%i/ yoe 4) (%i/ yoe 100))))))
              (let ((mp (%i/ (+ (* 5 doy) 2) 153)))
                (let ((d (+ (- doy (%i/ (+ (* 153 mp) 2) 5)) 1))
                      (m (if (< mp 10) (+ mp 3) (- mp 9))))
                  (list (+ (+ yoe (* era 400)) (if (<= m 2) 1 0)) m d))))))))))

; (year month day) -> days since 1970-01-01.
(def %days-from-civil
  (fn (_ y0 m d)
    (let ((y (if (<= m 2) (- y0 1) y0)))
      (let ((era (%fdiv y 400)))
        (let ((yoe (- y (* era 400))))
          (let ((doy (+ (%i/ (+ (* 153 (if (> m 2) (- m 3) (+ m 9))) 2) 5) (- d 1))))
            (let ((doe (+ (* yoe 365) (+ (- (%i/ yoe 4) (%i/ yoe 100)) doy))))
              (- (+ (* era 146097) doe) 719468))))))))

(def %pad2 (fn (_ n) (Str8 pad-left 2 #\0 (%number->str n))))

(def-class Date ()
  (doc "Civil dates over unix time: pure integer math, proleptic Gregorian, UTC only."
    (note "A date is an alist ((year . Y) (month . M) (day . D) (hour . H) (minute . MIN) (second . S) (wday . W)); month 1-12, wday 0-6 with 0 = Sunday. No timezones, no locale -- boundary code converts at the edge.")
    (example "(Assoc get 'year (Date from-unix 0))" "1970")
    (example "(Date ->iso (Date from-unix 0))" "\"1970-01-01T00:00:00Z\""))
  (static
    (method from-unix (self (param secs INT "Seconds since the unix epoch (negative = pre-1970)"))
      (doc "Split unix seconds into a civil date-time alist (UTC)."
        (returns ALIST "((year . Y) (month . M) (day . D) (hour . H) (minute . MIN) (second . S) (wday . W))")
        (example "(Assoc get 'wday (Date from-unix 0))" "4")
        (example "(Assoc get 'day (Date from-unix 86399))" "1")
        (example "(Assoc get 'year (Date from-unix -86400))" "1969"))
      (def days (%fdiv secs 86400))
      (def sod (- secs (* days 86400)))
      (def ymd (%civil-from-days days))
      (list (pair 'year (first ymd))
            (pair 'month (first (rest ymd)))
            (pair 'day (first (rest (rest ymd))))
            (pair 'hour (%i/ sod 3600))
            (pair 'minute (%i/ (%i% sod 3600) 60))
            (pair 'second (%i% sod 60))
            (pair 'wday (%i% (+ (%i% (+ days 4) 7) 7) 7))))

    (method to-unix (self (param date ALIST "Date alist; hour/minute/second default to 0 when absent"))
      (doc "Civil date-time alist (UTC) back to unix seconds -- the inverse of from-unix."
        (returns INT "Seconds since the unix epoch")
        (example "(Date to-unix '((year . 1970) (month . 1) (day . 1)))" "0")
        (example "(Date to-unix (Date from-unix 1234567890))" "1234567890"))
      (+ (* (%days-from-civil (Assoc get 'year date)
                              (Assoc get 'month date)
                              (Assoc get 'day date))
            86400)
         (+ (* (Assoc get-or 0 'hour date) 3600)
            (+ (* (Assoc get-or 0 'minute date) 60)
               (Assoc get-or 0 'second date)))))

    (method now (self)
      (doc "The current wall-clock civil date-time (UTC), from (Sys now)."
        (returns ALIST "Date alist for now")
        (sample "(Date now)" "((year . 2026) (month . 7) (day . 18) ...)"))
      (Date from-unix (Sys now)))

    (method ->iso (self (param date ALIST "Date alist"))
      (doc "Format a date alist as an ISO-8601 UTC timestamp."
        (returns STRING "\"YYYY-MM-DDTHH:MM:SSZ\"")
        (example "(Date ->iso (Date from-unix 1234567890))" "\"2009-02-13T23:31:30Z\""))
      (Str8 append
        (%number->str (Assoc get 'year date))
        "-" (%pad2 (Assoc get 'month date))
        "-" (%pad2 (Assoc get 'day date))
        "T" (%pad2 (Assoc get-or 0 'hour date))
        ":" (%pad2 (Assoc get-or 0 'minute date))
        ":" (%pad2 (Assoc get-or 0 'second date))
        "Z"))

    (method from-iso (self (param s STRING "ISO-8601 UTC timestamp: \"YYYY-MM-DDTHH:MM:SSZ\" or the bare date \"YYYY-MM-DD\""))
      (doc "Parse an ISO-8601 UTC timestamp back to a date alist -- the inverse of ->iso (#364). Strict per #61: wrong shape, out-of-range fields, or a nonexistent civil date (Feb 30) raises kind-'value. A bare date reads as midnight."
        (returns ALIST "Canonical date alist (wday included), as from-unix builds")
        (example "(Date from-iso \"2009-02-13T23:31:30Z\")" "(('year . 2009) ('month . 2) ('day . 13) ('hour . 23) ('minute . 31) ('second . 30) ('wday . 5))")
        (example "(Assoc get 'hour (Date from-iso \"1970-01-01\"))" "0")
        (example "(Date to-unix (Date from-iso \"2009-02-13T23:31:30Z\"))" "1234567890"))
      (def %bad (fn (_ what)
        (Err raise 'value (Str8 append "Date from-iso: " what) s)))
      (def %int-at (fn (_ q)
        (let ((n (%str->number q)))
          (if (null? n) (%bad "non-numeric field") n))))
      (def ti (Str8 index-of "T" s))
      (def date-part (if (null? ti) s (Str8 sub 0 ti s)))
      ; negative years: norm the leading '-' away for the split, restore after
      (def neg? (Str8 starts? "-" date-part))
      (def dp (if neg? (Str8 sub 1 (Str8 length date-part) date-part) date-part))
      (def dsegs (Str8 split "-" dp))
      (unless (= (List length dsegs) 3) (%bad "date is not YYYY-MM-DD"))
      (def y ((fn (_ v) (if neg? (- 0 v) v)) (%int-at (List ref 0 dsegs))))
      (def mo (%int-at (List ref 1 dsegs)))
      (def d (%int-at (List ref 2 dsegs)))
      (def tsegs
        (if (null? ti) (list 0 0 0)
          (let ((tp (Str8 sub (+ ti 1) (Str8 length s) s)))
            (do (unless (= (Str8 length tp) 9) (%bad "time is not HH:MM:SSZ"))
                (unless (Str8 ends? "Z" tp) (%bad "missing the Z (UTC-only by design)"))
                (let ((hh (Str8 split ":" (Str8 sub 0 8 tp))))
                  (do (unless (= (List length hh) 3) (%bad "time is not HH:MM:SSZ"))
                      (List map (fn (_ q) (%int-at q)) hh)))))))
      (def h (List ref 0 tsegs))
      (def mi (List ref 1 tsegs))
      (def sec (List ref 2 tsegs))
      (when (or (< mo 1) (> mo 12)) (%bad "month out of range"))
      (when (or (< d 1) (> d 31)) (%bad "day out of range"))
      (when (or (< h 0) (> h 23)) (%bad "hour out of range"))
      (when (or (< mi 0) (> mi 59)) (%bad "minute out of range"))
      (when (or (< sec 0) (> sec 59)) (%bad "second out of range"))
      ; canonicalize through unix seconds; a nonexistent civil date (Feb 30)
      ; shifts under the roundtrip and is refused rather than silently moved
      (def parsed (list (pair 'year y) (pair 'month mo) (pair 'day d)
                        (pair 'hour h) (pair 'minute mi) (pair 'second sec)))
      (def canon (Date from-unix (Date to-unix parsed)))
      (unless (and (= (Assoc get 'day canon) d) (= (Assoc get 'month canon) mo))
        (%bad "no such civil date"))
      canon)

    (method leap-year? (self (param y INT "Year"))
      (doc "Gregorian leap-year test."
        (returns BOOL "True for leap years")
        (example "(list (Date leap-year? 2024) (Date leap-year? 1900) (Date leap-year? 2000))" "(#t #f #t)"))
      (if (= (%i% y 4) 0)
        (if (= (%i% y 100) 0) (= (%i% y 400) 0) #t)
        #f))))

(doc (provide x/sys/date Date)
  (note "(Date now) needs x/sys/posix loaded for (Sys now); everything else is pure. Timezone-aware work happens at the boundary -- this module is UTC by design.")
  "Civil dates over unix time on the Date class: from-unix / to-unix / now / ->iso / leap-year?.")
