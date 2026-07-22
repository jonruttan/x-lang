; banner.x -- Startup banner display
;
; Requires: string.x (str=?), core/list.x (fold)

(def %lang-name ())
(def %lang-version ())
; Batch mode: x.sh sets --batch when a file is supplied with -f/-F.  The
; dialect entries skip the interactive launcher, so the C read-eval loop
; falls through to the file that x.sh concatenated after them.  Without
; this the launcher's (repl) reclaims terminal stdin from fd 3 (loop.x)
; and DISCARDS the still-unread file bytes -- reads are one byte at a
; time, so nothing is buffered ahead.
(def %batch?
  (%fold
    (fn (_ acc a) (or acc (str=? a "--batch")))
    ()
    args))
(def %banner
  (fn (_ )
    (def %quiet
      (%fold
        (fn (_ acc a)
          (or acc (str=? a "--quiet") (str=? a "-q")))
        ()
        args))
    (unless %quiet
      (unless (null? %lang-name)
        (do
          (display %lang-name)
          (unless (null? %lang-version)
            (do (display " v") (display %lang-version)))
          ; "x-lang" is the LANGUAGE's name, not a dialect's (#95) -- if
          ; an embedder names a dialect after the language itself,
          ; "x-lang v0.3.0 on x-lang" would read as a bug, so the suffix
          ; is suppressed for that one spelling.
          (unless (str=? %lang-name "x-lang")
            (display " on x-lang"))
          (newline)
          ; The two things a stranger cannot discover alone: how to get
          ; help, and how to leave.  ctrl-d earned its place back when the
          ; buffer layer learned to latch one-shot terminal EOF (#90).
          (display "(help) for help; (quit) or ctrl-d to exit")
          (newline))))))

(doc (provide x/repl/banner)
  "Startup banner printed when the REPL launches.")
