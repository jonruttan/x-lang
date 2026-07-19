; date.x -- Date: civil dates over unix time (#21). Pure integer math
; (Howard Hinnant's days/civil algorithms), UTC only -- no timezone
; database, no locale. A date is an ALIST:
;   ((year . 2026) (month . 7) (day . 18)
;    (hour . 21) (minute . 30) (second . 0) (wday . 6))
; month 1-12, day 1-31, wday 0-6 with 0 = Sunday.

(import x/core/alist)
(import x/type/class)
(import x/protocol/str/str8)

; Tower-proof integer ops: under x/and or x/or the ambient / promotes to
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

(def %pad2 (fn (_ n) (Str8 pad-left 2 #\0 (number->str n))))

(def-class Date ()
  (doc "Civil dates over unix time: pure integer math, proleptic Gregorian, UTC only."
    (note "A date is an alist ((year . Y) (month . M) (day . D) (hour . H) (minute . MIN) (second . S) (wday . W)); month 1-12, wday 0-6 with 0 = Sunday. No timezones, no locale -- boundary code converts at the edge.")
    (example "(assoc-get 'year (Date from-unix 0))" "1970")
    (example "(Date ->iso (Date from-unix 0))" "\"1970-01-01T00:00:00Z\""))
  (static
    (method from-unix (self (param secs INT "Seconds since the unix epoch (negative = pre-1970)"))
      (doc "Split unix seconds into a civil date-time alist (UTC)."
        (returns ALIST "((year . Y) (month . M) (day . D) (hour . H) (minute . MIN) (second . S) (wday . W))")
        (example "(assoc-get 'wday (Date from-unix 0))" "4")
        (example "(assoc-get 'day (Date from-unix 86399))" "1")
        (example "(assoc-get 'year (Date from-unix -86400))" "1969"))
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
      (+ (* (%days-from-civil (assoc-get 'year date)
                              (assoc-get 'month date)
                              (assoc-get 'day date))
            86400)
         (+ (* (Assoc get-or 0 'hour date) 3600)
            (+ (* (Assoc get-or 0 'minute date) 60)
               (Assoc get-or 0 'second date)))))

    (method now (self)
      (doc "The current wall-clock civil date-time (UTC), from (Sys time)."
        (returns ALIST "Date alist for now")
        (sample "(Date now)" "((year . 2026) (month . 7) (day . 18) ...)"))
      (Date from-unix (Sys time)))

    (method ->iso (self (param date ALIST "Date alist"))
      (doc "Format a date alist as an ISO-8601 UTC timestamp."
        (returns STRING "\"YYYY-MM-DDTHH:MM:SSZ\"")
        (example "(Date ->iso (Date from-unix 1234567890))" "\"2009-02-13T23:31:30Z\""))
      (Str8 append
        (number->str (assoc-get 'year date))
        "-" (%pad2 (assoc-get 'month date))
        "-" (%pad2 (assoc-get 'day date))
        "T" (%pad2 (Assoc get-or 0 'hour date))
        ":" (%pad2 (Assoc get-or 0 'minute date))
        ":" (%pad2 (Assoc get-or 0 'second date))
        "Z"))

    (method leap-year? (self (param y INT "Year"))
      (doc "Gregorian leap-year test."
        (returns BOOL "True for leap years")
        (example "(list (Date leap-year? 2024) (Date leap-year? 1900) (Date leap-year? 2000))" "(#t #f #t)"))
      (if (= (%i% y 4) 0)
        (if (= (%i% y 100) 0) (= (%i% y 400) 0) #t)
        #f))))

(doc (provide x/sys/date Date)
  (note "(Date now) needs x/sys/posix loaded for (Sys time); everything else is pure. Timezone-aware work happens at the boundary -- this module is UTC by design.")
  "Civil dates over unix time on the Date class: from-unix / to-unix / now / ->iso / leap-year?.")
