# Date: civil dates over unix time (#21)

# @weight 7
Pure integer math (Hinnant's civil algorithms), proleptic Gregorian,
UTC only. A date is an alist; wday 0 = Sunday. (Sys now) wall-clock
pins live in ext/posix coverage: here everything is deterministic.

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

### strict: bad shapes, out-of-range fields, nonexistent civil dates all raise 'value

```x
(do (import x/sys/date)
  (list (guard (e (Err kind-of e)) (Date from-iso "2023-02-30T00:00:00Z"))
        (guard (e (Err kind-of e)) (Date from-iso "2023-13-01T00:00:00Z"))
        (guard (e (Err kind-of e)) (Date from-iso "2023-01-01T25:00:00Z"))
        (guard (e (Err kind-of e)) (Date from-iso "garbage"))))
```
---
    ('value 'value 'value 'value)
