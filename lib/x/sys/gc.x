; gc.x -- Garbage collection hooks
;
; heap-mark-hook!, heap-free-hook!, heap-mark-root! are C primitives
; bound by src/x-prim/io.c (x_prim_io_register).  The underlying lists
; live in x-expr's heap-group; see ext/x-expr/include/x-base.h
; (x_base_field_heap_{mark,free}_hooks, x_base_field_heap_mark_roots).
;
; This file just wires heap-collect and re-exports the primitives.

(def heap-collect (fn (_ ) (applicative heap-mark heap-sweep) ()))

(provide x/sys/gc
  heap-collect heap-mark-root! heap-mark-hook! heap-free-hook!)
