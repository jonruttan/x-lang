; zone.x -- Zone: named time zones from the system's zone database.
;
; A zone is read from one file under /usr/share/zoneinfo, or under the
; directory TZDIR names, in the TZif format
; of RFC 8536: the moments the zone's offset from UTC changed, and after
; them a rule in the form of POSIX's TZ that says how it changes each year
; from then on.  The calendar is x/sys/date's; nothing here asks the C
; library, so a program may hold several zones at once and none of them
; depends on TZ.
;
; A Zone holds:
;   name     the name it was asked for, as "Europe/Paris"
;   changes  a list of (SECONDS . OFFSET), the unix second a change came
;            and the offset from then, in seconds east of UTC, the latest
;            first
;   initial  the offset before any of them
;   rule     nil, or (STANDARD) for an offset that does not change, or
;            (STANDARD DAYLIGHT START END), START and END each
;            (MONTH WEEK WEEKDAY SECONDS): the week of the month, 5 for
;            its last, the weekday 0 for Sunday, and the seconds into the
;            day on the clock in force before the change

(module x/sys/zone)
(import x/core/alist)
(import x/type/class)
(import x/type/list)
(import x/protocol/str/str8)
(import x/codec/bytes)
(import x/sys/file)
(import x/sys/date)

; Integer division whatever numeric tower is loaded, as x/sys/date has it.
(import x/core/doors int% int/)

; Where the zone database is: the directory TZDIR names, as the C library
; reads it, else the usual one.
(def %zone-directory
  (fn (_)
    (let ((dir (Sys getenv "TZDIR")))
      (if (or (null? dir) (str=? dir "")) "/usr/share/zoneinfo/" (Str8 append dir "/")))))

(def %zone-seconds-day 86400)
(def %zone-seconds-hour 3600)

; A over B, rounded toward the least: right for a second before 1970.
(def %zone-floor-div
  (fn (_ a b)
    (let ((q (int/ a b)))
      (if (and (< a 0) (not (= (* q b) a))) (- q 1) q))))

(def %zone-floor-mod (fn (_ a b) (- a (* (%zone-floor-div a b) b))))

; --- a zone's file -----------------------------------------------------------

; The big-endian integer of N bytes of REGION from AT, unsigned.
(def %zone-unsigned
  (fn (_ region at n)
    ((fn (self i acc)
       (if (>= i n) acc
         (self (+ i 1) (+ (* acc 256) (Bytes ref region (+ at i))))))
     0 0)))

; The same, read as two's complement.  The first byte carries the sign, so
; no step holds more than the answer does.
(def %zone-signed
  (fn (_ region at n)
    (let ((lead (Bytes ref region at)))
      ((fn (self i acc)
         (if (>= i n) acc
           (self (+ i 1) (+ (* acc 256) (Bytes ref region (+ at i))))))
       1 (if (>= lead 128) (- lead 256) lead)))))

; A TZif header is 44 bytes: the magic, a version, and after 15 unused
; bytes six counts of four bytes each.
(def %zone-header 44)
(def %zone-counts 20)
(def %zone-magic (Bytes of-list (list 84 90 105 102)))

; The count at the place I of the six in the header at BASE: 0 and 1 the
; indicators, 2 the leap seconds, 3 the changes, 4 the kinds of time, and
; 5 the bytes of their names.
(def %zone-count
  (fn (_ region base i) (%zone-unsigned region (+ base %zone-counts (* i 4)) 4)))

; How many bytes the data after the header at BASE takes, its times of
; WIDTH bytes.
(def %zone-data-size
  (fn (_ region base width)
    (+ (* (%zone-count region base 3) (+ width 1))
       (* (%zone-count region base 4) 6)
       (%zone-count region base 5)
       (* (%zone-count region base 2) (+ width 4))
       (%zone-count region base 1)
       (%zone-count region base 0))))

; The changes and the first offset in the block whose header is at BASE:
; (CHANGES . FIRST).
(def %zone-block
  (fn (_ region base width)
    (let ((times (%zone-count region base 3)) (kinds (%zone-count region base 4))
          (data (+ base %zone-header)))
      (let ((kinds-at (+ data (* times (+ width 1)))))
        (let ((offsets (List map (fn (_ j) (%zone-signed region (+ kinds-at (* j 6)) 4))
                                 (List range 0 kinds))))
          (pair
            (List fold
              (fn (_ changes i)
                (pair (pair (%zone-signed region (+ data (* i width)) width)
                            (List ref (Bytes ref region (+ data (* times width) i)) offsets))
                      changes))
              () (List range 0 times))
            (if (null? offsets) 0 (first offsets))))))))

(def %zone-newline (Bytes of-list (list 10)))

