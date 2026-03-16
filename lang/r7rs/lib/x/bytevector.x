; --- Bytevectors (R7RS §6.9) ---
; 2-slot object: slot 0 = length, slot 1 = ptr to malloc'd byte buffer.

(define %bv-malloc (dlsym %libc "malloc"))
(define %bv-memcpy (dlsym %libc "memcpy"))

(define %bytevector
  (make-type
    (lit BYTEVECTOR)
    (list
      (cons (lit write)
        (lambda (self)
          (display "#u8(")
          (let ((len (obj-ref self 0))
                (buf (obj-ref self 1)))
            (let loop ((i 0) (sep #f))
              (if (< i len)
                (begin
                  (if sep (display " "))
                  (display (ptr-ref buf i 1))
                  (loop (+ i 1) #t)))))
          (display ")"))))))

(define (bytevector? x) (type? x %bytevector))

(define (%bv-alloc n)
  (int->ptr (ptr-call %bv-malloc (if (= n 0) 1 n))))

(define (bytevector . bytes)
  (let ((len (length bytes)))
    (let ((bv (make-obj %bytevector 2))
          (buf (%bv-alloc len)))
      (obj-set! bv 0 len)
      (obj-set! bv 1 buf)
      (let loop ((lst bytes) (i 0))
        (if (not (null? lst))
          (begin
            (ptr-set! buf i (car lst) 1)
            (loop (cdr lst) (+ i 1)))))
      bv)))

(define (make-bytevector k . fill)
  (let ((byte (if (null? fill) 0 (car fill))))
    (let ((bv (make-obj %bytevector 2))
          (buf (%bv-alloc k)))
      (obj-set! bv 0 k)
      (obj-set! bv 1 buf)
      (let loop ((i 0))
        (if (< i k)
          (begin (ptr-set! buf i byte 1) (loop (+ i 1)))))
      bv)))

(define (bytevector-length bv)
  (obj-ref bv 0))

(define (bytevector-u8-ref bv k)
  (ptr-ref (obj-ref bv 1) k 1))

(define (bytevector-u8-set! bv k byte)
  (ptr-set! (obj-ref bv 1) k byte 1))

(define (bytevector-copy bv . args)
  (let ((src-len (obj-ref bv 0)))
    (let ((start (if (null? args) 0 (car args)))
          (end (if (or (null? args) (null? (cdr args)))
                 src-len (cadr args))))
      (let ((len (- end start)))
        (let ((new (make-bytevector len 0))
              (src (obj-ref bv 1)))
          (let ((dst (obj-ref new 1)))
            (if (> len 0)
              (ptr-call %bv-memcpy dst
                (int->ptr (+ (ptr->int src) start)) len)))
          new)))))

(define (bytevector-copy! to at from . args)
  (let ((src-len (obj-ref from 0)))
    (let ((start (if (null? args) 0 (car args)))
          (end (if (or (null? args) (null? (cdr args)))
                 src-len (cadr args))))
      (let ((len (- end start)))
        (if (> len 0)
          (ptr-call %bv-memcpy
            (int->ptr (+ (ptr->int (obj-ref to 1)) at))
            (int->ptr (+ (ptr->int (obj-ref from 1)) start)) len))))))

(define (bytevector-append . bvs)
  (let ((total (apply + (map bytevector-length bvs))))
    (let ((new (make-bytevector total 0)))
      (let ((dst (obj-ref new 1)))
        (let loop ((bvs bvs) (off 0))
          (if (not (null? bvs))
            (let ((len (bytevector-length (car bvs))))
              (if (> len 0)
                (ptr-call %bv-memcpy
                  (int->ptr (+ (ptr->int dst) off))
                  (obj-ref (car bvs) 1) len))
              (loop (cdr bvs) (+ off len))))))
      new)))

(define (utf8->string bv . args)
  (let ((src-len (obj-ref bv 0)))
    (let ((start (if (null? args) 0 (car args)))
          (end (if (or (null? args) (null? (cdr args)))
                 src-len (cadr args))))
      (let ((buf (obj-ref bv 1)))
        (list->string
          (let loop ((i start) (acc ()))
            (if (>= i end) (reverse acc)
              (loop (+ i 1)
                (cons (integer->char (ptr-ref buf i 1)) acc)))))))))

(define (string->utf8 str . args)
  (let ((start (if (null? args) 0 (car args)))
        (end (if (or (null? args) (null? (cdr args)))
               (string-length str)
               (cadr args))))
    (let ((len (- end start)))
      (let ((bv (make-bytevector len 0)))
        (let ((buf (obj-ref bv 1)))
          (let loop ((i 0) (si start))
            (if (< i len)
              (begin
                (ptr-set! buf i (char->integer (string-ref str si)) 1)
                (loop (+ i 1) (+ si 1))))))
        bv))))
