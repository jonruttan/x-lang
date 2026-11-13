; lint-image.x -- the library a lint child boots: lib/x-core.x and the linter,
; with the linter's functions compiled.
;
; tools/dev/lint.sh writes a state image of this file once
; (tools/dev/image-build.sh, keyed on the library, the linter and the engine)
; and boots every lint child from it, instead of evaluating the library and
; the linter from source in each one.  The child then loads the target's
; preload and runs the driver, tools/dev/lint-run.x.  Both includes are
; root-relative: the image writer runs from the checkout's root.
(include "lib/x-core.x")

; The linter's functions are compiled here, so the image carries them compiled
; and a child pays nothing for it at boot.  They are the closures the linter
; adds to the root, the names bound there by tools/dev/lint.x and not before
; it, x/tool/lint's walk among them.  A function compile-fn! cannot carry
; stays interpreted, with its reason on the Compiled list.
;
; The root is the environment a linted file's names are checked against, so
; nothing here is bound in it: the names before the linter are held by a let,
; and the linter is included in the root from inside it.
(import x/tool/fn-compile)
(let ((before (Env names (Env root)))
      (compile-fn! (eval (lit compile-fn!) (Module env (lit x/tool/fn-compile)))))
  (eval (lit (include "tools/dev/lint.x")) (Env root))
  (%for-each
    (fn (_ name)
      (def v (eval name))
      (when (eq? (Fn label v) (lit fn)) (compile-fn! name v)))
    (%filter (fn (_ name) (not (%memq? name before))) (Env names (Env root)))))
