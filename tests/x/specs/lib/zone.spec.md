# Zone: named time zones from the zone database

# @weight 5
A zone is one TZif file.  Every case reads the four under
`tests/x/fixtures/zone`, copies of the tz database's 2026f files, by naming
that directory in TZDIR, and puts the TZDIR it found back before it answers:
nothing here depends on the zones the machine has.  The offsets were checked
against Python's `zoneinfo` over the same files.

## offsets

### a zone's offset at an instant: standard and daylight time, the changes to the second

```x
(do (import x/sys/zone)
  (def dir-was (Sys getenv "TZDIR"))
  (Sys setenv "TZDIR" "tests/x/fixtures/zone")
  (def r (List map (fn (_ s) ((Zone named "America/New_York") offset s)) (list -2208988800 0 1000000000 1767225600 1772953199 1772953200 1784116800 1793509199 1793509200 2500000000 4102444800)))
  (if (null? dir-was) (Sys unsetenv "TZDIR") (Sys setenv "TZDIR" dir-was))
  r)
```
---
    (-18000 -18000 -14400 -18000 -18000 -14400 -14400 -14400 -14400 -14400 -18000)

### before a zone kept standard time its offset is the file's first, to the second

```x
(do (import x/sys/zone)
  (def dir-was (Sys getenv "TZDIR"))
  (Sys setenv "TZDIR" "tests/x/fixtures/zone")
  (def r (List map (fn (_ s) ((Zone named "Asia/Kolkata") offset s)) (list -2208988800 0 1000000000 1767225600 1772953199 1772953200 1784116800 1793509199 1793509200 2500000000 4102444800)))
  (if (null? dir-was) (Sys unsetenv "TZDIR") (Sys setenv "TZDIR" dir-was))
  r)
```
---
    (19270 19800 19800 19800 19800 19800 19800 19800 19800 19800 19800)

### daylight time of half an hour, south of the equator

```x
(do (import x/sys/zone)
  (def dir-was (Sys getenv "TZDIR"))
  (Sys setenv "TZDIR" "tests/x/fixtures/zone")
  (def r (List map (fn (_ s) ((Zone named "Australia/Lord_Howe") offset s)) (list -2208988800 0 1000000000 1767225600 1772953199 1772953200 1784116800 1793509199 1793509200 2500000000 4102444800)))
  (if (null? dir-was) (Sys unsetenv "TZDIR") (Sys setenv "TZDIR" dir-was))
  r)
```
---
    (36000 36000 37800 39600 39600 39600 37800 39600 39600 39600 39600)

### past the file's last change the rule it ends with answers

```x
(do (import x/sys/zone)
  (def dir-was (Sys getenv "TZDIR"))
  (Sys setenv "TZDIR" "tests/x/fixtures/zone")
  (def r (List map (fn (_ s) ((Zone named "Europe/Paris") offset s)) (list 2500000000 4102444800 4118169600 4133894400)))
  (if (null? dir-was) (Sys unsetenv "TZDIR") (Sys setenv "TZDIR" dir-was))
  r)
```
---
    (3600 3600 7200 3600)

### UTC needs no file, in any case

```x
(do (import x/sys/zone)
  (def dir-was (Sys getenv "TZDIR"))
  (Sys setenv "TZDIR" "tests/x/fixtures/zone")
  (def r (list ((Zone named "UTC") offset 1784116800) ((Zone named "utc") name) ((Zone named "Utc") offset -1)))
  (if (null? dir-was) (Sys unsetenv "TZDIR") (Sys setenv "TZDIR" dir-was))
  r)
```
---
    (0 "UTC" 0)

## civil time

### local: Date's fields on the zone's clock, with the offset and the zone's name

