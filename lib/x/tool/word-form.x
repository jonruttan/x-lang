; word-form.x -- a (fn ...) form over machine words as pure x: the loop
; compile-asm compiles, run without it.
;
; A kernel written once as a form is two functions: compile-asm's, and this
; one, the form with each operator replaced by the door it means.  The door
; objects themselves stand in the form where the names were, so it means the
; same thing in whatever environment evaluates it, and the compiled one is
; adopted only after it agrees with this one.
;
; A word holds an integer or a double's IEEE bits, and the operator says
; which.  + - * / < = >> << & and (*>> A B K) are the integer operations,
; through the int doors.
;
; Addresses are integers.  (%mem-byte-ref-at A I) is the byte at A + I,
; (%mem-byte-set-at! A I V) stores V's low byte there; (%mem-ref-at A I) and
; (%mem-set-at! A I V) are the machine word at A + I words, and %mem-ref /
; %mem-set! the same at a literal index.  A store answers the value stored,
; as the compiled store does.
;
; Doubles are their IEEE bits, as Float's payload is.  (f+ A B), f-, f*, f/
; and (f-sqrt A) answer a double, and so do (f-exp A), (f-tanh A) and (f-erf A),
; libm's exp, tanh and erf, which the compiled form calls as this one does; (f< A B) and (f= A B) answer as < and =
; do, false when either is a NaN; (i->f N) is the integer N as a double and
; (f->i A) the double truncated toward zero.  All of them run through
; x/num/float's stubs.  (f-ref A I) / (f-set! A I V) are the double at
; A + 8I bytes.  On an 8-byte word a double is one word, so word-form-wide
; writes those two as the word loads and stores compile-asm compiles.  On a
; 4-byte word a double is the two words Float keeps it in, and only the pure
; form runs.  The stubs are made the first time a form uses one.
;
; A single, a 32-bit float, is met only in memory.  (f32-ref A I) is the
; single at A + 4I bytes as a double, which holds it exactly, and
; (f32-set! A I V) stores the double V there rounded to a single and answers
; V.  The arithmetic between is the doubles': for f+ f- f* and f/ the result
; rounded to a single is the one single arithmetic answers.
(module x/tool/word-form)

(import x/core/doors int& int* int+ int- int/ int->ptr int< int= int>> int<< ptr-ref ptr-set! ptr-ref-word ptr-set-word! type-make-instance)
(import x/num/fixed fixed*)
(import x/type/vector)
(import x/type/list)

(def %word-form-ref (fn (_ a i) (ptr-ref-word (int->ptr a) (int* i %word-size))))
(def %word-form-ref! (fn (_ a i v) (do (ptr-set-word! (int->ptr a) (int* i %word-size) v) v)))

; A double in memory: one word on an 8-byte word, two (low first) on a
; 4-byte one.
(def %word-form-f-ref
  (if (int= %word-size 8)
    (fn (_ a i) (ptr-ref-word (int->ptr a) (int* i 8)))
    (fn (_ a i) (Vector of (ptr-ref-word (int->ptr a) (int* i 8)) (ptr-ref-word (int->ptr a) (int+ (int* i 8) 4))))))
(def %word-form-f-set!
  (if (int= %word-size 8)
    (fn (_ a i v) (do (ptr-set-word! (int->ptr a) (int* i 8) v) v))
    (fn (_ a i v)
      (do (ptr-set-word! (int->ptr a) (int* i 8) (Vector ref 0 v))
          (ptr-set-word! (int->ptr a) (int+ (int* i 8) 4) (Vector ref 1 v))
          v))))

(def %word-form-ops
  (list (pair (lit +) int+) (pair (lit -) int-) (pair (lit *) int*) (pair (lit /) int/) (pair (lit <) int<)
        (pair (lit =) int=) (pair (lit >>) int>>) (pair (lit <<) int<<) (pair (lit &) int&)
        (pair (lit *>>) fixed*)
        (pair (lit %mem-byte-ref-at) (fn (_ a i) (int& (ptr-ref (int->ptr (int+ a i)) 0 1) 255)))
        (pair (lit %mem-byte-set-at!) (fn (_ a i v) (do (ptr-set! (int->ptr (int+ a i)) 0 v 1) v)))
        (pair (lit %mem-ref-at) %word-form-ref)
        (pair (lit %mem-set-at!) %word-form-ref!)
        (pair (lit %mem-ref) %word-form-ref)
        (pair (lit %mem-set!) %word-form-ref!)
        (pair (lit f-ref) %word-form-f-ref)
        (pair (lit f-set!) %word-form-f-set!)))

; The double operations, made on first use: (name label libm-name).  The
; stubs answer as the pure form must: bits for a double, #t or #f for a
; comparison.  A libm stub ("d->d") takes and answers a Float, so f-sqrt
; wraps the bits in one and takes them back out.  x/num/float is imported
; then, not at load: an integer-only caller (the mixer, the canvas) loads no
; float tower, and a body that compiles its own tower after this module
; does not load float twice.
(def %word-form-float-labels
  (list (list (lit f+) "d+d" ()) (list (lit f-) "d-d" ()) (list (lit f*) "d*d" ()) (list (lit f/) "d/d" ())
        (list (lit f<) "d<d" ()) (list (lit f=) "d=d" ()) (list (lit f-sqrt) "d->d" "sqrt")
        (list (lit f-exp) "d->d" "exp") (list (lit f-tanh) "d->d" "tanh") (list (lit f-erf) "d->d" "erf")
        (list (lit i->f) "i->d" ()) (list (lit f->i) "d->i" ())
        (list (lit f32-ref) "f->d" ()) (list (lit f32-set!) "d->f" ())))
