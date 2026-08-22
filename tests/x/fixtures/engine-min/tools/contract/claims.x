; claims.x -- what x-engine-min asserts about itself.
;
; A PAPER ENGINE: contract files and nothing else -- no binary, no source.  It
; exists so the contract apparatus is exercised against an engine that is not
; x-engine-c, on every run, rather than only when someone remembers to try.
;
; It declares the `core` profile and nothing above it: no foreign door, no raw
; syscall door, no collector, no OS facilities.  x-lang's library needs `posix`,
; so the correct answer for this engine is a REFUSAL naming exactly the four
; capability groups it lacks -- which is what tools/check/second-engine.sh
; asserts.
;
; Pointing the apparatus here the first time found two real bugs: the contract
; gate hardcoded ext/x-engine-c so it could not judge any other engine, and the
; declaration generator added explicitly-grouped coordinates WITHOUT checking the
; engine had them, so this engine's declaration claimed a foreign door it has
; zero rows for.  A fixture is cheaper than remembering.
(def %claims (lit (
  (provides io/include)
  (provides reflect/layout-data)
  (provides reflect/word-probe)
  (provides invoke/pipe-stdin)
  (provides invoke/argv)
  (provides err/stderr-prefix)

  (guarantee gc/explicit-only)
  (guarantee gc/non-moving)
  (guarantee eval/tco)
  (guarantee tok/callback-no-alloc)
  (guarantee str/nul-terminated)
  (guarantee int/ptr-same-width)
)))