; The text between the two newlines that follow the data whose end is AT,
; or nil.
(def %zone-footer
  (fn (_ region at)
    (if (>= (+ at 1) (Bytes length region)) ()
      (let ((after (Bytes sub region (+ at 1) (- (Bytes length region) at 1))))
        (let ((n (Bytes find after %zone-newline)))
          (if (null? n) () (first (Bytes copy (Bytes sub after 0 n)))))))))

; (CHANGES FIRST RULE) from a file's bytes, or nil when they are not a
; zone's.  A file of version 2 or later has its times twice, of four bytes
; and then of eight; the second is read.
(def %zone-read
  (fn (_ region)
    (if (or (< (Bytes length region) %zone-header)
            (not (Bytes same? (Bytes sub region 0 4) %zone-magic)))
      ()
      (if (= (Bytes ref region 4) 0)
        (let ((block (%zone-block region 0 4)))
          (list (first block) (rest block) ()))
        (let ((base (+ %zone-header (%zone-data-size region 0 4))))
          (let ((block (%zone-block region base 8))
                (footer (%zone-footer region (+ base %zone-header (%zone-data-size region base 8)))))
            (list (first block) (rest block)
                  (if (or (null? footer) (str=? footer "")) () (%zone-rule footer)))))))))

; --- a rule ------------------------------------------------------------------

(def %zone-code (fn (_ text i) (Char ->int (Str8 ref i text))))

(def %zone-digit?
  (fn (_ text i)
    (and (< i (Str8 length text)) (>= (%zone-code text i) 48) (<= (%zone-code text i) 57))))

(def %zone-at?
  (fn (_ text i c) (and (< i (Str8 length text)) (= (%zone-code text i) c))))

; The number at I: (N . NEXT).
(def %zone-number
  (fn (_ text i)
    ((fn (self i n)
       (if (%zone-digit? text i) (self (+ i 1) (+ (* n 10) (- (%zone-code text i) 48)))
         (pair n i)))
     i 0)))

(def %zone-colon 58)

; Hours, and minutes and seconds after colons, at I, with a sign before
; them or none, as seconds: (SECONDS . NEXT).
(def %zone-clock
  (fn (_ text i)
    (let ((negative (%zone-at? text i 45)))
      (let ((h (%zone-number text (if (or negative (%zone-at? text i 43)) (+ i 1) i))))
        (let ((m (if (%zone-at? text (rest h) %zone-colon) (%zone-number text (+ (rest h) 1))
                   (pair 0 (rest h)))))
          (let ((s (if (%zone-at? text (rest m) %zone-colon) (%zone-number text (+ (rest m) 1))
                     (pair 0 (rest m)))))
            (let ((total (+ (* (first h) %zone-seconds-hour) (* (first m) 60) (first s))))
              (pair (if negative (- 0 total) total) (rest s)))))))))

; Where a zone's abbreviation at I ends: letters, or anything between
; angle brackets.
(def %zone-name-end
  (fn (_ text i)
    (if (%zone-at? text i 60)
      ((fn (self j) (if (or (>= j (Str8 length text)) (%zone-at? text j 62)) (+ j 1) (self (+ j 1))))
       i)
      ((fn (self j)
         (if (and (< j (Str8 length text))
                  (let ((c (%zone-code text j))) (or (and (>= c 65) (<= c 90)) (and (>= c 97) (<= c 122)))))
           (self (+ j 1))
           j))
       i))))

; The clock's time a change comes at when the rule gives none: 02:00.
(def %zone-change-default (* 2 %zone-seconds-hour))

; One end of the daylight time at I, Mmonth.week.weekday and a time after
; a slash: ((MONTH WEEK WEEKDAY SECONDS) . NEXT), or nil for a form that is
; not read.
(def %zone-rule-end
  (fn (_ text i)
    (if (not (%zone-at? text i 77)) ()
      (let ((month (%zone-number text (+ i 1))))
        (let ((week (%zone-number text (+ (rest month) 1))))
          (let ((weekday (%zone-number text (+ (rest week) 1))))
            (let ((at (if (%zone-at? text (rest weekday) 47) (%zone-clock text (+ (rest weekday) 1))
                        (pair %zone-change-default (rest weekday)))))
              (pair (list (first month) (first week) (first weekday) (first at)) (rest at)))))))))

