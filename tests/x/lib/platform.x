; Test harness: x-core.x + the platform-aware syscall / file layers, NO stubs.
;
; These specs check the PLATFORM-SELECTED values (syscall numbers, O_* flags)
; that syscall-id and (File file-modes) compute. Both are pure table lookups, so
; loading and exercising them issues NO real syscall -- safe on any OS. The
; assertions branch on os-darwin? to stay portable across Linux and macOS.
(include "lib/x-core.x")
(import x/platform/syscall)
(import x/sys/file)
