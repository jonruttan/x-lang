; tracker.x -- Tracker: a song of patterns played into a mixer, row by row,
; its tempo and its layers following a tension.
;
; A song is data, the forms a .xon file reads as:
;
;   (song "NAME"
;     (bpm 60) (rows 4)              beats a minute, rows a beat
;     (ticks 6)                      ticks a row, for a cell's effects
;     (tension-bpm 30)               beats a minute added at full tension
;     (echo 370 40 25)               an effect over the whole mixer, in
;     (reverb 120 80 30)             order: (echo MS FB WET), (reverb SIZE
;     (phase 1 4 3000 40 60)         DECAY WET), (phase LEAST-MS MOST-MS
;     (limit 90 100)                 PERIOD-MS FB WET), (chorus ...),
;                                    (drive ...), (crush ...), (sweep ...)
;                                    or (limit ...) (see Mixer effect!)
;     (instrument NAME PROP ...)     a voice's props (see Mixer play!), with
;                                    (release MS), (layer calm|tension) and
;                                    any number of (voice PROP ...), each a
;                                    voice of its own over the shared props
;     (pattern NAME (INSTRUMENT "CELLS") ...)
;     (order NAME ...))
;
; CELLS are a row each, apart by spaces: a note's name starts that note,
; "." carries on whatever is sounding, and "-" lets it go.  A note sounds
; its instrument's envelope until the next cell in its channel that is
; not ".", or the pattern's end, then fades over its release.  A note
; NAME:PCT plays at PCT percent.  A voice with a pitch of its own, (note
; ...) or (hz ...), keeps it: the note only starts it, as it does a drum.
; A note's cell and the "." cells it is held over can each carry effects,
; "/" then a letter and its numbers: "C4/v30,4 ./s-200 ." is a vibrato
; from the first row and a slide down from the second (see "A note's
; effects" below for the letters).
;
; Tension runs from 0 to 100: it speeds the tempo by its share of
; tension-bpm, and weighs each instrument's notes by its layer, a calm
; one's by what is left of 100 and a tension one's by the tension itself,
; so the one comes in as the other goes.  A note whose weight is 0 is not
; played.  A pace, a percentage, plays the whole song slower or faster
; than that.  A change of song waits for the end of the pattern playing,
; and brings the new song's effects in for the old one's: an effect of
; the same kind at the same place keeps what is ringing in it.
(module x/audio/tracker)

(import x/audio/mixer)
(import x/core/doors int* int+ int- int/ int% int< int= obj-make obj-ref obj-set! str-byte-len str-byte-ref char->int)

(def %fail (fn (_ what) (Err raise (lit value) (Str8 append "Tracker: " what) ())))

(def %prop
  (fn (_ forms key)
    (List find (fn (_ f) (if (pair? f) (eq? (first f) key) #f)) forms)))
(def %prop1 (fn (_ forms key default) ((fn (_ f) (if (null? f) default (first (rest f)))) (%prop forms key))))
(def %props (fn (_ forms key) (List filter (fn (_ f) (if (pair? f) (eq? (first f) key) #f)) forms)))

; --- Songs -----------------------------------------------------------------
;
; A song made from its form: (NAME BPM ROWS TENSION-BPM EFFECTS INSTRUMENTS
; PATTERNS ORDER TICKS).  An instrument is (NAME VOICES ENV RELEASE LAYER), a
; pattern (NAME CHANNEL ...), a channel (INSTRUMENT CELL ...), a cell
; (KIND NOTE PCT EFFECTS): KIND note, hold (".") or off ("-"), and each
; effect (LETTER ARG ...).

(def %tracker-keys (lit (release layer voice)))
(def %effect-heads (lit (echo reverb phase chorus drive crush sweep limit)))

(def %instrument
  (fn (_ f)
    (def name (first (rest f)))
    (def props (rest (rest f)))
    (def shared (List filter (fn (_ p) (not (List find (fn (_ k) (eq? k (first p))) %tracker-keys))) props))
    (def voices (List map (fn (_ v) (List append (rest v) shared)) (%props props (lit voice))))
    (def all (if (null? voices) (list shared) voices))
    (def env (%prop (first all) (lit env)))
    (list name all (if (null? env) (lit ((0 100))) (rest env)) (%prop1 props (lit release) 200)
          (%prop1 props (lit layer) ()))))

(def %cells
  (fn (_ s) (List filter (fn (_ c) (not (str=? c ""))) (Str8 split " " s))))

(def %digits
  (fn (_ s)
    ((fn (self i acc)
       (if (int< i (str-byte-len s)) (self (int+ i 1) (int+ (int* acc 10) (int- (char->int (str-byte-ref s i)) 48))) acc))
     0 0)))

; S as an integer, a leading "-" negative.  Raises for anything else.
(def %int
  (fn (_ s)
    (def neg (if (int< 1 (str-byte-len s)) (str=? (Str8 sub 0 1 s) "-") #f))
    (def ds (if neg (Str8 sub 1 (int- (str-byte-len s) 1) s) s))
    (unless (if (int< 0 (str-byte-len ds))
              ((fn (self i) (if (int< i (str-byte-len ds))
                              (if (int< (str-byte-ref ds i) 48) #f (if (int< 57 (str-byte-ref ds i)) #f (self (int+ i 1))))
                              #t))
               0)
              #f)
      (%fail (Str8 append "not a number: " s)))
    (if neg (int- 0 (%digits ds)) (%digits ds))))

(def %effect-letters (list "a" "v" "s" "p" "t" "f" "l" "c" "d" "r"))

; An effect in a cell, a letter and its numbers apart by commas, "v30,4",
; as (LETTER ARG ...).
(def %effect
  (fn (_ s)
    (def letter (if (int< 0 (str-byte-len s)) (Str8 sub 0 1 s) ""))
    (unless (List any? (fn (_ l) (str=? l letter)) %effect-letters) (%fail (Str8 append "no effect " s)))
    (def args (Str8 sub 1 (int- (str-byte-len s) 1) s))
    (pair letter (if (str=? args "") () (List map %int (Str8 split "," args))))))

(def %note-gain
  (fn (_ cell)
    (def parts (Str8 split ":" cell))
    (if (null? (rest parts)) (pair cell 100)
      (pair (first parts) (%int (first (rest parts)))))))

; A cell, "NOTE[:PCT]", "." or "-", each followed by any number of
; "/EFFECT", as (KIND NOTE PCT EFFECTS).
(def %cell
  (fn (_ s)
    (def parts (Str8 split "/" s))
    (def effects (List map %effect (rest parts)))
    (match ((str=? (first parts) ".") (list (lit hold) () 100 effects))
           ((str=? (first parts) "-") (list (lit off) () 100 effects))
           (#t ((fn (_ ng) (list (lit note) (first ng) (rest ng) effects)) (%note-gain (first parts)))))))

(def %pattern
  (fn (_ f instruments)
    (pair (first (rest f))
      (List map
        (fn (_ ch)
          (when (null? (Assoc entry (first ch) instruments))
            (%fail (Str8 append "no instrument named " (symbol->str (first ch)))))
          (pair (first ch) (List map %cell (%cells (first (rest ch))))))
        (rest (rest f))))))

(def %song
  (fn (_ form)
    (unless (if (pair? form) (eq? (first form) (lit song)) #f) (%fail "a song is (song NAME ...)"))
    (def props (rest (rest form)))
    (def instruments (List map (fn (_ f) (pair (first (rest f)) (%instrument f))) (%props props (lit instrument))))
    (def patterns (List map (fn (_ f) (%pattern f instruments)) (%props props (lit pattern))))
    (def order ((fn (_ f) (if (null? f) () (rest f))) (%prop props (lit order))))
    (when (null? order) (%fail "the song has no order"))
    (List for-each (fn (_ p) (when (null? (Assoc entry p patterns)) (%fail (Str8 append "no pattern named " (symbol->str p)))))
      order)
    (list (first (rest form)) (%prop1 props (lit bpm) 90) (%prop1 props (lit rows) 4)
          (%prop1 props (lit tension-bpm) 0)
          (List filter (fn (_ f) (if (pair? f) (List includes? (first f) %effect-heads) #f)) props)
          instruments patterns order (%prop1 props (lit ticks) 6))))

(def %s-bpm (fn (_ s) (List ref 1 s)))
(def %s-rows (fn (_ s) (List ref 2 s)))
(def %s-tbpm (fn (_ s) (List ref 3 s)))
(def %s-effects (fn (_ s) (List ref 4 s)))
(def %s-instruments (fn (_ s) (List ref 5 s)))
(def %s-patterns (fn (_ s) (List ref 6 s)))
(def %s-order (fn (_ s) (List ref 7 s)))
(def %s-ticks (fn (_ s) (List ref 8 s)))

; --- Trackers --------------------------------------------------------------
;
; A vector record: the song, the song waiting, the place in the order, the
; row, the tension, whether it has been stopped, the pace, a percentage of
; the song's own tempo, the names its effects have in the mixer, each
; a pair of its own, so two trackers in one mixer keep theirs apart, and
; each channel's last note, ((CHANNEL . NOTE) ...), for a portamento.

(def %vector-type ((prim-ref (lit type) (lit of)) (Vector make 0 ())))
(def %get (fn (_ r k) (obj-ref r (int+ k 1))))
(def %put! (fn (_ r k x) (obj-set! r (int+ k 1) x)))

(def %t-song 0) (def %t-next 1) (def %t-at 2) (def %t-row 3) (def %t-tension 4) (def %t-stopped 5)
(def %t-pace 6) (def %t-names 7) (def %t-last 8)

(def %make
  (fn (_ form)
    (def t (obj-make %vector-type 10))
    (obj-set! t 0 9)
    (%put! t %t-song (%song form))
    (%put! t %t-next ())
    (%put! t %t-at 0)
    (%put! t %t-row 0)
    (%put! t %t-tension 0)
    (%put! t %t-stopped #f)
    (%put! t %t-pace 100)
    (%put! t %t-names ())
    (%put! t %t-last ())
    t))

(def %pattern-now
  (fn (_ t)
    (def s (%get t %t-song))
    (rest (Assoc entry (List ref (%get t %t-at) (%s-order s)) (%s-patterns s)))))

; Rows in the pattern: its longest channel's.
(def %pattern-rows
  (fn (_ p) (List fold (fn (_ acc ch) ((fn (_ n) (if (int< acc n) n acc)) (List length (rest ch)))) 0 p)))

(def %row-ms
  (fn (_ t)
    (def s (%get t %t-song))
    (def bpm (int+ (%s-bpm s) (int/ (int* (%s-tbpm s) (%get t %t-tension)) 100)))
    (int/ 6000000 (int* (int* bpm (%s-rows s)) (%get t %t-pace)))))

(def %weight
  (fn (_ layer tension)
    (match ((null? layer) 100) ((eq? layer (lit calm)) (int- 100 tension)) ((eq? layer (lit tension)) tension) (#t 100))))

; Rows a note in CELLS sounds for: to the next cell that is not ".", or
; the end.
(def %held
  (fn (self cells n)
    (match ((null? cells) n) ((eq? (first (first cells)) (lit hold)) (self (rest cells) (int+ n 1))) (#t n))))

; ENV, points (MS PCT), cut at D ms: the points before it, the level there,
; and a fall to nothing over RELEASE.
(def %level-at
  (fn (self pts d last)
    (match ((null? pts) last)
           ((int< d (first (first pts)))
             ((fn (_ t1 l1)
                (if (int= t1 (first last)) l1
                  (int+ (first (rest last)) (int/ (int* (int- l1 (first (rest last))) (int- d (first last))) (int- t1 (first last))))))
              (first (first pts)) (first (rest (first pts)))))
           (#t (self (rest pts) d (first pts))))))

(def %env-for
  (fn (_ env d release)
    (def before (List filter (fn (_ p) (int< (first p) d)) env))
    (def at (%level-at env d (list 0 0)))
    (List append before (list (list d (if (pair? at) (first (rest at)) at)) (list (int+ d release) 0)))))

; Whether voice V has a pitch of its own, (note ...) or (hz ...): such a
; voice keeps it whatever note starts it, as a drum does.
(def %pitched?
  (fn (_ v) (if (null? (%prop v (lit note))) (not (null? (%prop v (lit hz)))) #t)))

; --- A note's effects ------------------------------------------------------
;
; A note's effects are known when it starts: its own cell's and those of
; the "." cells it is held over, each from its row.  Times are ms from the
; note's start; a tick is a row over the song's ticks.  An effect holds
; until the next of its letter in the note, or the note's end:
;
;   a X,Y,...   arpeggio: the note, then X, then Y ... semitones up, a tick each
;   v D,P       vibrato: D cents either way, a cycle every P ticks
;   s C         slide: C cents by the next slide or the note's end, then held
;   p N         portamento: from the channel's last note over N ticks
;   t D,P       tremolo: D percent down and back every P ticks
;   f P         fade: to P percent by the next fade or the note's end
;   l P         low-pass: to P percent of its cut by the next l or the note's end
;   c N         cut: let go N ticks into the row
;   d N         delay: start N ticks into the row (on the note's own cell)
;   r N         retrigger: start again every N ticks
;
; The pitch and the level are paths of points: a voice's (bend (MS CENTS)
; ...) and its envelope, straight between, with a point either side of
; where one jumps.

(def %max (fn (_ a b) (if (int< a b) b a)))
(def %min (fn (_ a b) (if (int< a b) a b)))

; Each effect of the note held H rows at the head of CELLS: (ROW LETTER ARG ...).
(def %note-effects
  (fn (_ cells h)
    ((fn (self cs k acc)
       (if (if (null? cs) #t (not (int< k h))) acc
         (self (rest cs) (int+ k 1) (List append acc (List map (fn (_ e) (pair k e)) (List ref 3 (first cs)))))))
     cells 0 ())))

; FX's effects LETTER as spans (FROM TO ARGS) in ms: each from its row to
; the next of its letter, the last to END.
(def %spans
  (fn (_ fx letter ms end)
    ((fn (self es)
       (if (null? es) ()
         (pair (list (%min end (int* ms (first (first es))))
                     (if (null? (rest es)) end (%min end (int* ms (first (first (rest es))))))
                     (rest (rest (first es))))
               (self (rest es)))))
     (List filter (fn (_ e) (str=? (first (rest e)) letter)) fx))))

; The first effect LETTER in FX, (ROW LETTER ARG ...), or nil.
(def %fx (fn (_ fx letter) (List find (fn (_ e) (str=? (first (rest e)) letter)) fx)))
(def %fx-arg (fn (_ e default) (if (null? e) default (if (null? (rest (rest e))) default (first (rest (rest e)))))))

; How far T is into span SP, or nil outside it: from the right at its
; ends when RIGHT, else from the left.
(def %within
  (fn (_ sp t right)
    (def from (first sp))
    (def to (first (rest sp)))
    (if (if right (if (int< t from) #f (int< t to)) (if (int< from t) (not (int< to t)) #f))
      (int- t from) ())))

; A period of P ticks in ms, at least LEAST and a multiple of it.
(def %period (fn (_ p tick least) (%max least (int* least (int/ (int* p tick) least)))))

; U ms into a period PER: from 0 up to D at a quarter, down to -D at three
; quarters, and back.
(def %wobble
  (fn (_ u per d)
    (def q (int/ per 4))
    (def p (int% u per))
    (match ((int< p q) (int/ (int* d p) q))
           ((int< p (int* 3 q)) (int- d (int/ (int* d (int- p q)) q)))
           (#t (int- (int/ (int* d (int- p (int* 3 q))) q) d)))))

; U ms into a period PER: from 0 up to D at its middle and back.
(def %swell
  (fn (_ u per d)
    (def h (int/ per 2))
    (def p (int% u per))
    (if (int< p h) (int/ (int* d p) h) (int/ (int* d (int- per p)) h))))

; Ramp: 0 before FROM, C by TO, C after.
(def %ramp
  (fn (_ t from to c)
    (match ((int< t from) 0) ((not (int< t to)) c) (#t (int/ (int* c (int- t from)) (int- to from))))))

; FROM, FROM + STEP, ... up to TO, and TO.
(def %marks
  (fn (_ from to step)
    ((fn (self t acc) (if (int< t to) (self (int+ t step) (pair t acc)) (pair to acc))) from ())))

; TIMES from 0 to END, in order, each once.
(def %times
  (fn (_ ts end)
    (List fold (fn (_ acc t) (if (if (null? acc) #f (int= (first acc) t)) acc (pair t acc))) ()
      (List sort (fn (_ a b) (int< b a)) (List filter (fn (_ t) (if (int< t 0) #f (not (int< end t)))) ts)))))

; The points (T V) of VALUE at each of TIMES, two where its value from the
; left and from the right differ.
(def %path
  (fn (_ times value)
    (List flat-map
      (fn (_ t)
        ((fn (_ r l) (if (int= l r) (list (list t r)) (list (list t l) (list t r))))
         (value t #t) (if (int< 0 t) (value t #f) (value t #t))))
      times)))

; The level of envelope PTS, (MS PCT) each, at T.
(def %env-level
  (fn (self pts t)
    (match ((null? pts) 0)
           ((null? (rest pts)) (if (int< t (first (first pts))) 0 (first (rest (first pts)))))
           ((int< t (first (first (rest pts))))
             ((fn (_ a b)
                (if (int< t (first a)) (first (rest a))
                  (int+ (first (rest a)) (int/ (int* (int- (first (rest b)) (first (rest a))) (int- t (first a)))
                                               (%max 1 (int- (first b) (first a)))))))
              (first pts) (first (rest pts))))
           (#t (self (rest pts) t)))))

; A note LEN ms long with the effects FX at MS a row and TICK a tick, its
; instrument's envelope ENV let go over RELEASE, glided from FROM cents
; (nil for none): (ENV BEND FILTER), BEND nil when its pitch is not moved
; and FILTER when its low-pass is not.
(def %shape
  (fn (_ fx len ms tick env release from)
    (def end (int+ len release))
    (def arps (%spans fx "a" ms end))
    (def vibs (%spans fx "v" ms end))
    (def slides (%spans fx "s" ms len))
    (def glide (if (null? from) () (pair from (int* tick (%fx-arg (%fx fx "p") 1)))))
    (def fades (%spans fx "f" ms len))
    (def lows (List filter (fn (_ sp) (not (null? (List ref 2 sp)))) (%spans fx "l" ms len)))
    (def trems (%spans fx "t" ms end))
    (def vib-per (fn (_ sp) (%period (List ref 1 (List ref 2 sp)) tick 4)))
    (def trem-per (fn (_ sp) (%period (List ref 1 (List ref 2 sp)) tick 2)))
    (def two? (fn (_ sp) (int< 1 (List length (List ref 2 sp)))))
    (def cents
      (fn (_ t right)
        (int+ (int+ (List fold (fn (_ acc sp)
                                 ((fn (_ u) (if (if (null? u) #t (null? (List ref 2 sp))) acc
                                              (int+ acc (int* 100 (List ref (int% (int/ (if right u (int- u 1)) tick) (int+ 1 (List length (List ref 2 sp))))
                                                                            (pair 0 (List ref 2 sp)))))))
                                  (%within sp t right)))
                               0 arps)
                    (List fold (fn (_ acc sp) ((fn (_ u) (if (if (null? u) #t (not (two? sp))) acc (int+ acc (%wobble u (vib-per sp) (first (List ref 2 sp))))))
                                               (%within sp t right)))
                               0 vibs))
              (int+ (List fold (fn (_ acc sp) (int+ acc (%ramp t (first sp) (first (rest sp)) (first (List ref 2 sp)))))
                               0 (List filter (fn (_ sp) (not (null? (List ref 2 sp)))) slides))
                    (if (null? glide) 0 (int- (first glide) (%ramp t 0 (%max 1 (rest glide)) (first glide))))))))
    (def toward (fn (_ t) (fn (_ sp) (int- 100 (%ramp t (first sp) (first (rest sp)) (int- 100 (first (List ref 2 sp))))))))
    (def product (fn (_ ps) (List fold (fn (_ acc f) (int/ (int* acc f) 100)) 100 ps)))
    (def factor
      (fn (_ t right)
        (product
          (List append
            (List map (toward t) (List filter (fn (_ sp) (not (null? (List ref 2 sp)))) fades))
            (List map (fn (_ sp) ((fn (_ u) (if (if (null? u) #t (not (two? sp))) 100 (int- 100 (%swell u (trem-per sp) (first (List ref 2 sp))))))
                                  (%within sp t right)))
                      trems)))))
    (def base (%env-for env len release))
    (def bends
      (List append (list 0 end)
        (List flat-map (fn (_ sp) (%marks (first sp) (first (rest sp)) tick)) arps)
        (List flat-map (fn (_ sp) (%marks (first sp) (first (rest sp)) (int/ (vib-per sp) 4))) vibs)
        (List flat-map (fn (_ sp) (list (first sp) (first (rest sp)))) slides)
        (if (null? glide) () (list (rest glide)))))
    (list (if (if (null? fades) (null? trems) #f) base
            (%path (%times (List append (List map first base) (list 0 end)
                                        (List flat-map (fn (_ sp) (list (first sp) (first (rest sp)))) fades)
                                        (List flat-map (fn (_ sp) (%marks (first sp) (first (rest sp)) (int/ (trem-per sp) 2))) trems))
                           end)
                   (fn (_ t right) (int/ (int* (%env-level base t) (factor t right)) 100))))
          (if (if (null? arps) (if (null? vibs) (if (null? slides) (null? glide) #f) #f) #f) ()
            (%path (%times bends end) cents))
          (if (null? lows) ()
            (%path (%times (List append (list 0 end) (List flat-map (fn (_ sp) (list (first sp) (first (rest sp)))) lows)) end)
                   (fn (_ t _) (product (List map (toward t) lows))))))))

; The note at the head of CELLS, in channel CI, started in M at MS a row:
; each voice of instrument INST at W percent, shaped by its effects.
(def %note!
  (fn (_ t m ci cells ms inst w)
    (def cell (first cells))
    (def note (List ref 1 cell))
    (def h (%held (rest cells) 1))
    (def fx (%note-effects cells h))
    (def tick (%max 1 (int/ ms (%s-ticks (%get t %t-song)))))
    (def cut (%fx fx "c"))
    (def len (if (null? cut) (int* h ms) (%min (int* h ms) (int+ (int* ms (first cut)) (int* tick (%fx-arg cut 0))))))
    (def delay ((fn (_ d) (if (if (null? d) #t (not (int= 0 (first d)))) 0 (int* tick (%fx-arg d 0)))) (%fx fx "d")))
    (def every ((fn (_ r) (if (null? r) len (%max 1 (int* tick (%fx-arg r 1))))) (%fx fx "r")))
    (def last (Assoc entry ci (%get t %t-last)))
    (def from (if (if (null? last) #t (null? (%fx fx "p"))) ()
                (int* 100 (int- (Mixer semitone (rest last)) (Mixer semitone note)))))
    (List for-each
      (fn (_ start)
        (def shape (%shape fx (%min every (int- len start)) ms tick (List ref 2 inst) (List ref 3 inst) from))
        (def at (int+ delay start))
        (Mixer play! m
          (List map (fn (_ v)
                      (def own (if (%pitched? v) v (pair (list (lit note) note) v)))
                      (def timed (if (int= at 0) own (pair (list (lit at) (int+ at (%prop1 v (lit at) 0))) own)))
                      (def bent (if (null? (List ref 1 shape)) timed (pair (pair (lit bend) (List ref 1 shape)) timed)))
                      (pair (pair (lit env) (first shape))
                            (if (null? (List ref 2 shape)) bent (pair (pair (lit filter) (List ref 2 shape)) bent))))
                    (List ref 1 inst))
          0 (int/ (int* w (List ref 2 cell)) 100)))
      (List filter (fn (_ s) (int< s len)) (%marks 0 len every)))
    (%put! t %t-last (pair (pair ci note) (List filter (fn (_ e) (not (int= (first e) ci))) (%get t %t-last))))))

; Row ROW of the pattern playing: each channel's note started.
(def %play-row!
  (fn (_ t m row)
    (def s (%get t %t-song))
    (def ms (%row-ms t))
    (def tension (%get t %t-tension))
    (List fold
      (fn (_ ci ch)
        (def cells (List drop row (rest ch)))
        (unless (null? cells)
          (when (eq? (first (first cells)) (lit note))
            (do (def inst (rest (Assoc entry (first ch) (%s-instruments s))))
                (def w (%weight (List ref 4 inst) tension))
                (unless (int= w 0) (%note! t m ci cells ms inst w)))))
        (int+ ci 1))
      0 (%pattern-now t))))

; The song's effects put over M, each under the tracker's name for its
; place, made the first time; a name with no effect left in the song is
; taken off.
(def %effects!
  (fn (_ t m)
    (def specs (%s-effects (%get t %t-song)))
    (def names
      ((fn (self ns n)
         (if (int< (List length ns) n) (self (List append ns (list (pair (lit tracker) (List length ns)))) n) ns))
       (%get t %t-names) (List length specs)))
    (%put! t %t-names names)
    ((fn (self ns ss)
       (unless (null? ns)
         (do (Mixer effect! m (first ns) (if (null? ss) () (first ss)))
             (self (rest ns) (if (null? ss) () (rest ss))))))
     names specs)))

; The tracker as a mixer source: the row due now played, the place moved
; on, the next row's frame answered.
(def %source
  (fn (_ t)
    (fn (_ m now)
      (if (%get t %t-stopped) ()
        (do (def rows (%pattern-rows (%pattern-now t)))
            (%play-row! t m (%get t %t-row))
            (def ms (%row-ms t))
            (if (int< (int+ (%get t %t-row) 1) rows)
              (%put! t %t-row (int+ (%get t %t-row) 1))
              (do (%put! t %t-row 0)
                  (if (null? (%get t %t-next))
                    (%put! t %t-at (if (int< (int+ (%get t %t-at) 1) (List length (%s-order (%get t %t-song))))
                                     (int+ (%get t %t-at) 1) 0))
                    (do (%put! t %t-song (%get t %t-next)) (%put! t %t-next ()) (%put! t %t-at 0) (%effects! t m)))))
            (int+ now (int/ (int* ms (Mixer rate m)) 1000)))))))

(def-class Tracker ()
  (doc "A song of patterns, played into a mixer row by row as one of its sources: instruments described as voices, patterns as rows of notes, an order to play them in, and a tension that speeds the tempo and brings one layer of instruments in as another goes."
    (example "(Tracker name (Tracker make (lit (song \"hum\" (instrument a (wave sine)) (pattern p (a \"C3 . . .\")) (order p)))))" "\"hum\"")
    (see make) (see play!) (see tension!))
  (static
    (method make (self (param form LIST "(song NAME PROP ...): see the module's notes"))
      (doc "A tracker at the start of the song, at no tension. Raises a label 'value for a song that names an instrument or a pattern it does not have, or has no order."
        (returns VECTOR "The tracker")
        (example "(Tracker name (Tracker make (lit (song \"hum\" (instrument a) (pattern p (a \"A3\")) (order p)))))" "\"hum\""))
      (%make form))

    (method name (self (param t VECTOR "A tracker"))
      (doc "The name of the song playing."
        (returns STRING "The name")
        (example "(Tracker name (Tracker make (lit (song \"hum\" (instrument a) (pattern p (a \"A3\")) (order p)))))" "\"hum\""))
      (first (%get t %t-song)))

    (method play! (self (param t VECTOR "A tracker")
                        (param m VECTOR "A mixer"))
      (doc "Play the song in M from the next frame it renders, its effects put over M's mix after any there; played again, the same effects are put back in their places, not added twice."
        (returns VECTOR "The tracker")
        (sample "(Tracker play! t m)" "t"))
      (%effects! t m)
      (%put! t %t-stopped #f)
      (Mixer source! m (%source t) (Mixer clock m))
      t)

    (method stop! (self (param t VECTOR "A tracker"))
      (doc "Play no more rows; the notes sounding fade as they would."
        (returns VECTOR "The tracker")
        (sample "(Tracker stop! t)" "t"))
      (%put! t %t-stopped #t)
      t)

    (method song! (self (param t VECTOR "A tracker")
                        (param form LIST "The next song"))
      (doc "Play FORM's song from its start once the pattern playing ends."
        (returns VECTOR "The tracker")
        (sample "(Tracker song! t (lit (song \"deep\" ...)))" "t"))
      (%put! t %t-next (%song form))
      t)

    (method tension! (self (param t VECTOR "A tracker")
                           (param pct INTEGER "0 calm to 100 tense"))
      (doc "Set the tension the next rows are played at."
        (returns VECTOR "The tracker")
        (sample "(Tracker tension! t 60)" "t"))
      (%put! t %t-tension (if (int< pct 0) 0 (if (int< 100 pct) 100 pct)))
      t)

    (method tension (self (param t VECTOR "A tracker"))
      (doc "The tension the rows are played at."
        (returns INTEGER "0 to 100")
        (example "(Tracker tension (Tracker make (lit (song \"hum\" (instrument a) (pattern p (a \"A3\")) (order p)))))" "0"))
      (%get t %t-tension))

    (method pace! (self (param t VECTOR "A tracker")
                        (param pct INTEGER "Percent of the song's own tempo, 10 to 400; 100 as written"))
      (doc "Play the next rows at PCT percent of the tempo the song and its tension give: the whole song slower or faster."
        (returns VECTOR "The tracker")
        (example "(Tracker row-ms (Tracker pace! (Tracker make (lit (song \"hum\" (bpm 60) (rows 4) (instrument a) (pattern p (a \"A3\")) (order p)))) 50))" "500"))
      (%put! t %t-pace (if (int< pct 10) 10 (if (int< 400 pct) 400 pct)))
      t)

    (method pace (self (param t VECTOR "A tracker"))
      (doc "The percent of the song's own tempo the rows are played at."
        (returns INTEGER "10 to 400")
        (example "(Tracker pace (Tracker make (lit (song \"hum\" (instrument a) (pattern p (a \"A3\")) (order p)))))" "100"))
      (%get t %t-pace))

    (method place (self (param t VECTOR "A tracker"))
      (doc "Where the song has reached: the pattern's place in the order and the next row to play."
        (returns PAIR "(AT . ROW)")
        (example "(Tracker place (Tracker make (lit (song \"hum\" (instrument a) (pattern p (a \"A3\")) (order p)))))" "(0 . 0)"))
      (pair (%get t %t-at) (%get t %t-row)))

    (method row-ms (self (param t VECTOR "A tracker"))
      (doc "A row's length at the tension now."
        (returns INTEGER "Milliseconds")
        (example "(Tracker row-ms (Tracker make (lit (song \"hum\" (bpm 60) (rows 4) (instrument a) (pattern p (a \"A3\")) (order p)))))" "250"))
      (%row-ms t))))

(doc (provide x/audio/tracker Tracker)
  "A music tracker over x/audio/mixer: songs as data, instruments, patterns of rows and an order, played row by row as a mixer source, the tempo and the layers following a tension."
  (example "(Tracker row-ms (Tracker make (lit (song \"hum\" (bpm 120) (rows 4) (instrument a) (pattern p (a \"A3\")) (order p)))))" "125"))
