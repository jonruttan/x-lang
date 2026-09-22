; Test harness: x-core.x + posix + hash + compile (no numeric types)
(include "lib/x-core.x")
(import x/sys/posix)
(import x/type/hash)
(import x/tool/compile
  compile-to-c compile-write compile-cc compile-load compile-cc-flags compile-ext
  compile-hosted? compile-with-writers compile-emitters compile-add-emitter!
  compile compile-c compile-asm compile-batch)
