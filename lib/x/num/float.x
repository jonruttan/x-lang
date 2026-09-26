; float.x -- Floating-point type with IEEE 754 bit-pattern storage
(module x/num/float)

(import x/type/class)
; Fetch the tokenizer prims from the catalog (ns `buf`/`tok` are de-registered, R5).
(def %buffer-token (prim-ref 'buf 'tok))

; Fetch the type-system helpers from the catalog (registered by sys/type.x).
(def %type-by-atom (prim-ref 'type 'by-atom))
(def %type-from-cell (prim-ref 'type 'from-cell))
(def %type-push-op (prim-ref 'type 'push-op))

; Fetch the conversion dispatcher from the catalog (registered by sys/convert.x).
(def %cvt (prim-ref 'convert 'to))
; Fetch the type prims from the catalog (ns `type` is de-registered, R5).
(def %make-instance (prim-ref 'type 'make-instance))
(def %make-type (prim-ref 'type 'make))
(def %type-of (prim-ref 'type 'of))
(def %type? (prim-ref 'type '?))
; The binary integer primitives, fetched from the catalog: the C operators as
; they were before core/arithmetic.x wrapped the bare names.
(def %int= (prim-ref (lit int) (lit =)))
; The machine-INT test, as predicates.x's number? was before float widened it.
(def %int-t (%type-of 0))
(def %int-number? (fn (_ x) (%type? x %int-t)))
; Fetch the ptr/ffi prims from the catalog (ns `ptr`/`ffi` are de-registered, R5).
(def %dlopen (prim-ref 'ffi 'dlopen))
(def %dlsym (prim-ref 'ffi 'dlsym))
(def %ptr-call (prim-ref 'ptr 'call))
(def %ptr->int (prim-ref 'ptr '->int))
; The string prims the printer below reads digits with.
(def %str-byte-len (prim-ref 'str 'byte-len))
(def %str-byte-ref (prim-ref 'str 'byte-ref))
(def %char->int (prim-ref 'char '->int))
(def %str-byte-sub (prim-ref 'str 'byte-sub))
(def %display-to-str (prim-ref 'io 'display-to-str))

; The engine does no floating point.  The double operations are machine
; code this module emits with the assembler (the stubs below), called
; through (ptr call), which passes and returns plain longs.
(import x/tool/asm)

;
; Float values are stored as IEEE 754 double bit patterns inside integers.
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
; Either way the digits are exact (bigint does the large products), and
; rounding them to 15 significant digits, ties to even, is what C's
; printf("%.15g") does with the same value.

(def %float-precision 15)

; The byte at I of S, as an INT (byte-ref answers a CHAR).
(def %byte-at
  (fn (_ s i) (%char->int (%str-byte-ref s i))))

