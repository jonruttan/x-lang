; story.x -- How everything comes together: x-expr, the engine, x-lang, its
; libraries and tools, bundles, langs and their dialects, drawn as one pair
; tree that grows (x/gfx/figure, x/gfx/scene)
;
; Usage:
;   sh x.sh -f examples/x-lang/story.x
;       draws the last frame and prints how many figures it holds and one
;       pixel of it
;
;   SCENES=web sh x.sh -f examples/x-lang/story.x
;       plays it in a browser; the page's address is printed on stderr
;
;   SCENES=sdl sh x.sh -f examples/x-lang/story.x
;       plays it in a window, on a host with SDL3
;
; What each beat says is taken from the projects' own words: x-expr's
; README, x-engine-c's README, and this repository's README and
; docs/architecture.md.

(import x/gfx/canvas)
(import x/gfx/figure)
(import x/gfx/scene)
(import x/num/float)
(import x/sys/posix)

; --- Figures ---------------------------------------------------------------

(def story-blue (list 88 196 221))
(def story-green (list 131 193 103))
(def story-pink (list 209 71 189))
(def story-gold (list 240 190 80))
(def story-grey (list 150 150 150))

; Words 0.2 high with their left edge at X and their middle at Y: a label's
; box is about 0 0 and a character as wide as it is high, so every line of
; words sits on the same baseline.
(def story-word
  (fn (_ text x y)
    (Figure shift (Figure label text 0.2) (Float + x (Float * (Str8 length text) 0.1)) y)))
(def story-name (fn (_ text x y) (Figure shift (Figure label text 0.2) x y)))
(def story-caption (fn (_ text) (Figure shift (Figure label text 0.24) 0 -3.7)))

; A cell: one of an object's slots.
(def story-cell
  (fn (_ x y side colour)
    (Figure shift (Figure fill (Figure stroke (Figure square side) colour 0.04) (list 20 40 60)) x y)))

(def story-link
  (fn (_ x0 y0 x1 y1) (Figure stroke (Figure line x0 y0 x1 y1) story-grey 0.03)))

; --- The stage -------------------------------------------------------------
;
; A state is (FIGURES CAPTION HEADINGS): what is on the stage, the one line
; of words under it or nil, and the headings across the top so far, the
; newest first.  A step is a function of a state, a play and a wait that
; answers the state afterwards.

(def story-figures (fn (_ state) (first state)))
(def story-words (fn (_ state) (first (rest state))))
(def story-heads (fn (_ state) (first (rest (rest state)))))

; What a state puts on the stage: the newest heading white, the ones before
; it grey.
(def story-shown
  (fn (_ state)
    (def heads (story-heads state))
    (List append (story-figures state)
      (if (null? heads) () (pair (first heads) (List map (fn (_ h) (Figure stroke h story-grey 0.02)) (rest heads))))
      (if (null? (story-words state)) () (list (story-words state))))))

(def story-with
  (fn (_ state figs) (list (List append (story-figures state) figs) (story-words state) (story-heads state))))

; The words under the stage become TEXT.
(def story-say
  (fn (_ text) (fn (_ state play wait) (list (story-figures state) (story-caption text) (story-heads state)))))
(def story-hush (fn (_ state play wait) (list (story-figures state) () (story-heads state))))

; TEXT becomes the heading, at X along the top, and is held a moment.
(def story-head
  (fn (_ text x)
    (fn (_ state play wait)
      ((fn (_ next) (do (wait (story-shown next) 0.4) next))
       (list (story-figures state) (story-words state) (pair (story-word text x 3.5) (story-heads state)))))))

; FIGS are drawn in over SECONDS and stay.
(def story-draw
  (fn (_ figs seconds)
    (fn (_ state play wait)
      (do (play (story-shown state) (List map (fn (_ f) (Figure create f)) figs) seconds)
          (story-with state figs)))))

; FIGS appear whole and are held for SECONDS.
(def story-show
  (fn (_ figs seconds)
    (fn (_ state play wait)
      ((fn (_ next) (do (wait (story-shown next) seconds) next))
       (story-with state figs)))))

