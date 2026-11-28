; tracker.x -- Tracker: a song of patterns played into a mixer, row by row,
; its tempo and its layers following a tension.
;
; A song is data, the forms a .xon file reads as:
;
;   (song "NAME"
;     (bpm 60) (rows 4)              beats a minute, rows a beat
;     (ticks 6)                      ticks a row, for a cell's effects
;     (tick-rate NUM DEN)            NUM/DEN ticks a second, in place of
;                                    bpm and rows: a row is its ticks
;     (tension-bpm 30)               beats a minute added at full tension
;     (let gap (* 3 tick))           a name a number can be, worked out as
;                                    the song plays (see "Names" below)
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
; Time is counted in ticks.  A song gives its tick rate, (tick-rate NUM
; DEN), or its beats a minute and rows a beat, which give B x R x N / 60
; ticks a second at its (ticks N); a row lasts its ticks, so the song's
; rows a beat and ticks a row only divide time, and the one rate counts
; it.  Three effects change the time from their row on, whichever
; channel they are in, as a module's speed and tempo do: m NUM,DEN the
; tick rate (DEN 1 when not given), k N the ticks a row, and h N the row
; held N rows more (1 when not given), its notes held and not struck
; again.  A row starts at the frame its exact time falls in: what a row's
; length leaves over a whole frame is carried to the next, so the song
; does not drift.
;
; Tension runs from 0 to 100: it speeds the tempo by its share of
; tension-bpm, in a song that gives beats a minute and while no m has
; set its rate, and weighs each instrument's notes by its layer, a calm
; one's by what is left of 100 and a tension one's by the tension itself,
; so the one comes in as the other goes.  A note whose weight is 0 is not
; played.  A pace, a percentage, plays the whole song slower or faster
; than that, whatever gives its rate.  A change of song waits for the end of the pattern playing,
; and brings the new song's effects in for the old one's: an effect of
; the same kind at the same place keeps what is ringing in it.
(module x/audio/tracker)

(import x/audio/mixer)
(import x/core/doors int* int+ int- int/ int% int< int= obj-make obj-ref obj-set! obj-same? str-byte-len str-byte-ref str->sym char->int)

(def %fail (fn (_ what) (Err raise (lit value) (Str8 append "Tracker: " what) ())))

(def %prop
  (fn (_ forms key)
    (List find (fn (_ f) (if (pair? f) (eq? (first f) key) #f)) forms)))
(def %prop1 (fn (_ forms key default) ((fn (_ f) (if (null? f) default (first (rest f)))) (%prop forms key))))
(def %props (fn (_ forms key) (List filter (fn (_ f) (if (pair? f) (eq? (first f) key) #f)) forms)))

; --- Songs -----------------------------------------------------------------
;
; A song made from its form: (NAME BPM ROWS TENSION-BPM EFFECTS INSTRUMENTS
; PATTERNS ORDER TICKS LETS NAMED-EFFECTS NAMED RATE), LETS its (let ...)
; forms as (NAME . EXPR), NAMED-EFFECTS whether its effects use a name,
; NAMED whether anything does and RATE its tick rate, (NUM . DEN) or nil
; for one of BPM.  An instrument is (NAME VOICES ENV RELEASE LAYER
; NAMED), NAMED whether its props use a name, a pattern (NAME CHANNEL ...),
; a channel (INSTRUMENT CELL ...), a cell (KIND NOTE PCT EFFECTS): KIND
; note, hold (".") or off ("-"), and each effect (LETTER ARG ...), an ARG
; an integer or a name.

(def %tracker-keys (lit (release layer voice)))
(def %effect-heads (lit (echo reverb phase chorus drive crush sweep limit)))

; --- Names -----------------------------------------------------------------
;
; A number in an instrument, a song effect or a cell's effect can be a
; name, worked out each time it is used, with the tempo then:
;
;   bpm     beats a minute as played: the tick rate over rows rows of
;           ticks ticks, so for a song of beats a minute its own, its
;           tension's share of tension-bpm added, at the pace
;   rows    rows a beat         ticks   ticks a row, as k last set them
;   row     a row's length in ms        beat    a beat's, rows rows
;   tick    a tick's, at least 1
;
; m, k and h take numbers, not names: they set the time the names are
; worked out from.
;
; and any the song defines, (let NAME EXPR), each from the ones before
; it.  An instrument or a song effect can also have a sum where a number
; goes: (+ A B ...), (- A B ...), (* A B ...), (/ A B) whole, (min A B
; ...), (max A B ...), each of integers and names.  A cell's effect takes
; a name, "C4/eecho,30,16", and no sum.  A word a prop takes, (wave sine),
; (pass low) or (layer calm), is never a name.

(def %own-names (lit (bpm rows ticks row beat tick)))
(def %ops (lit (+ - * / min max)))
(def %word-props (lit (wave pass layer)))

(def %op?
  (fn (_ x) (if (pair? x) (List includes? (first x) %ops) #f)))

; Whether X, a prop or a part of one, uses a name of NAMES or a sum;
; raises for a name in a sum that NAMES has not.
(def %uses?
  (fn (self x names)
    (match ((symbol? x) (List includes? x names))
           ((%op? x)
             (do (List for-each
                   (fn (_ a) (when (if (symbol? a) (not (List includes? a names)) #f)
                               (%fail (Str8 append "no name " (symbol->str a)))))
                   (rest x))
                 #t))
           ((pair? x) (if (List includes? (first x) %word-props) #f (List any? (fn (_ y) (self y names)) x)))
           (#t #f))))

; X with each name worked out from ENV, ((NAME . VALUE) ...), and each sum
; done: the integer for a name or a sum, X itself for anything else.
(def %resolve
  (fn (self x env)
    (match ((symbol? x) ((fn (_ b) (if (null? b) x (rest b))) (Assoc entry x env)))
           ((%op? x)
             ((fn (_ op args)
                (when (List any? (fn (_ a) (not (number? a))) args)
                  (%fail (Str8 append "not a number in " (symbol->str op))))
                (match ((null? args) (%fail (Str8 append "nothing to " (symbol->str op))))
                       ((eq? op (lit +)) (List fold int+ 0 args))
                       ((eq? op (lit *)) (List fold int* 1 args))
                       ((eq? op (lit -)) (if (null? (rest args)) (int- 0 (first args)) (List fold int- (first args) (rest args))))
                       ((eq? op (lit /))
                         (if (int= 0 (List ref 1 args)) (%fail "a sum divides by 0") (int/ (first args) (List ref 1 args))))
                       ((eq? op (lit min)) (List fold %min (first args) (rest args)))
                       (#t (List fold %max (first args) (rest args)))))
              (first x) (List map (fn (_ a) (self a env)) (rest x))))
           ((pair? x) (if (List includes? (first x) %word-props) x (List map (fn (_ y) (self y env)) x)))
           (#t x))))

; The lets of the song's PROPS, ((NAME . EXPR) ...) in order, each name
; new and its EXPR of integers and the names before it.
(def %lets
  (fn (_ props)
    (List fold
      (fn (_ acc f)
        (def name (if (pair? (rest f)) (List ref 1 f) ()))
        (unless (if (symbol? name) (if (pair? (rest (rest f))) (null? (rest (rest (rest f)))) #f) #f)
          (%fail "a let is (let NAME EXPR)"))
        (when (List includes? name (List append %own-names (List map first acc)))
          (%fail (Str8 append "a let names " (symbol->str name) " twice, or a name of the song's own")))
        (def expr (List ref 2 f))
        (def known (List append %own-names (List map first acc)))
        (unless (if (number? expr) #t (if (symbol? expr) (List includes? expr known) (if (%op? expr) (%uses? expr known) #f)))
          (%fail (Str8 append "not a number or a name: let " (symbol->str name))))
        (List append acc (list (pair name expr))))
      () (%props props (lit let)))))

(def %instrument
  (fn (_ f names)
    (def name (first (rest f)))
    (def props (rest (rest f)))
    (def shared (List filter (fn (_ p) (not (List find (fn (_ k) (eq? k (first p))) %tracker-keys))) props))
    (def voices (List map (fn (_ v) (List append (rest v) shared)) (%props props (lit voice))))
    (def all (if (null? voices) (list shared) voices))
    (def env (%prop (first all) (lit env)))
    (list name all (if (null? env) (lit ((0 100))) (rest env)) (%prop1 props (lit release) 200)
          (%prop1 props (lit layer) ()) (%uses? props names))))

; Instrument INST, (NAME VOICES ENV RELEASE LAYER NAMED), with its names
; worked out from ENV when it has any.
(def %instrument-now
  (fn (_ inst env)
    (if (List ref 5 inst)
      (list (first inst) (%resolve (List ref 1 inst) env) (%resolve (List ref 2 inst) env) (%resolve (List ref 3 inst) env)
            (List ref 4 inst) #f)
      inst)))

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

; ARGS, (NUM) or (NUM DEN), as (NUM . DEN), DEN 1 when not given, for
; WHAT.  Raises unless both are integers above 0.
(def %fraction
  (fn (_ args what)
    (def num (if (null? args) () (first args)))
    (def den (if (if (null? args) #t (null? (rest args))) 1 (first (rest args))))
    (unless (if (Num int? num) (if (Num int? den) (if (int< 0 num) (int< 0 den) #f) #f) #f)
      (%fail (Str8 append what " is NUM or NUM,DEN, each above 0")))
    (pair num den)))

(def %effect-letters (list "a" "v" "s" "p" "t" "f" "l" "w" "o" "x" "y" "c" "d" "r" "e" "m" "k" "h"))

; Effect E, (LETTER ARG ...), checked when it is one of the time's.
(def %timed
  (fn (_ e)
    (match ((str=? (first e) "m") (%fraction (rest e) "m"))
           ((str=? (first e) "k") (unless (if (null? (rest e)) #f (if (Num int? (first (rest e))) (int< 0 (first (rest e))) #f)) (%fail "k is N, 1 or more")))
           ((str=? (first e) "h") (unless (if (null? (rest e)) #t (if (Num int? (first (rest e))) (not (int< (first (rest e)) 0)) #f)) (%fail "h is N, 0 or more")))
           (#t ()))
    e))

; Whether S starts as a name does, with a letter.
(def %name-text?
  (fn (_ s) (if (int< 0 (str-byte-len s)) ((fn (_ b) (if (int< b 97) #f (not (int< 122 b)))) (str-byte-ref s 0)) #f)))

; An effect in a cell, a letter and its numbers apart by commas, "v30,4",
; as (LETTER ARG ...); an ARG that starts with a letter is a name, kept
; as its symbol.
(def %effect
  (fn (_ s)
    (def letter (if (int< 0 (str-byte-len s)) (Str8 sub 0 1 s) ""))
    (unless (List any? (fn (_ l) (str=? l letter)) %effect-letters) (%fail (Str8 append "no effect " s)))
    (def args (Str8 sub 1 (int- (str-byte-len s) 1) s))
    (%timed (pair letter (if (str=? args "") () (List map (fn (_ a) (if (%name-text? a) (str->sym a) (%int a))) (Str8 split "," args)))))))

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
  (fn (_ f instruments names)
    (pair (first (rest f))
      (List map
        (fn (_ ch)
          (when (null? (Assoc entry (first ch) instruments))
            (%fail (Str8 append "no instrument named " (symbol->str (first ch)))))
          (def cells (List map %cell (%cells (first (rest ch)))))
          (List for-each
            (fn (_ c) (List for-each
                        (fn (_ e) (List for-each (fn (_ a) (when (if (symbol? a) (not (List includes? a names)) #f)
                                                            (%fail (Str8 append "no name " (symbol->str a)))))
                                    (rest e)))
                        (List ref 3 c)))
            cells)
          (pair (first ch) cells))
        (rest (rest f))))))

(def %song
  (fn (_ form)
    (unless (if (pair? form) (eq? (first form) (lit song)) #f) (%fail "a song is (song NAME ...)"))
    (def props (rest (rest form)))
    (def lets (%lets props))
    (def names (List append %own-names (List map first lets)))
    (def instruments (List map (fn (_ f) (pair (first (rest f)) (%instrument f names))) (%props props (lit instrument))))
    (def patterns (List map (fn (_ f) (%pattern f instruments names)) (%props props (lit pattern))))
    (def order ((fn (_ f) (if (null? f) () (rest f))) (%prop props (lit order))))
    (when (null? order) (%fail "the song has no order"))
    (List for-each (fn (_ p) (when (null? (Assoc entry p patterns)) (%fail (Str8 append "no pattern named " (symbol->str p)))))
      order)
    (def rate (%prop props (lit tick-rate)))
    (when (if (null? rate) #f (not (null? (%prop props (lit bpm))))) (%fail "a song gives bpm or tick-rate, not both"))
    (def ticks (%prop1 props (lit ticks) 6))
    (unless (if (Num int? ticks) (int< 0 ticks) #f) (%fail "a song's ticks are 1 or more"))
    (def effects (List filter (fn (_ f) (if (pair? f) (List includes? (first f) %effect-heads) #f)) props))
    (def named-effects (List any? (fn (_ e) (%uses? e names)) effects))
    (def named-cells
      (List any? (fn (_ p) (List any? (fn (_ ch) (List any? (fn (_ c) (List any? (fn (_ e) (List any? symbol? (rest e))) (List ref 3 c)))
                                                          (rest ch)))
                                    (rest p)))
            patterns))
    (list (first (rest form)) (%prop1 props (lit bpm) 90) (%prop1 props (lit rows) 4)
          (%prop1 props (lit tension-bpm) 0)
          effects
          instruments patterns order ticks
          lets named-effects
          (if named-effects #t (if named-cells #t (List any? (fn (_ i) (List ref 5 (rest i))) instruments)))
          (if (null? rate) () (%fraction (rest rate) "tick-rate"))
          (List map (fn (_ p) (pair (first p) (%pattern-times (rest p)))) patterns))))

(def %s-bpm (fn (_ s) (List ref 1 s)))
(def %s-rows (fn (_ s) (List ref 2 s)))
(def %s-tbpm (fn (_ s) (List ref 3 s)))
(def %s-effects (fn (_ s) (List ref 4 s)))
(def %s-instruments (fn (_ s) (List ref 5 s)))
(def %s-patterns (fn (_ s) (List ref 6 s)))
(def %s-order (fn (_ s) (List ref 7 s)))
(def %s-ticks (fn (_ s) (List ref 8 s)))
(def %s-lets (fn (_ s) (List ref 9 s)))
(def %s-named-effects (fn (_ s) (List ref 10 s)))
(def %s-named (fn (_ s) (List ref 11 s)))
(def %s-rate (fn (_ s) (List ref 12 s)))
(def %s-times (fn (_ s) (List ref 13 s)))

; --- Trackers --------------------------------------------------------------
;
; A vector record: the song, the song waiting, the place in the order, the
; row, the tension, whether it has been stopped, the pace, a percentage of
; the song's own tempo, the names its effects have in the mixer, each
; a pair of its own, so two trackers in one mixer keep theirs apart, each
; channel's last note, ((CHANNEL . NOTE) ...), for a portamento, the
; song's effects as last put, their names worked out, the tick rate,
; (NUM . DEN) or nil for the song's beats a minute, the ticks a row, and
; the part of a frame the rows so far have left over, (NUM . PART), PART
; in NUMths of a frame.

(def %vector-type ((prim-ref (lit type) (lit of)) (Vector make 0 ())))
(def %get (fn (_ r k) (obj-ref r (int+ k 1))))
(def %put! (fn (_ r k x) (obj-set! r (int+ k 1) x)))

(def %t-song 0) (def %t-next 1) (def %t-at 2) (def %t-row 3) (def %t-tension 4) (def %t-stopped 5)
(def %t-pace 6) (def %t-names 7) (def %t-last 8) (def %t-specs 9) (def %t-rate 10) (def %t-ticks 11)
(def %t-carry 12)

; The time of song S at its start: its tick rate and ticks a row.
(def %time!
  (fn (_ t s)
    (%put! t %t-rate (%s-rate s))
    (%put! t %t-ticks (%s-ticks s))))

(def %make
  (fn (_ form)
    (def t (obj-make %vector-type 14))
    (obj-set! t 0 13)
    (%put! t %t-song (%song form))
    (%put! t %t-next ())
    (%put! t %t-at 0)
    (%put! t %t-row 0)
    (%put! t %t-tension 0)
    (%put! t %t-stopped #f)
    (%put! t %t-pace 100)
    (%put! t %t-names ())
    (%put! t %t-last ())
    (%put! t %t-specs ())
    (%time! t (%get t %t-song))
    (%put! t %t-carry (pair 0 0))
    t))

(def %pattern-now
  (fn (_ t)
    (def s (%get t %t-song))
    (rest (Assoc entry (List ref (%get t %t-at) (%s-order s)) (%s-patterns s)))))

; Rows in the pattern: its longest channel's.
(def %pattern-rows
  (fn (_ p) (List fold (fn (_ acc ch) ((fn (_ n) (if (int< acc n) n acc)) (List length (rest ch)))) 0 p)))

; --- Time ------------------------------------------------------------------
;
; A time is (RATE . TICKS): the tick rate, (NUM . DEN) ticks a second or nil
; for the song's beats a minute, and the ticks a row.

(def %gcd (fn (self a b) (if (int= b 0) a (self b (int% a b)))))

; The ticks a second at RATE, at the tension and the pace, (NUM . DEN) in
; lowest terms: a song's beats a minute B, rows a beat R and ticks a row N
; give B x R x N / 60.
(def %rate
  (fn (_ t rate)
    (def s (%get t %t-song))
    (def pace (%get t %t-pace))
    (def bpm (int+ (%s-bpm s) (int/ (int* (%s-tbpm s) (%get t %t-tension)) 100)))
    ((fn (_ n d) ((fn (_ g) (pair (int/ n g) (int/ d g))) (%gcd n d)))
     (if (null? rate) (int* (int* (int* bpm (%s-rows s)) (%s-ticks s)) pace) (int* (first rate) pace))
     (int* (if (null? rate) 60 (rest rate)) 100))))

; N ticks at RATE, (NUM . DEN) ticks a second, in units U a second, from
; PART NUMths of a unit left over: (UNITS . PART).  Tick by tick, so no
; product is larger than a unit's NUMths in a tick.
(def %count
  (fn (_ rate n u part)
    ((fn (self k whole c)
       (if (int< k 1) (pair whole c)
         ((fn (_ total) (self (int- k 1) (int+ whole (int/ total (first rate))) (int% total (first rate))))
          (int+ c (int* u (rest rate))))))
     n 0 part)))

; The part left over of CARRY, (NUM . PART), at RATE: none when the rate's
; NUM is another.
(def %part (fn (_ carry rate) (if (int= (first carry) (first rate)) (rest carry) 0)))

(def %time-letters (list "m" "k" "h"))

; The time effects of the row FRONTS start at, FRONTS each channel's
; cells from that row on, each channel's in turn.
(def %front-times
  (fn (_ fronts)
    (List flat-map
      (fn (_ cs) (if (null? cs) ()
                   (List filter (fn (_ e) (List any? (fn (_ l) (str=? l (first e))) %time-letters)) (List ref 3 (first cs)))))
      fronts)))

; Pattern P's time effects, a row each, each channel's in turn: read once,
; when the song is made, the channels' cells walked a row at a time.
(def %pattern-times
  (fn (_ p)
    (def n (%pattern-rows p))
    (Vector from-list
      ((fn (self k fronts acc)
         (if (int< k n)
           (self (int+ k 1) (List map (fn (_ cs) (if (null? cs) () (rest cs))) fronts) (pair (%front-times fronts) acc))
           (List reverse acc)))
       0 (List map rest p) ()))))

; The time effects of row ROW of the pattern playing in T.
(def %row-times
  (fn (_ t row)
    (def s (%get t %t-song))
    ((fn (_ v) (if (int< row (Vector length v)) (Vector ref row v) ()))
     (rest (Assoc entry (List ref (%get t %t-at) (%s-order s)) (%s-times s))))))

; TIME after a row's time effects ES: an m sets the rate, a k the ticks.
(def %time-after
  (fn (_ time es)
    (List fold
      (fn (_ tm e)
        (match ((str=? (first e) "m") (pair (%fraction (rest e) "m") (rest tm)))
               ((str=? (first e) "k") (pair (first tm) (first (rest e))))
               (#t tm)))
      time es)))

; The rows more a row's time effects ES hold it: the last h's, 1 when it
; gives no N, 0 when there is none.
(def %hold
  (fn (_ es)
    (List fold (fn (_ n e) (if (str=? (first e) "h") (if (null? (rest e)) 1 (first (rest e))) n)) 0 es)))

; The ticks a row of time effects ES lasts at TIME, its hold counted.
(def %row-ticks (fn (_ es time) (int* (rest time) (int+ 1 (%hold es)))))

; The ms from the start of row ROW of the pattern playing in T to the
; start of each of the H rows after it, from its own 0, (0 MS ...): row
; ROW at the time now, each after it at the time its effects give.  The
; ticks a second are worked out again only where an m changes them.
(def %offsets
  (fn (_ t row h)
    ((fn (self j time key r carry at acc)
       (if (int< j h)
         (do (def es (%row-times t (int+ row j)))
             (def tm (if (int= j 0) time (%time-after time es)))
             (def r1 (if (obj-same? key (first tm)) r (%rate t (first tm))))
             (def d (%count r1 (%row-ticks es tm) 1000 (%part carry r1)))
             (self (int+ j 1) tm (first tm) r1 (pair (first r1) (rest d)) (int+ at (first d)) (pair (int+ at (first d)) acc)))
         (List reverse acc)))
     0 (pair (%get t %t-rate) (%get t %t-ticks)) (lit none) () (pair 0 0) 0 (list 0))))

; A row's length in ms at the time now, its hold not counted.
(def %row-ms
  (fn (_ t) (first (%count (%rate t (%get t %t-rate)) (%get t %t-ticks) 1000 0))))

; A tick's length in ms at the time now, 1 at the least.
(def %tick-ms
  (fn (_ t) (%max 1 (first (%count (%rate t (%get t %t-rate)) 1 1000 0)))))

; The names the song playing in T has now, ((NAME . VALUE) ...): its own,
; from the tempo, then its lets in order.
(def %names-now
  (fn (_ t)
    (def s (%get t %t-song))
    (def row (%row-ms t))
    (def ticks (%get t %t-ticks))
    (def r (%rate t (%get t %t-rate)))
    (def d (int* (rest r) (int* (%s-rows s) ticks)))
    (def bpm (int+ (int* 60 (int/ (first r) d)) (int/ (int* 60 (int% (first r) d)) d)))
    (List fold (fn (_ env l) (List append env (list (pair (first l) (%resolve (rest l) env)))))
      (list (pair (lit bpm) bpm) (pair (lit rows) (%s-rows s)) (pair (lit ticks) ticks)
            (pair (lit row) row) (pair (lit beat) (int* row (%s-rows s))) (pair (lit tick) (%tick-ms t)))
      (%s-lets s))))

; The song's effects in T with their names worked out from ENV.
(def %specs-now
  (fn (_ t env)
    ((fn (_ specs) (if (%s-named-effects (%get t %t-song)) (List map (fn (_ e) (%resolve e env)) specs) specs))
     (%s-effects (%get t %t-song)))))

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
; note's start; a tick is its length at the note's row.  An effect holds
; until the next of its letter in the note, or the note's end:
;
;   a X,Y,...   arpeggio: the note, then X, then Y ... semitones up, a tick each
;   v D,P       vibrato: D cents either way, a cycle every P ticks
;   s C         slide: C cents by the next slide or the note's end, then held
;   p N         portamento: from the channel's last note over N ticks
;   t D,P       tremolo: D percent down and back every P ticks
;   f P         fade: to P percent by the next fade or the note's end
;   l P         low-pass: to P percent of its cut by the next l or the note's end
;   w P         width: a pulse's to P percent of its cycle by the next w or the
;               note's end, from its own width
;   o H         cutoff: a resonant filter's to H hertz by the next o or the
;               note's end, from its own cutoff (see Mixer play!)
;   x C         ring: the note rung by a modulator C cents from its pitch
;   y C         sync: the note hard-synced to a modulator C cents from its
;               pitch (see Mixer play!)
;   c N         cut: let go N ticks into the row
;   d N         delay: start N ticks into the row (on the note's own cell)
;   r N         retrigger: start again every N ticks
;   e MS,P,N    echo: the note again MS ms later at P percent (50), N times
;               (1), each at P percent of the one before
;
; and three that are the song's time, not the note's, from their row on
; (see the module's notes): m NUM,DEN the tick rate, k N the ticks a row,
; h N the row held N rows more.
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
; the next of its letter, the last to END, row K starting AT K ms in.
(def %spans
  (fn (_ fx letter at end)
    ((fn (self es)
       (if (null? es) ()
         (pair (list (%min end (at (first (first es))))
                     (if (null? (rest es)) end (%min end (at (first (first (rest es))))))
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

; A note LEN ms long with the effects FX, its row K starting AT K ms in,
; at TICK ms a tick, its
; instrument's envelope ENV let go over RELEASE, glided from FROM cents
; (nil for none): (ENV BEND FILTER WIDTHS CUTOFFS), BEND nil when its
; pitch is not moved and FILTER when its low-pass is not, WIDTHS and
; CUTOFFS the spans of its widths and cutoffs, nil for none.
(def %shape
  (fn (_ fx len at tick env release from)
    (def end (int+ len release))
    (def arps (%spans fx "a" at end))
    (def vibs (%spans fx "v" at end))
    (def slides (%spans fx "s" at len))
    (def glide (if (null? from) () (pair from (int* tick (%fx-arg (%fx fx "p") 1)))))
    (def fades (%spans fx "f" at len))
    (def lows (List filter (fn (_ sp) (not (null? (List ref 2 sp)))) (%spans fx "l" at len)))
    (def trems (%spans fx "t" at end))
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
                   (fn (_ t _) (product (List map (toward t) lows)))))
          (List filter (fn (_ sp) (not (null? (List ref 2 sp)))) (%spans fx "w" at len))
          (List filter (fn (_ sp) (not (null? (List ref 2 sp)))) (%spans fx "o" at len)))))

; The path of SPANS, a letter's spans from %shape, over END ms from FROM:
; each span moves it to its argument, and it holds between.
(def %span-path
  (fn (_ spans from end)
    (%path (%times (List append (list 0 end) (List flat-map (fn (_ sp) (list (first sp) (first (rest sp)))) spans)) end)
           (fn (_ t _) (List fold (fn (_ cur sp) (int+ cur (%ramp t (first sp) (first (rest sp)) (int- (first (List ref 2 sp)) cur))))
                                  from spans)))))

; Voice V with SPANS moving its path KEY from FROM, or V as it is when
; there are no SPANS or FROM is nil (it has no path KEY to move).
(def %moved
  (fn (_ v key spans end from)
    (if (if (null? spans) #t (null? from)) v
      (pair (pair key (%span-path spans from end)) v))))

; The first point's value of path KEY of voice V, or nil.
(def %start (fn (_ v key) ((fn (_ own) (if (null? own) () (first (rest (first (rest own)))))) (%prop v key))))

; Voice V with WIDTHS moving its width, when it is a pulse or has a width
; of its own: from its width's first point, a pulse's 50 when it has none.
(def %widened
  (fn (_ v widths end)
    (def own (%start v (lit width)))
    (%moved v (lit width) widths end
            (if (null? own) (if (eq? (%prop1 v (lit wave) ()) (lit pulse)) 50 ()) own))))

; Voice V with the note's first ring (x C) and sync (y C) of FX ahead of
; its own: a modulator C cents from its pitch, 0 when the effect has none.
(def %coupled
  (fn (_ v fx)
    (List fold (fn (_ acc lk) ((fn (_ e) (if (null? e) acc (pair (list (rest lk) (%fx-arg e 0)) acc))) (%fx fx (first lk))))
               v (list (pair "x" (lit ring)) (pair "y" (lit sync))))))

; The times and levels a note sounds at, (MS . PERCENT) each: itself at 0
; and 100, then the echoes of E, the note's e MS,PCT,N: N of them (1
; when it gives none), each MS after the one before at PCT percent of
; it (50 when it gives none).  An echo at 0 percent is not played.
(def %echoes
  (fn (_ e)
    (if (null? e) (list (pair 0 100))
      ((fn (_ gap pct n)
         ((fn (self k at level acc)
            (if (if (int< n k) #t (int= level 0)) (List reverse acc)
              (self (int+ k 1) (int+ at gap) (int/ (int* level pct) 100) (pair (pair at level) acc))))
          0 0 100 ()))
       (%max 1 (%fx-nth e 0 1)) (%max 0 (%min 100 (%fx-nth e 1 50))) (%max 0 (%fx-nth e 2 1))))))

; Effect E's number K from 0, or DEFAULT when it has none there.
(def %fx-nth
  (fn (_ e k default)
    ((fn (self args k) (match ((null? args) default) ((int= k 0) (first args)) (#t (self (rest args) (int- k 1)))))
     (rest (rest e)) k)))

; The note at the head of CELLS, in channel CI, started in M: its rows
; starting OFFS ms in, (0 MS ...), each a tick TICK ms long; each voice
; of instrument INST at W percent, shaped by its effects.
(def %note!
  (fn (_ t m ci cells offs tick inst w env)
    (def cell (first cells))
    (def note (List ref 1 cell))
    (def h (%held (rest cells) 1))
    (def fx ((fn (_ es) (if (null? env) es (List map (fn (_ e) (%resolve e env)) es))) (%note-effects cells h)))
    (def row-at (fn (_ k) (List ref k offs)))
    (def cut (%fx fx "c"))
    (def len (if (null? cut) (row-at h) (%min (row-at h) (int+ (row-at (first cut)) (int* tick (%fx-arg cut 0))))))
    (def delay ((fn (_ d) (if (if (null? d) #t (not (int= 0 (first d)))) 0 (int* tick (%fx-arg d 0)))) (%fx fx "d")))
    (def every ((fn (_ r) (if (null? r) len (%max 1 (int* tick (%fx-arg r 1))))) (%fx fx "r")))
    (def last (Assoc entry ci (%get t %t-last)))
    (def from (if (if (null? last) #t (null? (%fx fx "p"))) ()
                (int* 100 (int- (Mixer semitone (rest last)) (Mixer semitone note)))))
    (def echoes (%echoes (%fx fx "e")))
    (List for-each
      (fn (_ start)
        (def shape (%shape fx (%min every (int- len start)) row-at tick (List ref 2 inst) (List ref 3 inst) from))
        (List for-each
          (fn (_ echo)
            (def at (int+ (int+ delay start) (first echo)))
            (Mixer play! m
              (List map (fn (_ v)
                          (def end (int+ (%min every (int- len start)) (List ref 3 inst)))
                          (def own (%coupled (%moved (%widened (if (%pitched? v) v (pair (list (lit note) note) v)) (List ref 3 shape) end)
                                                     (lit cutoff) (List ref 4 shape) end (%start v (lit cutoff)))
                                             fx))
                          (def timed (if (int= at 0) own (pair (list (lit at) (int+ at (%prop1 v (lit at) 0))) own)))
                          (def bent (if (null? (List ref 1 shape)) timed (pair (pair (lit bend) (List ref 1 shape)) timed)))
                          (pair (pair (lit env) (first shape))
                                (if (null? (List ref 2 shape)) bent (pair (pair (lit filter) (List ref 2 shape)) bent))))
                        (List ref 1 inst))
              0 (int/ (int* (int/ (int* w (List ref 2 cell)) 100) (rest echo)) 100)))
          echoes))
      (List filter (fn (_ s) (int< s len)) (%marks 0 len every)))
    (%put! t %t-last (pair (pair ci note) (List filter (fn (_ e) (not (int= (first e) ci))) (%get t %t-last))))))

; Row ROW of the pattern playing: each channel's note started.
(def %play-row!
  (fn (_ t m row)
    (def s (%get t %t-song))
    (def p (%pattern-now t))
    (def tick (%tick-ms t))
    (def tension (%get t %t-tension))
    (def env (if (%s-named s) (%names-now t) ()))
    (List fold
      (fn (_ ci ch)
        (def cells (List drop row (rest ch)))
        (unless (null? cells)
          (when (eq? (first (first cells)) (lit note))
            (do (def inst (%instrument-now (rest (Assoc entry (first ch) (%s-instruments s))) env))
                (def w (%weight (List ref 4 inst) tension))
                (unless (int= w 0) (%note! t m ci cells (%offsets t row (%held (rest cells) 1)) tick inst w env)))))
        (int+ ci 1))
      0 p)))

; The song's effects put over M, each under the tracker's name for its
; place, made the first time; a name with no effect left in the song is
; taken off.  Their names are worked out with the tempo now, and the specs
; put kept to tell when a change of tempo changes them.
(def %effects!
  (fn (_ t m)
    (def specs (%specs-now t (if (%s-named-effects (%get t %t-song)) (%names-now t) ())))
    (%put! t %t-specs specs)
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

; The tracker as a mixer source: the time the row due now gives taken,
; the row played, the place moved on, and the next row's frame answered,
; the frame its exact time falls in.  The song's effects are put again
; before a row when a name they use has changed with the tempo.
(def %source
  (fn (_ t)
    (fn (_ m now)
      (if (%get t %t-stopped) ()
        (do (def p (%pattern-now t))
            (def rows (%pattern-rows p))
            (def row (%get t %t-row))
            (def es (%row-times t row))
            (def time (%time-after (pair (%get t %t-rate) (%get t %t-ticks)) es))
            (%put! t %t-rate (first time))
            (%put! t %t-ticks (rest time))
            (when (if (%s-named-effects (%get t %t-song))
                    (not (equal? (%specs-now t (%names-now t)) (%get t %t-specs))) #f)
              (%effects! t m))
            (%play-row! t m row)
            (def r (%rate t (first time)))
            (def due (%count r (%row-ticks es time) (Mixer rate m) (%part (%get t %t-carry) r)))
            (%put! t %t-carry (pair (first r) (rest due)))
            (if (int< (int+ row 1) rows)
              (%put! t %t-row (int+ row 1))
              (do (%put! t %t-row 0)
                  (if (null? (%get t %t-next))
                    (%put! t %t-at (if (int< (int+ (%get t %t-at) 1) (List length (%s-order (%get t %t-song))))
                                     (int+ (%get t %t-at) 1) 0))
                    (do (%put! t %t-song (%get t %t-next)) (%put! t %t-next ()) (%put! t %t-at 0)
                        (%time! t (%get t %t-song)) (%effects! t m)))))
            (int+ now (first due)))))))

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
      (doc "A row's length at the time and the tension now, a hold not counted, to the ms below."
        (returns INTEGER "Milliseconds")
        (example "(Tracker row-ms (Tracker make (lit (song \"hum\" (bpm 60) (rows 4) (instrument a) (pattern p (a \"A3\")) (order p)))))" "250"))
      (%row-ms t))

    (method names (self (param t VECTOR "A tracker"))
      (doc "The names a number in the song can be, worked out at the tension and pace now: bpm, rows, ticks, row, beat and tick, then the song's lets in order."
        (returns LIST "((NAME . VALUE) ...)")
        (example "(rest (Assoc entry (lit gap) (Tracker names (Tracker make (lit (song \"hum\" (bpm 60) (rows 4) (let gap (* 3 tick)) (instrument a) (pattern p (a \"A3\")) (order p)))))))" "123"))
      (%names-now t))))

(doc (provide x/audio/tracker Tracker)
  "A music tracker over x/audio/mixer: songs as data, instruments, patterns of rows and an order, played row by row as a mixer source, the tempo and the layers following a tension."
  (example "(Tracker row-ms (Tracker make (lit (song \"hum\" (bpm 120) (rows 4) (instrument a) (pattern p (a \"A3\")) (order p)))))" "125"))
