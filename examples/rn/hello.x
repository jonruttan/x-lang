; hello.x -- Hello world via syscall
;
; Usage:
;   sh x.sh -l rn -f examples/rn/hello.x

(do
  (display "Hello from x/rn!\n" "syscall write = " (syscall-id (lit write))
           "\n"))
