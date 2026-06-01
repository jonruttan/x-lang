; banner.x -- Startup banner display
;
; Requires: string.x (str=?), core/list.x (fold)

(def %lang-name ())
(def %lang-version ())
(def %banner
  (fn (_ )
    (def %quiet
      (fold
        (fn (_ acc a)
          (or acc (str=? a "--quiet") (str=? a "-q")))
        ()
        args))
    (if %quiet
      ()
      (if (null? %lang-name)
        ()
        (do
          (display %lang-name)
          (if (null? %lang-version)
            ()
            (do (display " v") (display %lang-version)))
          (display " on x-lang")
          (newline))))))

(doc (provide x/core/banner)
  "Startup banner printed when the REPL launches.")
