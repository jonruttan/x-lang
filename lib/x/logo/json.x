; json.x -- Turtle segment JSON output
(import x/logo/state)

; ============================================================
; Stream output (to stdout)
; ============================================================

(def turtle-json
  (fn ()
    (display "[")
    (def segs (reverse %turtle-segments))
    (def %out
      (fn (self segs first?)
        (if (null? segs) ()
          (do
            (if first? () (display ","))
            (def s (first segs))
            (def x1 (first s))
            (def y1 (first (rest s)))
            (def x2 (first (rest (rest s))))
            (def y2 (first (rest (rest (rest s)))))
            (def pen (first (rest (rest (rest (rest s))))))
            (def hdg (first (rest (rest (rest (rest (rest s)))))))
            (display "\n{\"x1\":") (display x1)
            (display ",\"y1\":") (display y1)
            (display ",\"x2\":") (display x2)
            (display ",\"y2\":") (display y2)
            (display ",\"pen\":")
            (display (if pen "true" "false"))
            (display ",\"heading\":") (display hdg)
            (display "}")
            (self (rest segs) #f)))))
    (%out segs #t)
    (display "\n]\n")))

; ============================================================
; String output (returns JSON string, no stdout)
; ============================================================

(def turtle-json-str
  (fn ()
    (def segs (reverse %turtle-segments))
    (def %seg-json
      (fn (_ s)
        (def x1 (write-to-str (first s)))
        (def y1 (write-to-str (first (rest s))))
        (def x2 (write-to-str (first (rest (rest s)))))
        (def y2 (write-to-str (first (rest (rest (rest s))))))
        (def pen (first (rest (rest (rest (rest s))))))
        (def hdg (write-to-str (first (rest (rest (rest (rest (rest s))))))))
        (str "{\"x1\":" x1
             ",\"y1\":" y1
             ",\"x2\":" x2
             ",\"y2\":" y2
             ",\"pen\":" (if pen "true" "false")
             ",\"heading\":" hdg "}")))
    (def %join
      (fn (self segs first?)
        (if (null? segs) ""
          (str (if first? "" ",\n")
               (%seg-json (first segs))
               (self (rest segs) #f)))))
    (str "[\n" (%join segs #t) "\n]\n")))

(provide x/logo/json turtle-json turtle-json-str)
