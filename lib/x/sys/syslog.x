; # x-lang
;
; ## lib/x/sys/syslog.x -- Syslog: a line to the system log, as syslog(3) sends it
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; syslog(3) is a datagram to the log daemon's unix socket -- /dev/log, or
; /var/run/syslog on Darwin -- holding one line in the RFC 3164 form the C
; libraries write: "<PRI>Mmm dd hh:mm:ss IDENT[PID]: TEXT", PRI the facility
; times eight plus the severity, the time local, the day space-padded.  The
; line is built here and sent through Socket's unix datagram door, so a
; program logs without a C library's syslog and the line can be tested
; without a daemon.  A send where no daemon listens answers #f: what to do
; then is the caller's.

(module x/sys/syslog)

(import x/type/class)
(import x/core/list)
(import x/core/alist)
(import x/sys/posix)
(import x/sys/date)
(import x/sys/socket)

(def-class Syslog ()
  (doc "A line to the system log as syslog(3) sends it: (Syslog send ident facility severity text) builds it and sends it to the log daemon's socket; (Syslog line ...) builds it alone."
    (example "(Syslog line \"dropbear\" (lit authpriv) (lit info) \"hello\" 0 42)" "a line beginning \"<86>Jan  1 \""))

  (static
    (%facilities (lit ((kern . 0) (user . 1) (mail . 2) (daemon . 3) (auth . 4) (syslog . 5)
                       (lpr . 6) (news . 7) (uucp . 8) (cron . 9) (authpriv . 10) (ftp . 11)
                       (local0 . 16) (local1 . 17) (local2 . 18) (local3 . 19)
                       (local4 . 20) (local5 . 21) (local6 . 22) (local7 . 23))))
    (%severities (lit ((emerg . 0) (alert . 1) (crit . 2) (err . 3) (warning . 4)
                       (notice . 5) (info . 6) (debug . 7))))
    (%months (lit ("Jan" "Feb" "Mar" "Apr" "May" "Jun" "Jul" "Aug" "Sep" "Oct" "Nov" "Dec")))

    (method path (self)
      (doc "The log daemon's socket on this system: /var/run/syslog on Darwin, /dev/log elsewhere."
        (returns STRING "A socket path")
        (sample "(Syslog path)" "\"/dev/log\" on Linux"))
      (if os-darwin? "/var/run/syslog" "/dev/log"))

    (method priority (self (param facility SYMBOL "kern, user, mail, daemon, auth, syslog, lpr, news, uucp, cron, authpriv, ftp, local0 to local7")
                           (param severity SYMBOL "emerg, alert, crit, err, warning, notice, info, debug"))
      (doc "The PRI a line leads with: the facility's number times eight plus the severity's. Raises a label 'value for a name it does not know."
        (returns INTEGER "0 to 191")
        (sample "(Syslog priority (lit authpriv) (lit info))" "86"))
      (def f (Assoc get facility (Syslog %facilities)))
      (def s (Assoc get severity (Syslog %severities)))
      (when (null? f) (Err raise 'value "Syslog: no such facility" facility))
      (when (null? s) (Err raise 'value "Syslog: no such severity" severity))
      (+ (* f 8) s))

    (method %two (self (param n INTEGER "0 to 99") (param pad STRING "The leading character under ten"))
      (doc "n in two characters." (returns STRING "Two characters"))
      (def t ((prim-ref (lit convert) (lit to)) n (Type named STRING) 10))
      (if (< n 10) (Str8 append pad t) t))

    (method stamp (self (param secs INTEGER "Seconds since the unix epoch"))
      (doc "The time a line carries: local, as \"Mmm dd hh:mm:ss\" with the day space-padded, as the C libraries write it."
        (returns STRING "15 characters")
        (sample "(Syslog stamp 0)" "\"Jan  1 00:00:00\" where local time is UTC"))
      (def d (Date local secs))
      (Str8 append (List ref (- (Assoc get (lit month) d) 1) (Syslog %months)) " "
                   (Syslog %two (Assoc get (lit day) d) " ") " "
                   (Syslog %two (Assoc get (lit hour) d) "0") ":"
                   (Syslog %two (Assoc get (lit minute) d) "0") ":"
                   (Syslog %two (Assoc get (lit second) d) "0")))

    (method line (self (param ident STRING "The program's name, as openlog's ident")
                       (param facility SYMBOL "The facility, as priority takes it")
                       (param severity SYMBOL "The severity, as priority takes it")
                       (param text STRING "The message")
                       (param secs INTEGER "The time, seconds since the unix epoch")
                       (param pid INTEGER "The process id the line names"))
      (doc "The line syslog(3) sends, without sending it: \"<PRI>Mmm dd hh:mm:ss IDENT[PID]: TEXT\"."
        (returns STRING "The line")
        (sample "(Syslog line \"sshd\" (lit auth) (lit notice) \"hi\" 0 7)" "\"<37>Jan  1 00:00:00 sshd[7]: hi\" where local time is UTC"))
      (def num (fn (_ n) ((prim-ref (lit convert) (lit to)) n (Type named STRING) 10)))
      (Str8 append "<" (num (Syslog priority facility severity)) ">" (Syslog stamp secs) " "
                   ident "[" (num pid) "]: " text))

    (method send (self (param ident STRING "The program's name, as openlog's ident")
                       (param facility SYMBOL "The facility, as priority takes it")
                       (param severity SYMBOL "The severity, as priority takes it")
                       (param text STRING "The message")
                       . (param where STRING "The daemon's socket; (Syslog path) when not given"))
      (doc "Send one line to the log daemon, stamped now with this process's id. Answers #t, or #f when no daemon is listening there -- the caller decides what then."
        (returns BOOL "Whether the line was sent")
        (sample "(Syslog send \"myprog\" (lit daemon) (lit info) \"started\")" "#t with a syslogd running"))
      (def path (if (null? where) (Syslog path) (first where)))
      (def fd (guard (e -1) (Socket unix-dgram-connect path)))
      (if (< fd 0) #f
        (do (def l (Syslog line ident facility severity text (Sys now) (Sys getpid)))
            (def sent (guard (e -1) (Socket send fd l)))
            (Socket close fd)
            (> sent 0))))))

(doc (provide x/sys/syslog Syslog)
  (note "No daemon is needed to build a line: (Syslog line ...) is pure but for the zone the time is shown in.")
  "syslog(3)'s line and its send, over Socket's unix datagram door.")