; 5^k by squaring; the generic * promotes to bigint past the machine int.
(def %pow5
  (fn (self k)
    (match
      ((%int= k 0) 1)
      ((%int= (& k 1) 1) (* 5 (self (- k 1))))
      (#t (let ((h (self (>> k 1)))) (* h h))))))

; A string of N copies of "0".
(def %zeros
  (fn (self n) (if (< n 1) "" (Str8 append "0" (self (- n 1))))))

; DS without its trailing zeros, keeping at least one digit.
(def %strip-zeros
  (fn (_ ds)
    ((fn (self n)
       (if (and (> n 1) (%int= (%byte-at ds (- n 1)) 48))
         (self (- n 1))
         (%str-byte-sub ds 0 n)))
     (%str-byte-len ds))))

; Is any digit of DS from I on non-zero?
(def %any-nonzero?
  (fn (self ds i)
    (if (>= i (%str-byte-len ds)) #f
      (if (%int= (%byte-at ds i) 48) (self ds (+ i 1)) #t))))

; The machine int the first N digits of DS spell (N <= 15, so it fits).
(def %digits->int
  (fn (_ ds n)
    ((fn (self i acc)
       (if (>= i n) acc
         (self (+ i 1) (+ (* acc 10) (- (%byte-at ds i) 48)))))
     0 0)))

; Round the digit string DS (value DS * 10^(X - len + 1), leading digit
; at decimal exponent X) to P significant digits, ties to even.  Answers
; (digits . X), X moving up one when the rounding carries out.
(def %round-digits
  (fn (_ ds x p)
    (if (<= (%str-byte-len ds) p) (pair ds x)
      (let ((kept (%str-byte-sub ds 0 p))
            (next (- (%byte-at ds p) 48)))
        (def k (%digits->int ds p))
        (def up
          (match
            ((> next 5) #t)
            ((< next 5) #f)
            ((%any-nonzero? ds (+ p 1)) #t)
            (#t (%int= (& k 1) 1))))
        (if (not up) (pair kept x)
          (let ((s (%display-to-str (+ k 1))))
            (if (> (%str-byte-len s) p)
              (pair (%str-byte-sub s 0 p) (+ x 1))
              (pair s x))))))))

; The %g layout of significant digits DS (no trailing zeros) at decimal
; exponent X: plain notation for -4 <= X < P, else d.ddde+XX.
(def %g-layout
  (fn (_ ds x p)
    (def n (%str-byte-len ds))
    (match
      ((or (< x -4) (>= x p))
        (Str8 append
          (%str-byte-sub ds 0 1)
          (if (> n 1) (Str8 append "." (%str-byte-sub ds 1 (- n 1))) "")
          (if (< x 0) "e-" "e+")
          (let ((xs (%display-to-str (if (< x 0) (- 0 x) x))))
            (if (< (%str-byte-len xs) 2) (Str8 append "0" xs) xs))))
      ((< x 0)
        (Str8 append "0." (%zeros (- (- 0 x) 1)) ds))
      ((< (+ x 1) n)
        (Str8 append (%str-byte-sub ds 0 (+ x 1)) "." (%str-byte-sub ds (+ x 1) (- n (+ x 1)))))
      (#t (Str8 append ds (%zeros (- (+ x 1) n)))))))

(def %bits->g
  (fn (_ bits)
    (def neg (< bits 0))
    (def sign (if neg "-" ""))
    (def ex (& (>> bits 52) 2047))
    (def frac (& bits (- (<< 1 52) 1)))
    (match
      ((%int= ex 2047)
        (if (%int= frac 0) (Str8 append sign "inf") "nan"))
      ((and (%int= ex 0) (%int= frac 0))
        (Str8 append sign "0"))
      (#t
        (let ((m (if (%int= ex 0) frac (| frac (<< 1 52))))
              (e (if (%int= ex 0) -1074 (- ex 1075))))
          (def ds (%display-to-str
                    (if (< e 0) (* m (%pow5 (- 0 e))) (%two-power-times m e))))
          (def x (+ (- (%str-byte-len ds) 1) (if (< e 0) e 0)))
          (def r (%round-digits ds x %float-precision))
          (Str8 append sign
            (%g-layout (%strip-zeros (first r)) (rest r) %float-precision)))))))

; M * 2^E for E >= 0, by doubling (the generic * promotes to bigint).
(def %two-power-times
  (fn (self m e)
    (if (< e 1) m
      (if (> e 29)
        (self (* m 536870912) (- e 29))
        (* m (<< 1 e))))))

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
    (let ((h (%dlopen "libm.so.6" 1)))
      (if h h
        (let ((h2 (%dlopen "libm.dylib" 1)))
          (if h2 h2
            (%dlopen () 1)))))))
(def %libm (%libm-open))

; --- The stubs: the double operations as machine code -------------------------
; (ptr call) passes its arguments in the general registers and reads the
; answer from x0/rax, and a double's bits are an INT here, so a double
; travels through it unchanged.  What it cannot do is reach the FP unit: a
; double operand lives in d0/xmm0.  Each stub is the few instructions that
; bridge the two -- move the bits into d registers, operate or call libm,
; move the result back -- emitted once by the assembler, in the portable
; vocabulary both backends lower (lib/x/tool/asm/).
;
; KIND names the stub, in the convention strings the engine's retired
; ffi-call used:
;   "d+d" "d-d" "d*d" "d/d"   bits, bits -> bits
;   "d<d" "d=d"               bits, bits -> BOOL (#f when either is NaN)
;   "i->d" "d->i"             int -> bits; bits -> int (toward zero)
;   "d->d" "dd->d"            a libm function NAME: FLOAT(s) -> FLOAT
;   "s0->d"                   a libm function NAME, called (s, NULL): STRING -> bits
;   "ptr"                     no stub: the dlsym'd pointer itself
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
  (fn (_ a kind addr)
    (match
      ((str=? kind "d+d") (do (%stub-args2! a) (asm-emit! a 'fadd d0 d0 d1) (%stub-ret! a)))
      ((str=? kind "d-d") (do (%stub-args2! a) (asm-emit! a 'fsub d0 d0 d1) (%stub-ret! a)))
      ((str=? kind "d*d") (do (%stub-args2! a) (asm-emit! a 'fmul d0 d0 d1) (%stub-ret! a)))
      ((str=? kind "d/d") (do (%stub-args2! a) (asm-emit! a 'fdiv d0 d0 d1) (%stub-ret! a)))
      ((str=? kind "d<d") (do (%stub-args2! a) (asm-emit! a 'flt x0 d0 d1)))
      ((str=? kind "d=d") (do (%stub-args2! a) (asm-emit! a 'feq x0 d0 d1)))
      ((str=? kind "i->d") (do (asm-emit! a 'scvtf d0 x0) (%stub-ret! a)))
      ((str=? kind "d->i") (do (asm-emit! a 'fmov/d d0 x0) (asm-emit! a 'fcvtzs x0 d0)))
      ((str=? kind "d->d") (do (asm-emit! a 'fmov/d d0 x0) (%stub-call! a addr) (%stub-ret! a)))
      ((str=? kind "dd->d") (do (%stub-args2! a) (%stub-call! a addr) (%stub-ret! a)))
      ((str=? kind "s0->d") (do (asm-emit! a 'mov x1 (imm 0)) (%stub-call! a addr) (%stub-ret! a)))
      (#t (Err raise 'value "Float: no such stub kind" kind)))))

; Room for the longest stub: a frame, a 64-bit immediate, a call and three
; moves, well under this on both backends.
(def %stub-capacity 128)

; The entry point for KIND (NAME resolved through libm when it has one), or
; nil when NAME does not resolve.  Each stub is its own small buffer.  The
; frame is the assembler's prologue: on x86-64 it is also what moves the
; first argument into x0, and it keeps the stack aligned for the libm call.
(def %stub-emit
  (fn (_ kind name)
    (let ((addr (if (null? name) () (%dlsym %libm name))))
      (if (and (not (null? name)) (null? addr)) ()
        (let ((a (asm-new %stub-capacity)))
          (do (asm-prologue! a)
              (%stub-body! a kind (if (null? addr) 0 (%ptr->int addr)))
              (asm-epilogue! a)
              (asm-finalize! a)))))))

; What a row's cell holds: the stub, or for "ptr" the pointer itself.
(def %stub-address
  (fn (_ kind name)
    (if (str=? kind "ptr") (%dlsym %libm name) (%stub-emit kind name))))

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
(def %stub-rows ())                 ; ((global kind name cell) ...), newest first
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
  (fn (_ kind cell)
    (match
      ((str=? kind "d->d")
        (fn (_ x) (%make-instance float (%ptr-call (first cell) (first x)))))
      ((str=? kind "dd->d")
        (fn (_ a b) (%make-instance float (%ptr-call (first cell) (first a) (first b)))))
      ((or (str=? kind "d<d") (str=? kind "d=d"))
        (fn (_ a b) (%int= (%ptr-call (first cell) a b) 1)))
      ((or (str=? kind "i->d") (str=? kind "d->i") (str=? kind "s0->d"))
        (fn (_ x) (%ptr-call (first cell) x)))
      ((str=? kind "ptr") (first cell))  ; the pointer itself
      (#t (fn (_ a b) (%ptr-call (first cell) a b))))))
(def %stub-fn
  (fn (_ global kind name)
    (let ((cell (pair (%stub-address kind name) ())))
      (do (set! %stub-rows (pair (list global kind name cell) %stub-rows))
          (%stub-make kind cell)))))
; The same door, exported, for a module or a bundle that binds a libm function
; this file does not -- erf, the hyperbolics -- with the kinds "d->d",
; "dd->d" and "ptr".  Its rows are rows here: the thunk below clears them and
; the recache hook remakes them, and libm is opened once, by this file.
(def libm-fn %stub-fn)
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
              ((fn (self l)
                 (if (null? l) ()
                   (do (self (rest l))
                       (eval (list (lit set!) (first (first l)) ()))
                       (%set-first! (first (rest (rest (rest (first l))))) ()))))
               %stub-rows)))
        %image-transients))
(set! %image-recache-hooks
  (pair (fn (_)
          (do (set! %libm (%libm-open))
              ((fn (self l)
                 (if (null? l) ()
                   (do (self (rest l))
                       (%set-first! (first (rest (rest (rest (first l)))))
                                    (%stub-address (first (rest (first l)))
                                                   (first (rest (rest (first l))))))
                       (eval (list (lit set!) (first (first l))
                                   (list %stub-make (first (rest (first l)))
                                         (first (rest (rest (rest (first l)))))))))))
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
  (%make-type
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
            (%type-of 42)
            (fn (_ value) (%make-instance float (int->float value))))
          (pair
            (%type-of "")
            (fn (_ value) (%make-instance float (str->float value))))
))
      (pair
        'to
        (list
          (pair (%type-of 42) (fn (_ self) (%float->int (first self))))
          (pair
            (%type-of "")
            (fn (_ self) (%float->str (first self)))))))))

(note "Predicates")

; --- Predicates and constructors ---

(def float? (fn (_ x) (%type? x float)))

; Door: coerce to float through the catalog; a miss is a raise, never nil
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
    (%make-instance float (%d+d (first a) (first b)))))

(def f-sub
  (fn (_ a b)
    (%make-instance float (%d-d (first a) (first b)))))

(def f-mul
  (fn (_ a b)
    (%make-instance float (%d*d (first a) (first b)))))

(def f-div
  (fn (_ a b)
    (%make-instance float (%d/d (first a) (first b)))))

; fmod is libm's, through a "dd->d" stub like every other math function.
(def f-mod (%stub-fn (lit f-mod) "dd->d" "fmod"))

(note "Comparisons")

; --- Comparisons ---

(def f-lt
  (fn (_ a b) (%d<d (first a) (first b))))

(def f-eq
  (fn (_ a b) (%d=d (first a) (first b))))

; Reader: called by tokenizer after successful analyse
; Uses %buffer-token to extract consumed text, then strtod to parse

(set! %float-read
  (fn (_ . args)
    (%make-instance
      float
      (%strtod (%buffer-token (first args))))))

(note "Math Functions")

; Each keeps its stub in a cell; the row it registers (%stub-fn above) is
; how an image gets it back.

(def fsin (%stub-fn (lit fsin) "d->d" "sin"))

(def fcos (%stub-fn (lit fcos) "d->d" "cos"))

(def %ftan (%stub-fn (lit %ftan) "d->d" "tan"))

(def fsqrt (%stub-fn (lit fsqrt) "d->d" "sqrt"))

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

(def fatan2 (%stub-fn (lit fatan2) "dd->d" "atan2"))

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

(def float-type (%type-by-atom float))
(%type-push-op float-type '+ (fn (_ a b) (f-add (ensure-float a) (ensure-float b))))
(%type-push-op float-type '- (fn (_ a b) (f-sub (ensure-float a) (ensure-float b))))
(%type-push-op float-type '* (fn (_ a b) (f-mul (ensure-float a) (ensure-float b))))
(%type-push-op float-type '/ (fn (_ a b) (f-div (ensure-float a) (ensure-float b))))
; Without this op, (% 1.2 1.4) fell through to x_prim_mod's integer
; fallback -- value-word % value-word on two float PAYLOAD POINTERS --
; and returned garbage ((gcd 1.2 1.4) famously yielded 8).
(%type-push-op float-type '% (fn (_ a b) (f-mod (ensure-float a) (ensure-float b))))
(%type-push-op float-type '< (fn (_ a b) (f-lt (ensure-float a) (ensure-float b))))
(%type-push-op float-type '= (fn (_ a b) (f-eq (ensure-float a) (ensure-float b))))

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
  "Test whether a value is a number (integer or float).")

(set! number? (fn (_ x) (if (%int-number? x) #t (float? x))))

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
    (let ((from-cell (%type-from-cell (%type-by-atom float))))
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
              (if (%int= sign -1) (f-sub fzero mag) mag)))
          (first from-cell))))))

(import x/type/class)

(def-class Float ()
  (static
    (method float? (self (param x ANY "Value to test"))
      (doc "Test whether a value is a float." (returns BOOL "True if x is a float"))
      (float? x))
    (method inexact? (self (param x ANY "Value to test"))
      (doc "Test whether a value is inexact. Equivalent to float?." (returns BOOL "True if x is a float"))
      (float? x))
    (method integer? (self (param x ANY "Value to test"))
      (doc "Test whether a value is an integer (the pre-float number? predicate)."
        (returns BOOL "True if x is a native integer"))
      (%int-number? x))
    (method real? (self (param x ANY "Value to test"))
      (doc "Test whether a value is a real number (numbers minus complexes)."
        (returns BOOL "True if x is real"))
      (real? x))
    ; --- Conversions ---
    (method bits->str (self (param bits INT "IEEE 754 double bit pattern"))
      (doc "Render a raw IEEE 754 bit pattern as its decimal string -- FFI plumbing; value-level work wants (Float from) / the printer." (returns STRING "Decimal string representation"))
      (%float->str bits))
    (method bits->int (self (param bits INT "IEEE 754 double bit pattern"))
      (doc "Truncate a raw IEEE 754 bit pattern to a machine integer -- FFI plumbing; value-level work wants (Float ->int)." (returns INT "Truncated integer value"))
      (%float->int bits))
    (method int->bits (self (param n INT "Integer value"))
      (doc "The IEEE 754 bit pattern of an integer's double value -- FFI plumbing, NOT a float constructor; (Float from) builds instances." (returns INT "IEEE 754 double bit pattern"))
      (int->float n))
    (method str->bits (self (param s STRING "Decimal string to parse"))
      (doc "The IEEE 754 bit pattern of a decimal string's double value -- FFI plumbing, NOT a parser-to-instance; (Float from) builds instances (the old from-str name claimed FLOAT and returned bits, #66)." (returns INT "IEEE 754 double bit pattern"))
      (str->float s))
    (method from (self (param x ANY "An exact number (int, bigint, rational), a numeric string, or a float (identity)"))
      (doc "Construct a float from any convertible value, through the conversion catalog -- the generic value door (was exact->inexact, #357). Raises tag 'type when nothing converts." (returns FLOAT "Float instance"))
      (float-of x))
    (method ->int (self (param x FLOAT "Float value (machine ints pass through)"))
      (doc "Convert an inexact float to an exact integer by truncation." (returns INT "Truncated integer value"))
      (%int-of x))
    ; --- Arithmetic / comparison (operands coerce via the from-alist) ---
    (method + (self (param a NUMBER "First operand") (param b NUMBER "Second operand"))
      (doc "Add two floats (other numerics coerce)." (returns FLOAT "Sum"))
      (f-add (ensure-float a) (ensure-float b)))
    (method - (self (param a NUMBER "First operand") (param b NUMBER "Second operand"))
      (doc "Subtract two floats (other numerics coerce)." (returns FLOAT "Difference"))
      (f-sub (ensure-float a) (ensure-float b)))
    (method * (self (param a NUMBER "First operand") (param b NUMBER "Second operand"))
      (doc "Multiply two floats (other numerics coerce)." (returns FLOAT "Product"))
      (f-mul (ensure-float a) (ensure-float b)))
    (method / (self (param a NUMBER "Dividend") (param b NUMBER "Divisor"))
      (doc "Divide two floats (other numerics coerce)." (returns FLOAT "Quotient"))
      (f-div (ensure-float a) (ensure-float b)))
    (method < (self (param a NUMBER "Left operand") (param b NUMBER "Right operand"))
      (doc "Test whether a is less than b (other numerics coerce)." (returns BOOL "True if a < b"))
      (f-lt (ensure-float a) (ensure-float b)))
    (method = (self (param a NUMBER "Left operand") (param b NUMBER "Right operand"))
      (doc "Test whether a equals b (other numerics coerce)." (returns BOOL "True if a equals b"))
      (f-eq (ensure-float a) (ensure-float b)))
    ; --- libm ---
    (method sin (self (param x FLOAT "Angle in radians"))
      (doc "Compute the sine of a float." (returns FLOAT "Sine of x"))
      (fsin x))
    (method cos (self (param x FLOAT "Angle in radians"))
      (doc "Compute the cosine of a float." (returns FLOAT "Cosine of x"))
      (fcos x))
    (method tan (self (param x FLOAT "Angle in radians"))
      (doc "Compute the tangent of a float." (returns FLOAT "Tangent of x"))
      (%ftan x))
    (method sqrt (self (param x FLOAT "Non-negative float"))
      (doc "Compute the square root of a float." (returns FLOAT "Square root of x"))
      (fsqrt x))
    (method exp (self (param x FLOAT "Exponent"))
      (doc "Compute e raised to a power." (returns FLOAT "e raised to the power x"))
      (%fexp x))
    (method log (self (param x FLOAT "Positive float"))
      (doc "Compute the natural logarithm of a float." (returns FLOAT "Natural logarithm of x"))
      (%flog x))
    (method abs (self (param x FLOAT "Float value"))
      (doc "Compute the absolute value of a float." (returns FLOAT "Absolute value of x"))
      (%fabs x))
    (method floor (self (param x FLOAT "Float value"))
      (doc "Round a float down to the nearest integer." (returns FLOAT "Largest integer not greater than x"))
      (%ffloor x))
    (method ceil (self (param x FLOAT "Float value"))
      (doc "Round a float up to the nearest integer." (returns FLOAT "Smallest integer not less than x"))
      (%fceil x))
    (method round (self (param x FLOAT "Float value"))
      (doc "Round a float to the nearest integer." (returns FLOAT "Nearest integer, ties away from zero"))
      (%fround x))
    (method trunc (self (param x FLOAT "Float value"))
      (doc "Truncate a float toward zero." (returns FLOAT "Integer part of x"))
      (%ftrunc x))
    (method rint (self (param x FLOAT "Float value"))
      (doc "Round a float to the nearest integer using the current rounding mode." (returns FLOAT "Nearest integer"))
      (%frint x))
    (method asin (self (param x FLOAT "Value in [-1, 1]"))
      (doc "Compute the arc sine of a float." (returns FLOAT "Arc sine in radians"))
      (%fasin x))
    (method acos (self (param x FLOAT "Value in [-1, 1]"))
      (doc "Compute the arc cosine of a float." (returns FLOAT "Arc cosine in radians"))
      (%facos x))
    (method atan (self (param x FLOAT "Float value"))
      (doc "Compute the arc tangent of a float." (returns FLOAT "Arc tangent in radians"))
      (%fatan x))
    (method pow (self (param base FLOAT "Base") (param exponent FLOAT "Exponent"))
      (doc "Raise a float to a power." (returns FLOAT "base raised to the power exponent"))
      (%fpow base exponent))
    (method atan2 (self (param y FLOAT "Y coordinate") (param x FLOAT "X coordinate"))
      (doc "Compute the arc tangent of y/x, using signs to determine the quadrant." (returns FLOAT "Angle in radians"))
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
    ; Bit tests on the stored pattern: exponent all-ones ((<< 2047 52),
    ; 0x7FF0000000000000) marks the specials; the 52 mantissa bits split
    ; NaN from infinity. The masks are DERIVED, not written out: a 17+-
    ; digit decimal literal parses as a BIGINT wherever num/bigint has
    ; capped the int reader, and & refuses bigints. All three are TOTAL
    ; predicates: #f, never a raise, off-domain.
    (method nan? (self (param x ANY "Value to test"))
      (doc "Is x a float NaN? #f for every non-float (an int is never NaN)."
        (returns BOOL "#t only for a NaN float")
        (sample "(Float nan? (/ 0.0 0.0))" "#t"))
      (if (float? x)
        (let ((em (<< 2047 52)))
          (if (= (& (first x) em) em)
            (not (= (& (first x) (- (<< 1 52) 1)) 0))
            #f))
        #f))
    (method inf? (self (param x ANY "Value to test"))
      (doc "Is x a float infinity, either sign? #f for every non-float."
        (returns BOOL "#t only for an infinite float")
        (sample "(Float inf? (/ 1.0 0.0))" "#t"))
      (if (float? x)
        (let ((em (<< 2047 52)))
          (if (= (& (first x) em) em)
            (= (& (first x) (- (<< 1 52) 1)) 0)
            #f))
        #f))
    (method finite? (self (param x ANY "Value to test"))
      (doc "Is x a finite number? #t for machine INTs and finite floats; #f for float inf/NaN and for everything else (rational/bigint instances answer through their own classes)."
        (returns BOOL "#t for machine ints and finite floats")
        (sample "(Float finite? 42)" "#t"))
      (match
        ((float? x)
         (let ((em (<< 2047 52)))
           (not (= (& (first x) em) em))))
        ((number? x) #t)
        (#t #f)))))

; Value dispatch (subject-last): (3.14 float?) -> (Float float? 3.14).
(def %type-push-call (prim-ref 'type 'push-call))
(%type-push-call (%type-by-atom float) (class-call-handler Float))

; Join the pact last, once the module is fully usable: any registration
; waiting on float fires against the finished class and type ops.
(Pact join 'float float)

(doc (provide x/num/float Float
  float float? float-of float-type ensure-float
  f-add f-sub f-mul f-div f-mod f-eq f-lt fsin fcos fsqrt fatan2 str->float int->float pi
  float-frac float-first-frac float-int-digits float-neg-int libm-fn)
  (note "Literal syntax: 3.14. The generic operators dispatch float operands")
  (note "through the type ops; mixed operands resolve by the from-relation.")
  (example "(+ 1 3.14)" "4.14")
  "IEEE 754 floating-point arithmetic, homed on the Float class.")
