; # Computational Expressions in C
;
; ## x-core.x -- x Core Standard Library
;
; @description Computational Expressions in C
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2021 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "

; --- Boot (evaluated by C read-eval loop, no module system yet) ---
(include "lib/x/boot/operatives.x")
(include "lib/x/boot/predicates.x")
(include "lib/x/boot/data.x")
(include "lib/x/boot/string.x")
(include "lib/x/boot/module.x")
(include "lib/x/boot/gc.x")

; --- Core control flow (if, let) ---
(include "lib/x/core/control.x")

(do
  (def x-lib-version "0.2.0")

  ; Pre-register all library paths so import calls are no-ops
  (set-first! %include-list-cell
    (pair "lib/x/doc/doc.x"
    (pair "lib/x/doc/doc-prims.x"
    (pair "lib/x/sys/type.x"
    (pair "lib/x/sys/convert.x"
    (pair "lib/x/core/fn.x"
    (pair "lib/x/core/logic.x"
    (pair "lib/x/core/list.x"
    (pair "lib/x/core/math.x"
    (pair "lib/x/core/syntax.x"
    (pair "lib/x/num/tower.x"
    (pair "lib/x/core/alist.x"
    (pair "lib/x/type/char.x"
    (pair "lib/x/type/string.x"
    (pair "lib/x/type/vector.x"
    (pair "lib/x/type/promise.x"
    (pair "lib/x/sys/token.x"
      (first %include-list-cell))))))))))))))))))

  ; --- Type system internals (before doc, cannot use provide) ---
  (include "lib/x/sys/type.x")
  (include "lib/x/sys/convert.x")

  ; --- Documentation system ---
  (include "lib/x/doc/doc.x")
  (include "lib/x/doc/doc-prims.x")

  ; --- Boolean operatives (and, or, time) ---
  (include "lib/x/boot/and-or.x")

  ; --- Core library ---
  (include "lib/x/core/fn.x")
  (include "lib/x/core/logic.x")
  (include "lib/x/core/list.x")
  (include "lib/x/core/math.x")
  (include "lib/x/core/syntax.x")
  (include "lib/x/num/tower.x")

  ; --- Variadic arithmetic (needs fold from list.x) ---
  (include "lib/x/boot/arithmetic.x")

  ; --- Intrinsics (tokenizer helpers, stderr, profile dump) ---
  (include "lib/x/boot/intrinsics.x")

  ; --- Type extensions ---
  (include "lib/x/core/alist.x")
  (include "lib/x/type/char.x")
  (include "lib/x/type/string.x")
  (include "lib/x/type/vector.x")
  (include "lib/x/type/promise.x")
  (include "lib/x/sys/token.x")

  ; --- Quasi-quoting (needs append from list.x, and/or) ---
  (include "lib/x/boot/quasi.x")

  ; --- REPL ---
  (include "lib/x/boot/repl.x")

  ; --- Banner ---
  (include "lib/x/boot/banner.x")

  ; --- Provide ---
  (doc (provide x/sys/type
    type-alist type-by-atom type-io type-cvt
    type-write-cell type-analyse-cell type-from-cell type-to-cell
    type-push-write type-pop-write type-push-analyse type-cast!)
    "Type system reflection and manipulation.")
  (doc (provide x/core
    null? if let do begin not atom? list convert number->str str->number
    str=? str-ref str-length substring
    newline heap-collect heap-mark-root! heap-mark-hook!
    heap-free-hook! include-once require-once provide import
    peek-char current-line quasi repl doc note help)
    (note "Built-in forms, module system, REPL, and documentation.")
    "Core language: operatives, string primitives, GC, modules."))