(def %word-form-float-ops ())
(def %word-form-float-make
  (fn (_)
    (import x/num/float float libm-fn)
    (List map
      (fn (_ e)
        ((fn (_ stub)
           (pair (first e)
             (match
               ((str=? (first (rest e)) "d->d")
                 (fn (_ a) (first (stub (type-make-instance float a)))))
               ((eq? (first e) (lit f32-ref))
                 (fn (_ a i) (stub (ptr-ref (int->ptr (int+ a (int* 4 i))) 0 4))))
               ((eq? (first e) (lit f32-set!))
                 (fn (_ a i v) (do (ptr-set! (int->ptr (int+ a (int* 4 i))) 0 (stub v) 4) v)))
               (#t stub))))
         (libm-fn (first e) (first (rest e)) (first (rest (rest e))))))
      %word-form-float-labels)))
(def %word-form-float
  (fn (_ name)
    (do (if (null? %word-form-float-ops)
          (set! %word-form-float-ops (%word-form-float-make))
          ())
        (Assoc entry name %word-form-float-ops))))

(def %word-form-subst
  (fn (self form)
    (match
      ((pair? form) (pair (self (first form)) (self (rest form))))
      ((symbol? form)
        ((fn (_ e) (if (null? e) form (rest e)))
         (if (null? (Assoc entry form %word-form-float-labels))
           (Assoc entry form %word-form-ops)
           (%word-form-float form))))
      (#t form))))

(def word-form-pure (fn (_ form) (eval (%word-form-subst form))))

; (*>> A B K) is A times B shifted down K places, the product exact through
; 64 bits: x/num/fixed's fixed* in the pure form.  A word of 8 bytes holds
; the product, so there the form says (>> (* A B) K), which compile-asm
; compiles as it stands.  A double is one word there too: (f-ref A I) is
; (%mem-ref-at A I) and (f-set! A I V) is (%mem-set-at! A I V).
(def word-form-wide
  (fn (self form)
    (match
      ((pair? form)
        (match
          ((eq? (first form) (lit *>>))
            (list (lit >>) (list (lit *) (self (first (rest form))) (self (first (rest (rest form)))))
                  (self (first (rest (rest (rest form)))))))
          ((eq? (first form) (lit f-ref)) (pair (lit %mem-ref-at) (self (rest form))))
          ((eq? (first form) (lit f-set!)) (pair (lit %mem-set-at!) (self (rest form))))
          (#t (pair (self (first form)) (self (rest form))))))
      (#t form))))

(doc word-form-pure "The function FORM means, as pure x: its operators bound to the int doors and x/num/float's stubs, so it runs where compile-asm cannot and answers what compile-asm's answers."
  (param form LIST "A (fn (self ...) ...) form over machine words: on integers + - * / < = >> << &, (*>> a b k) for a product shifted down k places through 64 bits; on doubles' bits f+ f- f* f/ f-sqrt, libm's f-exp, f-tanh and f-erf, the comparisons f< f=, and i->f f->i between the two; if, match, do; the %mem- byte and word loads and stores, the double loads and stores f-ref and f-set!, and f32-ref and f32-set!, which load a single as a double and store a double rounded to a single")
  (returns CALLABLE "The function")
  (example "(do (import x/tool/word-form word-form-pure) ((word-form-pure (lit (fn (self n acc) (if (< n 1) acc (self (- n 1) (+ acc n)))))) 4 0))" "10")
  (example "(do (import x/tool/word-form word-form-pure) ((word-form-pure (lit (fn (_ a b) (/ a b)))) 17 5))" "3")
  (example "(do (import x/tool/word-form word-form-pure) (import x/num/float) (equal? ((word-form-pure (lit (fn (_ a b) (f* a b)))) (first (Float from 3)) (first (Float from 2))) (first (Float from 6))))" "#t"))

(doc word-form-wide "FORM as compile-asm takes it on an 8-byte word, where one word holds a product and a double: each (*>> a b k) written as (>> (* a b) k), each f-ref and f-set! as the word load and store."
  (param form LIST "A word form")
  (returns LIST "The form, its *>> products spelled as a multiply and a shift and its double loads and stores as word ones")
  (example "(do (import x/tool/word-form word-form-wide) (equal? (word-form-wide (lit (fn (_ a b) (*>> a b 16)))) (lit (fn (_ a b) (>> (* a b) 16)))))" "#t")
  (example "(do (import x/tool/word-form word-form-wide) (equal? (word-form-wide (lit (fn (_ a) (f-set! a 0 (f-ref a 1))))) (lit (fn (_ a) (%mem-set-at! a 0 (%mem-ref-at a 1))))))" "#t"))

(doc (provide x/tool/word-form word-form-pure word-form-wide)
  "A (fn ...) form over machine words, integers and doubles' bits, the kind compile-asm compiles, as the pure-x function it means: the twin a compiled loop is checked against."
  (example "(do (import x/tool/word-form word-form-pure) ((word-form-pure (lit (fn (_ a b) (>> (- a b) 1)))) 1 8))" "-4"))
