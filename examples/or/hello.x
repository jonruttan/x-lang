; hello.x -- Hello world via syscall
;
; Usage:
;   cat lang/x-or/lib/or-base.x lang/x-or/examples/hello.x | ./x

(do
  (display "Hello from x/or!\n")
  (display "syscall write = ")
  (display (syscall-id (lit write)))
  (newline))
