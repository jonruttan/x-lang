; indent.x -- Indent-to-blocks pre-processor
;
; Converts indented lines to nested block structures.
; Flat tokens pass through unchanged; indented tokens are
; grouped into blocks based on indent level.
(import x/logo/types)
; Fetch the type prims from the catalog (ns `type` is de-registered, R5).
(def %type? (prim-ref 'type '?))


(def %logo-indent-to-blocks
  (fn (_ tokens)
    ; Stack entries: (indent-level . accumulated-tokens-reversed)

    (def %pop-to
      (fn (self target stack)
        (if (null? (rest stack)) stack
          (if (<= (first (first stack)) target)
            stack
            (let ((top (first stack))
                  (parent (first (rest stack)))
                  (rest-stack (rest (rest stack))))
              (def block (%make-indent-block (reverse (rest top))))
              (self target
                (pair (pair (first parent) (pair block (rest parent)))
                      rest-stack)))))))

    (def %flush-stack
      (fn (self stack)
        (if (null? (rest stack))
          (reverse (rest (first stack)))
          (let ((top (first stack))
                (parent (first (rest stack)))
                (rest-stack (rest (rest stack))))
            (def block (%make-indent-block (reverse (rest top))))
            (self (pair (pair (first parent) (pair block (rest parent)))
                        rest-stack))))))

    (def %process
      (fn (self toks stack)
        (if (null? toks)
          (%flush-stack stack)
          (let ((tok (first toks))
                (rest-toks (rest toks)))
            (if (%type? tok %logo-indent)
              (let ((indent (first (first tok))))
                (def new-stack (%pop-to indent stack))
                (def top (first new-stack))
                (if (= (first top) indent)
                  (self rest-toks
                    (pair (pair indent (pair tok (rest top)))
                          (rest new-stack)))
                  (self rest-toks
                    (pair (pair indent (list tok)) new-stack))))
              (let ((top (first stack)))
                (self rest-toks
                  (pair (pair (first top) (pair tok (rest top)))
                        (rest stack)))))))))

    (%process tokens (list (pair 0 ())))))

(provide x/logo/indent %logo-indent-to-blocks)
