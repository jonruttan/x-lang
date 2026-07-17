; assert.x -- spec-harness personality: x-core + the shipped test assertions.
;
; Loaded by a spec via `# @lib ../tests/x/lib/assert.x`; like the other test
; libs (token.x, fmt.x) it stands in for the default lib, so it includes
; x-core first. The helpers themselves (throws?, raised) now live under
; lib/x/test/assert.x so user programs can import them too.
(include "lib/x-core.x")
(import x/test/assert)