; A rule from its text, as EST5EDT,M3.2.0,M11.1.0.  An offset in it is
; hours west of UTC.  Daylight time is an hour on unless it says.  An end
; in a form other than M is not read, and the zone then has standard time
; alone.
(def %zone-rule
  (fn (_ text)
    (let ((std (%zone-clock text (%zone-name-end text 0))))
      (let ((standard (- 0 (first std))) (dst-name (%zone-name-end text (rest std))))
        (if (= dst-name (rest std)) (list standard)
          (let ((dst (if (or (%zone-at? text dst-name 44) (>= dst-name (Str8 length text)))
                       (pair (- 0 (+ standard %zone-seconds-hour)) dst-name)
                       (%zone-clock text dst-name))))
            (let ((start (if (%zone-at? text (rest dst) 44) (%zone-rule-end text (+ (rest dst) 1)) ())))
              (let ((end (if (and (not (null? start)) (%zone-at? text (rest start) 44))
                           (%zone-rule-end text (+ (rest start) 1))
                           ())))
                (if (or (null? start) (null? end)) (list standard)
                  (list standard (- 0 (first dst)) (first start) (first end)))))))))))

; The day a year, a month and a day name, counted from 1970-01-01.
(def %zone-day
  (fn (_ year month day)
    (int/ (Date to-unix (list (pair 'year year) (pair 'month month) (pair 'day day)))
          %zone-seconds-day)))

; The second on the clock that END falls at in YEAR, counted as if the
; clock were UTC.  A week past the month's end is its last.
(def %zone-rule-moment
  (fn (_ end year)
    (let ((month (first end)) (week (List second end)) (weekday (List third end)))
      (let ((first-day (%zone-day year month 1))
            (next-month (if (= month 12) (%zone-day (+ year 1) 1 1) (%zone-day year (+ month 1) 1))))
        (let ((day (+ first-day
                      (%zone-floor-mod
                        (- weekday (Assoc get 'wday (Date from-unix (* first-day %zone-seconds-day))))
                        7)
                      (* (- week 1) 7))))
          (+ (* (if (>= day next-month) (- day 7) day) %zone-seconds-day)
             (List ref 3 end)))))))

; The offset RULE gives at the unix second SECS.
(def %zone-rule-offset
  (fn (_ rule secs)
    (if (null? (rest rule)) (first rule)
      (let ((standard (first rule)) (daylight (List second rule)))
        (let ((year (Assoc get 'year (Date from-unix (+ secs standard)))))
          (let ((start (- (%zone-rule-moment (List third rule) year) standard))
                (end (- (%zone-rule-moment (List ref 3 rule) year) daylight)))
            (if (if (< start end) (and (>= secs start) (< secs end))
                  (or (>= secs start) (< secs end)))
              daylight standard)))))))

; The offset at SECS of a zone with these CHANGES, FIRST offset and RULE:
; the rule's past the last change, else that of the latest change not
; after it, else the first.
(def %zone-offset
  (fn (_ changes initial rule secs)
    (if (and (not (null? rule)) (or (null? changes) (>= secs (first (first changes)))))
      (%zone-rule-offset rule secs)
      (let ((change (List find (fn (_ c) (<= (first c) secs)) changes)))
        (if (null? change) initial (rest change))))))

; A name that may be a file's under the directory: no dot in it, so no way
; out of the directory, and not a path from the root.
(def %zone-name?
  (fn (_ name)
    (and (str? name)
         (not (or (str=? name "") (Str8 includes? "." name) (Str8 starts? "/" name))))))

; The (CHANGES FIRST RULE) of the zone NAME names, or nil when the system
; has no such zone.
(def %zone-load
  (fn (_ name)
    (let ((path (if (%zone-name? name) (Str8 append (%zone-directory) name) ())))
      (if (or (null? path) (not (eq? (File type path) 'file))) ()
        (let ((size (Assoc get 'size (File stat path))))
          (%zone-read (Bytes region (File read-all path) 0 size)))))))

; The name of the zone /etc/localtime is a link to, or nil.
(def %zone-linked
  (fn (_)
    (let ((target (if (eq? (File ltype "/etc/localtime") 'link) (File readlink "/etc/localtime") ())))
      (let ((at (if (null? target) () (Str8 index-of "zoneinfo/" target))))
        (if (null? at) () (Str8 sub (+ at 9) (Str8 length target) target))))))

(def-class Zone ()
  (doc "A named time zone, read from the system's zone database: its offset from UTC at any instant, and civil time on its clock both ways."
    (note "A zone is one file under /usr/share/zoneinfo, or under the directory TZDIR names in the environment, in the TZif format of RFC 8536: the changes the file lists, and past the last of them the yearly rule it ends with. Nothing is asked of the C library, so several zones can be held at once and TZ does not matter. \"UTC\" needs no file.")
    (note "The calendar is x/sys/date's: a date is the alist Date uses, and seconds are unix seconds.")
    (sample "((Zone named \"Europe/Paris\") offset 1784116800)" "7200")
    (sample "(Assoc get 'hour ((Zone named \"Asia/Tokyo\") local 0))" "9"))

  name      ; the name the zone was asked for
  changes   ; ((SECONDS . OFFSET) ...), the latest change first
  initial   ; the offset before the first change
  rule      ; the yearly rule past the last change, or nil

  (static
    (method named (self (param name STRING "A zone's name in the database, as \"America/New_York\""))
      (doc "The zone a name names, or nil when the system has no such zone. \"UTC\", in any case, is always there."
        (returns Zone "The zone, or nil")
        (example "((Zone named \"UTC\") offset 0)" "0")
        (example "(null? (Zone named \"Nowhere/Land\"))" "#t")
        (sample "((Zone named \"Asia/Kolkata\") name)" "\"Asia/Kolkata\""))
      (if (and (str? name) (str=? (Str8 upcase name) "UTC"))
        (new-from self (list 'name "UTC" 'changes () 'initial 0 'rule (list 0)))
        (let ((read (%zone-load name)))
          (if (null? read) ()
            (new-from self (list 'name name 'changes (first read)
                                 'initial (List second read) 'rule (List third read)))))))

    (method system (self)
      (doc "The system's zone: the one TZ names when it names one in the database, else the one /etc/localtime is a link to, else UTC."
        (returns Zone "The system's zone")
        (sample "((Zone system) name)" "\"America/New_York\""))
      (let ((tz (Sys getenv "TZ")))
        (let ((named (if (null? tz) () (Zone named tz))))
          (if (not (null? named)) named
            (let ((linked (%zone-linked)))
              (let ((found (if (null? linked) () (Zone named linked))))
                (if (null? found) (Zone named "UTC") found))))))))

  (method name (self)
    (doc "The name the zone was asked for."
      (returns STRING "The zone's name")
      (example "((Zone named \"utc\") name)" "\"UTC\""))
    (field 'name))

  (method offset (self (param secs INTEGER "Seconds since the unix epoch"))
    (doc "The zone's offset from UTC at an instant, in seconds east: what its clock is ahead of UTC by."
      (returns INTEGER "Seconds east of UTC")
      (example "((Zone named \"UTC\") offset 1784116800)" "0")
      (sample "((Zone named \"America/New_York\") offset 1784116800)" "-14400"))
    (%zone-offset (field 'changes) (field 'initial) (field 'rule) secs))

  (method local (self (param secs INTEGER "Seconds since the unix epoch"))
    (doc "Split unix seconds into a civil date-time alist on the zone's clock: (Date from-unix)'s fields for secs moved by the zone's offset, plus offset (seconds east of UTC) and zone (the zone's name). The same shape (Date local secs) answers for the process's own zone."
      (returns ALIST "((year . Y) (month . M) (day . D) (hour . H) (minute . MIN) (second . S) (wday . W) (offset . SECONDS-EAST) (zone . NAME))")
      (example "(Assoc get 'hour ((Zone named \"UTC\") local 3600))" "1")
      (sample "(Assoc get 'hour ((Zone named \"Asia/Tokyo\") local 0))" "9"))
    (let ((off (self offset secs)))
      (List append (Date from-unix (+ secs off))
              (list (pair 'offset off) (pair 'zone (field 'name))))))

  (method local->unix (self (param date ALIST "Date alist on the zone's clock; hour/minute/second default to 0 when absent"))
    (doc "Civil date-time alist on the zone's clock back to unix seconds -- the inverse of local. A time the clock shows twice, when it is set back, is the second of the two; a time it skips, when it is set forward, is the instant that much after the skip."
      (returns INTEGER "Seconds since the unix epoch")
      (example "((Zone named \"UTC\") local->unix '((year . 1970) (month . 1) (day . 2)))" "86400")
      (sample "((Zone named \"Asia/Tokyo\") local->unix '((year . 1970) (month . 1) (day . 1) (hour . 9)))" "0"))
    (let ((clock (Date to-unix date)))
      (let ((before (self offset (- clock %zone-seconds-day)))
            (after (self offset (+ clock %zone-seconds-day))))
        (if (= (self offset (- clock after)) after)
          (- clock after)
          (- clock before))))))

(doc (provide x/sys/zone Zone)
  (note "Needs x/sys/posix loaded for (Sys getenv), as (Date now) needs it for (Sys now). A system with no zone database knows \"UTC\" alone.")
  (example "((Zone named \"UTC\") offset 0)" "0")
  (sample "(Assoc get 'hour ((Zone named \"Europe/Paris\") local (Sys now)))" "the hour in Paris now, e.g. 15")
  "Named time zones on the Zone class: named / system, and a zone's name / offset / local / local->unix.")
