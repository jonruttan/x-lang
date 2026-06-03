; Test harness: x-core.x + stubbed syscall + x/sys/file
;
; file.x performs real I/O via raw Linux (x86_64) syscall numbers, so it
; cannot execute on a non-Linux dev machine -- a wrong syscall number
; corrupts memory.  To regression-test it portably we stub `syscall` and
; `syscall-id` to *capture* the arguments file.x passes instead of issuing a
; real syscall.  This pins down argument binding -- the bug being guarded
; against was every file.x function missing its `_` self slot, which shifted
; each argument by one (fd/pathname bound to the function itself).
;
; The stubs are defined at top level (NOT inside a `do`) so that file.x's
; top-level functions resolve `syscall`/`syscall-id`/`make-str` to these
; stubs rather than the C primitives.
(include "lib/x-core.x")

; %last-syscall holds the argument list of the most recent `syscall` call,
; e.g. (open "/path" 577) -- inspected by the spec cases.
(def %last-syscall (list ()))
(def syscall (fn (_ . a) (set-first! %last-syscall a) 0))
; identity stub: pass the symbolic name (open/read/write/close) straight
; through so cases can assert on it without a platform syscall table.
(def syscall-id (fn (_ n) n))
; make-str is an x-or-dialect C primitive absent from this build; fgetc only
; needs *a* buffer, and the stubbed syscall returns 0 (EOF) so the buffer's
; contents are never read -- a placeholder string suffices.
(def make-str (fn (_ n) " "))

(import x/sys/file)
