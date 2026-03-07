; cat.x -- Display a file using syscalls
;
; Usage (Linux x86_64):
;   cat lib/x.x lang/sl/lib/sl.x lang/sl/lib/file.x lang/sl/examples/cat.x | ./x
;
; Ported from the original SL project (examples/file/cat.sl)
; Author: Jon Ruttan, 2012

(begin
  (define buf (make-string 256))

  (define display-file (lambda (fd)
    (let ((n (fread fd buf 256)))
      (if (> n 0)
        (begin
          (syscall (syscall-id (lit write)) stdout buf n)
          (display-file fd))))))

  (let ((fd (fopen "lang/sl/examples/cat.x" (lit rdonly))))
    (display-string "=== cat.x ===\n")
    (display-file fd)
    (fclose fd)))
