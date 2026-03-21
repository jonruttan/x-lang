; cat.x -- Display a file using syscalls
;
; Usage:
;   cat lang/x-or/lib/or-base.x lang/x-or/lib/x/file.x lang/x-or/examples/cat.x | ./x

(do
  (def buf (make-string 256))

  (def display-file (fn (fd)
    (let ((n (fread fd buf 256)))
      (if (> n 0)
        (do
          (syscall (syscall-id (lit write)) stdout buf n)
          (display-file fd))))))

  (let ((fd (fopen "lang/x-or/examples/cat.x" (lit rdonly))))
    (display "=== cat.x ===\n")
    (display-file fd)
    (fclose fd)))
