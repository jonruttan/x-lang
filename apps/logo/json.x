; json.x -- Turtle bytecode and JSON output
(import logo/state)
; Fetch the io plumbing prims from the catalog (ns `io` partly de-registered, R5).
(def %write-to-str (prim-ref 'io 'write-to-str))


; ============================================================
; Bytecode JSON array string (for static embedding)
; ============================================================

(def turtle-bc-str
  (fn ()
    (def bc (List reverse %turtle-bc))
    (def %fstr (fn (_ v) (%write-to-str v)))
    (def %build
      (fn (self items acc first?)
        (if (null? items) acc
          (let ((item (first items)))
            (def sep (if first? "" ","))
            (def s
              (if (str? item)
                (Str append sep "\"" item "\"")
                (Str append sep (%fstr item))))
            (self (rest items) (Str append acc s) #f)))))
    (Str append "[" (%build bc "" #t) "]")))

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

(provide logo/json turtle-json turtle-json-str turtle-bc-str)
