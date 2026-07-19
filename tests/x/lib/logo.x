; Test harness: x-core.x + float + the Logo app's turtle kernel.
; The app lives under apps/ (#35); arm its import root so turtle.x's
; own (import logo/...) lines resolve, then import it as a module
; (include would sidestep the pre-seed and double-load its deps).
(include "lib/x-core.x")
(def %bignum ())
(include "lib/x/num/float.x")
(import-path! "apps")
(import logo/turtle)
