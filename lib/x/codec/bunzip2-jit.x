; bunzip2-jit.x -- the compiled loops behind Bunzip2.
;
; Loaded lazily by x/codec/bunzip2, as x/codec/inflate-jit is by Inflate:
; this module pulls the JIT toolchain, and the codec must stay loadable and
; correct on a host with no JIT.  The pure-x decoder in bunzip2.x is the
; reference and the fallback; this engine replaces its three loops that run
; once a symbol or a byte -- the coded symbols into the block buffer, the
; links of the inverse transform, and the walk back to the bytes -- and is
; adopted only after it agrees with the reference on the check streams.
;
; Each loop is one compiled step over a scratch of words, which calls itself
; until a budget of steps is spent and returns to its driver here, in x.  The
; symbols step does one thing a step: decode a symbol, write up to sixteen of
; a run's copies, or move up to eight move-to-front entries, a mode word
; saying which.  The walk step follows an entry and writes up to sixteen of
; the bytes it owes; it returns early when the output has less than 256
; bytes of room, and its driver grows the output and runs it again.  Headers
; and tables stay in x.
(module x/codec/bunzip2-jit)

(import x/tool/compile compile-asm)

(def %bj-make-str (prim-ref (lit str) (lit make)))
(def %bj-str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %bj-ptr->int (prim-ref (lit ptr) (lit ->int)))
(def %bj-pset (prim-ref (lit ptr) (lit set-word!)))
(def %bj-pref (prim-ref (lit ptr) (lit ref-word)))
(def %bj-oref (prim-ref (lit obj) (lit ref)))
(def %bj-oset! (prim-ref (lit obj) (lit set!)))
(def %bj-xor (prim-ref (lit int) (lit ^)))

; scratch layout (words)
(def %IN 0)         ; input address
(def %INLEN 1)
(def %INCNT 2)
(def %BB 3)         ; bits read ahead, most significant first
(def %BC 4)         ; and how many
(def %ST 5)         ; 0 running, 1 done, 2 return to the driver, <0 error
(def %STEPS 6)
(def %BUDGET 7)
(def %DBUF 8)       ; the block buffer's address, its size, entries written
(def %DSIZE 9)
(def %N 10)
(def %SEL 11)       ; the selectors' address and count, the next one
(def %NSEL 12)
(def %SN 13)
(def %NGROUPS 14)
(def %LEFT 15)      ; symbols left in the group in hand
(def %G 16)         ; that group's table, a word index
(def %RUN 17)       ; a run's place value, 0 outside one
(def %CNT 18)       ; and its count
(def %EOB 19)
(def %MODE 20)      ; symbols: 0 decode, 1 move-to-front, 2 run fill, 3 a symbol to place
(def %SYM 21)
(def %V 22)
(def %LEN 23)
(def %K 24)
(def %I 25)
(def %U 26)
(def %FILLB 27)
(def %FILLEND 28)
(def %OUT 29)       ; walk: output address, its size, bytes written
(def %CAP 30)
(def %OCNT 31)
(def %POS 32)
(def %CUR 33)
(def %CD 34)
(def %CRC 35)
(def %COPIES 36)
(def %TMP 37)
(def %COUNTS 64)    ; 256: each byte's count
(def %MTF 320)      ; 256: the move-to-front list
(def %SYMBYTE 576)  ; 256: symbol to byte
(def %CT 832)       ; 256: the CRC table
(def %GROUPS 1088)  ; six groups of %GSIZE
(def %GSIZE 308)    ; minlen, maxlen, limit (23), base (23), permute (258)
(def %GLIMIT 2)
(def %GBASE 25)
(def %GPERM 48)
(def %WORDS (+ %GROUPS (* 6 %GSIZE)))

(def %M32 4294967295)
(def %M40 1099511627775)

