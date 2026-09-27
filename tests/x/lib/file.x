; Test harness: x-core.x + x/sys/file + capturing stubs
;
; file.x performs real I/O via raw syscalls.  To regression-test the argument
; binding portably we stub `syscall-door`/`syscall`/`syscall-id`/`make-str` to
; *capture* the arguments each method passes instead of issuing a real syscall.
; This pins down argument binding -- the bug being guarded against was every
; File method missing its `self` slot, which shifted each argument by one
; (fd/pathname bound to the method itself).
;
; ORDER MATTERS: File resolves each call through `syscall-door` when file.x
; loads, so the door is stubbed after x/platform/syscall has defined the real
; one and before x/sys/file asks it for anything.
(include "lib/x-core.x")
(import x/platform/syscall)

; %last-syscall holds the argument list of the most recent call, e.g.
; (open "/path" 577) -- inspected by the spec cases.
(def %last-syscall (list ()))
; A door that makes no call: it records the name it was made for (open, read,
; write, close) ahead of the arguments it was applied to, so cases can assert
; on both without a platform syscall table.
(def syscall-door
  (fn (_ name)
    (fn (_ . a) (%set-first! %last-syscall (pair name a)) 0)))
(import x/sys/file)
(def syscall (fn (_ . a) (%set-first! %last-syscall a) 0))
(def syscall-id (fn (_ n) n))
; make-str is an radon-dialect C primitive absent from this build; (File getc)
; only needs *a* buffer, and the stubbed syscall returns 0 (EOF) so the
; buffer's contents are never read -- a placeholder string suffices.
(def make-str (fn (_ n) " "))
