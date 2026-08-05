; bench-sha256.x -- where a SHA-256 digest's time actually goes.
;
;   sh x.sh --no-pin -q -f tools/dev/bench-sha256.x -- [--parts] [--unroll N] [--size BYTES]
;
; Two reports, one harness -- they share the buffer layout, the round-body
; builder and the block driver, so splitting them into two files would
; mean copying all three.
;
;   (default)  compile the round loop, verify the FIPS vectors, and time
;              a digest end to end.
;   --parts    additionally time the digest's parts SEPARATELY over the
;              same block count: the compiled round loop, the interpreted
;              W fill, and the interpreted H shuffles.
;
; The --parts report is the one that matters, and it exists because
; guessing was wrong by two orders of magnitude.  The JIT work through
; #189-#195 sharpened the compiled round loop; --parts showed that loop
; to be 0.9% of a 25KB digest against 92.5% for the interpreted W fill.
; Optimising by intuition would have kept polishing the 0.9%.  Run this
; BEFORE optimising anything here, and believe it over the intuition.
;
; --unroll N emits N round bodies per recursive call, amortising the
; per-call argument boxing over N.  It is a knob for RE-MEASURING, not a
; recommendation: 1/2/4 measured 4.00s/3.92s/3.97s on a 25KB input --
; noise, because the boxing it removes is a fraction of that 0.9% -- and
; 8 trips the allocation ceiling while tripling compile time.  The
; unrolled shape is kept here, and only here, so the negative result
; stays reproducible instead of being re-derived from scratch.
;
; Input is synthetic and content-independent: SHA-256 does identical work
; per block whatever the bytes are, so a generated buffer keeps the
; benchmark reproducible and free of any build artifact.  The reference
; numbers above were taken at --size 25000.