; What an error status means; -1 is a short read.
(def %bj-error
  (fn (_ st)
    (match
      ((= st -1) "the input ends inside the stream")
      ((= st -2) "more symbols than selectors")
      ((= st -3) "a selector past the groups")
      ((= st -4) "a code no table holds")
      ((= st -5) "a run past the block's size")
      ((= st -6) "a block longer than its size")
      (#t "an unknown engine status"))))

; --- expression builders (generation time) ---
(def %M (fn (_ k) (list '%mem-ref 'a k)))
(def %S (fn (_ k v) (list '%mem-set! 'a k v)))
(def %MA (fn (_ e) (list '%mem-ref-at 'a e)))
(def %SA (fn (_ e v) (list '%mem-set-at! 'a e v)))
(def %fail (fn (_ st) (list 'do (list 'if (list '< (%M %ST) 0) 0 (%S %ST st)) 0)))

; One more input byte below the bits held, or, at the end of the input, the
; error status and eight zero bits.
(def %bj-refill
  (list 'if (list '< (%M %INCNT) (%M %INLEN))
    (list 'do
      (%S %BB (list '& (list '| (list '<< (%M %BB) 8) (list '%mem-byte-ref-at (%M %IN) (%M %INCNT))) %M40))
      (%S %INCNT (list '+ (%M %INCNT) 1))
      (%S %BC (list '+ (%M %BC) 8)))
    (list 'do (%S %ST -1) (%S %BB (list '& (list '<< (%M %BB) 8) %M40)) (%S %BC (list '+ (%M %BC) 8)))))

; The next step, or a return to the driver when the budget is spent.
(def %bj-continue
  (list 'if (list '>= (%M %STEPS) (%M %BUDGET))
    (list 'do (%S %ST 2) 0)
    (list 'do (%S %STEPS (list '+ (%M %STEPS) 1)) (list 'self 'a))))

; The group in hand's word k.
(def %GW (fn (_ k) (%MA (list '+ (%M %G) k))))

; LEN raised from minlen until V is within limit[LEN]: a level per length.
(def %bj-length
  (fn (self k)
    (if (> k 21) 0
      (list 'if (list '> (%M %V) (%MA (list '+ (list '+ (%M %G) %GLIMIT) (%M %LEN))))
        (list 'do (%S %LEN (list '+ (%M %LEN) 1)) (self (+ k 1)))
        0))))

; A symbol of the group in hand into SYM, or an error status.
(def %bj-decode
  (list 'do
    (list 'if (list '= (%M %LEFT) 0)
      (list 'if (list '>= (%M %SN) (%M %NSEL)) (%fail -2)
        (list 'do
          (%S %K (list '%mem-byte-ref-at (%M %SEL) (%M %SN)))
          (list 'if (list '>= (%M %K) (%M %NGROUPS)) (%fail -3)
            (list 'do
              (%S %G (list '+ %GROUPS (list '* (%M %K) %GSIZE)))
              (%S %SN (list '+ (%M %SN) 1))
              (%S %LEFT 50)))))
      0)
    (list 'if (list '< (%M %ST) 0) 0
      (list 'do
        (list 'if (list '< (%M %BC) (%GW 1)) %bj-refill 0)
        (list 'if (list '< (%M %BC) (%GW 1)) %bj-refill 0)
        (list 'if (list '< (%M %BC) (%GW 1)) %bj-refill 0)
        (%S %V (list '& (list '>> (%M %BB) (list '- (%M %BC) (%GW 1))) (list '- (list '<< 1 (%GW 1)) 1)))
        (%S %LEN (%GW 0))
        (%bj-length 0)
        (list 'if (list '> (%M %LEN) (%GW 1)) (%fail -4)
          (list 'do
            (%S %BC (list '- (%M %BC) (%M %LEN)))
            (%S %K (list '- (list '>> (%M %V) (list '- (%GW 1) (%M %LEN)))
                            (%MA (list '+ (list '+ (%M %G) %GBASE) (%M %LEN)))))
            (list 'if (list '< (%M %K) 0) (%fail -4)
              (list 'if (list '> (%M %K) 257) (%fail -4)
                (list 'do
                  (%S %SYM (%MA (list '+ (list '+ (%M %G) %GPERM) (%M %K))))
                  (%S %LEFT (list '- (%M %LEFT) 1)))))))))))

; Mode 0: a symbol decoded; a run symbol added to the run, any other one
; placed, after the run it ends is written out.
(def %bj-mode-decode
  (list 'do
    %bj-decode
    (list 'if (list '< (%M %ST) 0) 0
      (list 'if (list '< (%M %SYM) 2)
        (list 'do
          (list 'if (list '= (%M %RUN) 0) (list 'do (%S %RUN 1) (%S %CNT 0)) 0)
          (%S %CNT (list '+ (%M %CNT) (list '<< (%M %RUN) (%M %SYM))))
          (list 'if (list '< (%M %RUN) (%M %DSIZE)) (%S %RUN (list '<< (%M %RUN) 1)) 0)
          %bj-continue)
        (list 'if (list '= (%M %RUN) 0)
          (list 'do (%S %MODE 3) %bj-continue)
          (list 'do
            (%S %FILLEND (list '+ (%M %N) (%M %CNT)))
            (list 'if (list '> (%M %FILLEND) (%M %DSIZE)) (%fail -5)
              (list 'do
                (%S %FILLB (%MA (list '+ %SYMBYTE (%M %MTF))))
                (%SA (list '+ %COUNTS (%M %FILLB)) (list '+ (%MA (list '+ %COUNTS (%M %FILLB))) (%M %CNT)))
                (%S %RUN 0)
                (%S %MODE 2)
                %bj-continue))))))))

; Mode 2: up to sixteen of the run's copies written; done, the symbol that
; ended it is placed.
(def %bj-mode-fill
  (pair 'do
    (List append
      ((fn (self j)
         (if (= j 16) ()
           (pair
             (list 'if (list '< (%M %N) (%M %FILLEND))
               (list 'do
                 (list '%mem-set-at! (%M %DBUF) (%M %N) (%M %FILLB))
                 (%S %N (list '+ (%M %N) 1)))
               0)
             (self (+ j 1)))))
       0)
      (list
        (list 'if (list '>= (%M %N) (%M %FILLEND)) (%S %MODE 3) 0)
        %bj-continue))))

; Mode 3: the end symbol ends the block; any other one names the
; move-to-front entry to bring forward.
(def %bj-mode-place
  (list 'if (list '>= (%M %SYM) (%M %EOB)) (list 'do (%S %ST 1) 0)
    (list 'if (list '>= (%M %N) (%M %DSIZE)) (%fail -6)
      (list 'do
        (%S %I (list '- (%M %SYM) 1))
        (%S %U (%MA (list '+ %MTF (%M %I))))
        (%S %MODE 1)
        %bj-continue))))

; Mode 1: up to eight entries moved up one; at the front, the entry placed
; there and its byte written.
(def %bj-mode-mtf
  (pair 'do
    (List append
      ((fn (self j)
         (if (= j 8) ()
           (pair
             (list 'if (list '> (%M %I) 0)
               (list 'do
                 (%SA (list '+ %MTF (%M %I)) (%MA (list '+ %MTF (list '- (%M %I) 1))))
                 (%S %I (list '- (%M %I) 1)))
               0)
             (self (+ j 1)))))
       0)
      (list
        (list 'if (list '= (%M %I) 0)
          (list 'do
            (%S %MODE 0)
            (%SA %MTF (%M %U))
            (%S %TMP (%MA (list '+ %SYMBYTE (%M %U))))
            (%SA (list '+ %COUNTS (%M %TMP)) (list '+ (%MA (list '+ %COUNTS (%M %TMP))) 1))
            (list '%mem-set-at! (%M %DBUF) (%M %N) (%M %TMP))
            (%S %N (list '+ (%M %N) 1)))
          0)
        %bj-continue))))

(def %bj-symbols-expr
  (list 'fn '(self a)
    (list 'if (list '< (%M %ST) 0) 0
      (list 'if (list '= (%M %MODE) 0) %bj-mode-decode
        (list 'if (list '= (%M %MODE) 1) %bj-mode-mtf
          (list 'if (list '= (%M %MODE) 2) %bj-mode-fill
            %bj-mode-place))))))

; The links: eight entries a step, each entry's index set into the upper
; bits of the entry its byte sorts to.
(def %bj-link-expr
  (list 'fn '(self a)
    (pair 'do
      (List append
        ((fn (self j)
           (if (= j 8) ()
             (pair
               (list 'if (list '< (%M %I) (%M %N))
                 (list 'do
                   (%S %TMP (list '& (list '%mem-ref-at (%M %DBUF) (%M %I)) 255))
                   (%S %K (%MA (list '+ %COUNTS (%M %TMP))))
                   (list '%mem-set-at! (%M %DBUF) (%M %K)
                     (list '| (list '%mem-ref-at (%M %DBUF) (%M %K)) (list '<< (%M %I) 8)))
                   (%SA (list '+ %COUNTS (%M %TMP)) (list '+ (%M %K) 1))
                   (%S %I (list '+ (%M %I) 1)))
                 0)
               (self (+ j 1)))))
         0)
        (list
          (list 'if (list '>= (%M %I) (%M %N)) (list 'do (%S %ST 1) 0) %bj-continue))))))

; Up to sixteen of the copies owed of CUR written, the CRC over each.
(def %bj-emit
  (pair 'do
    ((fn (self j)
       (if (= j 16) ()
         (pair
           (list 'if (list '> (%M %COPIES) 0)
             (list 'do
               (list '%mem-byte-set-at! (%M %OUT) (%M %OCNT) (%M %CUR))
               (%S %OCNT (list '+ (%M %OCNT) 1))
               (%S %CRC (list '^ (list '& (list '<< (%M %CRC) 8) %M32)
                              (%MA (list '+ %CT (list '& (list '^ (list '>> (%M %CRC) 24) (%M %CUR)) 255)))))
               (%S %COPIES (list '- (%M %COPIES) 1)))
             0)
           (self (+ j 1)))))
     0)))

; The next entry followed: after four bytes alike, the byte is a count of
; more copies; otherwise it is the next byte, one copy owed.
(def %bj-follow
  (list 'do
    (%S %TMP (list '%mem-ref-at (%M %DBUF) (%M %POS)))
    (%S %POS (list '>> (%M %TMP) 8))
    (%S %TMP (list '& (%M %TMP) 255))
    (%S %LEFT (list '- (%M %LEFT) 1))
    (%S %CD (list '- (%M %CD) 1))
    (list 'if (list '= (%M %CD) 0)
      (list 'do (%S %CD 5) (%S %COPIES (%M %TMP)))
      (list 'do
        (list 'if (list '= (%M %TMP) (%M %CUR)) 0 (%S %CD 4))
        (%S %CUR (%M %TMP))
        (%S %COPIES 1)))))

(def %bj-walk-expr
  (list 'fn '(self a)
    (list 'do
      %bj-emit
      (list 'if (list '> (%M %COPIES) 0) %bj-continue
        (list 'if (list '= (%M %LEFT) 0) (list 'do (%S %ST 1) 0)
          (list 'if (list '> (list '+ (%M %OCNT) 256) (%M %CAP)) (list 'do (%S %ST 2) 0)
            (list 'do %bj-follow %bj-emit %bj-continue)))))))

; Steps a call may take before it returns: each one is a frame.
(def %bj-budget 256)

; --- build: compile, wire the drivers, and PROVE them against the reference ---
;
; state: bunzip2.x's slot numbers for its decoder state, as an alist
;        (in inlen incnt bitbuf bitcnt dbufp dbufsize out outp outcap outcnt).
; room:  bunzip2.x's (fn (_ s n)), room for n more output bytes.
; crc:   its CRC table, a vector whose slot i+1 holds byte i's entry.
; check: (fn (_ engine) -> #t) -- runs the reference's check streams through
;        a candidate (SYMBOLS LINK WALK) and answers whether every output
;        and CRC agreed with the reference's own.
;
; Answers (SYMBOLS LINK WALK), drop-ins for bunzip2.x's %decode-symbols!,
; %link! and %walk-block!.  Or raises: on a host with no assembler backend, a
; toolchain error, or any disagreement.  The caller guards; a raise means
; "stay pure-x".
(def bunzip2-jit-make
  (fn (_ state room crc check)
    (def %sym-step (compile-asm %bj-symbols-expr))
    (def %link-step (compile-asm %bj-link-expr))
    (def %walk-step (compile-asm %bj-walk-expr))
    (Heap collect)
    (def %buf (%bj-make-str (* 8 %WORDS)))
    (def %ptr (%bj-str->ptr %buf))
    (def %addr (%bj-ptr->int %ptr))
    (def %poke (fn (_ i v) (%bj-pset %ptr (* i 8) v)))
    (def %peek (fn (_ i) (%bj-pref %ptr (* i 8))))
    (def %slot (fn (_ name) (rest (Assoc entry name state))))
    ((fn (self i) (when (< i 256) (do (%poke (+ %CT i) (%bj-oref crc (+ i 1))) (self (+ i 1))))) 0)
    ; runs a step until it is done, or raises on its error
    (def %drive
      (fn (self step)
        (%poke %STEPS 0)
        (%poke %BUDGET %bj-budget)
        (%poke %ST 0)
        (step %addr)
        (match
          ((= (%peek %ST) 2) (self step))
          ((= (%peek %ST) 1) ())
          (#t (Err raise (lit value)
                (Str8 append "Bunzip2: " (%bj-error (%peek %ST)))
                (if (= (%peek %ST) -1)
                  (list (pair (lit bunzip) (lit data)) (pair (lit short) #t))
                  (list (pair (lit bunzip) (lit data)))))))))
    ; a vector's slots 1..n poked from word base on
    (def %load!
      (fn (self v base i n)
        (when (< i n) (do (%poke (+ base i) (%bj-oref v (+ i 1))) (self v base (+ i 1) n)))))
    (def %load-group!
      (fn (_ g base)
        (%poke base (first g))
        (%poke (+ base 1) (first (rest g)))
        (%load! (first (rest (rest g))) (+ base %GLIMIT) 0 23)
        (%load! (first (rest (rest (rest g)))) (+ base %GBASE) 0 23)
        (%load! (first (rest (rest (rest (rest g))))) (+ base %GPERM) 0 258)))
    (def %symbols
      (fn (_ s groups ngroups sel nsel sym->byte total counts)
        ((fn (self j) (when (< j ngroups) (do (%load-group! (%bj-oref groups (+ j 1)) (+ %GROUPS (* j %GSIZE))) (self (+ j 1))))) 0)
        (%load! sym->byte %SYMBYTE 0 256)
        ((fn (self i) (when (< i 256) (do (%poke (+ %MTF i) i) (%poke (+ %COUNTS i) 0) (self (+ i 1))))) 0)
        (%poke %IN (%bj-ptr->int (%bj-oref s (%slot (lit in)))))
        (%poke %INLEN (%bj-oref s (%slot (lit inlen))))
        (%poke %INCNT (%bj-oref s (%slot (lit incnt))))
        (%poke %BB (%bj-oref s (%slot (lit bitbuf))))
        (%poke %BC (%bj-oref s (%slot (lit bitcnt))))
        (%poke %DBUF (%bj-ptr->int (%bj-oref s (%slot (lit dbufp)))))
        (%poke %DSIZE (%bj-oref s (%slot (lit dbufsize))))
        (%poke %N 0)
        (%poke %SEL (%bj-ptr->int sel))
        (%poke %NSEL nsel)
        (%poke %SN 0)
        (%poke %NGROUPS ngroups)
        (%poke %LEFT 0)
        (%poke %RUN 0)
        (%poke %CNT 0)
        (%poke %EOB (+ total 1))
        (%poke %MODE 0)
        (%drive %sym-step)
        (%bj-oset! s (%slot (lit incnt)) (%peek %INCNT))
        (%bj-oset! s (%slot (lit bitbuf)) (%peek %BB))
        (%bj-oset! s (%slot (lit bitcnt)) (%peek %BC))
        ((fn (self i) (when (< i 256) (do (%bj-oset! counts (+ i 1) (%peek (+ %COUNTS i))) (self (+ i 1))))) 0)
        (%peek %N)))
    (def %link
      (fn (_ s counts n)
        ((fn (self i j)
           (when (< i 256)
             (do (%poke (+ %COUNTS i) j) (self (+ i 1) (+ j (%bj-oref counts (+ i 1)))))))
         0 0)
        (%poke %DBUF (%bj-ptr->int (%bj-oref s (%slot (lit dbufp)))))
        (%poke %N n)
        (%poke %I 0)
        (%drive %link-step)))
    (def %walk
      (fn (_ s pos cur n)
        (%poke %DBUF (%bj-ptr->int (%bj-oref s (%slot (lit dbufp)))))
        (%poke %POS pos)
        (%poke %CUR cur)
        (%poke %LEFT n)
        (%poke %CD 5)
        (%poke %CRC %M32)
        (%poke %COPIES 0)
        ((fn (self)
           (do (room s 4096)
               (%poke %OUT (%bj-ptr->int (%bj-oref s (%slot (lit outp)))))
               (%poke %CAP (%bj-oref s (%slot (lit outcap))))
               (%poke %OCNT (%bj-oref s (%slot (lit outcnt))))
               (%poke %STEPS 0)
               (%poke %BUDGET %bj-budget)
               (%poke %ST 0)
               (%walk-step %addr)
               (%bj-oset! s (%slot (lit outcnt)) (%peek %OCNT))
               (when (= (%peek %ST) 2) (self)))))
        (%bj-xor (%peek %CRC) %M32)))
    (def engine (list %symbols %link %walk))
    (unless (check engine)
      (Err raise (lit state) "bunzip2-jit: engine disagrees with the pure-x decoder" ()))
    ; the scratch is held by the drivers' closures
    (list (fn (_ s groups ngroups sel nsel sym->byte total counts)
            (do %buf (%symbols s groups ngroups sel nsel sym->byte total counts)))
          %link %walk)))

; The codec reaches the maker through the catalogue: it loads this module
; inside the function that builds the engine, where an import is one the
; linter cannot see.
(prim-reg! (lit bunzip2) (lit jit-make) bunzip2-jit-make)

(doc (provide x/codec/bunzip2-jit bunzip2-jit-make)
  "The compiled loops behind Bunzip2 (JIT, ARM64 and x86-64 backends): the coded symbols, the inverse transform's links and its walk, built and adopted only after agreeing with the pure-x decoder.")
