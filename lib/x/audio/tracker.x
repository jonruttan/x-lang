; tracker.x -- Tracker: a song of patterns played into a mixer, row by row,
; its tempo and its layers following a tension.
;
; A song is data, the forms a .xon file reads as:
;
;   (song "NAME"
;     (bpm 60) (rows 4)              beats a minute, rows a beat
;     (tension-bpm 30)               beats a minute added at full tension
;     (echo 370 40 25)               (MS FB WET), over the whole mixer
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
;
; Tension runs from 0 to 100: it speeds the tempo by its share of
; tension-bpm, and weighs each instrument's notes by its layer, a calm
; one's by what is left of 100 and a tension one's by the tension itself,
; so the one comes in as the other goes.  A note whose weight is 0 is not
; played.  A change of song waits for the end of the pattern playing.
(module x/audio/tracker)

(import x/audio/mixer)
(import x/core/doors int* int+ int- int/ int< int= obj-make obj-ref obj-set! str-byte-len str-byte-ref char->int)

(def %fail (fn (_ what) (Err raise (lit value) (Str8 append "Tracker: " what) ())))

(def %prop
  (fn (_ forms key)
    (List find (fn (_ f) (if (pair? f) (eq? (first f) key) #f)) forms)))
(def %prop1 (fn (_ forms key default) ((fn (_ f) (if (null? f) default (first (rest f)))) (%prop forms key))))
(def %props (fn (_ forms key) (List filter (fn (_ f) (if (pair? f) (eq? (first f) key) #f)) forms)))

; --- Songs -----------------------------------------------------------------
;
; A song made from its form: (NAME BPM ROWS TENSION-BPM ECHOES INSTRUMENTS
; PATTERNS ORDER).  An instrument is (NAME VOICES ENV RELEASE LAYER), a
; pattern (NAME CHANNEL ...), a channel (INSTRUMENT CELL ...).

(def %tracker-keys (lit (release layer voice)))

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

(def %pattern
  (fn (_ f instruments)
    (pair (first (rest f))
      (List map
        (fn (_ ch)
          (when (null? (Assoc entry (first ch) instruments))
            (%fail (Str8 append "no instrument named " (symbol->str (first ch)))))
          (pair (first ch) (%cells (first (rest ch)))))
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
          (List map rest (%props props (lit echo)))
          instruments patterns order)))

(def %s-bpm (fn (_ s) (List ref 1 s)))
(def %s-rows (fn (_ s) (List ref 2 s)))
(def %s-tbpm (fn (_ s) (List ref 3 s)))
(def %s-echoes (fn (_ s) (List ref 4 s)))
(def %s-instruments (fn (_ s) (List ref 5 s)))
(def %s-patterns (fn (_ s) (List ref 6 s)))
(def %s-order (fn (_ s) (List ref 7 s)))

; --- Trackers --------------------------------------------------------------
;
; A vector record: the song, the song waiting, the place in the order, the
; row, the tension, and whether it has been stopped.

(def %vector-type ((prim-ref (lit type) (lit of)) (Vector make 0 ())))
(def %get (fn (_ r k) (obj-ref r (int+ k 1))))
(def %put! (fn (_ r k x) (obj-set! r (int+ k 1) x)))

(def %t-song 0) (def %t-next 1) (def %t-at 2) (def %t-row 3) (def %t-tension 4) (def %t-stopped 5)

(def %make
  (fn (_ form)
    (def t (obj-make %vector-type 7))
    (obj-set! t 0 6)
    (%put! t %t-song (%song form))
    (%put! t %t-next ())
    (%put! t %t-at 0)
    (%put! t %t-row 0)
    (%put! t %t-tension 0)
    (%put! t %t-stopped #f)
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
    (int/ 60000 (int* bpm (%s-rows s)))))

(def %weight
  (fn (_ layer tension)
    (match ((null? layer) 100) ((eq? layer (lit calm)) (int- 100 tension)) ((eq? layer (lit tension)) tension) (#t 100))))

; Rows a note in CELLS sounds for: to the next cell that is not ".", or
; the end.
(def %held
  (fn (self cells n)
    (match ((null? cells) n) ((str=? (first cells) ".") (self (rest cells) (int+ n 1))) (#t n))))

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

(def %note-gain
  (fn (_ cell)
    (def parts (Str8 split ":" cell))
    (if (null? (rest parts)) (pair cell 100)
      (pair (first parts) (%digits (first (rest parts)))))))

(def %digits
  (fn (_ s)
    ((fn (self i acc)
       (if (int< i (str-byte-len s)) (self (int+ i 1) (int+ (int* acc 10) (int- (char->int (str-byte-ref s i)) 48))) acc))
     0 0)))

; Whether voice V has a pitch of its own, (note ...) or (hz ...): such a
; voice keeps it whatever note starts it, as a drum does.
(def %pitched?
  (fn (_ v) (if (null? (%prop v (lit note))) (not (null? (%prop v (lit hz)))) #t)))

; Row ROW of the pattern playing: each channel's note started.
(def %play-row!
  (fn (_ t m row)
    (def s (%get t %t-song))
    (def ms (%row-ms t))
    (def tension (%get t %t-tension))
    (List for-each
      (fn (_ ch)
        (def cells (List drop row (rest ch)))
        (unless (null? cells)
          (unless (match ((str=? (first cells) ".") #t) ((str=? (first cells) "-") #t) (#t #f))
            (do (def inst (rest (Assoc entry (first ch) (%s-instruments s))))
                (def w (%weight (List ref 4 inst) tension))
                (unless (int= w 0)
                  (do (def ng (%note-gain (first cells)))
                      (def env (%env-for (List ref 2 inst) (int* ms (%held (rest cells) 1)) (List ref 3 inst)))
                      (Mixer play! m
                        (List map (fn (_ v) (pair (pair (lit env) env)
                                                  (if (%pitched? v) v (pair (list (lit note) (first ng)) v))))
                                  (List ref 1 inst))
                        0 (int/ (int* w (rest ng)) 100))))))))
      (%pattern-now t))))

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
                    (do (%put! t %t-song (%get t %t-next)) (%put! t %t-next ()) (%put! t %t-at 0)))))
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
      (doc "Play the song in M from the next frame it renders, its echoes added to M's."
        (returns VECTOR "The tracker")
        (sample "(Tracker play! t m)" "t"))
      (List for-each (fn (_ e) (Mixer echo! m (List ref 0 e) (List ref 1 e) (List ref 2 e))) (%s-echoes (%get t %t-song)))
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
