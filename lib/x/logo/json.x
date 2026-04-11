; json.x -- Turtle bytecode and JSON output
(import x/logo/state)

; ============================================================
; Bytecode JSON array string (for static embedding)
; ============================================================

(def turtle-bc-str
  (fn ()
    (def bc (reverse %turtle-bc))
    (def %fstr (fn (_ v) (write-to-str v)))
    (def %build
      (fn (self items acc first?)
        (if (null? items) acc
          (let ((item (first items)))
            (def sep (if first? "" ","))
            (def s
              (if (str? item)
                (str sep "\"" item "\"")
                (str sep (%fstr item))))
            (self (rest items) (str acc s) #f)))))
    (str "[" (%build bc "" #t) "]")))

; ============================================================
; Legacy: segment JSON (kept for backward compatibility)
; ============================================================

(def turtle-json-str
  (fn ()
    (turtle-bc-str)))

(def turtle-json
  (fn ()
    (display (turtle-bc-str))
    (newline)))

(provide x/logo/json turtle-json turtle-json-str turtle-bc-str)
