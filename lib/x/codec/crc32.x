; crc32.x -- Crc32: the CRC-32 of ISO 3309 in pure x-lang.
;
; The checksum gzip, zip and git's pack indexes carry: the reflected
; polynomial 0xEDB88320, the register started at all ones and inverted at
; the end, a byte at a time through a table of 256 entries built when the
; module loads.  Zlib (x/codec/zlib) binds the system's libz for the same
; sum; this is the one for a system that has no libz, and the reference
; the two are checked against each other by.
;
; Pure INT on the C bit ops through the int doors; the exclusive or, which
; has no door, is (a | b) - (a & b) on the non-negative words here.  The
; byte loop is one top-level function calling itself in tail position.
(module x/codec/crc32)

(import x/type/vector)
; The compiled engine is on Compiled's list.
(import x/tool/compiled)

(def %add (prim-ref (lit int) (lit +)))
(def %sub (prim-ref (lit int) (lit -)))
(def %lt (prim-ref (lit int) (lit <)))
(def %eq (prim-ref (lit int) (lit =)))
(def %and (prim-ref (lit int) (lit &)))
(def %or (prim-ref (lit int) (lit |)))
(def %shr (prim-ref (lit int) (lit >>)))
(def %oref (prim-ref (lit obj) (lit ref)))
(def %oset! (prim-ref (lit obj) (lit set!)))
(def %pref (prim-ref (lit ptr) (lit ref)))
(def %str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %str-byte-len (prim-ref (lit str) (lit byte-len)))

(def %xor (fn (_ a b) (%sub (%or a b) (%and a b))))

; Slot i+1 holds byte i's CRC: eight shifts, the polynomial folded in
; when the low bit is set.
(def %table (Vector make 256 0))
((fn (self i)
   (if (%lt i 256)
     (do (%oset! %table (%add i 1)
           ((fn (fold k c)
              (if (%eq k 0) c
                (fold (%sub k 1) (if (%eq (%and c 1) 0) (%shr c 1) (%xor (%shr c 1) 3988292384)))))
            8 i))
         (self (%add i 1)))
     ()))
 0)

; The register after the bytes from i below n at p.  Once a byte, so the
; two exclusive ors are written out here rather than called: a call of
; %xor costs a frame, and two a byte made a 64K CRC 4.6M objects.
(def %fold
  (fn (self p i n c)
    (if (%lt i n)
      (do (def b (%and (%pref p i 1) 255))
          (def t (%oref %table (%add (%and (%sub (%or c b) (%and c b)) 255) 1)))
          (def s (%shr c 8))
          (self p (%add i 1) n (%sub (%or t s) (%and t s))))
      c)))

; START and LENGTH from an optional span, defaulting to the whole string.
(def %span
  (fn (_ s span)
    (match
      ((null? span) (list 0 (%str-byte-len s)))
      ((null? (rest span)) (list (first span) (%sub (%str-byte-len s) (first span))))
      (#t (list (first span) (first (rest span)))))))

(def %ptr-at (prim-ref (lit ptr) (lit ->int)))
(def %int->ptr (prim-ref (lit int) (lit ->ptr)))
(def %at (fn (_ p off) (%int->ptr (%add (%ptr-at p) off))))

; --- The compiled engine (JIT), adopted only when it proves out ------
;
; x/codec/crc32-jit compiles the byte loop.  As inflate's engine is, it is
; an entry of Compiled's made on demand, built for an input of
; %jit-threshold bytes or more or on (Crc32 jit!), and adopted only after it
; sums the check inputs below as %fold does.  The pure fold costs about
; sixty objects a byte -- the self-call and its bindings -- the engine none.

(def %fold-x (fn (_ p n c) (%fold p 0 n c)))

; Check inputs: the standard one, and 3000 bytes of every value in turn,
; from a register of all ones and from one mid-sum.
(def %agrees?
  (fn (_ eng)
    (def r ((prim-ref (lit str) (lit make)) 3000))
    (def p (%str->ptr r))
    ((fn (self i) (when (%lt i 3000) (do ((prim-ref (lit ptr) (lit set!)) p i (%and (%add (%shr (%add i 1) 0) (%shr i 3)) 255) 1) (self (%add i 1))))) 0)
    (and (= (%fold-x (%str->ptr "123456789") 9 4294967295) (eng (%str->ptr "123456789") 9 4294967295))
         (= (%fold-x p 3000 4294967295) (eng p 3000 4294967295))
         (= (%fold-x p 3000 123456789) (eng p 3000 123456789)))))

(def %jit-threshold 4096)
(def %entry ())

(def %jit-try!
  (fn (_)
    (when (null? %entry)
      (set! %entry
        (Compiled make-on-demand (lit crc32) %fold-x
          (fn (_)
            (import x/codec/crc32-jit)
            ((prim-ref (lit crc32) (lit jit-make)) %table %agrees?))
          (fn (_ v) ()))))
    ((fn (_ entry)
       (when (eq? (entry state) (lit interpreted)) (entry compile!))
       (eq? (entry state) (lit compiled)))
     %entry)))

; The fold for n bytes: the engine's when it is built, or when n is past the
; bar and a build succeeds; else the pure one.
(def %fold-for
  (fn (_ n)
    (do (when (and (>= n %jit-threshold)
                   ((fn (_ entry) (if (null? entry) #t (eq? (entry state) (lit interpreted)))) %entry))
          (%jit-try!))
        ((fn (_ entry)
           (if (if (null? entry) #f (eq? (entry state) (lit compiled)))
             (entry compiled)
             %fold-x))
         %entry))))

(def-class Crc32 ()
  (doc "The CRC-32 of ISO 3309 (gzip, zip, git's pack indexes) in pure x-lang.")
  (static
    (method of (self (param s STRING "Bytes")
                     . (param span LIST "START, then LENGTH: which bytes of s; default all of s"))
      (doc "The CRC-32 of the bytes. Give LENGTH for binary input: s's own length is measured to its first NUL."
        (returns INTEGER "The CRC, 0 to 4294967295")
        (example "(Crc32 of \"123456789\")" "3421780262")
        (example "(Crc32 of \"\")" "0"))
      (def sp (%span s span))
      (%xor ((%fold-for (first (rest sp))) (%at (%str->ptr s) (first sp)) (first (rest sp)) 4294967295) 4294967295))
    (method update (self (param crc INTEGER "The CRC so far; 0 to start")
                         (param s STRING "Bytes")
                         . (param span LIST "START, then LENGTH, as for of"))
      (doc "The CRC-32 of the data crc sums followed by the bytes: a sum carried on across pieces, as Zlib crc32 carries it."
        (returns INTEGER "The CRC, 0 to 4294967295")
        (example "(Crc32 update (Crc32 update 0 \"1234\") \"56789\")" "3421780262"))
      (def sp (%span s span))
      (%xor ((%fold-for (first (rest sp))) (%at (%str->ptr s) (first sp)) (first (rest sp)) (%xor crc 4294967295)) 4294967295))
    (method jit! (self)
      (doc "Build and adopt the compiled byte loop (JIT; ARM64 and x86-64 backends) now, if it sums the check inputs exactly as the pure-x fold does. Idempotent. Answers #t when the engine is active, #f when unavailable -- the pure-x fold carries on, with the same sums. of and update build it on their own for 4KB or more."
        (returns BOOL "#t when the compiled engine is active"))
      (%jit-try!))))

(doc (provide x/codec/crc32 Crc32)
  "The CRC-32 of ISO 3309 in pure x-lang: (Crc32 of s) and (Crc32 update crc s), the sum libz's crc32 answers.")
