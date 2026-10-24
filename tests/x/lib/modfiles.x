; Test harness: x-core.x + a module written in several files.  The suite
; boots from a state image of this file, so writing that image loads files
; through the loader of lib/x/boot/module.x in a fresh base -- the image
; writer's child -- and a buffer or frame it builds that the base cannot
; hold is caught when the image is written, before any case runs.
(include "lib/x-core.x")
(import-path! "tests/x/fixtures/modscope")
(import scoped/whole)
