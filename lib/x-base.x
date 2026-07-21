; # Computational Expressions in C
;
; ## x-base.x -- x Standard Library (non-interactive)
;
; @description x-base: non-interactive full-stack library with a COMPILED
;   numeric tower (see docs/dialects.md and docs/type-system.md).  The
;   analyser-compilation lives in lib/x/boot/tower-compiled.x, shared with
;   the xenon/radon bodies; this entry is x-core plus that block, without the
;   interactive banner/REPL.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2021 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
; Load core first (fast, no numeric tower)
(include "lib/x-core.x")
; Numeric tower with compiled tokenizer analysers (shared dialect heart)
(include "lib/x/boot/tower-compiled.x")
