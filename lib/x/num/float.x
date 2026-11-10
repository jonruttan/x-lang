; float.x -- Floating-point type with IEEE 754 bit-pattern storage
; lint-known: x3 x4 sp
(module x/num/float)

(import x/type/class)
; Fetch the tokenizer prims from the catalogue (ns `buf`/`tok` are de-registered, R5).
(import x/core/doors buf-tok char->int ffi-dlopen ffi-dlsym int% int* int+ int/ int= io-display-to-str obj-make obj-ref obj-set! ptr->int ptr-call ptr-ref str-byte-len str-byte-ref str-byte-sub type-by-atom type-from-cell type-make type-make-instance type-of type-push-call type-push-op type?)

; Fetch the type-system helpers from the catalogue (registered by sys/type.x).

; Fetch the conversion dispatcher from the catalogue (registered by sys/convert.x).
(def %cvt (prim-ref 'convert 'to))
; Fetch the type prims from the catalogue (ns `type` is de-registered, R5).
; The binary integer primitives, fetched from the catalogue: the C operators as
; they were before core/arithmetic.x wrapped the bare names.
; The machine-INT test, as predicates.x's number? was before float widened it.
(def %int-t (type-of 0))
(def %int-number? (fn (_ x) (type? x %int-t)))
; Fetch the ptr/ffi prims from the catalogue (ns `ptr`/`ffi` are de-registered, R5).
; The string prims the printer below reads digits with.

; The engine does no floating point.  The double operations are machine
; code this module emits with the assembler (the stubs below), called
; through (ptr call), which passes and returns plain longs.
(import x/tool/asm)

