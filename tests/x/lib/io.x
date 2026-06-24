; Test harness for REAL file I/O: x-core plus the I/O modules. Sys does file
; I/O via libc FFI (returns byte lists), File writes via raw syscall, Stream
; redirects display output to a file. syscall/syscall-id give unlink for cleanup.
; (None of this needs the x-or bundle -- these are just the modules x-or also
; happens to import.)
(include "lib/x-core.x")
(import x/sys/posix)
(import x/sys/file)
(import x/sys/stream)
(import x/platform/syscall)
