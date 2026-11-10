; Test harness: x-core.x + asm.x, and a double's bits through (Ptr call)
; on either word.
(include "lib/x-core.x")
(import x/tool/asm)
(import x/core/doors int= int* int+ int<)
(when (< %word-size 8) (import x/num/bigint))
(import x/num/u32 u32)

; A double's bits travel in one general register on an 8-byte word, and as
; two, the low word first, on a 4-byte one.  Argument K of a function is
; register K on the wide word and registers 2K, 2K+1 on the narrow, so two
; doubles fill the four argument registers; an answer that is a double goes
; out through a pointer, the fifth word, since (Ptr call) hands back one.
; On the wide word every helper below is the one instruction it replaces.
(def %ad-wide (int= %word-size 8))
(def %ad-reg
  (fn (_ n) (match ((int= n 0) x0) ((int= n 1) x1) ((int= n 2) x2) (#t x3))))
(def asm-arg (fn (_ k) (%ad-reg (if %ad-wide k (int* 2 k)))))

; Argument K, a double, into D.
(def asm-double-in!
  (fn (_ a d k)
    (if %ad-wide (asm-emit! a 'fmov/d d (asm-arg k))
      (asm-emit! a 'fmov/d2 d (asm-arg k) (%ad-reg (int+ (int* 2 k) 1))))))

; D, a double, as the answer.
(def asm-double-out!
  (fn (_ a d)
    (if %ad-wide (asm-emit! a 'fmov/x x0 d)
      (do (asm-emit! a 'ldr x4 (mem sp (asm-stack-arg 4)))
          (asm-emit! a 'fstr d (mem x4 0))))))

; D, a double, rounded to a single, whose bits are the answer.  The wide
; word goes through the d register T, whose bits above the single are zero.
(def asm-single-out!
  (fn (_ a t d)
    (if %ad-wide (do (asm-emit! a 'fcvt/s t d) (asm-emit! a 'fmov/x x0 t))
      (asm-emit! a 'fcvt/s x0 d))))

; Argument K, a single's bits, widened into D through the d register T.
(def asm-single-in!
  (fn (_ a d t k)
    (if %ad-wide (do (asm-emit! a 'fmov/d t (asm-arg k)) (asm-emit! a 'fcvt/d d t))
      (asm-emit! a 'fcvt/d d (asm-arg k)))))

; Argument K, an integer, rounded once to a single, whose bits are the
; answer.  The wide word goes through the d register T.
(def asm-int-single-out!
  (fn (_ a t k)
    (if %ad-wide (do (asm-emit! a 'scvtf/s t (asm-arg k)) (asm-emit! a 'fmov/x x0 t))
      (asm-emit! a 'scvtf/s x0 (asm-arg k)))))

; The narrow word's halves of V, a 64-bit pattern: (low high), each a word.
(def %ad-span (if %ad-wide 0 (* 65536 65536)))
(def %ad-split
  (fn (_ v)
    (let ((q (/ v %ad-span)))
      (let ((hi (if (< (- v (* q %ad-span)) 0) (- q 1) q)))
        (let ((lo (- v (* hi %ad-span))))
          (list (if (< lo (* 32768 65536)) lo (- lo %ad-span)) hi))))))
(def %ad-ptr-alloc (prim-ref (lit ptr) (lit alloc)))
(def %ad-ptr-ref (prim-ref (lit ptr) (lit ref)))
(def %ad-out (if %ad-wide () (%ad-ptr-alloc 8)))

; F called on A and B, each a 64-bit pattern or an integer: the answer word.
(def asm-double-call
  (fn (_ f a b)
    (if %ad-wide (Ptr call f a b)
      (let ((x (%ad-split a)) (y (%ad-split b)))
        (Ptr call f (first x) (first (rest x)) (first y) (first (rest y)) %ad-out)))))

; F called on A and B, answering a double: its 64-bit pattern.
(def asm-double-call/d
  (fn (_ f a b)
    (if %ad-wide (Ptr call f a b)
      (do (asm-double-call f a b)
          (let ((lo (%ad-ptr-ref %ad-out 0 4)) (hi (%ad-ptr-ref %ad-out 4 4)))
            (+ (* hi %ad-span) (if (int< lo 0) (+ lo %ad-span) lo)))))))

; F called on A and B, answering a single's bits, unsigned on either word.
(def asm-double-call/s (fn (_ f a b) (u32 (asm-double-call f a b))))
