; json.x -- Turtle segment JSON output
; Format: {"x":..,"y":..,"h":..,"d":..,"p":1}
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
            (display "\n{\"x\":") (display (first s))
            (display ",\"y\":") (display (first (rest s)))
            (display ",\"h\":") (display (first (rest (rest s))))
            (display ",\"d\":") (display (first (rest (rest (rest s)))))
            (display ",\"p\":") (display (if (first (rest (rest (rest (rest s))))) "1" "0"))
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
        (str "{\"x\":" (write-to-str (first s))
             ",\"y\":" (write-to-str (first (rest s)))
             ",\"h\":" (write-to-str (first (rest (rest s))))
             ",\"d\":" (write-to-str (first (rest (rest (rest s)))))
             ",\"p\":" (if (first (rest (rest (rest (rest s))))) "1" "0") "}")))
    (def %join
      (fn (self segs first?)
        (if (null? segs) ""
          (str (if first? "" ",\n")
               (%seg-json (first segs))
               (self (rest segs) #f)))))
    (str "[\n" (%join segs #t) "\n]\n")))

(provide x/logo/json turtle-json turtle-json-str)
