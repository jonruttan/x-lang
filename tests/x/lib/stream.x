; Test harness: x-core.x + x/sys/stream
;
; Stream's redirect core is pure X -- it push/pops the base's `fileout` fd, no
; syscall. These specs exercise only that syscall-free surface (construction,
; the redirect plumbing, restore), so they run portably under x-core. The
; file-backed methods (to-file / write / with-output-to-file) need the radon
; dialect (real syscall/make-str) and are verified separately, in radon.
(include "lib/x-core.x")
(import x/sys/stream)
