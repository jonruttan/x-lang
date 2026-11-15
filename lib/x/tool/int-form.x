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
; (%mem-set-at! A I V) are the machine word at A + I words, and %mem-ref /
; %mem-set! the same at a literal index.  A store answers the value stored,
; as the compiled store does.
;
; Doubles are their IEEE bits, as Float's payload is: (%f+ A B), %f-, %f*,
; %f/ operate on them through x/num/float's stubs, and (%f-ref A I) /
; (%f-set! A I V) are the double at A + 8I bytes.  On an 8-byte word a
; double is one word, so int-form-wide writes those two as the word loads
; and stores compile-asm compiles.  On a 4-byte word a double is the two
; words Float keeps it in, and only the pure form runs.  The stubs are made
; the first time a form uses one.
(module x/tool/int-form)

(import x/core/doors int& int* int+ int- int->ptr int< int= int>> int<< ptr-ref ptr-set! ptr-ref-word ptr-set-word!)
(import x/num/fixed fixed*)
(import x/type/vector)
(import x/type/list)

(def %int-form-word (fn (_ a i) (ptr-ref-word (int->ptr a) (int* i %word-size))))
(def %int-form-word! (fn (_ a i v) (do (ptr-set-word! (int->ptr a) (int* i %word-size) v) v)))

; A double in memory: one word on an 8-byte word, two (low first) on a
; 4-byte one.
(def %int-form-double
  (if (int= %word-size 8)
    (fn (_ a i) (ptr-ref-word (int->ptr a) (int* i 8)))
    (fn (_ a i) (Vector of (ptr-ref-word (int->ptr a) (int* i 8)) (ptr-ref-word (int->ptr a) (int+ (int* i 8) 4))))))
(def %int-form-double!
  (if (int= %word-size 8)
    (fn (_ a i v) (do (ptr-set-word! (int->ptr a) (int* i 8) v) v))
    (fn (_ a i v)
      (do (ptr-set-word! (int->ptr a) (int* i 8) (Vector ref 0 v))
          (ptr-set-word! (int->ptr a) (int+ (int* i 8) 4) (Vector ref 1 v))
          v))))

(def %int-form-ops
  (list (pair (lit +) int+) (pair (lit -) int-) (pair (lit *) int*) (pair (lit <) int<)
        (pair (lit =) int=) (pair (lit >>) int>>) (pair (lit <<) int<<) (pair (lit &) int&)
        (pair (lit *>>) fixed*)
        (pair (lit %mem-byte-ref-at) (fn (_ a i) (int& (ptr-ref (int->ptr (int+ a i)) 0 1) 255)))
        (pair (lit %mem-byte-set-at!) (fn (_ a i v) (do (ptr-set! (int->ptr (int+ a i)) 0 v 1) v)))
        (pair (lit %mem-ref-at) %int-form-word)
        (pair (lit %mem-set-at!) %int-form-word!)
        (pair (lit %mem-ref) %int-form-word)
        (pair (lit %mem-set!) %int-form-word!)
        (pair (lit %f-ref) %int-form-double)
        (pair (lit %f-set!) %int-form-double!)))

; The double operations, made on first use: (name . label).  x/num/float is
; imported then, not at load: an integer-only caller (the mixer, the canvas)
; loads no float tower, and a body that compiles its own tower after this
; module does not load float twice.
(def %int-form-float-labels
  (list (pair (lit %f+) "d+d") (pair (lit %f-) "d-d") (pair (lit %f*) "d*d") (pair (lit %f/) "d/d")))
(def %int-form-float-ops ())
(def %int-form-float-make
  (fn (_)
    (import x/num/float libm-fn)
    (List map (fn (_ e) (pair (first e) (libm-fn (first e) (rest e) ()))) %int-form-float-labels)))
(def %int-form-float
  (fn (_ name)
    (do (if (null? %int-form-float-ops)
          (set! %int-form-float-ops (%int-form-float-make))
          ())
        (Assoc entry name %int-form-float-ops))))

(def %int-form-subst
  (fn (self form)
    (match
      ((pair? form) (pair (self (first form)) (self (rest form))))
      ((symbol? form)
        ((fn (_ e) (if (null? e) form (rest e)))
         (if (null? (Assoc entry form %int-form-float-labels))
           (Assoc entry form %int-form-ops)
           (%int-form-float form))))
      (#t form))))

(def int-form-pure (fn (_ form) (eval (%int-form-subst form))))

; (*>> A B K) is A times B shifted down K places, the product exact through
; 64 bits: x/num/fixed's fixed* in the pure form.  A word of 8 bytes holds
; the product, so there the form says (>> (* A B) K), which compile-asm
; compiles as it stands.  A double is one word there too: (%f-ref A I) is
; (%mem-ref-at A I) and (%f-set! A I V) is (%mem-set-at! A I V).
(def int-form-wide
  (fn (self form)
    (match
      ((pair? form)
        (match
          ((eq? (first form) (lit *>>))
            (list (lit >>) (list (lit *) (self (first (rest form))) (self (first (rest (rest form)))))
                  (self (first (rest (rest (rest form)))))))
          ((eq? (first form) (lit %f-ref)) (pair (lit %mem-ref-at) (self (rest form))))
          ((eq? (first form) (lit %f-set!)) (pair (lit %mem-set-at!) (self (rest form))))
          (#t (pair (self (first form)) (self (rest form))))))
      (#t form))))

(doc int-form-pure "The integer function FORM means, as pure x: its operators bound to the int doors, so it runs where compile-asm cannot and answers what compile-asm's answers."
  (param form LIST "A (fn (self ...) ...) form over integers: + - * < = >> << &, (*>> a b k) for a product shifted down k places through 64 bits, if, match, do, the %mem- byte and word loads and stores, and on doubles' bits %f+ %f- %f* %f/ with the double loads and stores %f-ref and %f-set!")
  (returns CALLABLE "The function")
  (example "(do (import x/tool/int-form int-form-pure) ((int-form-pure (lit (fn (self n acc) (if (< n 1) acc (self (- n 1) (+ acc n)))))) 4 0))" "10")
  (example "(do (import x/tool/int-form int-form-pure) ((int-form-pure (lit (fn (_ a b) (%f* a b)))) 4609434218613702656 4611686018427387904))" "4613937818241073152"))

(doc int-form-wide "FORM as compile-asm takes it on an 8-byte word, where one word holds a product and a double: each (*>> a b k) written as (>> (* a b) k), each %f-ref and %f-set! as the word load and store."
  (param form LIST "An int form")
  (returns LIST "The form, its *>> products spelled as a multiply and a shift and its double loads and stores as word ones")
  (example "(do (import x/tool/int-form int-form-wide) (equal? (int-form-wide (lit (fn (_ a b) (*>> a b 16)))) (lit (fn (_ a b) (>> (* a b) 16)))))" "#t")
  (example "(do (import x/tool/int-form int-form-wide) (equal? (int-form-wide (lit (fn (_ a) (%f-set! a 0 (%f-ref a 1))))) (lit (fn (_ a) (%mem-set-at! a 0 (%mem-ref-at a 1))))))" "#t"))

(doc (provide x/tool/int-form int-form-pure int-form-wide)
  "An integer (fn ...) form, the kind compile-asm compiles, as the pure-x function it means: the twin a compiled loop is checked against."
  (example "(do (import x/tool/int-form int-form-pure) ((int-form-pure (lit (fn (_ a b) (>> (- a b) 1)))) 1 8))" "-4"))
