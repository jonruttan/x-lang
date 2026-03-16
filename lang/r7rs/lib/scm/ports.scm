; --- Port extensions (R7RS §6.13) ---

(define (port? x) (or (input-port? x) (output-port? x)))
(define (close-port p)
  (cond ((input-port? p) (close-input-port p))
        ((output-port? p) (close-output-port p))))

; --- String input ports (R7RS §6.13.3) ---
; Implementation: write string to a temp file, open for reading.

(define %c-mkstemp (dlsym %libc "mkstemp"))
(define %c-unlink (dlsym %libc "unlink"))
(define %c-write-raw (dlsym %libc "write"))
(define %c-memcpy (dlsym %libc "memcpy"))
(define %c-lseek (dlsym %libc "lseek"))

(define (open-input-string str)
  ; Create temp file
  (let ((template (string-copy "/tmp/xstr-XXXXXX")))
    (let ((fd (ptr-call %c-mkstemp (string->ptr template))))
      (if (< fd 0) (error "open-input-string: mkstemp failed"))
      ; Unlink immediately (file stays open but name removed)
      (ptr-call %c-unlink (string->ptr template))
      ; Write string content
      (let ((len (string-length str)))
        (if (> len 0)
          (ptr-call %c-write-raw fd (string->ptr str) len)))
      ; Seek back to start
      (ptr-call %c-lseek fd 0 0)
      ; Create input port
      (%make-port fd (lit input)
        (obj-make "BUFFER"
          (int->ptr (ptr-call %c-malloc 65536)) 32)))))

; --- String output ports (R7RS §6.13.3) ---
; Implementation: write to a temp file, read back for get-output-string.

(define %c-read-raw (dlsym %libc "read"))
(define %c-free (dlsym %libc "free"))

(define %string-output-port-tag (cons (lit %string) (lit output)))

(define (open-output-string)
  (let ((template (string-copy "/tmp/xout-XXXXXX")))
    (let ((fd (ptr-call %c-mkstemp (string->ptr template))))
      (if (< fd 0) (error "open-output-string: mkstemp failed"))
      (ptr-call %c-unlink (string->ptr template))
      ; Store the tag in the port's buffer slot to identify string ports
      (%make-port fd (lit output) %string-output-port-tag))))

(define (%string-output-port? p)
  (and (output-port? p) (eq? (%port-buffer p) %string-output-port-tag)))

(define (get-output-string p)
  (if (not (%string-output-port? p))
    (error "get-output-string: not a string output port"))
  (let ((fd (%port-fd p)))
    ; Get current position (= total bytes written)
    (let ((len (ptr-call %c-lseek fd 0 1)))
      ; Seek to start
      (ptr-call %c-lseek fd 0 0)
      ; Read all content
      (if (<= len 0) ""
        (let ((buf (int->ptr (ptr-call %c-malloc (+ len 1)))))
          (ptr-call %c-read-raw fd buf len)
          ; Null-terminate
          (ptr-set! buf len 0 1)
          ; Seek back to end for further writes
          (ptr-call %c-lseek fd 0 2)
          (let ((result (ptr->string buf)))
            (ptr-call %c-free buf)
            result))))))