;
; Float values are stored as IEEE 754 double bit patterns: inside an integer
; where the word holds all 64 bits, and in a VECTOR of two words, the low word
; first, where it does not (a 4-byte word).  A value's payload is `(first
; value)` on either; what reads or makes one below asks %word-size, and the
; stubs take the two-word form as two arguments a double and give their
; answer back through a pointer.
; The tokenizer's competitive scoring system ensures "3.14" (score 4)
; outscores the integer match "3" (score 1).
;
; Forward-declare reader

(def %float-read ())

(note "Conversion")

; --- Printing: %.15g, in x ---
; A finite double is exactly m * 2^e with an integer m.  For e >= 0 that is
; the integer m * 2^e; for e < 0 it is (m * 5^-e) * 10^e, so its decimal
; digits are those of the integer m * 5^-e with the point moved -e places.
; That integer is held as limbs, base 10^9, least significant first, and
; built by multiplying by a small factor a pass at a time, so every product
; fits a machine int and the digits are exact without bigint (float loads
; with or without it).  Rounding them to 15 significant digits, ties to
; even, is what C's printf("%.15g") does with the same value.

(def %float-precision 15)

; The byte at I of S, as an INT (byte-ref answers a CHAR).
(def %byte-at
  (fn (_ s i) (char->int (str-byte-ref s i))))

; The limb base, and the largest factor each pass multiplies by:
; a limb times a factor, plus the carry, stays under 2^63.
; On a 4-byte word the same bound is 2^31: base 10^4, and factors 5^6 and
; 2^14, so a limb times a factor plus the carry stays under 2^28.
(def %limb-base (if (int= %word-size 8) 1000000000 10000))
(def %limb-digits (if (int= %word-size 8) 9 4))
(def %pow5-step (if (int= %word-size 8) 12 6))   ; 5^12 = 244140625; 5^6 = 15625
(def %pow2-step (if (int= %word-size 8) 29 14))  ; 2^29 = 536870912; 2^14 = 16384

; The machine int operators throughout: these are limbs and small factors,
; and the generic / answers a rational once num/rational has loaded.

; N (positive) as limbs, least significant first, with no zero top limb.
(def %int->limbs
  (fn (self n)
    (if (int= n 0) ()
      (pair (int% n %limb-base) (self (int/ n %limb-base))))))

; LIMBS * S, S small.
(def %limbs*
  (fn (_ limbs s)
    ((fn (self ls carry)
       (if (null? ls)
         (%int->limbs carry)
         (let ((v (int+ (int* (first ls) s) carry)))
           (pair (int% v %limb-base) (self (rest ls) (int/ v %limb-base))))))
     limbs 0)))

; LIMBS + S, S small.
(def %limbs+s
  (fn (self ls s)
    (match
      ((int= s 0) ls)
      ((null? ls) (%int->limbs s))
      (#t (let ((v (int+ (first ls) s)))
            (pair (int% v %limb-base) (self (rest ls) (int/ v %limb-base))))))))

; LIMBS * B^K, K passes of B^STEP and one of the rest.
(def %limbs*pow
  (fn (self limbs b step k)
    (if (> k step)
      (self (%limbs* limbs (%int-pow b step)) b step (- k step))
      (%limbs* limbs (%int-pow b k)))))

(def %int-pow
  (fn (self b k) (if (int= k 0) 1 (int* b (self b (- k 1))))))

; The decimal digits of LIMBS, the top limb bare and the rest padded to nine.
(def %limbs->str
  (fn (self limbs)
    (if (null? (rest limbs)) (io-display-to-str (first limbs))
      (Str8 append (self (rest limbs))
        (let ((d (io-display-to-str (first limbs))))
          (Str8 append (%zeros (- %limb-digits (str-byte-len d))) d))))))

; A string of N copies of "0".
(def %zeros
  (fn (self n) (if (< n 1) "" (Str8 append "0" (self (- n 1))))))

; DS without its trailing zeros, keeping at least one digit.
(def %strip-zeros
  (fn (_ ds)
    ((fn (self n)
       (if (and (> n 1) (int= (%byte-at ds (- n 1)) 48))
         (self (- n 1))
         (str-byte-sub ds 0 n)))
     (str-byte-len ds))))

; Is any digit of DS from I on non-zero?
(def %any-nonzero?
  (fn (self ds i)
    (if (>= i (str-byte-len ds)) #f
      (if (int= (%byte-at ds i) 48) (self ds (+ i 1)) #t))))

; DS plus one, as digits: the trailing nines roll to zeros and the digit
; before them goes up, or a 1 goes in front of a string of nines.  On the
; string, not through an int: fifteen digits are more than a 4-byte word.
(def %digits-inc
  (fn (_ ds)
    (def n (str-byte-len ds))
    ((fn (self i)
       (match
         ((< i 0) (Str8 append "1" (%zeros n)))
         ((int= (%byte-at ds i) 57) (self (- i 1)))
         (#t (Str8 append (str-byte-sub ds 0 i)
                          (io-display-to-str (- (%byte-at ds i) 47))
                          (%zeros (- (- n i) 1))))))
     (- n 1))))

; Round the digit string DS (value DS * 10^(X - len + 1), leading digit
; at decimal exponent X) to P significant digits, ties to even.  Answers
; (digits . X), X moving up one when the rounding carries out.
(def %round-digits
  (fn (_ ds x p)
    (if (<= (str-byte-len ds) p) (pair ds x)
      (let ((kept (str-byte-sub ds 0 p))
            (next (- (%byte-at ds p) 48)))
        (def up
          (match
            ((> next 5) #t)
            ((< next 5) #f)
            ((%any-nonzero? ds (+ p 1)) #t)
            (#t (int= (& (%byte-at ds (- p 1)) 1) 1))))
        (if (not up) (pair kept x)
          (let ((s (%digits-inc kept)))
            (if (> (str-byte-len s) p)
              (pair (str-byte-sub s 0 p) (+ x 1))
              (pair s x))))))))

; The %g layout of significant digits DS (no trailing zeros) at decimal
; exponent X: plain notation for -4 <= X < P, else d.ddde+XX.
(def %g-layout
  (fn (_ ds x p)
    (def n (str-byte-len ds))
    (match
      ((or (< x -4) (>= x p))
        (Str8 append
          (str-byte-sub ds 0 1)
          (if (> n 1) (Str8 append "." (str-byte-sub ds 1 (- n 1))) "")
          (if (< x 0) "e-" "e+")
          (let ((xs (io-display-to-str (if (< x 0) (- 0 x) x))))
            (if (< (str-byte-len xs) 2) (Str8 append "0" xs) xs))))
      ((< x 0)
        (Str8 append "0." (%zeros (- (- 0 x) 1)) ds))
      ((< (+ x 1) n)
        (Str8 append (str-byte-sub ds 0 (+ x 1)) "." (str-byte-sub ds (+ x 1) (- n (+ x 1)))))
      (#t (Str8 append ds (%zeros (- (+ x 1) n)))))))

; A double's fields from its stored bit pattern, on either word, as
; (NEG EX FHI LO).  The sign, exponent and fraction are read from the high
; word: the whole payload on an 8-byte word, the second of the two on a
; 4-byte one.  EX is the 11-bit exponent field; FHI the fraction bits the
; high word holds, all fifty-two on an 8-byte word and the top twenty on a
; 4-byte one; LO the low thirty-two on a 4-byte word and 0 on an 8-byte one.
(def float-split
  (fn (_ bits)
    (def wide (int= %word-size 8))
    (def hi (if wide bits (obj-ref bits 2)))
    (list (< hi 0)
          (& (>> hi (if wide 52 20)) 2047)
          (& hi (if wide (- (<< 1 52) 1) 1048575))
          (if wide 0 (obj-ref bits 1)))))

; The mantissa goes straight to limbs, since on a 4-byte word no int holds
; its fifty-three bits: the low word joins sixteen bits at a time.
(def %bits->g
  (fn (_ bits)
    (def wide (int= %word-size 8))
    (def fields (float-split bits))
    (def neg (first fields))
    (def ex (first (rest fields)))
    (def frac (first (rest (rest fields))))
    (def lo (first (rest (rest (rest fields)))))
    (def sign (if neg "-" ""))
    (def frac-zero? (and (int= frac 0) (int= lo 0)))
    (match
      ((int= ex 2047)
        (if frac-zero? (Str8 append sign "inf") "nan"))
      ((and (int= ex 0) frac-zero?)
        (Str8 append sign "0"))
      (#t
        (let ((mh (if (int= ex 0) frac (| frac (<< 1 (if wide 52 20)))))
              (e (if (int= ex 0) -1074 (- ex 1075))))
          (def m
            (if wide (%int->limbs mh)
              (%limbs+s (%limbs* (%limbs+s (%limbs* (%int->limbs mh) 65536) (& (>> lo 16) 65535)) 65536)
                        (& lo 65535))))
          (def ds (%limbs->str
                    (if (< e 0)
                      (%limbs*pow m 5 %pow5-step (- 0 e))
                      (%limbs*pow m 2 %pow2-step e))))
          (def x (+ (- (str-byte-len ds) 1) (if (< e 0) e 0)))
          (def r (%round-digits ds x %float-precision))
          (Str8 append sign
            (%g-layout (%strip-zeros (first r)) (rest r) %float-precision)))))))

(def %float->str
  (fn (_ bits)
    ; %.15g renders int-valued doubles bare ("1"), which re-reads as an
    ; INT -- keep the point so floats round-trip (#45 R4). Skip anything
    ; already carrying a point, an exponent, or inf/nan.
    (let ((s (%bits->g bits)))
      (match
        ((Str8 includes? "." s) s)
        ((Str8 includes? "e" s) s)
        ((Str8 includes? "n" s) s)
        (#t (Str8 append s ".0"))))))

(def int->float
  (fn (_ n) (%d<-i n)))

(def %float->int
  (fn (_ bits) (%i<-d bits)))

; State machine for tokenizer: matches [0-9]+\.[0-9]+
; Uses intrinsic scoring — score computed from buffer length.
; After first fractional digit: continue digits or score

(def float-frac ())

(set! float-frac
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57))
      float-frac
      (%seq (%buffer-unread buffer) (%score-set score 1 buffer)))))
; Must see at least one digit after '.'

(def float-first-frac
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57))
      (%seq (%score-set score 1 buffer) float-frac)
      ())))
; Integer part: digits until '.'

(def float-int-digits ())

(set! float-int-digits
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57))
      float-int-digits
      (if (= chr 46) float-first-frac ()))))
; Sign: a '-' entry must see a digit next, so a lone '-' (the operator)
; and '-.' fall through to the symbol type unclaimed.

(def float-neg-int
  (fn (_ buffer score chr)
    (if (and (>= chr 48) (<= chr 57)) float-int-digits ())))
; --- The math library ---
; Try libm.so.6 (Linux), libm.dylib (macOS), then fall back to current process

(def %libm-open
  (fn (_)
    (let ((h (ffi-dlopen "libm.so.6" 1)))
      (if h h
        (let ((h2 (ffi-dlopen "libm.dylib" 1)))
          (if h2 h2
            (ffi-dlopen () 1)))))))
(def %libm (%libm-open))

; On a 4-byte word: the 8 bytes a stub writes a double answer to, and the
; vector type a payload is made of.  The region is this process's, like the
; stubs: emptied for a state image and made again when one loads.
(def %ptr-alloc (prim-ref (lit ptr) (lit alloc)))
(def %out-make (fn (_) (if (int= %word-size 8) () (%ptr-alloc 8))))
(def %out (%out-make))
(def %words-t (if (int= %word-size 8) () (type-of (Vector of 0 0))))

; --- The stubs: the double operations as machine code -------------------------
; (ptr call) passes its arguments in the general registers and reads the
; answer from x0/rax, and a double's bits are an INT here, so a double
; travels through it unchanged.  What it cannot do is reach the FP unit: a
; double operand lives in d0/xmm0.  Each stub is the few instructions that
; bridge the two -- move the bits into d registers, operate or call libm,
; move the result back -- emitted once by the assembler, in the portable
; vocabulary both backends lower (lib/x/tool/asm/).
;
; LABEL names the stub, in the convention strings the engine's retired
; ffi-call used:
;   "d+d" "d-d" "d*d" "d/d"   bits, bits -> bits
;   "d<d" "d=d"               bits, bits -> BOOL (#f when either is NaN)
;   "i->d" "d->i"             int -> bits; bits -> int (toward zero)
;   "d->f" "f->d"             double bits -> single bits (rounded); back
;   "i->f"                    int -> single bits (rounded once)
;   "d->d" "dd->d"            a libm function NAME: FLOAT(s) -> FLOAT
;   "s0->d"                   a libm function NAME, called (s, NULL): STRING -> bits
;   "ii->d"                   a C function NAME of two integer or pointer
;                             arguments, answering a double: strtod(s, &end) --
;                             INTEGER, INTEGER -> bits
;   "di->d" "dp->d"           a libm function NAME of a double and an integer
;                             or pointer: ldexp(x, n), frexp(x, &e) --
;                             bits, INTEGER -> bits
;   "ptr"                    no stub: the dlsym'd pointer itself
; A NAME that does not resolve gets no stub: the cell holds nil, and a call
; through it raises in (ptr call), catchably.

; The two-operand moves in, and the result out.
(def %stub-args2!
  (fn (_ a)
    (do (asm-emit! a 'fmov/d d0 x0)
        (asm-emit! a 'fmov/d d1 x1))))
(def %stub-ret!
  (fn (_ a) (asm-emit! a 'fmov/x x0 d0)))
; Call ADDR, which answers in d0.  x8 is the call-target register of the
; portable model.
(def %stub-call!
  (fn (_ a addr)
    (do (asm-load-imm64! a x8 addr)
        (asm-emit! a 'blr x8))))

(def %stub-body!
  (fn (_ a label addr)
    (match
      ((str=? label "d+d") (do (%stub-args2! a) (asm-emit! a 'fadd d0 d0 d1) (%stub-ret! a)))
      ((str=? label "d-d") (do (%stub-args2! a) (asm-emit! a 'fsub d0 d0 d1) (%stub-ret! a)))
      ((str=? label "d*d") (do (%stub-args2! a) (asm-emit! a 'fmul d0 d0 d1) (%stub-ret! a)))
      ((str=? label "d/d") (do (%stub-args2! a) (asm-emit! a 'fdiv d0 d0 d1) (%stub-ret! a)))
      ((str=? label "d<d") (do (%stub-args2! a) (asm-emit! a 'flt x0 d0 d1)))
      ((str=? label "d=d") (do (%stub-args2! a) (asm-emit! a 'feq x0 d0 d1)))
      ((str=? label "i->d") (do (asm-emit! a 'scvtf d0 x0) (%stub-ret! a)))
      ((str=? label "d->i") (do (asm-emit! a 'fmov/d d0 x0) (asm-emit! a 'fcvtzs x0 d0)))
      ((str=? label "d->f") (do (asm-emit! a 'fmov/d d0 x0) (asm-emit! a 'fcvt/s d0 d0) (%stub-ret! a)))
      ((str=? label "f->d") (do (asm-emit! a 'fmov/d d0 x0) (asm-emit! a 'fcvt/d d0 d0) (%stub-ret! a)))
      ((str=? label "i->f") (do (asm-emit! a 'scvtf/s d0 x0) (%stub-ret! a)))
      ((str=? label "d->d") (do (asm-emit! a 'fmov/d d0 x0) (%stub-call! a addr) (%stub-ret! a)))
      ((str=? label "dd->d") (do (%stub-args2! a) (%stub-call! a addr) (%stub-ret! a)))
      ((str=? label "s0->d") (do (asm-emit! a 'mov x1 (imm 0)) (%stub-call! a addr) (%stub-ret! a)))
      ; the arguments are in the integer registers already
      ((str=? label "ii->d") (do (%stub-call! a addr) (%stub-ret! a)))
      ; the double to d0, the integer down to the first integer register
      ((or (str=? label "di->d") (str=? label "dp->d"))
        (do (asm-emit! a 'fmov/d d0 x0) (asm-emit! a 'mov x0 x1) (%stub-call! a addr) (%stub-ret! a)))
      (#t (Err raise 'value "Float: no such stub label" label)))))

; The same stubs on a 4-byte word.  A double is two arguments, low word then
; high, and an answer that is a double goes out through a pointer, the last
; argument: (ptr call) hands back one word.  The first four words travel in
; the argument registers and the fifth, when there is one, on the stack,
; where asm-stack-arg says the prologue left it.  x4 keeps the pointer
; across a libm call, since the prologue saves it.
(def %stub-args2-2w!
  (fn (_ a)
    (do (asm-emit! a 'fmov/d2 d0 x0 x1)
        (asm-emit! a 'fmov/d2 d1 x2 x3))))
(def %stub-out-2w!
  (fn (_ a r) (asm-emit! a 'fstr d0 (mem r 0))))
(def %stub-fifth-2w!
  (fn (_ a) (asm-emit! a 'ldr x4 (mem sp (asm-stack-arg 4)))))
(def %stub-body-2w!
  (fn (_ a label addr)
    (match
      ((str=? label "d+d") (do (%stub-args2-2w! a) (%stub-fifth-2w! a) (asm-emit! a 'fadd d0 d0 d1) (%stub-out-2w! a x4)))
      ((str=? label "d-d") (do (%stub-args2-2w! a) (%stub-fifth-2w! a) (asm-emit! a 'fsub d0 d0 d1) (%stub-out-2w! a x4)))
      ((str=? label "d*d") (do (%stub-args2-2w! a) (%stub-fifth-2w! a) (asm-emit! a 'fmul d0 d0 d1) (%stub-out-2w! a x4)))
      ((str=? label "d/d") (do (%stub-args2-2w! a) (%stub-fifth-2w! a) (asm-emit! a 'fdiv d0 d0 d1) (%stub-out-2w! a x4)))
      ((str=? label "d<d") (do (%stub-args2-2w! a) (asm-emit! a 'flt x0 d0 d1)))
      ((str=? label "d=d") (do (%stub-args2-2w! a) (asm-emit! a 'feq x0 d0 d1)))
      ((str=? label "i->d") (do (asm-emit! a 'scvtf d0 x0) (%stub-out-2w! a x1)))
      ((str=? label "d->i") (do (asm-emit! a 'fmov/d2 d0 x0 x1) (asm-emit! a 'fcvtzs x0 d0)))
      ((str=? label "d->f") (do (asm-emit! a 'fmov/d2 d0 x0 x1) (asm-emit! a 'fcvt/s x0 d0)))
      ((str=? label "f->d") (do (asm-emit! a 'fcvt/d d0 x0) (%stub-out-2w! a x1)))
      ((str=? label "i->f") (asm-emit! a 'scvtf/s x0 x0))
      ((str=? label "d->d") (do (asm-emit! a 'fmov/d2 d0 x0 x1) (asm-emit! a 'mov x4 x2) (%stub-call! a addr) (%stub-out-2w! a x4)))
      ((str=? label "dd->d") (do (%stub-args2-2w! a) (%stub-fifth-2w! a) (%stub-call! a addr) (%stub-out-2w! a x4)))
      ((str=? label "s0->d") (do (asm-emit! a 'mov x4 x1) (asm-emit! a 'mov x1 (imm 0)) (%stub-call! a addr) (%stub-out-2w! a x4)))
      ((str=? label "ii->d") (do (asm-emit! a 'mov x4 x2) (%stub-call! a addr) (%stub-out-2w! a x4)))
      ((or (str=? label "di->d") (str=? label "dp->d"))
        (do (asm-emit! a 'fmov/d2 d0 x0 x1) (asm-emit! a 'mov x0 x2) (asm-emit! a 'mov x4 x3) (%stub-call! a addr) (%stub-out-2w! a x4)))
      (#t (Err raise 'value "Float: no such stub label" label)))))

; Room for the longest stub: a frame, a 64-bit immediate, a call and three
; moves, well under this on both backends.
(def %stub-capacity 128)

; The entry point for LABEL (NAME resolved through libm when it has one), or
; nil when NAME does not resolve, or when this machine has no assembler
; backend to emit it with: a platform without one loads the tower with its
; float cells empty.  Each stub is its own small buffer.  The frame is the
; assembler's prologue: on x86-64 it is also what moves the first argument
; into x0, and it keeps the stack aligned for the libm call.
(def %stub-emit
  (fn (_ label name)
    (let ((addr (if (null? name) () (ffi-dlsym %libm name))))
      (if (or (not (asm-backend?)) (and (not (null? name)) (null? addr))) ()
        (let ((a (asm-new %stub-capacity)))
          (do (asm-prologue! a)
              ((if (int= %word-size 8) %stub-body! %stub-body-2w!)
               a label (if (null? addr) 0 (ptr->int addr)))
              (asm-epilogue! a)
              (asm-finalize! a)))))))

; What a row's cell holds: the stub, or for "ptr" the pointer itself.
(def %stub-address
  (fn (_ label name)
    (if (str=? label "ptr") (ffi-dlsym %libm name) (%stub-emit label name))))

; --- What the stubs are is this process's alone --------------------------------
; The handle, every pointer resolved through it, and every stub (an address
; in memory this process mapped).  A state image cannot carry them (the
; transient rule, boot/reflect.x): the handle has no symbol, a stub has no
; name at all, and a symbol of a library the loader has not opened does not
; resolve -- glibc keeps a dlopen'd libm out of the global scope, where
; macOS's libSystem folds it in.  So each binding below REGISTERS ITSELF,
; once, on the line that makes it: a row the hook remakes it from, and a
; transient the writer images as nil.  The maker is shared by the load and
; the hook.
(def %stub-rows ())                 ; ((global label name cell) ...), newest first
;  THE ADDRESS LIVES IN A CELL, AND NEVER INSIDE A CLOSURE.  The maker used
; to close over the resolved address, which puts a raw address in the
; closure's own frame -- where the transient rule cannot reach it.
; %image-transients names GLOBALS, so clearing fsin empties the global and
; leaves the frame the closure still holds; seventeen of those survived the
; child's collect and the writer refused the image on `unnameable: 16`.
;  IT REFUSED ON LINUX ONLY, and that is what kept it quiet.  Nothing about
; the heap differs by platform -- a mac bakes in the same addresses -- only
; whether the writer can NAME them: glibc keeps a dlopen'd libm out of the
; global scope, where macOS's libSystem folds it in, so words that have no
; name under glibc resolve and are named there.  A clean `unnameable: 0` on
; a mac was this bug passing quietly, not its absence.
;  So the address goes in a ONE-SLOT CELL the closure reads at call time.
; The cells are emptied by a thunk among the transients -- run inside the
; child, before the walk, so the walk never meets an address -- and refilled
; by the recache hook after the load.  A closure now holds a cell, which is
; an ordinary pair and images like one; the cost is one indirection per
; call.
(def %stub-make
  (fn (_ label cell)
    ((if (int= %word-size 8) %stub-make-1w %stub-make-2w) label cell)))
(def %stub-make-1w
  (fn (_ label cell)
    (match
      ((str=? label "d->d")
        (fn (_ x) (type-make-instance float (ptr-call (first cell) (first x)))))
      ((str=? label "dd->d")
        (fn (_ a b) (type-make-instance float (ptr-call (first cell) (first a) (first b)))))
      ((or (str=? label "d<d") (str=? label "d=d"))
        (fn (_ a b) (int= (ptr-call (first cell) a b) 1)))
      ((or (str=? label "i->d") (str=? label "d->i") (str=? label "s0->d")
           (str=? label "d->f") (str=? label "f->d") (str=? label "i->f"))
        (fn (_ x) (ptr-call (first cell) x)))
      ((str=? label "ptr") (first cell))  ; the pointer itself
      (#t (fn (_ a b) (ptr-call (first cell) a b))))))
; On a 4-byte word.  A payload is a vector of two words; the closure hands
; the stub the words, and reads a double answer back from %out, the 8 bytes
; every "->d" stub writes.  The payload's words are read with obj-ref: slot 0
; of a vector is its length, so the low word is slot 1 and the high slot 2.
(def %lo (fn (_ p) (obj-ref p 1)))
(def %hi (fn (_ p) (obj-ref p 2)))
(def %out-words
  (fn (_)
    (let ((v (obj-make %words-t 3)))
      (do (obj-set! v 0 2)
          (obj-set! v 1 (ptr-ref %out 0 4))
          (obj-set! v 2 (ptr-ref %out 4 4))
          v))))
(def %stub-make-2w
  (fn (_ label cell)
    (match
      ((str=? label "d->d")
        (fn (_ x) (do (ptr-call (first cell) (%lo (first x)) (%hi (first x)) %out)
                      (type-make-instance float (%out-words)))))
      ((str=? label "dd->d")
        (fn (_ a b) (do (ptr-call (first cell) (%lo (first a)) (%hi (first a)) (%lo (first b)) (%hi (first b)) %out)
                        (type-make-instance float (%out-words)))))
      ((or (str=? label "d<d") (str=? label "d=d"))
        (fn (_ a b) (int= (ptr-call (first cell) (%lo a) (%hi a) (%lo b) (%hi b)) 1)))
      ((or (str=? label "d->i") (str=? label "d->f"))
        (fn (_ x) (ptr-call (first cell) (%lo x) (%hi x))))
      ((str=? label "i->f")
        (fn (_ x) (ptr-call (first cell) x)))
      ((or (str=? label "i->d") (str=? label "f->d") (str=? label "s0->d"))
        (fn (_ x) (do (ptr-call (first cell) x %out) (%out-words))))
      ((str=? label "ii->d")
        (fn (_ a b) (do (ptr-call (first cell) a b %out) (%out-words))))
      ((or (str=? label "di->d") (str=? label "dp->d"))
        (fn (_ x n) (do (ptr-call (first cell) (%lo x) (%hi x) n %out) (%out-words))))
      ((str=? label "ptr") (first cell))
      (#t (fn (_ a b) (do (ptr-call (first cell) (%lo a) (%hi a) (%lo b) (%hi b) %out) (%out-words)))))))
; A row is (GLOBAL LABEL NAME CELL HELD?): HELD? when the closure has gone to
; a caller who keeps it (libm-fn), so its cell must be filled at a load.
(def %stub-fn
  (fn (_ global label name . held)
    (let ((cell (pair (%stub-address label name) ())))
      (do (set! %stub-rows (pair (list global label name cell (not (null? held))) %stub-rows))
          (%stub-make label cell)))))
;  A STUB OF THIS FILE'S OWN IS MADE AT ITS FIRST CALL AFTER A LOAD.  Encoding
; thirty stubs cost every process that loads this module 55 ms, and most do no
; float arithmetic.  This file calls its stubs by name, never keeping one, so
; the hook binds each name to this closure instead: the first call makes the
; stub, binds the name to it and calls it, and every later call is the stub's
; own.  A closure handed out by libm-fn is kept by its caller, which only the
; cell reaches, so those are made at the load as before.
(def %stub-lazy
  (fn (_ global label name cell)
    (fn (_ . args)
      (do (if (null? (first cell)) (%set-first! cell (%stub-address label name)) ())
          ((fn (_ made) (do (eval (list (lit set!) global (list (lit lit) made))) (apply made args)))
           (%stub-make label cell))))))
; The same door, exported, for a module or a bundle that binds a libm function
; this file does not -- erf, the hyperbolics -- with the labels "d->d",
; "dd->d" and "ptr", or wants a stub this file makes none of, by any label
; above with NAME nil.  Its rows are rows here: the thunk below clears them
; and the recache hook remakes them, and libm is opened once, by this file.
(def libm-fn (fn (_ global label name) (%stub-fn global label name #t)))
;  A THUNK, NOT SYMBOLS.  boot/reflect.x states the rule: a symbol among the
; transients is cleared in the child's root, a thunk is run.  The handle and
; the rows' names live in this module's frame, which a symbol in the list
; would not reach, and what has to be emptied for each row is a cell that
; each closure holds and no name reaches at all.  So one thunk clears all
; three: the handle, each row's binding (a set! evaluated here, in the
; module's frame) and each row's cell.  Registered after the maker and read
; at RUN time, so it covers every row made below it.
(set! %image-transients
  (pair (fn (_)
          (do (set! %libm ())
              (set! %out ())
              ((fn (self l)
                 (if (null? l) ()
                   (do (self (rest l))
                       ; A held row's closure went to a caller, who holds it by a
                       ; name of its own, in a frame this one may not reach: its
                       ; cell is what is emptied, and the name is left alone.  A
                       ; "ptr" row's caller holds the pointer itself, so its name
                       ; is set, as every row's was.
                       (if (if (first (rest (rest (rest (rest (first l))))))
                             (not (str=? (first (rest (first l))) "ptr")) #f)
                         ()
                         (eval (list (lit set!) (first (first l)) ())))
                       (%set-first! (first (rest (rest (rest (first l))))) ()))))
               %stub-rows)))
        %image-transients))
(set! %image-recache-hooks
  (pair (fn (_)
          (do (set! %libm (%libm-open))
              (set! %out (%out-make))
              ((fn (self l)
                 (if (null? l) ()
                   (do (self (rest l))
                       ((fn (_ global label name cell held?)
                          ; A held closure reads its cell, so refilling the cell is
                          ; the whole of remaking it; the caller's name is not
                          ; touched, since it may be a module's.  A "ptr" row and
                          ; a lazy row are rebound, as before.
                          (if (if held? (not (str=? label "ptr")) #f)
                            (%set-first! cell (%stub-address label name))
                            (eval (list (lit set!) global
                                        (list (lit lit)
                                              (if (if held? #t (str=? label "ptr"))
                                                (do (%set-first! cell (%stub-address label name))
                                                    (%stub-make label cell))
                                                (%stub-lazy global label name cell)))))))
                        (first (first l)) (first (rest (first l))) (first (rest (rest (first l))))
                        (first (rest (rest (rest (first l))))) (first (rest (rest (rest (rest (first l))))))))))
               %stub-rows)))
        %image-recache-hooks))

; The operations on bits.  float's arithmetic, comparisons and conversions
; below are these, wrapped.
(def %d+d (%stub-fn (lit %d+d) "d+d" ()))
(def %d-d (%stub-fn (lit %d-d) "d-d" ()))
(def %d*d (%stub-fn (lit %d*d) "d*d" ()))
(def %d/d (%stub-fn (lit %d/d) "d/d" ()))
(def %d<d (%stub-fn (lit %d<d) "d<d" ()))
(def %d=d (%stub-fn (lit %d=d) "d=d" ()))
(def %d<-i (%stub-fn (lit %d<-i) "i->d" ()))
(def %i<-d (%stub-fn (lit %i<-d) "d->i" ()))

(def %strtod (%stub-fn (lit %strtod) "s0->d" "strtod"))

(def str->float
  (fn (_ s) (%strtod s)))

; Float type with tokenizer, display, and alist-based convert

(def float ())
(set! float
  (type-make
    "FLOAT"
    (list
      (pair
        'write
        (fn (_ self) (display (%float->str (first self)))))
      (pair
        'analyse
        (fn (_ buffer score chr)
          ; Entry: digit [0-9], or '-' followed by a digit

          (if (and (>= chr 48) (<= chr 57))
            float-int-digits
            (if (= chr 45) float-neg-int ()))))
      (pair 'read (fn (_ . args) (%float-read (first args))))
      (pair
        'from
        (list
          (pair
            (type-of 42)
            (fn (_ value) (type-make-instance float (int->float value))))
          (pair
            (type-of "")
            (fn (_ value) (type-make-instance float (str->float value))))
))
      (pair
        'to
        (list
          (pair (type-of 42) (fn (_ self) (%float->int (first self))))
          (pair
            (type-of "")
            (fn (_ self) (%float->str (first self)))))))))

(note "Predicates")

; --- Predicates and constructors ---

(def float? (fn (_ x) (type? x float)))

; Door: promote to float through the catalogue; a miss is a raise, never nil
; into (first)/d+d (the C core is unchecked -- guards live in x-lang).
(def %to-float
  (fn (_ x what)
    (if (float? x) x
      (let ((f (%cvt x float)))
        (if (float? f) f (Err raise 'type what x))))))

(def float-of
  (fn (_ x) (%to-float x "Float from: not convertible to FLOAT")))

(def %int-of
  (fn (_ x)
    (match
      ((float? x) (%float->int (first x)))
      ((%int-number? x) x)
      (#t (Err raise 'type "Float ->int: not a float" x)))))

(note "Arithmetic")

; --- Arithmetic ---

(def f-add
  (fn (_ a b)
    (type-make-instance float (%d+d (first a) (first b)))))

(def f-sub
  (fn (_ a b)
    (type-make-instance float (%d-d (first a) (first b)))))

(def f-mul
  (fn (_ a b)
    (type-make-instance float (%d*d (first a) (first b)))))

(def f-div
  (fn (_ a b)
    (type-make-instance float (%d/d (first a) (first b)))))

; fmod is libm's, through a "dd->d" stub like every other math function.
(def f-mod (%stub-fn (lit f-mod) "dd->d" "fmod" #t))

(note "Comparisons")

; --- Comparisons ---

(def f-lt
  (fn (_ a b) (%d<d (first a) (first b))))

(def f-eq
  (fn (_ a b) (%d=d (first a) (first b))))

; Reader: called by tokenizer after successful analyse
; Uses buf-tok to extract consumed text, then strtod to parse

(set! %float-read
  (fn (_ . args)
    (type-make-instance
      float
      (%strtod (buf-tok (first args))))))

(note "Math Functions")

; Each keeps its stub in a cell; the row it registers (%stub-fn above) is
; how an image gets it back.

(def fsin (%stub-fn (lit fsin) "d->d" "sin" #t))

(def fcos (%stub-fn (lit fcos) "d->d" "cos" #t))

(def %ftan (%stub-fn (lit %ftan) "d->d" "tan"))

(def fsqrt (%stub-fn (lit fsqrt) "d->d" "sqrt" #t))

(def %fexp (%stub-fn (lit %fexp) "d->d" "exp"))

(def %flog (%stub-fn (lit %flog) "d->d" "log"))

(def %fabs (%stub-fn (lit %fabs) "d->d" "fabs"))

(def %ffloor (%stub-fn (lit %ffloor) "d->d" "floor"))

(def %fceil (%stub-fn (lit %fceil) "d->d" "ceil"))

(def %fround (%stub-fn (lit %fround) "d->d" "round"))

(def %ftrunc (%stub-fn (lit %ftrunc) "d->d" "trunc"))

(def %frint (%stub-fn (lit %frint) "d->d" "rint"))

(def %fasin (%stub-fn (lit %fasin) "d->d" "asin"))

(def %facos (%stub-fn (lit %facos) "d->d" "acos"))

(def %fatan (%stub-fn (lit %fatan) "d->d" "atan"))

(def %fpow (%stub-fn (lit %fpow) "dd->d" "pow"))

(def fatan2 (%stub-fn (lit fatan2) "dd->d" "atan2" #t))

(def %flog2 (%stub-fn (lit %flog2) "d->d" "log2"))

(def %flog10 (%stub-fn (lit %flog10) "d->d" "log10"))

(def %fhypot (%stub-fn (lit %fhypot) "dd->d" "hypot"))

; --- Constants ---

(def pi (fatan2 (float-of 0) (float-of -1)))

(def %e (%fexp (float-of 1)))

(def ensure-float
  (fn (_ x) (%to-float x "Float: operand not convertible to FLOAT")))

; --- Type ops: the generic operators dispatch float operands here ---
; ensure-float goes through the cvt from-alist, so the other side may be an
; int, string, bigint, or rational (all declared). The old %safe wrapper chain
; is gone: bigint owns the + - * int-overflow policy, rational owns /, and the
; binary C operators dispatch everything typed.

(def float-type (type-by-atom float))
(type-push-op float-type '+ (fn (_ a b) (f-add (ensure-float a) (ensure-float b))))
(type-push-op float-type '- (fn (_ a b) (f-sub (ensure-float a) (ensure-float b))))
(type-push-op float-type '* (fn (_ a b) (f-mul (ensure-float a) (ensure-float b))))
(type-push-op float-type '/ (fn (_ a b) (f-div (ensure-float a) (ensure-float b))))
; Without this op, (% 1.2 1.4) fell through to x_prim_mod's integer
; fallback -- value-word % value-word on two float PAYLOAD POINTERS --
; and returned garbage ((gcd 1.2 1.4) famously yielded 8).
(type-push-op float-type '% (fn (_ a b) (f-mod (ensure-float a) (ensure-float b))))
(type-push-op float-type '< (fn (_ a b) (f-lt (ensure-float a) (ensure-float b))))
(type-push-op float-type '= (fn (_ a b) (f-eq (ensure-float a) (ensure-float b))))

(note "R7RS Predicates")

; --- R7RS predicates ---
; %int-number? already saved by x-core.x

; number? and real? are cohort predicates (transitional globals, like the other
; type predicates): defined/extended in place by the tower modules. complex.x
; set!-narrows real? to exclude complex instances. integer?/inexact? have no
; extenders and live only on the Float class.
(doc number?
  (param x ANY "Value to test")
  (returns BOOL "True if x is a number")
  (example "(list (number? 2.5) (number? \"2.5\"))" "(#t #f)")
  "Test whether a value is a number (now including floats).")

(def %float-was-number? number?)
(set! number? (fn (_ x) (if (float? x) #t (%float-was-number? x))))

; --- Bigint -> float conversion (registered late, after f+/f* are defined) ---
; A pairwise registration: it needs bigint's handle (the from-alist key) and
; float's arithmetic (the converter body), so neither module alone can install
; it. Filed with the pact, it runs right here when bigint loaded first, at
; bigint's join when bigint loads later, and never when bigint never loads.
; (The old `(if (not (null? %bigint))` guard raised Unbound SYMBOL whenever
; bigint was absent -- an unbound global is not nil.)
(import x/sys/pact)
(Pact when (list 'bigint)
  (fn (_ big)
    ; %bigint-base and `reverse` (x/core/list) are bigint.x's load-time
    ; bindings; the pact guarantees bigint fully loaded before this fires.
    (let ((from-cell (type-from-cell (type-by-atom float))))
      (%set-first! from-cell
        (pair
          (pair big
            (fn (_ value)
              (def sign (first (first value)))
              (def limbs (%reverse (rest (first value))))
              (def fbase (float-of (eval (lit bigint-base) (module x/num/bigint))))
              (def fzero (float-of 0))
              ; Horner's method on reversed (now MSB-first) limbs
              (def %go
                (fn (self ls acc)
                  (if (null? ls) acc
                    (self (rest ls) (f-add (f-mul acc fbase) (float-of (first ls)))))))
              (def mag (%go limbs fzero))
              (if (int= sign -1) (f-sub fzero mag) mag)))
          (first from-cell))))))

(import x/type/class)

(def-class Float ()
  (static
    (method float? (self (param x ANY "Value to test"))
      (doc "Test whether a value is a float." (returns BOOL "True if x is a float")
        (example "(list (Float float? 2.5) (Float float? 2))" "(#t #f)"))
      (float? x))
    (method inexact? (self (param x ANY "Value to test"))
      (doc "Test whether a value is inexact. Equivalent to float?." (returns BOOL "True if x is a float")
        (example "(Float inexact? 0.5)" "#t"))
      (float? x))
    (method integer? (self (param x ANY "Value to test"))
      (doc "Test whether a value is an integer (the pre-float number? predicate)."
        (returns BOOL "True if x is a native integer")
        (example "(list (Float integer? 3) (Float integer? 3.0))" "(#t #f)"))
      (%int-number? x))
    (method real? (self (param x ANY "Value to test"))
      (doc "Test whether a value is a real number (numbers minus complexes)."
        (returns BOOL "True if x is real")
        (example "(Float real? 2.5)" "#t"))
      (real? x))
    ; --- Conversions ---
    ; The bit pattern is an INTEGER where the word holds all 64 bits, and a
    ; VECTOR of two words, the low word first, on a 4-byte word.
    (method bits->str (self (param bits ANY "IEEE 754 double bit pattern: an INTEGER, or a VECTOR of two words on a 4-byte word"))
      (doc "Render a raw IEEE 754 bit pattern as its decimal string -- FFI plumbing; value-level work wants (Float from) / the printer." (returns STRING "Decimal string representation")
        (example "(Float bits->str (Float int->bits 3))" "\"3.0\""))
      (%float->str bits))
    (method bits->int (self (param bits ANY "IEEE 754 double bit pattern: an INTEGER, or a VECTOR of two words on a 4-byte word"))
      (doc "Truncate a raw IEEE 754 bit pattern to a machine integer -- FFI plumbing; value-level work wants (Float ->int)." (returns INTEGER "Truncated integer value")
        (example "(Float bits->int (Float str->bits \"2.5\"))" "2"))
      (%float->int bits))
    (method int->bits (self (param n INTEGER "Integer value"))
      (doc "The IEEE 754 bit pattern of an integer's double value -- FFI plumbing, NOT a float constructor; (Float from) builds instances." (returns ANY "IEEE 754 double bit pattern: an INTEGER, or a VECTOR of two words on a 4-byte word")
        (example "(Float bits->str (Float int->bits 1))" "\"1.0\"")
        (sample "(Float int->bits 1)" "4607182418800017408"))
      (int->float n))
    (method str->bits (self (param s STRING "Decimal string to parse"))
      (doc "The IEEE 754 bit pattern of a decimal string's double value -- FFI plumbing, NOT a parser-to-instance; (Float from) builds instances (the old from-str name claimed FLOAT and returned bits, #66)." (returns ANY "IEEE 754 double bit pattern: an INTEGER, or a VECTOR of two words on a 4-byte word")
        (example "(= (Float str->bits \"1.0\") (Float int->bits 1))" "#t"))
      (str->float s))
    (method from (self (param x ANY "An exact number (int, bigint, rational), a numeric string, or a float (identity)"))
      (doc "Construct a float from any convertible value, through the conversion catalogue -- the generic value door (was exact->inexact, #357). Raises a label 'type when nothing converts." (returns FLOAT "Float instance")
        (example "(Float from 3)" "3.0"))
      (float-of x))
    (method ->int (self (param x FLOAT "Float value (machine ints pass through)"))
      (doc "Convert an inexact float to an exact integer by truncation." (returns INTEGER "Truncated integer value")
        (example "(Float ->int -2.7)" "-2"))
      (%int-of x))
    ; --- Arithmetic / comparison (operands promote via the from-alist) ---
    (method + (self (param a NUMBER "First operand") (param b NUMBER "Second operand"))
      (doc "Add two floats (other numerics promote)." (returns FLOAT "Sum")
        (example "(Float + 1 0.5)" "1.5"))
      (f-add (ensure-float a) (ensure-float b)))
    (method - (self (param a NUMBER "First operand") (param b NUMBER "Second operand"))
      (doc "Subtract two floats (other numerics promote)." (returns FLOAT "Difference")
        (example "(Float - 3 0.5)" "2.5"))
      (f-sub (ensure-float a) (ensure-float b)))
    (method * (self (param a NUMBER "First operand") (param b NUMBER "Second operand"))
      (doc "Multiply two floats (other numerics promote)." (returns FLOAT "Product")
        (example "(Float * 2 1.25)" "2.5"))
      (f-mul (ensure-float a) (ensure-float b)))
    (method / (self (param a NUMBER "Dividend") (param b NUMBER "Divisor"))
      (doc "Divide two floats (other numerics promote)." (returns FLOAT "Quotient")
        (example "(Float / 1 4)" "0.25"))
      (f-div (ensure-float a) (ensure-float b)))
    (method < (self (param a NUMBER "Left operand") (param b NUMBER "Right operand"))
      (doc "Test whether a is less than b (other numerics promote)." (returns BOOL "True if a < b")
        (example "(Float < 1 1.5)" "#t"))
      (f-lt (ensure-float a) (ensure-float b)))
    (method = (self (param a NUMBER "Left operand") (param b NUMBER "Right operand"))
      (doc "Test whether a equals b (other numerics promote)." (returns BOOL "True if a equals b")
        (example "(Float = 2 2.0)" "#t"))
      (f-eq (ensure-float a) (ensure-float b)))
    ; --- libm ---
    (method sin (self (param x FLOAT "Angle in radians"))
      (doc "Compute the sine of a float." (returns FLOAT "Sine of x")
        (example "(Float sin 0.0)" "0.0"))
      (fsin x))
    (method cos (self (param x FLOAT "Angle in radians"))
      (doc "Compute the cosine of a float." (returns FLOAT "Cosine of x")
        (example "(Float cos 0.0)" "1.0"))
      (fcos x))
    (method tan (self (param x FLOAT "Angle in radians"))
      (doc "Compute the tangent of a float." (returns FLOAT "Tangent of x")
        (example "(Float tan 0.0)" "0.0"))
      (%ftan x))
    (method sqrt (self (param x FLOAT "Non-negative float"))
      (doc "Compute the square root of a float." (returns FLOAT "Square root of x")
        (example "(Float sqrt 16.0)" "4.0"))
      (fsqrt x))
    (method exp (self (param x FLOAT "Exponent"))
      (doc "Compute e raised to a power." (returns FLOAT "e raised to the power x")
        (example "(Float exp 0.0)" "1.0"))
      (%fexp x))
    (method log (self (param x FLOAT "Positive float"))
      (doc "Compute the natural logarithm of a float." (returns FLOAT "Natural logarithm of x")
        (example "(Float log 1.0)" "0.0"))
      (%flog x))
    (method abs (self (param x FLOAT "Float value"))
      (doc "Compute the absolute value of a float." (returns FLOAT "Absolute value of x")
        (example "(Float abs -2.5)" "2.5"))
      (%fabs x))
    (method floor (self (param x FLOAT "Float value"))
      (doc "Round a float down to the nearest integer." (returns FLOAT "Largest integer not greater than x")
        (example "(Float floor -2.5)" "-3.0"))
      (%ffloor x))
    (method ceil (self (param x FLOAT "Float value"))
      (doc "Round a float up to the nearest integer." (returns FLOAT "Smallest integer not less than x")
        (example "(Float ceil 2.1)" "3.0"))
      (%fceil x))
    (method round (self (param x FLOAT "Float value"))
      (doc "Round a float to the nearest integer." (returns FLOAT "Nearest integer, ties away from zero")
        (example "(Float round 2.5)" "3.0"))
      (%fround x))
    (method trunc (self (param x FLOAT "Float value"))
      (doc "Truncate a float toward zero." (returns FLOAT "Integer part of x")
        (example "(Float trunc -2.7)" "-2.0"))
      (%ftrunc x))
    (method rint (self (param x FLOAT "Float value"))
      (doc "Round a float to the nearest integer using the current rounding mode." (returns FLOAT "Nearest integer")
        (example "(Float rint 2.5)" "2.0"))
      (%frint x))
    (method asin (self (param x FLOAT "Value in [-1, 1]"))
      (doc "Compute the arc sine of a float." (returns FLOAT "Arc sine in radians")
        (example "(Float asin 0.0)" "0.0"))
      (%fasin x))
    (method acos (self (param x FLOAT "Value in [-1, 1]"))
      (doc "Compute the arc cosine of a float." (returns FLOAT "Arc cosine in radians")
        (example "(Float acos 1.0)" "0.0"))
      (%facos x))
    (method atan (self (param x FLOAT "Float value"))
      (doc "Compute the arc tangent of a float." (returns FLOAT "Arc tangent in radians")
        (example "(Float atan 0.0)" "0.0"))
      (%fatan x))
    (method pow (self (param base FLOAT "Base") (param exponent FLOAT "Exponent"))
      (doc "Raise a float to a power." (returns FLOAT "base raised to the power exponent")
        (example "(Float pow 2.0 10.0)" "1024.0"))
      (%fpow base exponent))
    (method atan2 (self (param y FLOAT "Y coordinate") (param x FLOAT "X coordinate"))
      (doc "Compute the arc tangent of y/x, using signs to determine the quadrant." (returns FLOAT "Angle in radians")
        (example "(Float atan2 0.0 1.0)" "0.0"))
      (fatan2 y x))

    ; --- The math tail (#363) ---
    (method log2 (self (param x FLOAT "Positive float"))
      (doc "Compute the base-2 logarithm of a float."
        (returns FLOAT "log2(x)")
        (sample "(Float log2 8.0)" "3.0"))
      (%flog2 x))
    (method log10 (self (param x FLOAT "Positive float"))
      (doc "Compute the base-10 logarithm of a float."
        (returns FLOAT "log10(x)")
        (sample "(Float log10 1000.0)" "3.0"))
      (%flog10 x))
    (method hypot (self (param x FLOAT "First leg") (param y FLOAT "Second leg"))
      (doc "Compute sqrt(x^2 + y^2) without intermediate overflow (libm hypot)."
        (returns FLOAT "The hypotenuse")
        (sample "(Float hypot 3.0 4.0)" "5.0"))
      (%fhypot x y))

    ; --- Constants (#363) ---
    ; pi and %e were already computed at load (atan2/exp); tau derives
    ; per call through the float adder.
    (method type (self)
      (doc "The float type handle, for Convert and Type."
        (returns ATOM "The FLOAT type handle")
        (sample "(Float float? (Convert to 42 (Float type)))" "#t"))
      float)
    (method pi (self)
      (doc "The circle constant pi, 3.14159265..."
        (returns FLOAT "pi")
        (sample "(Float pi)" "3.14159265358979"))
      pi)
    (method e (self)
      (doc "Euler's number e, 2.71828182..."
        (returns FLOAT "e")
        (sample "(Float e)" "2.71828182845905"))
      %e)
    (method tau (self)
      (doc "The turn constant tau = 2*pi, 6.28318530..."
        (returns FLOAT "tau")
        (sample "(Float tau)" "6.28318530717959"))
      (f-add pi pi))

    ; --- IEEE-special predicates (#363) ---
    ; Field tests on the stored pattern, through float-split: an exponent
    ; field of all ones marks the specials, and a fraction of zero splits
    ; infinity from NaN.  All three are TOTAL predicates: #f, never a
    ; raise, off-domain.
    (method nan? (self (param x ANY "Value to test"))
      (doc "Is x a float NaN? #f for every non-float (an int is never NaN)."
        (returns BOOL "#t only for a NaN float")
        (sample "(Float nan? (/ 0.0 0.0))" "#t"))
      (if (float? x)
        (let ((f (float-split (first x))))
          (if (= (first (rest f)) 2047)
            (not (and (= (first (rest (rest f))) 0) (= (first (rest (rest (rest f)))) 0)))
            #f))
        #f))
    (method inf? (self (param x ANY "Value to test"))
      (doc "Is x a float infinity, either sign? #f for every non-float."
        (returns BOOL "#t only for an infinite float")
        (sample "(Float inf? (/ 1.0 0.0))" "#t"))
      (if (float? x)
        (let ((f (float-split (first x))))
          (if (= (first (rest f)) 2047)
            (and (= (first (rest (rest f))) 0) (= (first (rest (rest (rest f)))) 0))
            #f))
        #f))
    (method finite? (self (param x ANY "Value to test"))
      (doc "Is x a finite number? #t for machine INTs and finite floats; #f for float inf/NaN and for everything else (rational/bigint instances answer through their own classes)."
        (returns BOOL "#t for machine ints and finite floats")
        (sample "(Float finite? 42)" "#t"))
      (match
        ((float? x)
         (not (= (first (rest (float-split (first x)))) 2047)))
        ((number? x) #t)
        (#t #f)))))

; Value dispatch (subject-last): (3.14 float?) -> (Float float? 3.14).
(type-push-call (type-by-atom float) (class-call-handler Float))

; Join the pact last, once the module is fully usable: any registration
; waiting on float fires against the finished class and type ops.
(Pact join 'float float)

(doc (provide x/num/float Float
  float float? float-of float-type ensure-float
  f-add f-sub f-mul f-div f-mod f-eq f-lt fsin fcos fsqrt fatan2 str->float int->float pi
  float-frac float-first-frac float-int-digits float-neg-int float-split libm-fn)
  (note "Literal syntax: 3.14. The generic operators dispatch float operands")
  (note "through the type ops; mixed operands resolve by the from-relation.")
  (example "(+ 1 3.14)" "4.14")
  "IEEE 754 floating-point arithmetic, homed on the Float class.")
