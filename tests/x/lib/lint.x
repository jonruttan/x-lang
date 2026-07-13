; Test harness: x-core.x + lint.x
; Loads the lint tool ONCE per batch. The spec's tests used to raw-include
; lib/x/tool/lint.x apiece: 31 re-loads x ~150 MB of objects with no GC
; between snippets made the batch's true footprint ~5 GB (macOS memory
; compression hid it; any small-RAM box OOMs honestly).
(include "lib/x-core.x")
(include "lib/x/tool/lint.x")