```x
(do (import x/sys/zone)
  (def dir-was (Sys getenv "TZDIR"))
  (Sys setenv "TZDIR" "tests/x/fixtures/zone")
  (def r ((Zone named "America/New_York") local 1784116800))
  (if (null? dir-was) (Sys unsetenv "TZDIR") (Sys setenv "TZDIR" dir-was))
  r)
```
---
    (('year . 2026) ('month . 7) ('day . 15) ('hour . 8) ('minute . 0) ('second . 0) ('wday . 3) ('offset . -14400) ('zone . "America/New_York"))

### local->unix is its inverse

```x
(do (import x/sys/zone)
  (def dir-was (Sys getenv "TZDIR"))
  (Sys setenv "TZDIR" "tests/x/fixtures/zone")
  (def r (let ((z (Zone named "Europe/Paris"))) (List map (fn (_ s) (- (z local->unix (z local s)) s)) (list -2208988800 0 1000000000 1784116800 4102444800))))
  (if (null? dir-was) (Sys unsetenv "TZDIR") (Sys setenv "TZDIR" dir-was))
  r)
```
---
    (0 0 0 0 0)

### a date alone is its midnight

```x
(do (import x/sys/zone)
  (def dir-was (Sys getenv "TZDIR"))
  (Sys setenv "TZDIR" "tests/x/fixtures/zone")
  (def r ((Zone named "Asia/Kolkata") local->unix (lit ((year . 2026) (month . 1) (day . 1)))))
  (if (null? dir-was) (Sys unsetenv "TZDIR") (Sys setenv "TZDIR" dir-was))
  r)
```
---
    1767205800

### a time the clock skips is the instant that much after the skip

```x
(do (import x/sys/zone)
  (def dir-was (Sys getenv "TZDIR"))
  (Sys setenv "TZDIR" "tests/x/fixtures/zone")
  (def r (let ((z (Zone named "America/New_York"))) (Assoc get (lit hour) (z local (z local->unix (lit ((year . 2026) (month . 3) (day . 8) (hour . 2) (minute . 30))))))))
  (if (null? dir-was) (Sys unsetenv "TZDIR") (Sys setenv "TZDIR" dir-was))
  r)
```
---
    3

### a time the clock shows twice is the second of the two

```x
(do (import x/sys/zone)
  (def dir-was (Sys getenv "TZDIR"))
  (Sys setenv "TZDIR" "tests/x/fixtures/zone")
  (def r (let ((z (Zone named "America/New_York"))) (list (z local->unix (lit ((year . 2026) (month . 11) (day . 1) (hour . 1) (minute . 30)))) (Assoc get (lit offset) (z local 1793514600)))))
  (if (null? dir-was) (Sys unsetenv "TZDIR") (Sys setenv "TZDIR" dir-was))
  r)
```
---
    (1793514600 -18000)

### and so for a zone that moves half an hour

```x
(do (import x/sys/zone)
  (def dir-was (Sys getenv "TZDIR"))
  (Sys setenv "TZDIR" "tests/x/fixtures/zone")
  (def r ((Zone named "Australia/Lord_Howe") local->unix (lit ((year . 2026) (month . 4) (day . 5) (hour . 1) (minute . 45)))))
  (if (null? dir-was) (Sys unsetenv "TZDIR") (Sys setenv "TZDIR" dir-was))
  r)
```
---
    1775315700

## names

### a name the database has not is nil, as is one that is no name

```x
(do (import x/sys/zone)
  (def dir-was (Sys getenv "TZDIR"))
  (Sys setenv "TZDIR" "tests/x/fixtures/zone")
  (def r (list (null? (Zone named "Nowhere/Land")) (null? (Zone named "")) (null? (Zone named 5))))
  (if (null? dir-was) (Sys unsetenv "TZDIR") (Sys setenv "TZDIR" dir-was))
  r)
```
---
    (#t #t #t)

### a name cannot reach outside the database

```x
(do (import x/sys/zone)
  (def dir-was (Sys getenv "TZDIR"))
  (Sys setenv "TZDIR" "tests/x/fixtures/zone")
  (def r (list (null? (Zone named "../zone/Asia/Kolkata")) (null? (Zone named "/etc/localtime"))))
  (if (null? dir-was) (Sys unsetenv "TZDIR") (Sys setenv "TZDIR" dir-was))
  r)
```
---
    (#t #t)

### a file that is not a zone's is nil, and so is a directory

```x
(do (import x/sys/zone)
  (def dir-was (Sys getenv "TZDIR"))
  (Sys setenv "TZDIR" "tests/x/fixtures/zone")
  (def r (list (null? (Zone named "NotAZone")) (null? (Zone named "Asia"))))
  (if (null? dir-was) (Sys unsetenv "TZDIR") (Sys setenv "TZDIR" dir-was))
  r)
```
---
    (#t #t)

### a zone keeps the name it was asked for

```x
(do (import x/sys/zone)
  (def dir-was (Sys getenv "TZDIR"))
  (Sys setenv "TZDIR" "tests/x/fixtures/zone")
  (def r ((Zone named "Asia/Kolkata") name))
  (if (null? dir-was) (Sys unsetenv "TZDIR") (Sys setenv "TZDIR" dir-was))
  r)
```
---
    "Asia/Kolkata"

## the system's zone

### system: the zone TZ names when the database has it

```x
(do (import x/sys/zone)
  (def dir-was (Sys getenv "TZDIR"))
  (def tz-was (Sys getenv "TZ"))
  (Sys setenv "TZDIR" "tests/x/fixtures/zone")
  (def tz-name (fn (_ tz) (do (Sys setenv "TZ" tz) ((Zone system) name))))
  (def r (list (tz-name "Asia/Kolkata") (tz-name "Europe/Paris")))
  (if (null? tz-was) (Sys unsetenv "TZ") (Sys setenv "TZ" tz-was))
  (if (null? dir-was) (Sys unsetenv "TZDIR") (Sys setenv "TZDIR" dir-was))
  r)
```
---
    ("Asia/Kolkata" "Europe/Paris")
