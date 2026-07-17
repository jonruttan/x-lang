; cat.x -- Display a file using raw syscalls
;
; Usage:
;   sh x.sh -l x-or -f examples/or/cat.x
;
; (Run from the repository root -- the file path below is repo-relative.)

(do
  ; A GC-owned byte buffer for the read syscall to fill
  (def buf (Str8 make 256 #\space))

  (def display-file (fn (self fd)
    (let ((n (File read fd buf 256)))
      (if (> n 0)
        (do
          (syscall (syscall-id (lit write)) stdout buf n)
          (self fd))))))

  (let ((fd (File open "examples/or/cat.x" (lit rdonly))))
    (display "=== cat.x ===\n")
    (display-file fd)
    (File close fd)))
