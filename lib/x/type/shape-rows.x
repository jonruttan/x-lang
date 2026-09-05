; type/shape-rows.x -- what each engine type's units ARE, as data.
;
; Two consumers, which is why this is a file and not a run of calls inside
; lib/x/type/type.x: helium declares these on its own base at boot, and a state
; image loader (lib/img.x) declares them on a bare base before it rebuilds a
; single object -- with no class system loaded, so it cannot reach the Type
; class.  A row is (name count kinds); a negative count is -k leading units
; plus the kind of the slot-0-counted payload, and the last kind repeats.
; Kind codes are the engine's two-bit encoding, in mask order.
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(def %type-kind-codes
  (lit ((ref . 0) (word . 1) (bytes . 2) (foreign . 3))))

(def %type-shape-rows
  (lit (("INTEGER"   1 (word))       ; the value word
        ("CHARACTER" 1 (word))       ; the code point
        ("STRING"    1 (bytes))      ; pointer to its bytes
        ("SYMBOL"    1 (bytes))      ; pointer to its name
        ("PRIMITIVE" 1 (foreign))    ; a C function address
        ("POINTER"   1 (foreign))    ; an address C owns
        ; The two callables are [fn-ptr][state]: slot 0 is a raw C function
        ; pointer, NOT a heap object.  x-type/procedure.h and
        ; x-type/operative.h both say so, and both warn that marking it as one
        ; would corrupt the GC free list.  State is slot 1.
        ("PROCEDURE" 2 (foreign ref))
        ("OPERATIVE" 2 (foreign ref)))))
