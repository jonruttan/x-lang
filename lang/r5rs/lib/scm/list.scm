; --- List operations (R5RS §6.3) ---

; --- Mutation ---

(define (vector-set! v i val)
  (obj-set! v (+ i 1) val))
(define (vector-fill! v fill)
  (let ((len (obj-ref v 0)))
    (let loop ((i 1))
      (if (<= i len)
        (begin (obj-set! v i fill) (loop (+ i 1)))))))

; --- List predicate ---

(define
  (list? x)
  (if (null? x) #t (if (pair? x) (list? (cdr x)) #f)))

; --- Membership with eq? ---

(define
  (memq x lst)
  (cond
    ((null? lst) #f)
    ((eq? x (car lst)) lst)
    (#t (memq x (cdr lst)))))

; --- Membership with eqv? ---

(define
  (memv x lst)
  (cond
    ((null? lst) #f)
    ((eqv? x (car lst)) lst)
    (#t (memv x (cdr lst)))))

; --- Membership with equal? ---

(define
  (member x lst)
  (cond
    ((null? lst) #f)
    ((equal? x (car lst)) lst)
    (#t (member x (cdr lst)))))

; --- Association with eq? ---

(define
  (assq key alist)
  (cond
    ((null? alist) #f)
    ((eq? key (caar alist)) (car alist))
    (#t (assq key (cdr alist)))))

; --- Association with eqv? ---

(define
  (assv key alist)
  (cond
    ((null? alist) #f)
    ((eqv? key (caar alist)) (car alist))
    (#t (assv key (cdr alist)))))

; --- Association with equal? ---

(define
  (assoc key alist)
  (cond
    ((null? alist) #f)
    ((equal? key (caar alist)) (car alist))
    (#t (assoc key (cdr alist)))))
