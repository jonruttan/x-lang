; tools/release/hash-isa.x -- print the pure-x sha256 of the ISA contract.
;
; The release workflow's dogfood cross-check: x/codec/sha256 is the
; consumer-side verify anchor, and it must agree with coreutils on the
; ISA fingerprint consumers will check against.  This lived INLINE in
; release.yml until v0.4.0's tag failed on it: the embedded script
; still called the retired (File slurp), and a workflow that only runs
; on tags is invisible to every gate (the #180 rot family).  As a tree
; file it is greppable, lintable, and named by the retirement sweeps.
(import x/sys/file)
(import x/codec/sha256)
(display (Sha256 hex (File read-all "engine/tools/contract/isa.x")))
(newline)
