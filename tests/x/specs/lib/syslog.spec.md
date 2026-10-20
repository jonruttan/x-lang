# Syslog: a line to the system log, as syslog(3) sends it
# @weight 1

## the line

### the priority is the facility times eight plus the severity

```x
(do (import x/sys/syslog)
  (list (Syslog priority (lit kern) (lit emerg)) (Syslog priority (lit authpriv) (lit info))
        (Syslog priority (lit local7) (lit debug))))
```
---
    (0 86 191)

### a name the C library has no number for raises a label 'value

```x
(do (import x/sys/syslog)
  (list (guard (e (Err label e)) (Syslog priority (lit nowhere) (lit info)))
        (guard (e (Err label e)) (Syslog priority (lit user) (lit loud)))))
```
---
    ('value 'value)

### the stamp is the local time as "Mmm dd hh:mm:ss", the day space-padded

```x
(do (import x/sys/syslog) (import x/sys/date) (import x/core/alist)
  (def secs 1790000000)
  (def d (Date local secs))
  (def s (Syslog stamp secs))
  (list (Str8 length s) (Str8 sub 3 1 s) (Str8 sub 9 1 s) (Str8 sub 12 1 s)
        (str=? (Str8 sub 4 2 s) (if (< (Assoc get 'day d) 10)
                                  (Str8 append " " ((prim-ref 'convert 'to) (Assoc get 'day d) (Type named STRING) 10))
                                  ((prim-ref 'convert 'to) (Assoc get 'day d) (Type named STRING) 10)))))
```
---
    (15 " " ":" ":" #t)

### the line: PRI, stamp, ident and pid, then the text

```x
(do (import x/sys/syslog)
  (def l (Syslog line "dropbear" (lit authpriv) (lit info) "Not backgrounding" 1790000000 42))
  (list (Str8 sub 0 4 l) (str=? (Str8 sub 4 15 l) (Syslog stamp 1790000000)) (Str8 sub 19 (- (Str8 length l) 19) l)))
```
---
    ("<86>" #t " dropbear[42]: Not backgrounding")

## the send

### a line sent to a bound datagram socket arrives as one datagram

```x
(do (import x/sys/syslog) (import x/sys/socket) (import x/sys/file) (import x/sys/posix)
  (def tmp (File temp "/tmp/x-syslog-spec-"))
  (File close (first tmp))
  (File unlink (rest tmp))
  (def path (rest tmp))
  (def fd (Socket unix-dgram-bind path))
  (def sent (Syslog send "spec" (lit user) (lit notice) "one line" path))
  (def got (Socket recv fd 512))
  (Socket close fd)
  (File unlink path)
  (def tail (Str8 append " spec[" ((prim-ref 'convert 'to) (Sys getpid) (Type named STRING) 10) "]: one line"))
  (list sent (Str8 sub 0 4 got)
        (str=? (Str8 sub (- (Str8 length got) (Str8 length tail)) (Str8 length tail) got) tail)))
```
---
    (#t "<13>" #t)

### where no daemon listens the send answers #f

```x
(do (import x/sys/syslog)
  (Syslog send "spec" (lit user) (lit info) "nobody hears" "/tmp/x-syslog-spec-nobody"))
```
---
    #f
