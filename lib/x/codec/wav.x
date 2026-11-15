; wav.x -- Wav: WAV files (RIFF WAVE, integer PCM) read in pure x-lang.
;
; A WAV file is a RIFF file: "RIFF", its size, "WAVE", then chunks, each
; a four-byte id, a 32-bit little-endian size and that many bytes, padded
; to an even length.  The "fmt " chunk names the format: 1 is integer PCM,
; 0xFFFE the extensible form, whose sub-format's first two bytes name it
; again; then the channels, the frames a second, and the bits a sample.
; The "data" chunk holds the frames, each a sample for every channel in
; turn, little-endian, 8 bits unsigned or 16, 24 or 32 bits signed.  A
; sampler's "smpl" chunk names the MIDI note the sound is at and its loops,
; each with an inclusive last frame.
;
; Out comes the sound as one channel of signed 16-bit little-endian
; samples, the form x/audio/mixer plays: each frame the mean of its
; channels, rounded down, each sample its top 16 bits.  Floating-point samples, and any
; other format, raise a label 'value naming what was wrong, as does a file
; that is not WAV or ends early.
(module x/codec/wav)

(import x/tool/compiled)
(import x/tool/word-form word-form-pure)

(import x/core/doors char->int int& int* int+ int- int->ptr int/ int< int<< int= int>> ptr->int ptr-ref ptr-set! str->ptr str-byte-len str-byte-ref str-make)

(def %fail (fn (_ what) (Err raise (lit value) (Str8 append "Wav: " what) ())))

(def %u8 (fn (_ p i) (int& (ptr-ref p i 1) 255)))
(def %u16 (fn (_ p i) (int+ (%u8 p i) (int<< (%u8 p (int+ i 1)) 8))))
(def %u32 (fn (_ p i) (int+ (%u16 p i) (int<< (%u16 p (int+ i 2)) 16))))

(def %at (fn (_ p off) (int->ptr (int+ (ptr->int p) off))))

