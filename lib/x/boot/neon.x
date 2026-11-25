; boot/neon.x -- the neon dialect body: everything but the launcher
;
; Neon is the base for a language built on x-lang: helium, the compiler and
; the Lexer, and no reader syntax of its own.  The xenon and radon bodies
; include this one and add the tower and x-lang's literals above it.
;
; Included by the lib/ne.x entry.  The (repl) launcher cannot ride a nested
; (include ...): the REPL reads the CURRENT input source, so inside an
; include frame it meets the file's EOF and exits instead of reading the
; session's stdin.  The entry therefore keeps the launcher at stream top
; level and includes this body.

; The core: helium's libraries.
(include "lib/x-core.x")
; The compiler, and the core's reader hooks compiled by it.  Named from the
; root, as the core is: this body is included before the core has loaded
; the module system, so no directory is on the include stack for a ./ path
; to resolve against.  It registers its own name, so the import of it in
; boot/tower-compiled.x is then a no-op.
(include-once "lib/x/boot/compiler.x")

; Pre-seed invariant (check-boot-order): loaded via raw `include` from the
; entries, which does not register.
(%set-first! %module-loaded-cell
  (pair (lit x/boot/neon) (first %module-loaded-cell)))

; The function compiler: loading it compiles the library's own hot loops
; (lib/x/tool/fn-compile.x), each on Compiled's list.
(import x/tool/fn-compile)
; The Lexer, whose states compile now that the assembler lane is open, and
; the Dict it is built on.
(import x/type/dict)
(import x/reader/lexer)

(set! %lang-name "neon")
(set! %lang-version x-lib-version)
