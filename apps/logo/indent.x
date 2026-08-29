; indent.x -- Indent-to-blocks pre-processor
;
; Converts indented lines to nested block structures.
; Flat tokens pass through unchanged; indented tokens are
; grouped into blocks based on indent level.
;
; #520: THE STACK IS NOT HERE ANY MORE. This file used to own a
; (indent-level . accumulated-tokens-reversed) stack and a %pop-to that closed
; every block deeper than the incoming column -- the same algorithm x-sweet
; owned a second copy of, in a different shape, with different answers at the
; edges. x/reader/indent holds it now. What is left here is the part that was
; ever Logo's: what a block IS, and where the tokens go.
;
; LOGO'S TWO POLICY ANSWERS, STATED RATHER THAN IMPLIED BY A LOOP:
;
;   tab stop 1      a tab is one column. Set where the measuring happens, in
;                   logo/types.x, because that is the reader's business.
;   mismatch open   a line dedenting to a column no open block sits at OPENS a
;                   block there. That is exactly what %pop-to did -- pop to the
;                   first level at or above the column, then push when it did
;                   not match -- and it is a genuine choice rather than a
;                   default: Python raises on that input and x-sweet unwinds
;                   past it. Three surfaces, three answers, and until now none
;                   of them written down.
(import logo/types)
(import x/reader/indent)
; Fetch the type prims from the catalog (ns `type` is de-registered, R5).
(def %type? (prim-ref 'type '?))


(def %logo-indent-to-blocks
  (fn (_ tokens)
    ; One accumulator per open level, innermost first, each holding its tokens
    ; reversed. The COLUMNS are the indenter's; only the tokens are ours.
    (def ind (Indent make 1 (lit open)))

    (def %close-one
      (fn (_ accs)
        (def block (%make-indent-block (List reverse (first accs))))
        (pair (pair block (first (rest accs))) (rest (rest accs)))))

    ; feed's contract -- zero or more `close`, then exactly one `open` or
    ; `same` -- is what lets this be a fold. The old %pop-to had to count the
    ; levels a dedent crossed and then ask separately whether it had landed on
    ; one; both questions are answered in the event list now.
    (def %apply
      (fn (self evs accs tok)
        (if (null? evs)
          accs
          (if (eq? (first evs) (lit close))
            (self (rest evs) (%close-one accs) tok)
            (if (eq? (first evs) (lit open))
              (self (rest evs) (pair (list tok) accs) tok)
              (self (rest evs)
                (pair (pair tok (first accs)) (rest accs)) tok))))))

    (def %process
      (fn (self toks accs)
        (if (null? toks)
          ; End of input closes what is still open. close-all reports the
          ; closes and nothing else -- there is no line to continue.
          (%apply (ind close-all) accs ())
          (let ((tok (first toks)))
            (if (%type? tok %logo-indent)
              (self (rest toks) (%apply (ind feed (first (first tok))) accs tok))
              ; Not an indent token: it joins the line already being built, and
              ; the indenter never hears about it.
              (self (rest toks)
                (pair (pair tok (first accs)) (rest accs))))))))

    (List reverse (first (%process tokens (list ()))))))

(provide logo/indent %logo-indent-to-blocks)