(def %span
  (fn (_ s span)
    (match
      ((null? span) (list 0 (str-byte-len s)))
      ((null? (rest span)) (list (first span) (int- (str-byte-len s) (first span))))
      (#t (list (first span) (first (rest span)))))))

; The four bytes at I spell ID.
(def %id?
  (fn (_ p i id)
    ((fn (self k)
       (match ((int= k 4) #t)
              ((int= (%u8 p (int+ i k)) (char->int (str-byte-ref id k))) (self (int+ k 1)))
              (#t #f)))
     0)))

; The chunks of the file at P, LEN bytes: ((AT OFFSET SIZE) ...), AT where
; its id is, OFFSET where its bytes start.
(def %chunks
  (fn (_ p len)
    (unless (if (int< 11 len) (if (%id? p 0 "RIFF") (%id? p 8 "WAVE") #f) #f)
      (%fail "not a WAV file: no RIFF WAVE header"))
    ((fn (self i acc)
       (if (int< len (int+ i 8))
         acc
         ((fn (_ size)
            (when (int< len (int+ (int+ i 8) size)) (%fail "the file ends early"))
            (self (int+ (int+ i 8) (int+ size (int& size 1)))
                  (pair (list i (int+ i 8) size) acc)))
          (%u32 p (int+ i 4)))))
     12 ())))

; The first chunk of CHUNKS, of the file at P, whose id is ID.
(def %chunk
  (fn (_ p chunks id)
    (List find (fn (_ c) (%id? p (first c) id)) (List reverse chunks))))

; The format of the file at P, LEN bytes: (RATE CHANNELS BITS FRAMES DATA),
; DATA the offset of its frames.
(def %format
  (fn (_ p len)
    (def chunks (%chunks p len))
    (def fmt (%chunk p chunks "fmt "))
    (def data (%chunk p chunks "data"))
    (when (null? fmt) (%fail "no fmt chunk"))
    (when (null? data) (%fail "no data chunk"))
    (def f (List ref 1 fmt))
    (when (int< (List ref 2 fmt) 16) (%fail "a fmt chunk shorter than 16 bytes"))
    (def tag (%u16 p f))
    (def kind (if (int= tag 65534)
                (if (int< (List ref 2 fmt) 26) (%fail "an extensible fmt chunk with no sub-format") (%u16 p (int+ f 24)))
                tag))
    (unless (int= kind 1)
      (%fail (if (int= kind 3) "floating-point samples are not read: only integer PCM" "a format that is not PCM")))
    (def channels (%u16 p (int+ f 2)))
    (def rate (%u32 p (int+ f 4)))
    (def bits (%u16 p (int+ f 14)))
    (when (int= channels 0) (%fail "no channels"))
    (unless (match ((int= bits 8) #t) ((int= bits 16) #t) ((int= bits 24) #t) ((int= bits 32) #t) (#t #f))
      (%fail "bits a sample other than 8, 16, 24 or 32"))
    (list rate channels bits (int/ (List ref 2 data) (int* channels (int>> bits 3))) (List ref 1 data))))

; --- The frames, as a kernel ----------------------------------------------
;
; Frames F to N written to byte address O as one channel of signed 16-bit
; little-endian samples, read from byte address P at byte AT: each frame
; CH samples of W bytes, their top 16 bits from byte TOP of each, or, EIGHT
; 1, 8 bits unsigned raised to 16; their sum ACC, from channel C, times
; RECIP 65536ths, 65536 over CH, is the frame.  The loop is an integer form
; (x/tool/word-form), run pure, or compiled once it agrees.
(def %mono-form
  (lit (fn (self o p f n c ch w top eight acc at recip)
    (if (< f n)
      (if (< c ch)
        (self o p f n (+ c 1) ch w top eight
              (+ acc (if (= eight 1)
                       (<< (- (%mem-byte-ref-at p at) 128) 8)
                       (- (+ (%mem-byte-ref-at p (+ at top)) (<< (%mem-byte-ref-at p (+ (+ at top) 1)) 8))
                          (<< (& (%mem-byte-ref-at p (+ (+ at top) 1)) 128) 9))))
              (+ at w) recip)
        (do (%mem-byte-set-at! o (+ f f) (*>> acc recip 16))
            (%mem-byte-set-at! o (+ (+ f f) 1) (>> (*>> acc recip 16) 8))
            (self o p (+ f 1) n 0 ch w top eight 0 at recip)))
      0))))

(def %pure (word-form-pure %mono-form))
(def %k-mono %pure)

(def %addr (fn (_ s) (ptr->int (str->ptr s))))

; The kernel K run on bytes made from SEED, CH channels of W bytes: the
; frames it writes, as a string of their bytes' values.
(def %trial
  (fn (_ k ch w seed)
    (def src (str-make 256))
    ((fn (self i x) (when (int< i 256) (do (ptr-set! (str->ptr src) i (int& (int>> x 7) 255) 1) (self (int+ i 1) (int& (int+ (int* x 1103515245) seed) 2147483647)))))
     0 seed)
    (def out (str-make 64))
    (k (%addr out) (%addr src) 0 16 0 ch w (if (int= w 1) 0 (int- w 2)) (if (int= w 1) 1 0) 0 0 (int/ 65536 ch))
    ((fn (self i acc) (if (int< i 32) (self (int+ i 1) (pair (int& (ptr-ref (str->ptr out) i 1) 255) acc)) acc)) 0 ())))

; The compiled kernel, in ENGINE, writes what the pure one writes.
(def %agrees?
  (fn (_ engine)
    (List all? (fn (_ t) (equal? (%trial %pure (first t) (List ref 1 t) 12345) (%trial (first engine) (first t) (List ref 1 t) 12345)))
               (list (list 2 1) (list 1 2) (list 3 3) (list 2 4)))))

(def %entry ())

; The compiled kernel, built and adopted the first time a long sound is
; read, where the toolchain has a backend and it agrees.
(def %jit-try!
  (fn (_)
    (when (null? %entry)
      (set! %entry
        (Compiled make-on-demand (lit wav) (list %pure)
          (fn (_)
            (import x/tool/word-form-jit)
            ((prim-ref (lit word-form) (lit jit-make)) (list %mono-form) %agrees?))
          (fn (_ ks) (set! %k-mono (first ks))))))
    ((fn (_ entry) (when (eq? (entry state) (lit interpreted)) (entry compile!))) %entry)))

; The sound at P, FRAMES frames of CHANNELS samples of BITS from offset AT,
; as one channel of signed 16-bit samples.
(def %mono
  (fn (_ p at frames channels bits)
    (when (int< 4095 frames) (guard (_ ()) (%jit-try!)))
    (def width (int>> bits 3))
    (def out (str-make (int+ (int* frames 2) 1)))
    (%k-mono (%addr out) (ptr->int p) 0 frames 0 channels width (if (int= bits 8) 0 (int- width 2)) (if (int= bits 8) 1 0)
             0 at (int/ 65536 channels))
    out))

; The loop and root of the smpl chunk among CHUNKS of the file at P, within
; FRAMES: ((START END) ROOT), END past the loop's last frame, each nil when
; the file names none.
(def %sampler
  (fn (_ p chunks frames)
    (def c (%chunk p chunks "smpl"))
    (if (if (null? c) #t (int< (List ref 2 c) 36))
      (list () ())
      ((fn (_ s)
         (list (if (if (int< 0 (%u32 p (int+ s 28))) (not (int< (List ref 2 c) 60)) #f)
                 ((fn (_ start end)
                    (if (if (int< start end) (not (int< frames end)) #f) (list start end) ()))
                  (%u32 p (int+ s 44)) (int+ (%u32 p (int+ s 48)) 1))
                 ())
               ((fn (_ note) (if (int< note 128) note ())) (%u32 p (int+ s 12)))))
       (List ref 1 c)))))

(def-class Wav ()
  (doc "WAV files read in pure x-lang: integer PCM at 8, 16, 24 or 32 bits, any channels, and a sampler's loop and root note, as one channel of signed 16-bit samples for x/audio/mixer."
    (example "(do (import x/codec/bytes) (def r (Bytes of-hex \"524946462800000057415645666d74201000000001000100401f0000803e0000020010006461746104000000ff7f0080\")) (Wav format (first r) 0 (List ref 2 r)))" "(8000 1 16 2)")
    (see decode))
  (static
    (method format (self (param s STRING "Bytes holding a WAV file")
                         . (param span LIST "START, then LENGTH: which bytes of s; default all of s"))
      (doc "The file's frames a second, channels, bits a sample and frames, from its fmt and data chunks, without reading the frames. Give LENGTH for a file held in a buffer: s's own length is measured to its first NUL, and a WAV file has many. Raises a label 'value when the bytes are not a WAV file of integer PCM."
        (returns LIST "(RATE CHANNELS BITS FRAMES)")
        (example "(do (import x/codec/bytes) (def r (Bytes of-hex \"524946462800000057415645666d74201000000001000100401f0000803e0000020010006461746104000000ff7f0080\")) (Wav format (first r) 0 (List ref 2 r)))" "(8000 1 16 2)"))
      (def sp (%span s span))
      (def p (%at (str->ptr s) (first sp)))
      (def f (%format p (first (rest sp))))
      (list (List ref 0 f) (List ref 1 f) (List ref 2 f) (List ref 3 f)))
    (method decode (self (param s STRING "Bytes holding a WAV file")
                         . (param span LIST "START, then LENGTH, as for format"))
      (doc "The sound as one channel: each frame the mean of its channels, rounded down, each sample its top 16 bits, signed, little-endian, the form (Mixer sample!) and (Mixer cycle!) take. With it, a sampler chunk's first loop, END past its last frame, and the MIDI note the sound is at (60 is C4), each nil when the file has none. Raises a label 'value naming what is wrong with a file that is not WAV, ends early, or holds floating-point or other samples."
        (returns LIST "(RATE FRAMES PCM LOOP ROOT): PCM a buffer of FRAMES x 2 bytes; LOOP (START END) or nil; ROOT a MIDI note or nil")
        (example "(do (import x/codec/bytes) (def r (Bytes of-hex \"524946462800000057415645666d74201000000001000100401f0000803e0000020010006461746104000000ff7f0080\")) (def d (Wav decode (first r) 0 (List ref 2 r))) (list (first d) (List ref 1 d) (Bytes hex (list (List ref 2 d) 0 4))))" "(8000 2 \"ff7f0080\")"))
      (def sp (%span s span))
      (def p (%at (str->ptr s) (first sp)))
      (def len (first (rest sp)))
      (def f (%format p len))
      (def frames (List ref 3 f))
      (def smpl (%sampler p (%chunks p len) frames))
      (list (first f) frames (%mono p (List ref 4 f) frames (List ref 1 f) (List ref 2 f)) (first smpl) (List ref 1 smpl)))))

(doc (provide x/codec/wav Wav)
  (example "(do (import x/codec/bytes) (let ((r (Bytes of-hex \"524946462800000057415645666d74201000000001000100401f0000803e0000020010006461746104000000ff7f0080\"))) (Wav format (first r) 0 (List ref 2 r))))" "(8000 1 16 2)")
  "WAV files read in pure x-lang: (Wav decode s) answers the sound as one channel of signed 16-bit samples, with a sampler's loop and root note, and (Wav format s) its rate, channels, bits and frames.")