; FROM becomes TO over SECONDS, and TO stays.
(def story-move
  (fn (_ from to seconds)
    (fn (_ state play wait)
      (do (play (story-shown state) (list (Figure morph from to)) seconds)
          (story-with state (list to))))))

; FROM becomes TO over SECONDS, and neither stays.
(def story-pass
  (fn (_ from to seconds)
    (fn (_ state play wait)
      (do (play (story-shown state) (list (Figure morph from to)) seconds)
          state))))

; --- The beats -------------------------------------------------------------

(def story-steps
  (list
    ; x-expr: atoms and pairs, and a base that is a tree of them.
    (story-head "x-expr" -6.85)
    (story-say "atom")
    (story-draw (list (story-cell 0.25 2.6 0.5 story-blue)) 1)
    (story-say "atom, pair")
    (story-draw (list (story-cell 0.75 2.6 0.5 story-blue)) 1)
    (story-say "the base: a pair tree")
    (story-draw (list (story-link 0.75 2.35 2.2 1.65)) 0.6)
    (story-draw (list (story-cell 1.95 1.4 0.5 story-blue) (story-cell 2.45 1.4 0.5 story-blue)) 1)
    (story-show (list (story-name "io" 1.75 0.8) (story-name "meta" 2.75 0.8)) 0.6)
    (story-say "types, heap")
    (story-show (list (story-word "types" -2.6 2.75) (story-word "heap" -2.6 2.4)) 1)

    ; The engine: the half the core leaves nil is filled, and types are
    ; registered.
    (story-head "x-engine" -5.37)
    (story-say "env, ctrl")
    (story-draw (list (story-link 0.25 2.35 -1.2 1.65)) 0.6)
    (story-draw (list (story-cell -1.45 1.4 0.5 story-green) (story-cell -0.95 1.4 0.5 story-green)) 1)
    (story-show (list (story-name "env" -1.65 0.8) (story-name "ctrl" -0.75 0.8)) 0.6)
    story-hush
    (story-draw (list (Figure stroke (Figure line 1.75 0.6 1.75 -2.05) story-green 0.04)) 1)
    (story-show
      (list (story-word "symbol" 1.95 0.2) (story-word "list" 1.95 -0.15) (story-word "integer" 1.95 -0.5)
            (story-word "string" 1.95 -0.85) (story-word "primitive" 1.95 -1.2)
            (story-word "procedure" 1.95 -1.55) (story-word "operative" 1.95 -1.9))
      1)
    (story-say "no printer, no REPL, no library")
    (story-draw (list (Figure stroke (Figure arrow -6.6 1.4 -2 1.4) story-grey 0.04)) 1)
    (story-show (list (story-name "stdin" -4.3 1.75)) 1.2)

    ; x-lang: read from stdin, it adds bindings and types to what is there.
    (story-head "x-lang" -3.49)
    (story-show (list (story-name "x-core.x" -4.3 1.05)) 0.4)
    story-hush
    (story-pass (Figure stroke (Figure line -6.5 1.4 -5.9 1.4) story-pink 0.08)
                (Figure stroke (Figure line -2.9 1.4 -2.3 1.4) story-pink 0.08) 1)
    (story-draw (list (story-cell -1.65 0.2 0.22 story-pink) (story-cell -1.65 -0.15 0.22 story-pink)) 0.6)
    (story-pass (Figure stroke (Figure line -6.5 1.4 -5.9 1.4) story-pink 0.08)
                (Figure stroke (Figure line -2.9 1.4 -2.3 1.4) story-pink 0.08) 1)
    (story-draw (list (story-cell -1.65 -0.5 0.22 story-pink) (story-cell -1.65 -0.85 0.22 story-pink)) 0.6)
    (story-draw (list (Figure stroke (Figure line 1.75 -2.05 1.75 -2.75) story-pink 0.04)) 0.6)
    (story-show (list (story-word "vector" 1.95 -2.25) (story-word "promise" 1.95 -2.6)) 0.6)
    (story-say "printer, REPL: written in x-lang")
    (story-show () 1.6)

    ; The libraries: modules, loaded as they are asked for.
    (story-head "libraries" -2.01)
    (story-say "over 200 modules")
    (story-draw
      (list (Figure stroke (Figure polygon (list (list 3.55 3) (list 6.75 3) (list 6.75 1.25) (list 3.55 1.25))) story-gold 0.04))
      1)
    (story-show
      (List map (fn (_ at) (story-cell (first at) (first (rest at)) 0.26 story-gold))
        (list (list 3.9 2.6) (list 4.4 2.6) (list 4.9 2.6) (list 5.4 2.6) (list 5.9 2.6) (list 6.4 2.6)
              (list 3.9 2.1) (list 4.4 2.1) (list 4.9 2.1) (list 5.4 2.1) (list 5.9 2.1) (list 6.4 2.1)
              (list 3.9 1.6) (list 4.4 1.6) (list 4.9 1.6) (list 5.4 1.6) (list 5.9 1.6)))
      1.2)

    ; The toolchain: tools written in x-lang, working on the same structure.
    (story-head "toolchain" 0.07)
    story-hush
    (story-show
      (list (story-word "linter" 4.3 0.4) (story-word "formatter" 4.3 0.05) (story-word "coverage" 4.3 -0.3)
            (story-word "profiler" 4.3 -0.65) (story-word "compiler" 4.3 -1))
      0.6)
    (story-draw (list (Figure stroke (Figure arrow 4.15 0.4 2.85 1.2) story-gold 0.04)) 1)

    ; A bundle: pinned and verified, then part of the library.
    (story-head "bundles" 2.15)
    (story-say "pinned, verified")
    (story-pass (story-cell 6.7 -2.8 0.4 story-pink) (story-cell 6.7 0.85 0.4 story-pink) 1.2)
    (story-move (story-cell 6.7 0.85 0.4 story-pink) (story-cell 6.4 1.6 0.26 story-pink) 1)

    ; Langs: other languages, read from the same stream.
    (story-head "langs" 3.83)
    story-hush
    (story-draw (list (Figure stroke (Figure arrow -5.9 0.65 -5.9 1.25) story-pink 0.04)) 0.6)
    (story-show
      (list (story-word "Scheme" -6.85 0.4) (story-word "BASIC" -6.85 -0.1)
            (story-word "SQL" -6.85 -0.6) (story-word "shell" -6.85 -1.1))
      1.2)

    ; Dialects: each language as x speaks it, x-lang's own among them.
    (story-head "dialects" 5.11)
    (story-show
      (list (story-word "R5RS R7RS" -5.2 0.4) (story-word "Microsoft 6502" -5.2 -0.1)
            (story-word "DuckDB's" -5.2 -0.6) (story-word "ash" -5.2 -1.1))
      1.2)
    (story-show (list (story-word "x-lang" -6.85 -1.6) (story-word "helium xenon radon" -5.2 -1.6)) 2)))

