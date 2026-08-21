; doc-forms.x -- report every form used directly in a (def-class ...) body
;
;   sh x.sh --no-pin -q -f tools/check/doc-forms.x -- FILE...
;
; Prints one "FILE CLASS FORM" line per class-body form, for
; tools/check/doc-forms.sh to check against tools/contract/doc-forms.x.
;
; STRUCTURAL, not a grep: a class body is s-expressions, and the head of a
; body form is only knowable by reading it as one.  The file is parsed, never
; evaluated -- this walks the same shape lib/x/doc/doc-gen.x walks, which is
; the point: what it finds is exactly what that walker will be handed.
;
; Symbol comparison is by NAME, like doc-gen's own: symbols intern per base,
; so a form read here is not eq? to a symbol written here.

(do
  (import x/sys/posix)
  (import x/sys/file)
  (import x/codec/xon)
  (import x/tool/contract)

  (Contract alloc-guard!)

  (def %df-argv (Contract argv))
  (when (null? %df-argv)
    (do (%stderr "Usage: x.sh --no-pin -q -f tools/check/doc-forms.x -- FILE...\n")
        (Sys exit 1)))

  (def %df-name (fn (_ x) (if (symbol? x) (symbol->str x) "")))

  (def %df-is? (fn (_ x s) (str=? (%df-name x) s)))

  ; A body form's head, reported once per occurrence. A (static ...) block is
  ; reported AND descended, because doc-gen both recognises it and walks
  ; through it -- a form hiding inside one must be covered too.
  (def %df-emit-body
    (fn (self body file cname)
      (unless (null? body)
        ; A bare symbol IS a member declaration -- (private balance ...) --
        ; so it normalises to the (name) shape, exactly as doc-gen does.
        (do (let ((f (if (symbol? (first body)) (list (first body)) (first body))))
              (when (pair? f)
                (do (display file) (display " ") (display cname) (display " ")
                    (display (%df-name (first f))) (newline)
                    ; static and the visibility blocks all SPLICE their tail
                    ; into the class body, so their contents are class-body
                    ; forms too and must be walked, or a member declared
                    ; inside one goes unchecked.
                    (when (or (%df-is? (first f) "static")
                            (or (%df-is? (first f) "private")
                                (%df-is? (first f) "protected")))
                      (self (rest f) file cname)))))
            (self (rest body) file cname)))))

  ; def-class forms are not always at the top level -- a module that imports
  ; before defining wraps everything in (do ...) -- so a do body is descended
  ; and nothing else is.  Walking EVERY pair instead reads every method body
  ; in the library and trips the allocation guard on the first chunk; a class
  ; is not declared inside an expression.
  (def %df-walk
    (fn (self form file)
      (when (pair? form)
        (match
          ((%df-is? (first form) "def-class")
            (%df-emit-body (rest (rest (rest form))) file
                           (%df-name (first (rest form)))))
          ((%df-is? (first form) "do")
            (List for-each (fn (_ sub) (self sub file)) (rest form)))
          (#t ())))))

  (List for-each
    (fn (_ file)
      (List for-each
        (fn (_ form) (%df-walk form file))
        (Xon parse (File read-all file))))
    %df-argv))
