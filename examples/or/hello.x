; hello.x -- Hello world via syscall
;
; Usage:
;   sh x.sh -l x-or -f examples/or/hello.x

(do
  (display "Hello from x/or!\n")
  (display "syscall write = ")
  (display (syscall-id (lit write)))
  (newline))
