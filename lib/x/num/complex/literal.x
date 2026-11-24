; complex/literal.x -- the complex literal: 3+4i, 2-3i, 1.5i
;
; Importing this module installs the literal on the base that imports it:
; an analyse handler and a read handler on the COMPLEX type.  x/num/complex
; is the library -- the type, its arithmetic, its conversions, its printer --
; and installs no reader syntax.
;
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(module x/num/complex/literal)
(import x/core/doors buf-tok int+ int- type-make-instance type-push-analyse)
(import x/num/float float str->float)
(import x/num/complex make-complex complex-type)

(def %int (Type named INTEGER))
(def %cvt (prim-ref (lit convert) (lit to)))

; The states are module-level defs: the compiled analyser in
; boot/tower-compiled.x captures them as free variables once, and its
; compiled twins of cx-imag-frac, cx-imag-int, cx-real-frac and cx-real-int
; must agree with these form for form.

; --- Tokenizer state machine for complex literals ---
; Matches: <digits>[.<digits>][+-]<digits>[.<digits>]i
; Also: <digits>[.<digits>]i  (pure imaginary)

(def cx-imag-frac ())
(set! cx-imag-frac
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57))
      cx-imag-frac
      (if (= chr 105)
        (%score-set score 1 buffer)
        ()))))

(def cx-imag-dot
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57))
      cx-imag-frac
      ())))

(def cx-imag-int ())
(set! cx-imag-int
  (fn (_ buffer score chr)
    (match
      ((and (>= chr 48) (<= chr 57)) cx-imag-int)
      ((= chr 46) cx-imag-dot)
      ((= chr 105) (%score-set score 1 buffer))
      (#t ()))))

(def cx-sign
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57))
      cx-imag-int
      ())))

(def cx-real-frac ())
(set! cx-real-frac
  (fn (_ buffer score chr)
    (match
      ((and (>= chr 48) (<= chr 57)) cx-real-frac)
      ((= chr 43) cx-sign)
      ((= chr 45) cx-sign)
      ((= chr 105) (%score-set score 1 buffer))
      (#t ()))))

(def cx-real-dot
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57))
      cx-real-frac
      ())))

; Entry after a leading '-': a digit starts the (negative) real part.
; The read side already handles the sign (its separator search starts
; at index 1), so this state is all -1+2i needed (#45 R4).
(def cx-neg
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57)) cx-real-int ())))

(def cx-real-int ())
(set! cx-real-int
  (fn (_ buffer score chr)
    (match
      ((and (>= chr 48) (<= chr 57)) cx-real-int)
      ((= chr 46) cx-real-dot)
      ((= chr 43) cx-sign)
      ((= chr 45) cx-sign)
      ((= chr 105) (%score-set score 1 buffer))
      (#t ()))))

; --- Reader helpers ---

(def %cx-find-char
  (fn (self s i len ch)
    (if (>= i len) ()
      (if (= (%cvt (%str-ref s i) %int) ch)
        i
        (self s (int+ i 1) len ch)))))

(def %cx-parse-num
  (fn (_ s)
    (if (%cx-find-char s 0 (%str-length s) 46)
      (type-make-instance float (str->float s))
      (%cvt s %int))))

(def %cx-literal-read
  (fn (_ . args)
    (let ((tok (buf-tok (first args))))
      (let ((len (%str-length tok)))
        (let ((body (%substring tok 0 (int- len 1))))
          (let ((blen (int- len 1)))
            (let ((sign-pos (%cx-find-char body 1 blen 43)))
              (if (null? sign-pos)
                (set! sign-pos (%cx-find-char body 1 blen 45)))
              (if sign-pos
                (make-complex
                  (%cx-parse-num (%substring body 0 sign-pos))
                  (%cx-parse-num (%substring body sign-pos blen)))
                (make-complex 0 (%cx-parse-num body))))))))))

; Entry: a digit, or '-' then a digit (a negative real part).
(def %cx-literal-analyse
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57)) cx-real-int
      (if (= chr 45) cx-neg ()))))

(type-push-analyse complex-type %cx-literal-analyse)
((prim-ref (lit type) (lit push-read)) complex-type %cx-literal-read)

(doc (provide x/num/complex/literal
  cx-real-int cx-real-dot cx-real-frac cx-sign cx-neg cx-imag-int cx-imag-dot cx-imag-frac)
  (note "The exported names are the analyser's states, which boot/tower-compiled.x compiles in place.")
  (sample "(import x/num/complex/literal)" "3+4i now reads as a complex on this base")
  "The complex literal a+bi, installed on the importing base's COMPLEX type.")