; Every step in turn, from an empty stage: the figures at the end.
(def story-run
  (fn (_ play wait)
    (story-shown (List fold (fn (_ state step) (step state play wait)) (list () () ()) story-steps))))

; --- Running ---------------------------------------------------------------

; With no window the steps go straight to their ends and the last frame is
; drawn, 160 by 90: how many figures it holds, and the pixel inside the
; first cell.
(def story-still
  (fn (_)
    ((fn (_ figures)
       (do (display "figures ")
           (write (List length figures))
           (newline)
           (display "cell ")
           (write (Canvas pixel (Scene frame figures () 1 160 90) 82 15))
           (newline)))
     (story-run (fn (_ figures animations seconds) figures) (fn (_ figures seconds) figures)))))

(def story-live
  (fn (_ front)
    (def stage (Scene open front "story" 854 480 15))
    (Scene wait stage
      (story-run (fn (_ figures animations seconds) (Scene play stage figures animations seconds))
                 (fn (_ figures seconds) (Scene wait stage figures seconds)))
      3)
    (Scene close stage)))

((fn (_ how)
   (match
     ((null? how) (story-still))
     ((str=? how "web") (do (import x/sys/web) (story-live Web)))
     ((str=? how "sdl") (do (import x/sys/sdl) (story-live Sdl)))
     (#t (story-still))))
 (Sys getenv "SCENES"))
