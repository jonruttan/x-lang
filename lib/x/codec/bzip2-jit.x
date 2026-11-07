; bzip2-jit.x -- the compiled loops behind Bzip2.
;
; Loaded lazily by x/codec/bzip2, as x/codec/deflate-jit is by Deflate: this
; module pulls the JIT toolchain, and the codec must stay loadable and
; correct on a host with no JIT.  The pure-x encoder in bzip2.x is the
; reference and the fallback; this engine replaces its five loops that run
; once a byte or a symbol -- the input's runs into the block, the sort, the
; move-to-front values, the selection of a table for each group, and the
; writing of the symbols -- and is adopted only after the streams it writes
; for the codec's check inputs are byte for byte the reference's.
;
; Each loop is one compiled function over a scratch of words, its loops
; self-calls in tail position, which the compiler makes jumps: a whole
; block is one call.  A phase argument says which loop it is in.  The
; tables and the sort's arrays are bzip2.x's own regions, reached through
; their addresses in the scratch.
(module x/codec/bzip2-jit)

(import x/tool/compile compile-asm)

(import x/core/doors obj-ref obj-set! ptr->int ptr-ref-word ptr-set-word! str->ptr str-make)

; scratch layout (words)
(def %BLOCK 0)     ; the block's address, its count and limit
(def %N 1)
(def %NBMAX 2)
(def %INCH 3)      ; the run in hand
(def %INRUN 4)
(def %CRC 5)
(def %TAB 6)       ; the shared tables' address
(def %IN 7)        ; the input's address and end
(def %END 8)
(def %FM 9)        ; the sort's order, classes and heads
(def %EC 10)
(def %BH 11)
(def %OUT 12)      ; the output's address and count, the bits not yet a byte
(def %OCNT 13)
(def %BB 14)
(def %BL 15)
(def %SEL 16)      ; the selectors' address, the symbol and table counts
(def %NMTF 17)
(def %NGROUPS 18)
(def %H 19)        ; the sort's round, scan and quicksort state
(def %R 20)
(def %NOTDONE 21)
(def %K 22)
(def %L 23)
(def %RR 24)
(def %LO 25)
(def %HI 26)
(def %SP 27)
(def %RND 28)
(def %MED 29)
(def %LTLO 30)
(def %UNLO 31)
(def %UNHI 32)
(def %GTHI 33)
(def %NN 34)
(def %MM 35)
(def %I 36)
(def %J 37)
(def %TMP 38)
(def %ECT 39)
(def %CC 40)
(def %P1 41)
(def %P2 42)
(def %CNT 43)
(def %T0 44)
(def %T1 45)
(def %T2 46)
(def %T3 47)
(def %GE 48)
(def %BT 49)
(def %NUSE 50)     ; how many byte values the block uses
(def %STLO 64)     ; the quicksort's stack, 100 ranges
(def %STHI 164)
(def %YY 264)      ; the move-to-front list, 256
(def %COST 520)    ; a group's cost under each table, 6
(def %FTAB 528)    ; the byte counts, 257
(def %WORDS 800)

; bzip2.x's table offsets, words from %TAB
(def %CT 0)
(def %INUSE 256)
(def %UNSEQ 512)
(def %MTFFREQ 768)
(def %LENS 1026)
(def %RFREQ 2574)
(def %CODES 4122)
(def %ASIZE 258)
(def %SELMTF 18016)

(def %M32 4294967295)

