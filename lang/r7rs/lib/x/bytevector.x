; --- Bytevectors (R7RS §6.9) ---
; Backed by a list of exact integers (0-255).

(define %bytevector
  (make-type
    (lit BYTEVECTOR)
    (list
      (cons (lit write)
        (lambda (self)
          (display "#u8(")
          (let loop ((lst (first self)) (sep #f))
            (if (not (null? lst))
              (begin
                (if sep (display " "))
                (display (car lst))
                (loop (cdr lst) #t))))
          (display ")"))))))

(define (bytevector? x) (type? x %bytevector))

(define (bytevector . bytes)
  (make-instance %bytevector bytes))

(define (make-bytevector k . fill)
  (let ((byte (if (null? fill) 0 (car fill))))
    (let loop ((i k) (acc ()))
      (if (= i 0) (make-instance %bytevector acc)
        (loop (- i 1) (cons byte acc))))))

(define (bytevector-length bv)
  (length (first bv)))

(define (bytevector-u8-ref bv k)
  (list-ref (first bv) k))

(define (bytevector-u8-set! bv k byte)
  (let loop ((lst (first bv)) (i 0) (acc ()))
    (if (null? lst) (error "bytevector-u8-set!: index out of range")
      (if (= i k)
        (set-car! lst byte)
        (loop (cdr lst) (+ i 1) acc)))))

(define (bytevector-copy bv . args)
  (let ((lst (first bv)))
    (let ((start (if (null? args) 0 (car args)))
          (end (if (or (null? args) (null? (cdr args)))
                 (length lst)
                 (cadr args))))
      (make-instance %bytevector
        (let loop ((l (list-tail lst start)) (i start) (acc ()))
          (if (>= i end) (reverse acc)
            (loop (cdr l) (+ i 1) (cons (car l) acc))))))))

(define (bytevector-copy! to at from . args)
  (let ((src (first from)))
    (let ((start (if (null? args) 0 (car args)))
          (end (if (or (null? args) (null? (cdr args)))
                 (length src)
                 (cadr args))))
      (let ((dst (list-tail (first to) at))
            (s (list-tail src start)))
        (let loop ((d dst) (s s) (i start))
          (if (< i end)
            (begin (set-car! d (car s))
              (loop (cdr d) (cdr s) (+ i 1)))))))))

(define (bytevector-append . bvs)
  (make-instance %bytevector
    (apply append (map (lambda (bv) (first bv)) bvs))))

(define (utf8->string bv . args)
  (let ((lst (first bv)))
    (let ((start (if (null? args) 0 (car args)))
          (end (if (or (null? args) (null? (cdr args)))
                 (length lst)
                 (cadr args))))
      (list->string
        (let loop ((l (list-tail lst start)) (i start) (acc ()))
          (if (>= i end) (reverse acc)
            (loop (cdr l) (+ i 1) (cons (integer->char (car l)) acc))))))))

(define (string->utf8 str . args)
  (let ((start (if (null? args) 0 (car args)))
        (end (if (or (null? args) (null? (cdr args)))
               (string-length str)
               (cadr args))))
    (make-instance %bytevector
      (let loop ((i start) (acc ()))
        (if (>= i end) (reverse acc)
          (loop (+ i 1) (cons (char->integer (string-ref str i)) acc)))))))
