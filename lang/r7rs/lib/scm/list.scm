; --- List extensions (R7RS §6.4) ---

(define
  (make-list n . fill)
  (let ((v (if (null? fill) #f (car fill))))
    (let loop
      ((i n) (acc ()))
      (if (= i 0) acc (loop (- i 1) (cons v acc))))))
(define
  (list-copy lst)
  (if (pair? lst) (cons (car lst) (list-copy (cdr lst))) lst))
