; gc.x -- Garbage collection hooks
;
; heap-collect, heap-mark-hook!, heap-free-hook!, heap-mark-root! are all
; C primitives bound by src/x-prim/io.c (x_prim_io_register).  The
; underlying hook/root lists live in x-expr's heap-group; see
; ext/x-expr/include/x-base.h (x_base_field_heap_{mark,free}_hooks,
; x_base_field_heap_mark_roots).
;
; heap-collect runs an atomic mark+sweep in one C call.  It MUST be atomic:
; mark and sweep cannot straddle an allocation, or the sweep frees the
; eval-list cell the evaluator is mid-traversal on (the env/ctrl/extras
; base-tree cells and eval-list scratch cells are X_OBJ_FLAG_NONE, kept
; alive only by marking).  The old (applicative heap-mark heap-sweep)
; definition was non-atomic and crashed when invoked mid-expression; the
; raw (heap-mark)/(heap-sweep) primitives remain exposed but are low-level.
;
; This file just re-exports the C primitives for module import.

; NOTE: this module loads before the doc system (x/doc/doc.x), so it cannot
; wrap its provide in (doc ...). Its module description is registered
; retroactively in x/doc/doc-prims.x.
(provide x/sys/gc
  heap-collect heap-mark-root! heap-mark-hook! heap-free-hook!)
