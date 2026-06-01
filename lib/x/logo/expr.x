; expr.x -- Logo expression parser (recursive descent over token lists)
;
; Each parse function takes a token list, returns (value . remaining-tokens).
; Precedence (low→high): comparison, additive, multiplicative, power, unary, primary.

(import x/logo/state)
(import x/logo/types)

; ============================================================
; Function registry (SQRT, ABS, SIN, COS, etc.)
; ============================================================

(def %logo-functions ())

(def %logo-fn-lookup
  (fn (_ name) (%alist-find name %logo-functions)))

(def %logo-lookup
  (fn (_ word) (%alist-find word %logo-commands)))

; ============================================================
; Operator helpers
; ============================================================

(def %is-op-str?
  (fn (_ tok s)
    (and (type? tok %logo-op)
         (str=? (first tok) s))))

(def %op-precedence
  (fn (_ tok)
    (if (not (type? tok %logo-op)) -1
      (let ((s (first tok)))
        (match
          ((str=? s "=")  1) ((str=? s ">")  1) ((str=? s "<")  1)
          ((str=? s ">=") 1) ((str=? s "<=") 1) ((str=? s "<>") 1)
          ((str=? s "+")  2) ((str=? s "-")  2)
          ((str=? s "*")  3) ((str=? s "/")  3)
          ((str=? s "^")  4)
          (#t -1))))))

(def %op-apply
  (fn (_ op left right)
    (def %float? (or (float? left) (float? right)))
    (match
      ((str=? op "+") (if %float? (f+ (%as-float left) (%as-float right)) (+ left right)))
      ((str=? op "-") (if %float? (f- (%as-float left) (%as-float right)) (- left right)))
      ((str=? op "*") (if %float? (f* (%as-float left) (%as-float right)) (* left right)))
      ((str=? op "/") (f/ (%as-float left) (%as-float right)))
      ((str=? op "^") (fexp (f* (%as-float right) (flog (%as-float left)))))
      ((str=? op "=")
        (match
          ((str? left)  (str=? left right))
          ((float? left) (f= left (%as-float right)))
          (#t (= left right))))
      ((str=? op ">")  (> (%as-float left) (%as-float right)))
      ((str=? op "<")  (< (%as-float left) (%as-float right)))
      ((str=? op ">=") (>= (%as-float left) (%as-float right)))
      ((str=? op "<=") (<= (%as-float left) (%as-float right)))
      ((str=? op "<>") (if (str? left) (not (str=? left right)) (not (= left right))))
      (#t (error (Str append "Unknown operator: " op))))))

; ============================================================
; Expression parser (returns (value . remaining-tokens))
; ============================================================

(def %logo-parse-expr ())
(def %logo-parse-primary ())
(def %logo-parse-fn-args ())
(def %logo-parse-infix ())
(def %logo-resolve-word ())
(def %logo-call-with-args ())
(def %logo-resolve-value ())

; Resolve a word (already upcased) in expression context
(set! %logo-resolve-word
  (fn (_ word rest-t)
    ; Function/command call with parens: NAME(args)
    (if (and (not (null? rest-t)) (%is-paren? (first rest-t) "("))
      (%logo-call-with-args word (rest rest-t))
      ; Variable, 0-arg function, or 0-arg command
      (%logo-resolve-value word rest-t))))

(set! %logo-call-with-args
  (fn (_ word tokens-after-paren)
    (let ((args-result (%logo-parse-fn-args tokens-after-paren)))
      (def args (first args-result))
      (def fn-entry (%logo-fn-lookup word))
      (if (not (null? fn-entry))
        (pair (apply (%cmd-handler fn-entry) args) (rest args-result))
        (let ((cmd (%logo-lookup word)))
          (if (null? cmd)
            (error (Str append "Unknown function: " word))
            (pair (apply (%cmd-handler cmd) args) (rest args-result))))))))

(set! %logo-resolve-value
  (fn (_ word rest-t)
    (let ((var (assoc word %logo-vars str=?)))
      (if (not (null? var)) (pair (rest var) rest-t)
        (let ((fn-entry (%logo-fn-lookup word)))
          (if (and (not (null? fn-entry)) (null? (rest (rest fn-entry))))
            (pair ((first (rest fn-entry))) rest-t)
            (let ((cmd (%logo-lookup word)))
              (if (and (not (null? cmd)) (= (%cmd-arity cmd) 0))
                (pair ((%cmd-handler cmd)) rest-t)
                (error (Str append "Undefined: " word))))))))))

(set! %logo-parse-primary
  (fn (_ tokens)
    (if (null? tokens) (error "Expected expression")
      (let ((tok (first tokens))
            (rest-t (rest tokens)))
        (match
          ((number? tok)        (pair tok rest-t))
          ((float? tok)         (pair tok rest-t))
          ((%is-string? tok)    (pair (%logo-string-val tok) rest-t))
          ((%is-block? tok)     (pair tok rest-t))
          ((%is-paren? tok "(")
            (let ((inner (%logo-parse-expr rest-t)))
              (if (null? (rest inner))
                (error "Expected )")
                (let ((next (first (rest inner))))
                  (match
                    ((%is-paren? next ")")
                      (pair (first inner) (rest (rest inner))))
                    ; Comma — return value, skip comma
                    ; Handles COMMAND (arg1, arg2) syntax
                    ((%is-op-str? next ",")
                      (pair (first inner) (rest (rest inner))))
                    (#t (error "Expected )")))))))
          ((%is-op-str? tok "-")
            (let ((r (%logo-parse-primary rest-t)))
              (pair (if (float? (first r))
                      (f* (exact->inexact -1) (first r))
                      (- (first r)))
                    (rest r))))
          (#t
            (let ((raw-word (%logo-word tok)))
              (if (null? raw-word)
                (error "Unexpected token in expression")
                (%logo-resolve-word (Str upcase raw-word) rest-t)))))))))

; Parse function arguments: expr, expr, ... )
(set! %logo-parse-fn-args
  (fn (_ tokens)
    (def %collect
      (fn (self toks acc)
        (match
          ((null? toks) (error "Missing ) in function call"))
          ((%is-paren? (first toks) ")")
            (pair (reverse acc) (rest toks)))
          (#t
            (let ((r (%logo-parse-expr toks)))
              (if (and (not (null? (rest r)))
                       (%is-op-str? (first (rest r)) ","))
                (self (rest (rest r)) (pair (first r) acc))
                (self (rest r) (pair (first r) acc))))))))
    (%collect tokens ())))

; Precedence-climbing infix parser
(set! %logo-parse-infix
  (fn (_ tokens left min-prec)
    (if (null? tokens) (pair left tokens)
      (let ((prec (%op-precedence (first tokens))))
        (if (< prec min-prec) (pair left tokens)
          (let ((op (first (first tokens)))
                (after-op (rest tokens)))
            (let ((right-result (%logo-parse-primary after-op)))
              (def right (first right-result))
              (def rest-tokens (rest right-result))
              (def next-prec (if (str=? op "^") prec (+ prec 1)))
              (def climbed (%logo-parse-infix rest-tokens right next-prec))
              (set! right (first climbed))
              (set! rest-tokens (rest climbed))
              (%logo-parse-infix rest-tokens (%op-apply op left right) min-prec))))))))

; Top-level expression parser
(set! %logo-parse-expr
  (fn (_ tokens)
    (let ((primary (%logo-parse-primary tokens)))
      (%logo-parse-infix (rest primary) (first primary) 0))))

(def %logo-parse-one-expr %logo-parse-expr)

(provide x/logo/expr
  %logo-parse-expr %logo-parse-one-expr
  %logo-functions %logo-fn-lookup %logo-lookup
  %logo-resolve-word %is-op-str?)
