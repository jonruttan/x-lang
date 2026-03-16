; --- Hygienic Macros (R5RS §4.3) ---

; Ellipsis symbol (used for pattern matching, also registered as tokenizer in syntax.x)
(define %ellipsis-sym (string->symbol "..."))

; Gensym: generate unique symbols for hygiene

(define %gensym-counter 0)
(define
  (gensym)
  (set! %gensym-counter (+ %gensym-counter 1))
  (string->symbol
    (string-append "%g" (number->string %gensym-counter))))

; Safe eval: returns (t . value) if bound, () if unbound

(define
  (%sr-safe-eval sym env)
  (guard (e ()) (pair #t (eval sym env))))

; Sentinel for pattern match failure (unique identity)

(define %sr-no-match (pair (lit no) (lit match)))

; Remove duplicates (eq?)

(define
  (%sr-unique lst)
  (let loop
    ((in lst) (out ()))
    (if (null? in)
      (reverse out)
      (if (memq (car in) out)
        (loop (cdr in) out)
        (loop (cdr in) (pair (car in) out))))))

; --- Ellipsis helpers ---

; Count fixed elements in a pattern tail (after ...)

(define
  (%sr-tail-length pat)
  (if (pair? pat) (+ 1 (%sr-tail-length (cdr pat))) 0))

; Collect pattern variable names from a sub-pattern

(define
  (%sr-pattern-pvars pat literals)
  (if (symbol? pat)
    (if (or (eq? pat (lit _)) (memq pat literals))
      ()
      (list pat))
    (if (pair? pat)
      (append
        (%sr-pattern-pvars (car pat) literals)
        (%sr-pattern-pvars (cdr pat) literals))
      ())))

; Find pvars in template that have ellipsis bindings

(define
  (%sr-ellipsis-pvars template bindings)
  (if (symbol? template)
    (let ((b (assq template bindings)))
      (if (and b (pair? (cdr b)) (eq? (cadr b) %ellipsis-sym))
        (list template)
        ()))
    (if (pair? template)
      (append
        (%sr-ellipsis-pvars (car template) bindings)
        (%sr-ellipsis-pvars (cdr template) bindings))
      ())))

; Forward declaration for mutual recursion

(define %sr-match ())

; Match (sub-pat ... . tail-pat) against form list

(define
  (%sr-ellipsis-match
    sub-pat
    tail-pat
    form
    literals
    bindings)
  (let*
    ((pvars (%sr-unique (%sr-pattern-pvars sub-pat literals)))
      (tail-len (%sr-tail-length tail-pat))
      (form-len (length form))
      (rep-count (- form-len tail-len)))
    (if (< rep-count 0)
      %sr-no-match
      (let loop
        ((i 0)
          (f form)
          (collected (map (lambda (v) (list v)) pvars)))
        (if (= i rep-count)
          ; Match tail, then add ellipsis bindings

          (let ((tb (%sr-match tail-pat f literals bindings)))
            (if (eq? tb %sr-no-match)
              %sr-no-match
              (let add
                ((cs collected) (bs tb))
                (if (null? cs)
                  bs
                  (add
                    (cdr cs)
                    (pair
                      (pair (caar cs) (pair %ellipsis-sym (reverse (cdar cs))))
                      bs))))))
          ; Match next repeated element

          (let ((b (%sr-match sub-pat (car f) literals ())))
            (if (eq? b %sr-no-match)
              %sr-no-match
              (loop
                (+ i 1)
                (cdr f)
                (map
                  (lambda
                    (cv)
                    (let ((found (assq (car cv) b)))
                      (if found (pair (car cv) (pair (cdr found) (cdr cv))) cv)))
                  collected)))))))))

; Pattern matching for syntax-rules
; Returns bindings alist on success, %sr-no-match on failure
; Ellipsis bindings stored as (pvar . (... val1 val2 ...))

(set!
  %sr-match
  (lambda
    (pattern form literals bindings)
    (if (eq? pattern (lit _))
      bindings
      (if (symbol? pattern)
        (if (memq pattern literals)
          (if (and (symbol? form) (eq? pattern form))
            bindings
            %sr-no-match)
          (pair (pair pattern form) bindings))
        (if (null? pattern)
          (if (null? form) bindings %sr-no-match)
          (if (pair? pattern)
            ; Check for ellipsis: (sub-pat ... . tail)

            (if (and
                  (pair? (cdr pattern))
                  (eq? (cadr pattern) %ellipsis-sym))
              (%sr-ellipsis-match
                (car pattern)
                (cddr pattern)
                form
                literals
                bindings)
              ; Normal pair matching

              (if (pair? form)
                (let ((b (%sr-match (car pattern) (car form) literals bindings)))
                  (if (eq? b %sr-no-match)
                    %sr-no-match
                    (%sr-match (cdr pattern) (cdr form) literals b)))
                %sr-no-match))
            (if (equal? pattern form) bindings %sr-no-match)))))))

; Collect non-pvar symbols from template (excludes ... marker)

(define
  (%sr-introduced template pvars)
  (if (symbol? template)
    (if (or (memq template pvars) (eq? template %ellipsis-sym))
      ()
      (list template))
    (if (pair? template)
      (append
        (%sr-introduced (car template) pvars)
        (%sr-introduced (cdr template) pvars))
      ())))

; Substitute pattern variables in template
; Handles (tmpl ... . rest) by expanding ellipsis-bound vars

(define
  (%sr-subst template bindings)
  (if (symbol? template)
    (let ((b (assq template bindings)))
      (if b (cdr b) template))
    (if (pair? template)
      ; Check for ellipsis: (tmpl ... . rest)

      (if (and
            (pair? (cdr template))
            (eq? (cadr template) %ellipsis-sym))
        (let*
          ((sub-tmpl (car template))
            (rest-tmpl (cddr template))
            (epvars
              (%sr-unique (%sr-ellipsis-pvars sub-tmpl bindings)))
            (count
              (if (null? epvars)
                0
                (length (cddr (assq (car epvars) bindings))))))
          (let loop
            ((i 0) (acc ()))
            (if (= i count)
              (append (reverse acc) (%sr-subst rest-tmpl bindings))
              (let ((slice
                      (map
                        (lambda
                          (pv)
                          (pair pv (list-ref (cddr (assq pv bindings)) i)))
                        epvars)))
                (loop
                  (+ i 1)
                  (pair (%sr-subst sub-tmpl (append slice bindings)) acc))))))
        ; Normal pair

        (pair
          (%sr-subst (car template) bindings)
          (%sr-subst (cdr template) bindings)))
      template)))

; Rename symbols in template

(define
  (%sr-rename template renames)
  (if (symbol? template)
    (let ((r (assq template renames))) (if r (cdr r) template))
    (if (pair? template)
      (pair
        (%sr-rename (car template) renames)
        (%sr-rename (cdr template) renames))
      template)))

; Instantiate template with bindings and hygiene
; 1. Find introduced symbols (in template, not pattern vars)
; 2. For those bound in def-env: rename to gensyms, wrap in let
; 3. Substitute pattern variables

(define
  (%sr-instantiate template bindings def-env)
  (let*
    ((pvars (map car bindings))
      (introduced (%sr-unique (%sr-introduced template pvars)))
      (renames
        (let loop
          ((syms introduced) (acc ()))
          (if (null? syms)
            (reverse acc)
            (let ((v (%sr-safe-eval (car syms) def-env)))
              (if (pair? v)
                (loop (cdr syms) (pair (pair (car syms) (cdr v)) acc))
                (loop (cdr syms) acc))))))
      (renamed (%sr-rename template renames))
      (expanded (%sr-subst renamed bindings)))
    expanded))

; Try each clause, return first match's expansion

(define
  (%sr-expand form literals clauses def-env)
  (if (null? clauses)
    (error "syntax-rules: no matching pattern")
    (let*
      ((clause (car clauses))
        (pattern (car clause))
        (template
          (if (pair? (cdr clause)) (cadr clause) (lit (begin))))
        (bindings (%sr-match (cdr pattern) (cdr form) literals ())))
      (if (eq? bindings %sr-no-match)
        (%sr-expand form literals (cdr clauses) def-env)
        (%sr-instantiate template bindings def-env)))))

; syntax-rules: returns a transformer fn (lexically scoped closure)
; Captures literals, clauses, and def-env for hygiene

(define
  syntax-rules
  (op (literals . clauses)
    sr-env
    (fn (form) (%sr-expand form literals clauses sr-env))))

; define-syntax: bind name to a syntax transformer
; Strategy: store transformer fn under a gensym, bind name to an op
; that calls it. The op is dynamically scoped so it finds the gensym
; in the env at call time.

(define
  define-syntax
  (op (name transformer-expr)
    e
    (def %ds-xfm (eval transformer-expr e))
    (def %ds-xfm-name
      (string->symbol
        (string-append "%xfm-" (symbol->string name))))
    (eval
      (list
        (lit begin)
        (list (lit def) %ds-xfm-name %ds-xfm)
        (list
          (lit def)
          name
          (list
            (lit op)
            (lit %sr-args)
            (lit %sr-env)
            (list
              (lit eval!)
              (list
                %ds-xfm-name
                (list (lit pair) (list (lit lit) name) (lit %sr-args))))))))))

; let-syntax: local syntax bindings
; Processes one binding at a time, wrapping in let + recursing
; Uses %ls- prefixed params to avoid shadowing by let*/let (which also
; use 'bindings'/'body'/'e' as op params in dynamic scope).

(define
  let-syntax
  (op (%ls-bindings . %ls-body)
    %ls-e
    (if (null? %ls-bindings)
      (eval (pair (lit begin) %ls-body) %ls-e)
      (begin
        (def %ls-b (car %ls-bindings))
        (def %ls-name (car %ls-b))
        (def %ls-xfm (eval (cadr %ls-b) %ls-e))
        (def %ls-xfm-name
          (string->symbol
            (string-append "%xfm-" (symbol->string %ls-name))))
        (eval
          (list
            (lit begin)
            (list (lit def) %ls-xfm-name %ls-xfm)
            (list
              (lit let)
              (list
                (list
                  %ls-name
                  (list
                    (lit op)
                    (lit %sr-args)
                    (lit %sr-env)
                    (list
                      (lit eval!)
                      (list
                        %ls-xfm-name
                        (list (lit pair) (list (lit lit) %ls-name) (lit %sr-args)))))))
              (pair (lit let-syntax) (pair (cdr %ls-bindings) %ls-body))))
          %ls-e)))))

; letrec-syntax: like let-syntax but transformers can see each other
; We achieve this by evaluating all transformers first, then binding them all
; Uses same strategy as define-syntax: def gensym names, then let-bind macro ops

(define
  letrec-syntax
  (op (%lrs-bindings . %lrs-body)
    %lrs-e
    (if (null? %lrs-bindings)
      (eval (pair (lit begin) %lrs-body) %lrs-e)
      (begin
        ; Build defs + let-bindings for all transformers

        (def %lrs-defs ())
        (def %lrs-let-bindings ())
        (for-each
          (lambda
            (b)
            (def %lrs-n (car b))
            (def %lrs-xfm (eval (cadr b) %lrs-e))
            (def %lrs-xn
              (string->symbol
                (string-append "%xfm-" (symbol->string %lrs-n))))
            (set!
              %lrs-defs
              (cons (list (lit def) %lrs-xn %lrs-xfm) %lrs-defs))
            (set!
              %lrs-let-bindings
              (cons
                (list
                  %lrs-n
                  (list
                    (lit op)
                    (lit %sr-args)
                    (lit %sr-env)
                    (list
                      (lit eval)
                      (list
                        %lrs-xn
                        (list (lit pair) (list (lit lit) %lrs-n) (lit %sr-args)))
                      (lit %sr-env))))
                %lrs-let-bindings)))
          %lrs-bindings)
        (eval
          (append
            (list (lit begin))
            (reverse %lrs-defs)
            (list
              (pair
                (lit let)
                (pair (reverse %lrs-let-bindings) %lrs-body))))
          %lrs-e)))))
