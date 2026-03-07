; hello.x -- Hello world via syscall
;
; Usage (Linux x86_64):
;   cat lib/x.x lang/sl/lib/sl.x lang/sl/examples/hello.x | ./x
;
; The simplest syscall example: write a string to stdout.

(begin
  (display-string "Hello from SL!\n")
  (display-string "syscall write = ")
  (display (syscall-id (lit write)))
  (sl-newline))
