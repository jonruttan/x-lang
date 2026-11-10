; int-form.x -- an integer (fn ...) form as pure x: the loop compile-asm
; compiles, run without it.
;
; A kernel written once as a form is two functions: compile-asm's, and this
; one, the form with each operator replaced by the int door it means.  The
; door objects themselves stand in the form where the names were, so it
; means the same thing in whatever environment evaluates it, and the
; compiled one is adopted only after it agrees with this one.
;
; Addresses are integers.  (%mem-byte-ref-at A I) is the byte at A + I,
; (%mem-byte-set-at! A I V) stores V's low byte there; (%mem-ref-at A I) and
; (%mem-set-at! A I V) are the machine word at A + I words.  A store answers
; the value stored, as the compiled store does.
(module x/tool/int-form)

(import x/core/doors int& int* int+ int- int->ptr int< int= int>> int<< ptr-ref ptr-set! ptr-ref-word ptr-set-word!)
(import x/num/fixed fixed*)

(def %int-form-ops
  (list (pair (lit +) int+) (pair (lit -) int-) (pair (lit *) int*) (pair (lit <) int<)
        (pair (lit =) int=) (pair (lit >>) int>>) (pair (lit <<) int<<) (pair (lit &) int&)
        (pair (lit *>>) fixed*)
        (pair (lit %mem-byte-ref-at) (fn (_ a i) (int& (ptr-ref (int->ptr (int+ a i)) 0 1) 255)))
        (pair (lit %mem-byte-set-at!) (fn (_ a i v) (do (ptr-set! (int->ptr (int+ a i)) 0 v 1) v)))
        (pair (lit %mem-ref-at) (fn (_ a i) (ptr-ref-word (int->ptr a) (int* i %word-size))))
        (pair (lit %mem-set-at!) (fn (_ a i v) (do (ptr-set-word! (int->ptr a) (int* i %word-size) v) v)))))

(def %int-form-subst
  (fn (self form)
    (match
      ((pair? form) (pair (self (first form)) (self (rest form))))
      ((symbol? form) ((fn (_ e) (if (null? e) form (rest e))) (Assoc entry form %int-form-ops)))
      (#t form))))

(def int-form-pure (fn (_ form) (eval (%int-form-subst form))))

; (*>> A B K) is A times B shifted down K places, the product exact through
; 64 bits: x/num/fixed's fixed* in the pure form.  A word of 8 bytes holds
; the product, so there the form says (>> (* A B) K), which compile-asm
; compiles as it stands.
(def int-form-wide
  (fn (self form)
    (match
      ((pair? form)
        (if (eq? (first form) (lit *>>))
          (list (lit >>) (list (lit *) (self (first (rest form))) (self (first (rest (rest form)))))
                (self (first (rest (rest (rest form))))))
          (pair (self (first form)) (self (rest form)))))
      (#t form))))

(doc int-form-pure "The integer function FORM means, as pure x: its operators bound to the int doors, so it runs where compile-asm cannot and answers what compile-asm's answers."
  (param form LIST "A (fn (self ...) ...) form over integers: + - * < = >> << &, (*>> a b k) for a product shifted down k places through 64 bits, if, match, do, and the %mem- byte and word loads and stores")
  (returns CALLABLE "The function")
  (example "(do (import x/tool/int-form int-form-pure) ((int-form-pure (lit (fn (self n acc) (if (< n 1) acc (self (- n 1) (+ acc n)))))) 4 0))" "10"))

(doc int-form-wide "FORM with each (*>> a b k) written as (>> (* a b) k): the form compile-asm takes on an 8-byte word, where one word holds the product."
  (param form LIST "An int form")
  (returns LIST "The form, its *>> products spelled as a multiply and a shift")
  (example "(do (import x/tool/int-form int-form-wide) (int-form-wide (lit (fn (_ a b) (*>> a b 16)))))" "(fn (_ a b) (>> (* a b) 16))"))

(doc (provide x/tool/int-form int-form-pure int-form-wide)
  "An integer (fn ...) form, the kind compile-asm compiles, as the pure-x function it means: the twin a compiled loop is checked against."
  (example "(do (import x/tool/int-form int-form-pure) ((int-form-pure (lit (fn (_ a b) (>> (- a b) 1)))) 1 8))" "-4"))