(do
  (import x/tool/compile)
  (import x/codec/sha256)
  (import x/tool/contract)

  (Contract alloc-guard!)

  (def %make-str (prim-ref (lit str) (lit make)))
  (def %str->ptr (prim-ref (lit str) (lit ->ptr)))
  (def %ptr->int (prim-ref (lit ptr) (lit ->int)))
  (def %pset (prim-ref (lit ptr) (lit set-word!)))
  (def %pref (prim-ref (lit ptr) (lit ref-word)))
  (def %clock (prim-ref (lit sys) (lit clock)))
  (def %M 4294967295)

  ; --- args: [--parts] [--unroll N] [--size BYTES] ---
  (def %argv (Contract argv))
  (def %flag?
    (fn (self name av)
      (match ((null? av) #f) ((str=? (first av) name) #t) (#t (self name (rest av))))))
  (def %opt
    (fn (self name av dflt)
      (match
        ((null? av) dflt)
        ((and (str=? (first av) name) (pair? (rest av)))
          (%str->number (first (rest av)) 10))
        (#t (self name (rest av) dflt)))))
  (def %parts? (%flag? "--parts" %argv))
  (def %unroll (%opt "--unroll" %argv 1))
  (def %size (%opt "--size" %argv 25000))
  ; 64 rounds have to divide evenly into groups, or the loop steps past
  ; its own terminator and runs forever.
  (unless (= 0 (% 64 %unroll))
    (do (%stderr "bench-sha256: --unroll must divide 64 (1 2 4 8 16 32 64)\n")
        (Sys exit 1)))

  ; layout: 0..15 W | 16..23 a..h | 24 t1 25 t2 | 32..95 K | 96..103 H
  (def %KB 32)
  (def %HB 96)
  (def %buf (%make-str 1024))
  (def %ptr (%str->ptr %buf))
  (def %addr (%ptr->int %ptr))
  (def %poke (fn (_ i v) (%pset %ptr (* i 8) v)))
  (def %peek (fn (_ i) (%pref %ptr (* i 8))))

  ; --- round body, built as an expression at generation time ---
  (def %C  (fn (_ i) (list '%mem-ref 'a i)))
  (def %AT (fn (_ e) (list '%mem-ref-at 'a e)))
  (def %setC (fn (_ i v) (list '%mem-set! 'a i v)))
  (def %setAT (fn (_ e v) (list '%mem-set-at! 'a e v)))
  (def %rotr (fn (_ x n) (list '& (list '| (list '>> x n) (list '<< x (- 32 n))) %M)))
  (def %bs0 (fn (_ x) (list '^ (%rotr x 2)  (list '^ (%rotr x 13) (%rotr x 22)))))
  (def %bs1 (fn (_ x) (list '^ (%rotr x 6)  (list '^ (%rotr x 11) (%rotr x 25)))))
  (def %ss0 (fn (_ x) (list '^ (%rotr x 7)  (list '^ (%rotr x 18) (list '>> x 3)))))
  (def %ss1 (fn (_ x) (list '^ (%rotr x 17) (list '^ (%rotr x 19) (list '>> x 10)))))
  (def %ch  (fn (_ x y z) (list '^ (list '& x y) (list '& (list '& (list '~ x) %M) z))))
  (def %maj (fn (_ x y z) (list '^ (list '& x y) (list '^ (list '& x z) (list '& y z)))))
  (def %m32 (fn (_ e) (list '& e %M)))
  (def %A (%C 16)) (def %B (%C 17)) (def %Cc (%C 18)) (def %D (%C 19))
  (def %E (%C 20)) (def %F (%C 21)) (def %G (%C 22)) (def %H (%C 23))

  ; The round index as an EXPRESSION: unrolled round k reads (+ t k).
  ; k=0 stays plain `t`, so --unroll 1 emits no wasted add and is a true
  ; baseline rather than a baseline-plus-overhead.
  (def %te (fn (_ k) (if (= k 0) 't (list '+ 't k))))
  (def %w (fn (_ te off) (%AT (list '& (list '- te off) 15))))
  (def %extend-for
    (fn (_ te)
      (%setAT (list '& te 15)
        (%m32 (list '+ (list '+ (%ss1 (%w te 2)) (%w te 7))
                       (list '+ (%ss0 (%w te 15)) (%w te 16)))))))
  (def %round-for
    (fn (_ te)
      (list 'do
        (list 'if (list '< te 16) 0 (%extend-for te))
        (%setC 24 (%m32 (list '+ (list '+ %H (%bs1 %E))
                                  (list '+ (%ch %E %F %G)
                                        (list '+ (%AT (list '+ %KB te))
                                              (%AT (list '& te 15)))))))
        (%setC 25 (%m32 (list '+ (%bs0 %A) (%maj %A %B %Cc))))
        (%setC 23 %G) (%setC 22 %F) (%setC 21 %E)
        (%setC 20 (%m32 (list '+ %D (%C 24))))
        (%setC 19 %Cc) (%setC 18 %B) (%setC 17 %A)
        (%setC 16 (%m32 (list '+ (%C 24) (%C 25)))))))
  (def %bodies
    (fn (self k)
      (if (= k %unroll)
        (list (list 'self 'a (list '+ 't %unroll)))
        (pair (%round-for (%te k)) (self (+ k 1))))))
  (def %rounds-expr
    (list 'fn '(self a t)
      (list 'if (list '= 't 64) 0 (pair 'do (%bodies 0)))))

  (def %node-count
    (fn (self e) (if (pair? e) (+ (self (first e)) (self (rest e))) 1)))
  (display "unroll ")(display %unroll)
  (display "   nodes ")(display (%node-count %rounds-expr))(newline)
  (def %t-compile (%clock))
  (def %rounds (compile-asm %rounds-expr))
  (set! %t-compile (- (%clock) %t-compile))
  (display "compile        ")(display %t-compile)(display " us")(newline)

  ; --- x-lang side: K table, H init, block driver ---
  ((fn (self i)
     (match ((= i 64) ())
       (#t (do (%poke (+ %KB i) (%sha-oref %sha-k (+ i 1))) (self (+ i 1)))))) 0)
  (def %init-h
    (fn (_)
      ((fn (self i hs)
         (match ((null? hs) ())
           (#t (do (%poke (+ %HB i) (first hs)) (self (+ i 1) (rest hs)))))) 0 %sha-ih)))
  (def %fill-w
    (fn (_ s len total base)
      ((fn (self t)
         (match ((= t 16) ())
           (#t (do (%poke t (%sha-word s len total (%sha+ base (<< t 2))))
                   (self (%sha+ t 1)))))) 0)))
  (def %load-h
    (fn (_) ((fn (self i)
      (match ((= i 8) ()) (#t (do (%poke (+ 16 i) (%peek (+ %HB i))) (self (+ i 1)))))) 0)))
  (def %store-h
    (fn (_) ((fn (self i)
      (match ((= i 8) ())
        (#t (do (%poke (+ %HB i) (& (%sha+ (%peek (+ %HB i)) (%peek (+ 16 i))) %M))
                (self (+ i 1)))))) 0)))
  (def %block
    (fn (_ s len total base)
      (%fill-w s len total base)
      (%load-h)
      (%rounds %addr 0)
      (%store-h)))
  (def %blocks-of (fn (_ len) (<< (%sha+ (>> (%sha+ len 8) 6) 1) 6)))
  (def %digest
    (fn (_ s)
      (def len (Str8 length s))
      (def total (%blocks-of len))
      (%init-h)
      ((fn (self b)
         (match ((= b total) ()) (#t (do (%block s len total b) (self (%sha+ b 64)))))) 0)
      ((fn (self i acc)
         (match ((= i 8) acc)
           (#t (self (+ i 1)
                 (Str8 append acc
                   (Str pad-left 8 #\0 (%cvt (%peek (+ %HB i)) %string 16))))))) 0 "")))

  ; --- correctness before speed: a fast wrong digest is worth nothing ---
  (def %vec
    (fn (_ label s want)
      (def got (%digest s))
      (display label)(display (if (str=? got want) "ok" "WRONG"))(newline)
      (if (not (str=? got want))
        (Err raise 'state (Str8 append "bench-sha256: vector failed: " label) ()))))
  (%vec "vector abc     " "abc"
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  (%vec "vector empty   " ""
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
  (%vec "vector 56-byte " "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
    "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")

  ; --- throughput ---
  (def %input (%make-str %size))
  (def %len (Str8 length %input))
  (def %total (%blocks-of %len))
  (def %nblocks (>> %total 6))
  (display "input          ")(display %size)
  (display " bytes, ")(display %nblocks)(display " blocks")(newline)
  (def %t-digest (%clock))
  (%digest %input)
  (set! %t-digest (- (%clock) %t-digest))
  (display "digest         ")(display %t-digest)(display " us")(newline)

  ; --- the attribution report ---
  ; Each part runs over the SAME block count as the digest above, so the
  ; three numbers are comparable to it and should roughly sum to it.  A
  ; sum well under the total means something outside these three is
  ; paying, and THAT is the next thing to look at.
  (when %parts?
    (do
      (%init-h)
      (def %t-rounds (%clock))
      ((fn (self b)
         (match ((= b %nblocks) ()) (#t (do (%rounds %addr 0) (self (+ b 1)))))) 0)
      (set! %t-rounds (- (%clock) %t-rounds))

      (def %t-fill (%clock))
      ((fn (self b)
         (match ((= b %nblocks) ())
           (#t (do (%fill-w %input %len %total (<< b 6)) (self (+ b 1)))))) 0)
      (set! %t-fill (- (%clock) %t-fill))

      (def %t-shuffle (%clock))
      ((fn (self b)
         (match ((= b %nblocks) ()) (#t (do (%load-h) (%store-h) (self (+ b 1)))))) 0)
      (set! %t-shuffle (- (%clock) %t-shuffle))

      (newline)
      (display "  compiled rounds   ")(display %t-rounds)(display " us")(newline)
      (display "  W fill            ")(display %t-fill)(display " us")(newline)
      (display "  H shuffles        ")(display %t-shuffle)(display " us")(newline)
      (display "  sum of parts      ")
      (display (+ %t-rounds (+ %t-fill %t-shuffle)))(display " us")(newline))))