; --- expression builders (generation time) ---
(def %M (fn (_ k) (list '%mem-ref 'a k)))
(def %S (fn (_ k v) (list '%mem-set! 'a k v)))
(def %MA (fn (_ e) (list '%mem-ref-at 'a e)))
(def %SA (fn (_ e v) (list '%mem-set-at! 'a e v)))
(def %AT (fn (_ base e) (list '%mem-ref-at (%M base) e)))
(def %AT! (fn (_ base e v) (list '%mem-set-at! (%M base) e v)))
(def %TB (fn (_ off e) (%AT %TAB (list '+ off e))))
(def %TB! (fn (_ off e v) (%AT! %TAB (list '+ off e) v)))
(def %INC (fn (_ k) (%S k (list '+ (%M k) 1))))
(def %DEC (fn (_ k) (%S k (list '- (%M k) 1))))
(def %GO (fn (_ ph) (list 'self 'a ph)))
(def %WHEN (fn (_ c e) (list 'if c e 0)))
(def %NE (fn (_ x y) (list 'if (list '= x y) 0 1)))

; The CRC over byte b.
(def %zj-crc
  (fn (_ b)
    (%S %CRC (list '^ (list '& (list '<< (%M %CRC) 8) %M32)
                   (%TB %CT (list '& (list '^ (list '>> (%M %CRC) 24) b) 255))))))

; --- the input's runs into the block ---
;
; bzip2.x's %take!: phase 0 takes a byte; a run that ends goes to phase 1,
; which runs the CRC over its K copies and then writes it into the block.
; The byte that ended it is at I.  Answers where it stopped.
(def %zj-byte-out
  (fn (_ v)
    (list 'do
      (list '%mem-byte-set-at! (%M %BLOCK) (%M %N) v)
      (%INC %N))))

(def %zj-take-expr
  (list 'fn '(self a ph i k)
    (list 'if (list '= 'ph 0)
      (list 'if (list '>= 'i (%M %END)) 'i
        (list 'if (list '>= (%M %N) (%M %NBMAX)) 'i
          (list 'do
            (%S %T0 (list '%mem-byte-ref-at (%M %IN) 'i))
            (list 'if (list 'if (list '= (%M %T0) (%M %INCH)) (list '< (%M %INRUN) 255) 0)
              (list 'do (%INC %INRUN) (list 'self 'a 0 (list '+ 'i 1) 0))
              (list 'if (list '< (%M %INCH) 256)
                (list 'self 'a 1 'i (%M %INRUN))
                (list 'do (%S %INCH (%M %T0)) (%S %INRUN 1) (list 'self 'a 0 (list '+ 'i 1) 0)))))))
      (list 'if (list '> 'k 0)
        (list 'do (%zj-crc (%M %INCH)) (list 'self 'a 1 'i (list '- 'k 1)))
        (list 'do
          (%TB! %INUSE (%M %INCH) 1)
          (%zj-byte-out (%M %INCH))
          (%WHEN (list '> (%M %INRUN) 1) (%zj-byte-out (%M %INCH)))
          (%WHEN (list '> (%M %INRUN) 2) (%zj-byte-out (%M %INCH)))
          (%WHEN (list '> (%M %INRUN) 3)
            (list 'do
              (%zj-byte-out (%M %INCH))
              (%TB! %INUSE (list '- (%M %INRUN) 4) 1)
              (%zj-byte-out (list '- (%M %INRUN) 4))))
          (%S %INCH (list '%mem-byte-ref-at (%M %IN) 'i))
          (%S %INRUN 1)
          (list 'self 'a 0 (list '+ 'i 1) 0))))))

; --- the sort: bzip2.x's %sort-x, fallbackSort, phase for phase ---
(def %FTB (fn (_ e) (%MA (list '+ %FTAB e))))
(def %FTB! (fn (_ e v) (%SA (list '+ %FTAB e) v)))
(def %FMR (fn (_ e) (%AT %FM e)))
(def %ECR (fn (_ e) (%AT %EC e)))
(def %BHR (fn (_ e) (%AT %BH e)))
(def %BYTE (fn (_ e) (list '%mem-byte-ref-at (%M %BLOCK) e)))

(def %zj-swap
  (fn (_ i j)
    (list 'do
      (%S %TMP (%FMR i))
      (%AT! %FM i (%FMR j))
      (%AT! %FM j (%M %TMP)))))

(def %zj-push
  (fn (_ lo hi)
    (list 'do
      (%SA (list '+ %STLO (%M %SP)) lo)
      (%SA (list '+ %STHI (%M %SP)) hi)
      (%INC %SP))))

; Each phase: (PHASE BODY).  The hot ones first: the chain is walked in
; this order.
(def %zj-sort-phases
  (list
    ; 21: the partition's low scan
    (list 21
      (list 'if (list '> (%M %UNLO) (%M %UNHI)) (%GO 22)
        (list 'do
          (%S %T0 (list '- (%ECR (%FMR (%M %UNLO))) (%M %MED)))
          (list 'if (list '= (%M %T0) 0)
            (list 'do (%zj-swap (%M %UNLO) (%M %LTLO)) (%INC %LTLO) (%INC %UNLO) (%GO 21))
            (list 'if (list '> (%M %T0) 0) (%GO 22)
              (list 'do (%INC %UNLO) (%GO 21)))))))
    ; 22: its high scan
    (list 22
      (list 'if (list '> (%M %UNLO) (%M %UNHI)) (%GO 23)
        (list 'do
          (%S %T0 (list '- (%ECR (%FMR (%M %UNHI))) (%M %MED)))
          (list 'if (list '= (%M %T0) 0)
            (list 'do (%zj-swap (%M %UNHI) (%M %GTHI)) (%DEC %GTHI) (%DEC %UNHI) (%GO 22))
            (list 'if (list '< (%M %T0) 0)
              (list 'do (%zj-swap (%M %UNLO) (%M %UNHI)) (%INC %UNLO) (%DEC %UNHI) (%GO 21))
              (list 'do (%DEC %UNHI) (%GO 22)))))))
    ; 33: insertion by one, the inner loop
    (list 33
      (list 'if (list 'if (list '<= (%M %J) (%M %HI)) (list '> (%M %ECT) (%ECR (%FMR (%M %J)))) 0)
        (list 'do (%AT! %FM (list '- (%M %J) 1) (%FMR (%M %J))) (%INC %J) (%GO 33))
        (list 'do (%AT! %FM (list '- (%M %J) 1) (%M %TMP)) (%DEC %I) (%GO 32))))
    ; 31: insertion by four, the inner loop
    (list 31
      (list 'if (list 'if (list '<= (%M %J) (%M %HI)) (list '> (%M %ECT) (%ECR (%FMR (%M %J)))) 0)
        (list 'do (%AT! %FM (list '- (%M %J) 4) (%FMR (%M %J))) (%S %J (list '+ (%M %J) 4)) (%GO 31))
        (list 'do (%AT! %FM (list '- (%M %J) 4) (%M %TMP)) (%DEC %I) (%GO 30))))
    ; 6: each position's class for the round
    (list 6
      (list 'if (list '>= (%M %I) (%M %N))
        (list 'do (%S %NOTDONE 0) (%S %R -1) (%GO 7))
        (list 'do
          (%WHEN (%NE (%BHR (%M %I)) 0) (%S %J (%M %I)))
          (%S %K (list '- (%FMR (%M %I)) (%M %H)))
          (%WHEN (list '< (%M %K) 0) (%S %K (list '+ (%M %K) (%M %N))))
          (%AT! %EC (%M %K) (%M %J))
          (%INC %I)
          (%GO 6))))
    ; 12: a sorted bucket's heads marked
    (list 12
      (list 'if (list '> (%M %I) (%M %RR))
        (list 'do (%S %R (%M %RR)) (%GO 7))
        (list 'do
          (%S %T0 (%ECR (%FMR (%M %I))))
          (%WHEN (%NE (%M %CC) (%M %T0)) (%AT! %BH (%M %I) 1))
          (%S %CC (%M %T0))
          (%INC %I)
          (%GO 12))))
    ; 8: past the heads to the next bucket's first entry
    (list 8
      (list 'if (%NE (%BHR (%M %K)) 0) (list 'do (%INC %K) (%GO 8))
        (list 'do
          (%S %L (list '- (%M %K) 1))
          (list 'if (list '>= (%M %L) (%M %N)) (%GO 10) (%GO 9)))))
    ; 9: to its end
    (list 9
      (list 'if (list '= (%BHR (%M %K)) 0) (list 'do (%INC %K) (%GO 9))
        (list 'do
          (%S %RR (list '- (%M %K) 1))
          (list 'if (list '>= (%M %RR) (%M %N)) (%GO 10)
            (list 'if (list '< (%M %L) (%M %RR))
              (list 'do
                (%S %NOTDONE (list '+ (%M %NOTDONE) (list '+ (list '- (%M %RR) (%M %L)) 1)))
                (%S %SP 0)
                (%zj-push (%M %L) (%M %RR))
                (%S %RND 0)
                (%GO 20))
              (list 'do (%S %R (%M %RR)) (%GO 7)))))))
    ; 32: insertion by one, the outer loop
    (list 32
      (list 'if (list '< (%M %I) (%M %LO)) (%GO 20)
        (list 'do
          (%S %TMP (%FMR (%M %I)))
          (%S %ECT (%ECR (%M %TMP)))
          (%S %J (list '+ (%M %I) 1))
          (%GO 33))))
    ; 30: insertion by four, the outer loop
    (list 30
      (list 'if (list '< (%M %I) (%M %LO))
        (list 'do (%S %I (list '- (%M %HI) 1)) (%GO 32))
        (list 'do
          (%S %TMP (%FMR (%M %I)))
          (%S %ECT (%ECR (%M %TMP)))
          (%S %J (list '+ (%M %I) 4))
          (%GO 31))))
    ; 20: the quicksort's next range
    (list 20
      (list 'if (list '= (%M %SP) 0)
        (list 'do (%S %I (%M %L)) (%S %CC -1) (%GO 12))
        (list 'do
          (%DEC %SP)
          (%S %LO (%MA (list '+ %STLO (%M %SP))))
          (%S %HI (%MA (list '+ %STHI (%M %SP))))
          (list 'if (list '< (list '- (%M %HI) (%M %LO)) 10)
            (list 'if (list '= (%M %LO) (%M %HI)) (%GO 20)
              (list 'if (list '> (list '- (%M %HI) (%M %LO)) 3)
                (list 'do (%S %I (list '- (%M %HI) 4)) (%GO 30))
                (list 'do (%S %I (list '- (%M %HI) 1)) (%GO 32))))
            (list 'do
              (%S %RND (list '& (list '+ (list '* (%M %RND) 7621) 1) 32767))
              (%S %T0 (list '% (%M %RND) 3))
              (%S %MED (%ECR (%FMR (list 'if (list '= (%M %T0) 0) (%M %LO)
                                     (list 'if (list '= (%M %T0) 1) (list '>> (list '+ (%M %LO) (%M %HI)) 1)
                                       (%M %HI))))))
              (%S %LTLO (%M %LO))
              (%S %UNLO (%M %LO))
              (%S %UNHI (%M %HI))
              (%S %GTHI (%M %HI))
              (%GO 21))))))
    ; 23: the partition done
    (list 23
      (list 'if (list '< (%M %GTHI) (%M %LTLO)) (%GO 20)
        (list 'do
          (%S %NN (list '- (%M %LTLO) (%M %LO)))
          (%WHEN (list '< (list '- (%M %UNLO) (%M %LTLO)) (%M %NN)) (%S %NN (list '- (%M %UNLO) (%M %LTLO))))
          (%S %P1 (%M %LO))
          (%S %P2 (list '- (%M %UNLO) (%M %NN)))
          (%S %CNT (%M %NN))
          (%GO 24))))
    ; 24: the equal entries at the low end swapped to the middle
    (list 24
      (list 'if (list '> (%M %CNT) 0)
        (list 'do (%zj-swap (%M %P1) (%M %P2)) (%INC %P1) (%INC %P2) (%DEC %CNT) (%GO 24))
        (list 'do
          (%S %MM (list '- (%M %HI) (%M %GTHI)))
          (%WHEN (list '< (list '- (%M %GTHI) (%M %UNHI)) (%M %MM)) (%S %MM (list '- (%M %GTHI) (%M %UNHI))))
          (%S %P1 (%M %UNLO))
          (%S %P2 (list '+ (list '- (%M %HI) (%M %MM)) 1))
          (%S %CNT (%M %MM))
          (%GO 25))))
    ; 25: and at the high end; the two sides pushed, the larger first
    (list 25
      (list 'if (list '> (%M %CNT) 0)
        (list 'do (%zj-swap (%M %P1) (%M %P2)) (%INC %P1) (%INC %P2) (%DEC %CNT) (%GO 25))
        (list 'do
          (%S %NN (list '- (list '- (list '+ (%M %LO) (%M %UNLO)) (%M %LTLO)) 1))
          (%S %MM (list '+ (list '- (%M %HI) (list '- (%M %GTHI) (%M %UNHI))) 1))
          (list 'if (list '> (list '- (%M %NN) (%M %LO)) (list '- (%M %HI) (%M %MM)))
            (list 'do (%zj-push (%M %LO) (%M %NN)) (%zj-push (%M %MM) (%M %HI)))
            (list 'do (%zj-push (%M %MM) (%M %HI)) (%zj-push (%M %LO) (%M %NN))))
          (%GO 20))))
    ; 7: the scan for the next bucket starts past the last
    (list 7 (list 'do (%S %K (list '+ (%M %R) 1)) (%GO 8)))
    ; 10: the round done: another, doubled, while buckets were sorted
    (list 10
      (list 'do
        (%S %H (list '* (%M %H) 2))
        (list 'if (list 'if (list '> (%M %H) (%M %N)) 1 (list '= (%M %NOTDONE) 0))
          (list 'do (%S %I 0) (%GO 11))
          (list 'do (%S %I 0) (%S %J 0) (%GO 6)))))
    ; 11: the origin, where position 0 sorted to
    (list 11
      (list 'if (list '= (%FMR (%M %I)) 0) (%M %I)
        (list 'do (%INC %I) (%GO 11))))
    ; 40: the counts cleared
    (list 40
      (list 'if (list '< (%M %I) 257)
        (list 'do (%FTB! (%M %I) 0) (%INC %I) (%GO 40))
        (list 'do (%S %I 0) (%GO 0))))
    ; 0: the bytes counted
    (list 0
      (list 'if (list '< (%M %I) (%M %N))
        (list 'do (%S %T0 (%BYTE (%M %I))) (%FTB! (%M %T0) (list '+ (%FTB (%M %T0)) 1)) (%INC %I) (%GO 0))
        (list 'do (%S %I 1) (%S %J (%FTB 0)) (%GO 1))))
    ; 1: the counts made running totals
    (list 1
      (list 'if (list '< (%M %I) 257)
        (list 'do (%S %J (list '+ (%M %J) (%FTB (%M %I)))) (%FTB! (%M %I) (%M %J)) (%INC %I) (%GO 1))
        (list 'do (%S %I 0) (%GO 2))))
    ; 2: each position placed in its byte's bucket
    (list 2
      (list 'if (list '< (%M %I) (%M %N))
        (list 'do
          (%S %T0 (%BYTE (%M %I)))
          (%S %K (list '- (%FTB (%M %T0)) 1))
          (%FTB! (%M %T0) (%M %K))
          (%AT! %FM (%M %K) (%M %I))
          (%INC %I)
          (%GO 2))
        (list 'do (%S %I 0) (%GO 3))))
    ; 3: the heads cleared
    (list 3
      (list 'if (list '< (%M %I) (list '+ (%M %N) 64))
        (list 'do (%AT! %BH (%M %I) 0) (%INC %I) (%GO 3))
        (list 'do (%S %I 0) (%GO 4))))
    ; 4: each byte's bucket a head
    (list 4
      (list 'if (list '< (%M %I) 256)
        (list 'do (%AT! %BH (%FTB (%M %I)) 1) (%INC %I) (%GO 4))
        (list 'do (%S %I 0) (%GO 5))))
    ; 5: the block-end sentinels, then the first round
    (list 5
      (list 'if (list '< (%M %I) 32)
        (list 'do
          (%AT! %BH (list '+ (%M %N) (list '* (%M %I) 2)) 1)
          (%AT! %BH (list '+ (list '+ (%M %N) (list '* (%M %I) 2)) 1) 0)
          (%INC %I)
          (%GO 5))
        (list 'do (%S %H 1) (%S %I 0) (%S %J 0) (%GO 6))))))

(def %zj-dispatch
  (fn (self phases)
    (if (null? (rest phases)) (first (rest (first phases)))
      (list 'if (list '= 'ph (first (first phases)))
        (first (rest (first phases)))
        (self (rest phases))))))

(def %zj-sort-expr (list 'fn '(self a ph) (%zj-dispatch %zj-sort-phases)))

; --- move-to-front and zero runs: bzip2.x's %mtf-x ---
;
; Phase 0 reads a position; 1 moves its byte's place to the front; 2
; writes a zero run before it, 3 the run at the block's end.  T1 holds the
; place of the byte in hand, T2 the entry carried down, T3 where.
(def %zj-mtf-out
  (fn (_ v)
    (list 'do
      (%S %T0 v)
      (%AT! %EC 'wr (%M %T0))
      (%TB! %MTFFREQ (%M %T0) (list '+ (%TB %MTFFREQ (%M %T0)) 1)))))

(def %zj-shift-start
  (fn (_ wr)
    (list 'do
      (%S %T2 (%MA (list '+ %YY 1)))
      (%SA (list '+ %YY 1) (%MA %YY))
      (%S %T3 1)
      (list 'self 'a 1 'i wr 0))))

(def %zj-mtf-expr
  (list 'fn '(self a ph i wr z)
    (list 'if (list '= 'ph 1)
      (list 'if (list '= (%M %T2) (%M %T1))
        (list 'do
          (%SA %YY (%M %T2))
          (%zj-mtf-out (list '+ (%M %T3) 1))
          (list 'self 'a 0 (list '+ 'i 1) (list '+ 'wr 1) 0))
        (list 'do
          (%INC %T3)
          (%S %T0 (%MA (list '+ %YY (%M %T3))))
          (%SA (list '+ %YY (%M %T3)) (%M %T2))
          (%S %T2 (%M %T0))
          (list 'self 'a 1 'i 'wr 0)))
      (list 'if (list '= 'ph 0)
        (list 'if (list '>= 'i (%M %N))
          (list 'if (list '> 'z 0) (list 'self 'a 3 'i 'wr (list '- 'z 1))
            (list 'do (%zj-mtf-out (list '+ (%M %NUSE) 1)) (list '+ 'wr 1)))
          (list 'do
            (%S %K (list '- (%FMR 'i) 1))
            (%WHEN (list '< (%M %K) 0) (%S %K (list '+ (%M %K) (%M %N))))
            (%S %T1 (%TB %UNSEQ (%BYTE (%M %K))))
            (list 'if (list '= (%MA %YY) (%M %T1))
              (list 'self 'a 0 (list '+ 'i 1) 'wr (list '+ 'z 1))
              (list 'if (list '> 'z 0) (list 'self 'a 2 'i 'wr (list '- 'z 1))
                (%zj-shift-start 'wr)))))
        (list 'do
          (%zj-mtf-out (list '& 'z 1))
          (list 'if (list '< (list '- 'z 2) 0)
            (list 'if (list '= 'ph 2)
              (%zj-shift-start (list '+ 'wr 1))
              (list 'do (list 'self 'a 0 'i (list '+ 'wr 1) 0)))
            (list 'self 'a 'ph 'i (list '+ 'wr 1) (list '>> (list '- 'z 2) 1))))))))

; --- one pass of the selection: bzip2.x's %select-x ---
;
; Phase 0 starts a group, 1 adds each symbol's length under each table, 2
; picks the cheapest table, 3 counts the group's symbols for it.
(def %zj-cost-add
  (fn (self t)
    (if (= t 6) ()
      (pair (%WHEN (list '< t (%M %NGROUPS))
              (%SA (list '+ %COST t)
                   (list '+ (%MA (list '+ %COST t))
                        (%TB %LENS (list '+ (* t %ASIZE) (%M %T0))))))
            (self (+ t 1))))))

(def %zj-best
  (fn (self t)
    (if (= t 6) ()
      (pair (%WHEN (list 'if (list '< t (%M %NGROUPS)) (list '< (%MA (list '+ %COST t)) (%M %T1)) 0)
              (list 'do (%S %T1 (%MA (list '+ %COST t))) (%S %BT t)))
            (self (+ t 1))))))

(def %zj-select-expr
  (list 'fn '(self a ph gs i nsel)
    (list 'if (list '= 'ph 1)
      (list 'if (list '> 'i (%M %GE)) (list 'self 'a 2 'gs 'gs 'nsel)
        (pair 'do
          (pair (%S %T0 (%AT %EC 'i))
                (List append (%zj-cost-add 0) (list (list 'self 'a 1 'gs (list '+ 'i 1) 'nsel))))))
      (list 'if (list '= 'ph 3)
        (list 'if (list '> 'i (%M %GE)) (list 'self 'a 0 (list '+ (%M %GE) 1) 0 (list '+ 'nsel 1))
          (list 'do
            (%S %T0 (list '+ %RFREQ (list '+ (list '* (%M %BT) %ASIZE) (%AT %EC 'i))))
            (%AT! %TAB (%M %T0) (list '+ (%AT %TAB (%M %T0)) 1))
            (list 'self 'a 3 'gs (list '+ 'i 1) 'nsel)))
        (list 'if (list '= 'ph 0)
          (list 'if (list '>= 'gs (%M %NMTF)) 'nsel
            (list 'do
              (%S %GE (list '+ 'gs 49))
              (%WHEN (list '>= (%M %GE) (%M %NMTF)) (%S %GE (list '- (%M %NMTF) 1)))
              (%SA %COST 0) (%SA (list '+ %COST 1) 0) (%SA (list '+ %COST 2) 0)
              (%SA (list '+ %COST 3) 0) (%SA (list '+ %COST 4) 0) (%SA (list '+ %COST 5) 0)
              (list 'self 'a 1 'gs 'gs 'nsel)))
          (pair 'do
            (List append
              (list (%S %T1 (%MA %COST)) (%S %BT 0))
              (%zj-best 1)
              (list (list '%mem-byte-set-at! (%M %SEL) 'nsel (%M %BT))
                    (list 'self 'a 3 'gs 'gs 'nsel)))))))))

; --- the symbols written: bzip2.x's %write-x ---
;
; The bit buffer holds under eight bits before a code and a code is at most
; seventeen, so three flushes always make room.
(def %zj-flush
  (%WHEN (list '>= (%M %BL) 8)
    (list 'do
      (list '%mem-byte-set-at! (%M %OUT) (%M %OCNT) (list '>> (%M %BB) 24))
      (%INC %OCNT)
      (%S %BB (list '& (list '<< (%M %BB) 8) %M32))
      (%S %BL (list '- (%M %BL) 8)))))

(def %zj-write-expr
  (list 'fn '(self a gs i s)
    (list 'if (list '> 'i (%M %GE))
      (list 'if (list '>= 'i (%M %NMTF)) 0
        (list 'do
          (%S %GE (list '+ 'i 49))
          (%WHEN (list '>= (%M %GE) (%M %NMTF)) (%S %GE (list '- (%M %NMTF) 1)))
          (%S %BT (list '* (list '%mem-byte-ref-at (%M %SEL) (list '+ 's 1)) %ASIZE))
          (list 'self 'a 'i 'i (list '+ 's 1))))
      (list 'do
        %zj-flush %zj-flush %zj-flush
        (%S %T0 (list '+ (%M %BT) (%AT %EC 'i)))
        (%S %T1 (%TB %LENS (%M %T0)))
        (%S %BB (list '| (%M %BB) (list '<< (%TB %CODES (%M %T0)) (list '- (list '- 32 (%M %BL)) (%M %T1)))))
        (%S %BL (list '+ (%M %BL) (%M %T1)))
        (list 'self 'a 'gs (list '+ 'i 1) 's)))))

; --- build: compile, wire the drivers, and PROVE them against the reference ---
;
; state: bzip2.x's slot numbers, as an alist (blockp nblock nbmax inch inrun
;        crc tabp workp workn outp outcnt bsbuff bslive selp).
; work:  bzip2.x's (fn (_ e n)), the sort's arrays made for n entries.
; room:  its (fn (_ e n)), room for n more output bytes.
; check: (fn (_ engine) -> #t) -- whether an engine (TAKE SORT MTF SELECT
;        WRITE) writes the reference's bytes for the check inputs.
;
; Answers (TAKE SORT MTF SELECT WRITE), drop-ins for bzip2.x's %take!,
; %sort-x, %mtf-x, %select-x and %write-x.  Or raises: on a host with no
; assembler backend, a toolchain error, or any disagreement.  The caller
; guards; a raise means "stay pure-x".
(def bzip2-jit-make
  (fn (_ state work room check)
    ; the engine lays out and computes in 8-byte words
    (if (< %word-size 8) (Err raise (lit state) "bzip2-jit: written for an 8-byte word" ()))
    (def %take-step (compile-asm %zj-take-expr))
    (def %sort-step (compile-asm %zj-sort-expr))
    (def %mtf-step (compile-asm %zj-mtf-expr))
    (def %select-step (compile-asm %zj-select-expr))
    (def %write-step (compile-asm %zj-write-expr))
    (Heap collect)
    (def %buf (str-make (* 8 %WORDS)))
    (def %ptr (str->ptr %buf))
    (def %addr (ptr->int %ptr))
    (def %poke (fn (_ i v) (ptr-set-word! %ptr (* i 8) v)))
    (def %peek (fn (_ i) (ptr-ref-word %ptr (* i 8))))
    (def %slot (fn (_ name) (rest (Assoc entry name state))))
    (def %get (fn (_ e name) (obj-ref e (%slot name))))
    (def %put! (fn (_ e name v) (obj-set! e (%slot name) v)))
    (def %addr-of (fn (_ e name) (ptr->int (%get e name))))
    ; the block, the tables and the sort's arrays
    (def %load!
      (fn (_ e)
        (%poke %BLOCK (%addr-of e (lit blockp)))
        (%poke %N (%get e (lit nblock)))
        (%poke %TAB (%addr-of e (lit tabp)))
        (%poke %SEL (%addr-of e (lit selp)))
        (def w (%get e (lit workn)))
        (def p (%addr-of e (lit workp)))
        (%poke %FM p)
        (%poke %EC (+ p (* w 8)))
        (%poke %BH (+ p (* w 16)))))
    (def %take
      (fn (_ e p i end)
        (%poke %BLOCK (%addr-of e (lit blockp)))
        (%poke %N (%get e (lit nblock)))
        (%poke %NBMAX (%get e (lit nbmax)))
        (%poke %INCH (%get e (lit inch)))
        (%poke %INRUN (%get e (lit inrun)))
        (%poke %CRC (%get e (lit crc)))
        (%poke %TAB (%addr-of e (lit tabp)))
        (%poke %IN (ptr->int p))
        (%poke %END end)
        (def j (%take-step %addr 0 i 0))
        (%put! e (lit nblock) (%peek %N))
        (%put! e (lit inch) (%peek %INCH))
        (%put! e (lit inrun) (%peek %INRUN))
        (%put! e (lit crc) (%peek %CRC))
        j))
    (def %sort
      (fn (_ e)
        (work e (%get e (lit nblock)))
        (%load! e)
        (%poke %I 0)
        (%sort-step %addr 40)))
    (def %mtf
      (fn (_ e)
        (%load! e)
        ; the used bytes numbered in order, and the counts cleared
        (def tab (%get e (lit tabp)))
        (def tref (fn (_ k) (ptr-ref-word tab (* k 8))))
        (def tset (fn (_ k v) (ptr-set-word! tab (* k 8) v)))
        (def nuse
          ((fn (self i cnt)
             (if (= i 256) cnt
               (if (= (tref (+ %INUSE i)) 0) (self (+ i 1) cnt)
                 (do (tset (+ %UNSEQ i) cnt) (self (+ i 1) (+ cnt 1))))))
           0 0))
        (%put! e (lit ninuse) nuse)
        (%poke %NUSE nuse)
        ((fn (self i) (when (< i %ASIZE) (do (tset (+ %MTFFREQ i) 0) (self (+ i 1))))) 0)
        ((fn (self i) (when (< i 256) (do (%poke (+ %YY i) i) (self (+ i 1))))) 0)
        (%mtf-step %addr 0 0 0 0)))
    (def %select
      (fn (_ e nmtf ngroups)
        (%load! e)
        (%poke %NMTF nmtf)
        (%poke %NGROUPS ngroups)
        (%select-step %addr 0 0 0 0)))
    (def %write
      (fn (_ e nmtf nsel)
        (%load! e)
        (room e (+ (/ (* nmtf 17) 8) 64))
        (%poke %OUT (%addr-of e (lit outp)))
        (%poke %OCNT (%get e (lit outcnt)))
        (%poke %BB (%get e (lit bsbuff)))
        (%poke %BL (%get e (lit bslive)))
        (%poke %NMTF nmtf)
        (%poke %GE -1)
        (%write-step %addr 0 0 -1)
        (%put! e (lit outcnt) (%peek %OCNT))
        (%put! e (lit bsbuff) (%peek %BB))
        (%put! e (lit bslive) (%peek %BL))))
    (def engine (list %take %sort %mtf %select %write))
    (unless (check engine)
      (Err raise (lit state) "bzip2-jit: engine disagrees with the pure-x encoder" ()))
    ; the scratch is held by the drivers' closures
    (list (fn (_ e p i end) (do %buf (%take e p i end))) %sort %mtf %select %write)))

; The codec reaches the maker through the catalogue: it loads this module
; inside the function that builds the engine, where an import is one the
; linter cannot see.
(prim-reg! (lit bzip2) (lit jit-make) bzip2-jit-make)

(doc (provide x/codec/bzip2-jit bzip2-jit-make)
  "The compiled loops behind Bzip2 (JIT, ARM64 and x86-64 backends): the input's runs, the sort, the move-to-front values, the table selection and the symbol writer, built and adopted only after writing what the pure-x encoder writes.")
