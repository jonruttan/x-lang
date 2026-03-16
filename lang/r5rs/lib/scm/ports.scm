; --- Port system (R5RS §6.6) ---

; FFI setup for file operations
(define %libc (dlopen () 1))
(define %c-open (dlsym %libc "open"))
(define %c-close (dlsym %libc "close"))
(define %c-fchmod (dlsym %libc "fchmod"))
(define %c-malloc (dlsym %libc "malloc"))

; Base object navigation
(define %base-root (first (%base)))
(define %base-files (first (rest %base-root)))
(define %base-env (first (rest (rest %base-root))))
(define %filein-stack-slot %base-files)
(define %fileout-stack-slot (rest %base-files))
(define %buffer-stack-slot (rest (rest %base-env)))
(define %fileout-atom (first (first (rest %base-files))))
(define %line-stack-slot
  (rest (rest (rest (rest (rest %base-root))))))

; Save C primitives before overriding
(define %prim-read read)
(define %prim-read-char read-char)
(define %prim-peek-char peek-char)
(define %prim-write write)
(define %prim-display display)
(define %prim-newline newline)

; Transcript state (fd or #f)
(define %transcript-fd #f)

; PORT custom type
(define %port-type
  (make-type "PORT"
    (list
      (cons (lit write)
        (lambda (self)
          (let ((data (first self)))
            (%prim-display "#<")
            (%prim-display (cadr data))
            (%prim-display "-port ")
            (%prim-display (car data))
            (%prim-display ">")))))))
; Port constructor: (fd direction buffer)
; direction = input or output, buffer = for input ports only
(define (%make-port fd direction buf)
  (make-instance %port-type (list fd direction buf #t)))
(define (input-port? x)
  (and (type? x %port-type) (eq? (cadr (first x)) (lit input))))
(define (output-port? x)
  (and (type? x %port-type) (eq? (cadr (first x)) (lit output))))
(define (%port-fd p) (car (first p)))
(define (%port-open? p) (cadddr (first p)))
(define (%port-buffer p) (caddr (first p)))
(define (%port-close! p)
  (set-car! (cdddr (first p)) #f))

; EOF object
(define %eof-obj (cons (lit eof) (lit eof)))
(define (eof-object? x) (eq? x %eof-obj))

; Current ports
(define (%make-stdin-port)
  (%make-port 0 (lit input) (first (first %buffer-stack-slot))))
(define (%make-stdout-port)
  (%make-port 1 (lit output) #f))
(define (current-input-port) (%make-stdin-port))
(define (current-output-port) (%make-stdout-port))

; Open/close
(define (open-input-file path)
  (let ((fd (ptr-call %c-open path 0)))
    (if (< fd 0) (error "cannot open input file")
      (%make-port fd (lit input)
        (obj-make "BUFFER"
          (int->ptr (ptr-call %c-malloc 65536)) 32)))))
(define (open-output-file path)
  (let ((fd (ptr-call %c-open path 1537 438)))
    (if (< fd 0) (error "cannot open output file")
      (begin (ptr-call %c-fchmod fd 438)
        (%make-port fd (lit output) #f)))))
(define (close-input-port p)
  (ptr-call %c-close (%port-fd p))
  (%port-close! p))
(define (close-output-port p)
  (ptr-call %c-close (%port-fd p))
  (%port-close! p))

; Input port redirection: push fd and buffer onto stacks
(define (%with-input-port port thunk)
  (let ((fd (%port-fd port))
        (buf (%port-buffer port)))
    (set-car! %filein-stack-slot
      (cons fd (car %filein-stack-slot)))
    (set-car! %buffer-stack-slot
      (cons buf (car %buffer-stack-slot)))
    (let ((result (thunk)))
      (set-car! %filein-stack-slot
        (cdr (car %filein-stack-slot)))
      (set-car! %buffer-stack-slot
        (cdr (car %buffer-stack-slot)))
      result)))

; Output port redirection: swap fileout fd
(define (%with-output-port port thunk)
  (let ((saved (first-int %fileout-atom)))
    (set-first-int %fileout-atom (%port-fd port))
    (let ((result (thunk)))
      (set-first-int %fileout-atom saved)
      result)))

; Port-aware read (echo to transcript)
(set! read
  (lambda args
    (if (null? args)
      (let ((r (%prim-read)))
        (let ((result (if (null? r) %eof-obj r)))
          (if %transcript-fd
            (begin
              (%transcript-out (lambda () (%prim-write result)))
              (%transcript-out (lambda () (%prim-newline)))))
          result))
      (%with-input-port (car args)
        (lambda ()
          (let ((r (%prim-read)))
            (if (null? r) %eof-obj r)))))))

; Port-aware read-char (echo to transcript)
(set! read-char
  (lambda args
    (if (null? args)
      (let ((r (%prim-read-char)))
        (let ((result (if (null? r) %eof-obj r)))
          (if (and %transcript-fd (not (eof-object? result)))
            (%transcript-out
              (lambda () (%prim-display (make-string 1 result)))))
          result))
      (%with-input-port (car args)
        (lambda ()
          (let ((r (%prim-read-char)))
            (if (null? r) %eof-obj r)))))))

; Port-aware peek-char
(set! peek-char
  (lambda args
    (if (null? args)
      (let ((r (%prim-peek-char)))
        (if (null? r) %eof-obj r))
      (%with-input-port (car args)
        (lambda ()
          (let ((r (%prim-peek-char)))
            (if (null? r) %eof-obj r)))))))

; char-ready? (always #t for file ports, check buffer for stdin)
(define (char-ready? . args) #t)

; Transcript tee: write to transcript fd, then restore
(define (%transcript-out thunk)
  (let ((%ts (first-int %fileout-atom)))
    (set-first-int %fileout-atom %transcript-fd)
    (thunk)
    (set-first-int %fileout-atom %ts)))

; Port-aware write
(set! write
  (lambda (obj . args)
    (if (null? args)
      (begin
        (%prim-write obj)
        (if %transcript-fd
          (%transcript-out (lambda () (%prim-write obj)))))
      (%with-output-port (car args)
        (lambda () (%prim-write obj))))))

; Port-aware display
(set! display
  (lambda (obj . args)
    (if (null? args)
      (begin
        (%prim-display obj)
        (if %transcript-fd
          (%transcript-out (lambda () (%prim-display obj)))))
      (%with-output-port (car args)
        (lambda () (%prim-display obj))))))

; Port-aware newline (use %prim-display "\n" since %prim-newline calls display)
(set! newline
  (lambda args
    (if (null? args)
      (begin
        (%prim-display "\n")
        (if %transcript-fd
          (%transcript-out (lambda () (%prim-display "\n")))))
      (%with-output-port (car args)
        (lambda () (%prim-display "\n"))))))

; Port-aware write-char
(set! write-char
  (lambda (c . args)
    (if (null? args)
      (begin
        (%prim-display (make-string 1 c))
        (if %transcript-fd
          (%transcript-out (lambda () (%prim-display (make-string 1 c))))))
      (%with-output-port (car args)
        (lambda () (%prim-display (make-string 1 c)))))))

; Higher-order port operations
(define (call-with-input-file path proc)
  (let ((port (open-input-file path)))
    (let ((result (proc port)))
      (close-input-port port)
      result)))
(define (call-with-output-file path proc)
  (let ((port (open-output-file path)))
    (let ((result (proc port)))
      (close-output-port port)
      result)))
(define (with-input-from-file path thunk)
  (let ((port (open-input-file path)))
    (let ((result (%with-input-port port thunk)))
      (close-input-port port)
      result)))
(define (with-output-to-file path thunk)
  (let ((port (open-output-file path)))
    (let ((result (%with-output-port port thunk)))
      (close-output-port port)
      result)))

; load = include
(define load include)

; transcript
(define (transcript-on filename)
  (if %transcript-fd (transcript-off))
  (set! %transcript-fd (ptr-call %c-open filename 1537 438))
  (if (< %transcript-fd 0)
    (begin (set! %transcript-fd #f) (error "cannot open transcript file"))
    (ptr-call %c-fchmod %transcript-fd 438)))
(define (transcript-off)
  (if %transcript-fd
    (begin (ptr-call %c-close %transcript-fd)
           (set! %transcript-fd #f))))
