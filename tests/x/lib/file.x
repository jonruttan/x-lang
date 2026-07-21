; Test harness: x-core.x + x/sys/file + capturing stubs
;
; file.x performs real I/O via raw Linux syscalls, so it cannot execute on a
; non-Linux dev machine -- a wrong syscall number corrupts memory.  To
; regression-test it portably we stub `syscall`/`syscall-id`/`make-str` to
; *capture* the arguments each method passes instead of issuing a real syscall.
; This pins down argument binding -- the bug being guarded against was every
; File method missing its `self` slot, which shifted each argument by one
; (fd/pathname bound to the method itself).
;
; ORDER MATTERS: file.x imports x/platform/syscall, whose REAL `syscall-id`
; returns numeric syscall ids.  We install the stubs AFTER the import so they
; win -- File's methods resolve `syscall`/`syscall-id`/`make-str` as globals at
; call time, so the later (stub) definitions shadow both the real syscall-id
; and the absent radon C primitives.
(include "lib/x-core.x")
(import x/sys/file)

; %last-syscall holds the argument list of the most recent `syscall` call,
; e.g. (open "/path" 577) -- inspected by the spec cases.
(def %last-syscall (list ()))
(def syscall (fn (_ . a) (set-first! %last-syscall a) 0))
; identity stub: pass the symbolic name (open/read/write/close) straight
; through so cases can assert on it without a platform syscall table.
(def syscall-id (fn (_ n) n))
; make-str is an radon-dialect C primitive absent from this build; (File getc)
; only needs *a* buffer, and the stubbed syscall returns 0 (EOF) so the
; buffer's contents are never read -- a placeholder string suffices.
(def make-str (fn (_ n) " "))
