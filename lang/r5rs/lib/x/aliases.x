; --- Scheme aliases for x-lang primitives ---

(def lambda fn)
(def begin do)
(def modulo %)
(def cons pair)
(def car first)
(def cdr rest)
(def set-car! set-first!)
(def set-cdr! set-rest!)
(def quote lit)
(def quasiquote quasi)

; --- Boolean constants ---

(def else #t)

; --- write-char / newline ---

(def write-char (fn (c) (display (make-string 1 c))))

; --- Composition accessors (all 28 c*r, up to 4 deep) ---

(def caar (fn (x) (first (first x))))
(def cadr (fn (x) (first (rest x))))
(def cdar (fn (x) (rest (first x))))
(def cddr (fn (x) (rest (rest x))))
(def caaar (fn (x) (first (first (first x)))))
(def caadr (fn (x) (first (first (rest x)))))
(def cadar (fn (x) (first (rest (first x)))))
(def caddr (fn (x) (first (rest (rest x)))))
(def cdaar (fn (x) (rest (first (first x)))))
(def cdadr (fn (x) (rest (first (rest x)))))
(def cddar (fn (x) (rest (rest (first x)))))
(def cdddr (fn (x) (rest (rest (rest x)))))
(def caaaar (fn (x) (first (first (first (first x))))))
(def caaadr (fn (x) (first (first (first (rest x))))))
(def caadar (fn (x) (first (first (rest (first x))))))
(def caaddr (fn (x) (first (first (rest (rest x))))))
(def cadaar (fn (x) (first (rest (first (first x))))))
(def cadadr (fn (x) (first (rest (first (rest x))))))
(def caddar (fn (x) (first (rest (rest (first x))))))
(def cadddr (fn (x) (first (rest (rest (rest x))))))
(def cdaaar (fn (x) (rest (first (first (first x))))))
(def cdaadr (fn (x) (rest (first (first (rest x))))))
(def cdadar (fn (x) (rest (first (rest (first x))))))
(def cdaddr (fn (x) (rest (first (rest (rest x))))))
(def cddaar (fn (x) (rest (rest (first (first x))))))
(def cddadr (fn (x) (rest (rest (first (rest x))))))
(def cdddar (fn (x) (rest (rest (rest (first x))))))
(def cddddr (fn (x) (rest (rest (rest (rest x))))))

; --- make-vector: accept 1 or 2 args (R5RS optional fill) ---

(def %make-vector-orig make-vector)
(def make-vector
  (fn (n . rest)
    (%make-vector-orig n (if (null? rest) () (first rest)))))

; --- Scheme list aliases ---

(def list-ref (fn (lst n) (nth n lst)))
(def list-tail (fn (lst n) (drop n lst)))
(def string-copy (fn (s) (substring s 0 (string-length s))))

; --- define: (define x val) or (define (f args...) body...) ---

(def define
  (op (name-or-form . body)
    e
    (if (pair? name-or-form)
      (eval
        (list
          (lit def)
          (first name-or-form)
          (pair (lit fn) (pair (rest name-or-form) body))))
      (eval (list (lit def) name-or-form (first body))))))
