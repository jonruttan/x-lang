; # Computational Expressions in C
;
; ## ne.x -- neon: the base for a language built on x-lang
;
; @description neon: helium plus the compiler and the Lexer, with no reader
;   syntax of its own (lib/x/boot/neon.x), and the interactive banner/REPL.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
(include "lib/x/boot/neon.x")
; Reclaim the compiler's load burst -- the same collect, at the same moment,
; for the same reason as lib/xe.x: the entry's top level, after the include
; has returned, is the first point at which nothing is in flight.
((prim-ref (lit heap) (lit collect)))
; Interactive launcher, unless x.sh passed --batch; see lib/xe.x for why it
; is here and what the guard is for.
; The boot ends here: the rest of the input is the program, read into an
; environment of its own (boot/module.x, %module-program!).
(%module-program!)
(unless %batch? (do (guard (_ ()) (import x/repl/line)) (%banner) (repl)))
