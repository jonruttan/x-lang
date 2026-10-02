# Date: civil dates over unix time (#21)

# @weight 7
Pure integer math (Hinnant's civil algorithms), proleptic Gregorian,
UTC, and local time under a TZ each case sets. A date is an alist; wday 0 =
Sunday. (Sys now) wall-clock pins live in ext/posix coverage: here
everything is deterministic.

## known instants

### the epoch is Thursday 1970-01-01

```x
(do (import x/sys/date)
  (let ((d (Date from-unix 0)))
    (list (Assoc get 'year d) (Assoc get 'month d) (Assoc get 'day d) (Assoc get 'wday d))))
```
---
    (1970 1 1 4)

### a famous timestamp formats correctly

```x
(do (import x/sys/date)
  (Date ->iso (Date from-unix 1234567890)))
```
---
    "2009-02-13T23:31:30Z"

### the last pre-epoch second is 1969-12-31 23:59:59

```x
(do (import x/sys/date)
  (Date ->iso (Date from-unix -1)))
```
---
    "1969-12-31T23:59:59Z"

### leap day 2024 exists and roundtrips

```x
(do (import x/sys/date)
  (Date ->iso (Date from-unix (Date to-unix '((year . 2024) (month . 2) (day . 29))))))
```
---
    "2024-02-29T00:00:00Z"

### hour/minute/second default to zero in to-unix

```x
(do (import x/sys/date)
  (Date to-unix '((year . 1970) (month . 1) (day . 2))))
```
---
    86400

## the roundtrip law

### to-unix inverts from-unix across 4000 days spanning the epoch

Steps of 86399 seconds (not a divisor of a day) walk through every
time-of-day and both sides of the epoch.

```x
(do (import x/sys/date)
  (let go ((i 0) (t -172800000) (bad 0))
    (if (= i 4000) bad
      (go (+ i 1) (+ t 86399)
          (if (= (Date to-unix (Date from-unix t)) t) bad (+ bad 1))))))
```
---
    0

### century boundaries obey the Gregorian leap rules

```x
(do (import x/sys/date)
  (list (Date leap-year? 2024) (Date leap-year? 1900) (Date leap-year? 2000) (Date leap-year? 2100)))
```
---
    (#t #f #t #f)

### March 1st follows Feb 28 in non-leap years, Feb 29 in leap years

```x
(do (import x/sys/date)
  (list (Assoc get 'day (Date from-unix (+ (Date to-unix '((year . 2023) (month . 2) (day . 28))) 86400)))
        (Assoc get 'day (Date from-unix (+ (Date to-unix '((year . 2024) (month . 2) (day . 28))) 86400)))))
```
---
    (1 29)

## wall clock

### (Sys now) is wall time, after 2023, and time-of-day's usec is sane

```x
(do (import x/sys/posix) (import x/sys/date)
  (let ((t (Sys now)) (tod (Sys time-of-day)))
    (list (> t 1700000000) (>= (rest tod) 0) (< (rest tod) 1000000)
          (Assoc has? 'wday (Date now)))))
```
---
    (#t #t #t #t)

## from-iso (#364)

### the inverse of ->iso, wday included

```x
(do (import x/sys/date)
  (list (Date ->iso (Date from-iso "2009-02-13T23:31:30Z"))
        (Date to-unix (Date from-iso "2009-02-13T23:31:30Z"))
        (Assoc get 'wday (Date from-iso "2009-02-13T23:31:30Z"))
        (Date ->iso (Date from-iso "1970-01-01"))))
```
---
    ("2009-02-13T23:31:30Z" 1234567890 5 "1970-01-01T00:00:00Z")

### strict: badly formed inputs, out-of-range fields, nonexistent civil dates all raise 'value

```x
(do (import x/sys/date)
  (list (guard (e (Err label e)) (Date from-iso "2023-02-30T00:00:00Z"))
        (guard (e (Err label e)) (Date from-iso "2023-13-01T00:00:00Z"))
        (guard (e (Err label e)) (Date from-iso "2023-01-01T25:00:00Z"))
        (guard (e (Err label e)) (Date from-iso "garbage"))))
```
---
    ('value 'value 'value 'value)

## local time

Each case sets TZ to a POSIX rule string, which glibc and Darwin read alike
with no zone database, and puts the TZ it found back before it answers.
The expectations are the system date's: `TZ=... date -r SECS`.

### Sys zone: the offset, name and daylight flag a TZ rule gives at an instant

```x
(do (import x/sys/date)
  (def tz-was (Sys getenv "TZ"))
  (def tz-at (fn (_ tz secs) (do (Sys setenv "TZ" tz) (Sys zone secs))))
  (def tz-r (list (tz-at "UTC0" 1790000000)
                  (tz-at "EST5EDT,M3.2.0,M11.1.0" 1790000000)
                  (tz-at "EST5EDT,M3.2.0,M11.1.0" 1767225600)
                  (tz-at "<+0530>-5:30" 1790000000)))
  (if (null? tz-was) (Sys unsetenv "TZ") (Sys setenv "TZ" tz-was))
  tz-r)
```
---
    ((('offset . 0) ('name . "UTC") ('dst . #f)) (('offset . -14400) ('name . "EDT") ('dst . #t)) (('offset . -18000) ('name . "EST") ('dst . #f)) (('offset . 19800) ('name . "+0530") ('dst . #f)))

### Date local: the civil fields in the zone, across midnight and the year, with its offset and name

```x
(do (import x/sys/date)
  (def tz-was (Sys getenv "TZ"))
  (def tz-at (fn (_ tz secs) (do (Sys setenv "TZ" tz) (Date local secs))))
  (def tz-r (list (tz-at "EST5EDT,M3.2.0,M11.1.0" 1790000000)
                  (tz-at "EST5EDT,M3.2.0,M11.1.0" 1767225600)
                  (tz-at "<+0530>-5:30" 1767225600)))
  (if (null? tz-was) (Sys unsetenv "TZ") (Sys setenv "TZ" tz-was))
  tz-r)
```
---
    ((('year . 2026) ('month . 9) ('day . 21) ('hour . 10) ('minute . 13) ('second . 20) ('wday . 1) ('offset . -14400) ('zone . "EDT")) (('year . 2025) ('month . 12) ('day . 31) ('hour . 19) ('minute . 0) ('second . 0) ('wday . 3) ('offset . -18000) ('zone . "EST")) (('year . 2026) ('month . 1) ('day . 1) ('hour . 5) ('minute . 30) ('second . 0) ('wday . 4) ('offset . 19800) ('zone . "+0530")))

### Date local under UTC is from-unix with a zero offset

```x
(do (import x/sys/date)
  (def tz-was (Sys getenv "TZ"))
  (Sys setenv "TZ" "UTC0")
  (def tz-l (Date local 1234567890))
  (if (null? tz-was) (Sys unsetenv "TZ") (Sys setenv "TZ" tz-was))
  (list (equal? (List take 7 tz-l) (Date from-unix 1234567890)) (Assoc get 'offset tz-l)))
```
---
    (#t 0)
