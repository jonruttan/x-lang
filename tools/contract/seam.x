; seam.x -- what a lang may rely on, and what the platform must keep providing.
;
; A lang (docs/lang-contract.md) is a different surface language living in its
; own repository, loaded over a dialect.  It reaches the platform through a
; handful of names -- it sets %lang-name so the banner says what it is, it
; arms its module root with import-path!, it calls repl to hand over a
; session.  Those names are a CONTRACT.  The rest of lib/ is not.
;
; WHY THIS FILE EXISTS.  The last generation of langs died three ways, and one
; of them was this: module and global names moved underneath them while nobody
; was looking.  A lang in another repository cannot fail this tree's tests, so
; the only way that break is caught before a user hits it is here -- a rename
; that drops a seam name fails the gate, and restoring it or editing this file
; is then a deliberate, reviewable act rather than a silent one.
;
; DECLARED, NOT DERIVED, and that is a departure from base-paths.x worth being
; explicit about.  tools/check/base-routes.sh derives the route names from the
; library's own call sites, because the caller is in this tree.  A lang's call
; sites are NOT in this tree and never will be -- that is the whole point of a
; lang -- so there is nothing here to derive from.  This file is the other
; shape the repo already uses: a closed vocabulary the language owns, like
; tools/contract/features.x, held against reality by a gate.
;
; FORMAT (one form per line, closed vocabulary -- an unknown form is an error):
;
;   (seam CLASS NAME "what it is")
;
;   always     bound in every dialect, in every tree.  A lang may use it
;              plainly.
;   installed  bound ONLY in an installed tree; ABSENT in a repo checkout.  A
;              lang must guard it, and the gate proves the guard is needed by
;              checking the name is absent from a checkout -- a seam row that
;              quietly became unconditional would make every guard look like
;              superstition.
;   bundle     bound ONLY while a lang BUNDLE is loaded (`-l NAME` resolving
;              through langs/*/lang.xon); absent in a bare dialect.  The gate
;              checks both halves, and the second half needs a bundle to load
;              -- tools/contract/bundles/seamprobe/ is that bundle, and it is
;              a fixture rather than a lang: nine lines whose only job is to
;              be loaded.  A class nothing can probe is documentation, which
;              is the state this file exists to end.
;
; docs/lang-contract.md carries the same table for readers; the gate holds the
; two to each other, so the documented seam cannot drift from the enforced one.

(seam always %lang-name     "the surface's name -- what the banner prints")
(seam always %lang-version  "the surface's version, printed beside the name")
(seam always %banner        "prints the greeting; a lang calls it or replaces it")
(seam always %repl-prompt   "the prompt string, set! by a lang to claim the line")
; %repl-print and %repl-read are %repl-prompt's siblings and were missed when
; this table was first written: loop.x documents the printer as customizable
; and x-krn set! it on its first day, which is how the omission was found.  A
; lang that re-means what a result LOOKS like needs the printer -- Kernel shows
; (b c) where x shows ('b 'c) -- and one that re-means SYNTAX needs the reader.
(seam always %repl-print    "the result printer, set! by a lang that prints its own values")
(seam always %repl-read     "the reader the loop calls, set! by a lang with its own syntax")
(seam always repl           "the read-eval-print loop a lang hands its session to")
(seam always %batch?        "whether -f/--batch was passed: no session to hand over")
(seam always import-path!   "arm an import root at runtime -- how a lang finds its own modules")
; eval! IS HOW A LANG IMPLEMENTS define, and that is not obvious from its
; docstring ("evaluate in current environment").  A lang's define is an
; operative that must bind in the caller's world, and plain `eval` only manages
; it when the call happens to sit in tail position, so TCO has popped the frame
; -- an accident of shape that x-lang#527 records breaking under one extra
; frame.  eval! does no env save/restore, so the binding persists regardless.
; x-krn's whole suite turns on it: 59 of 72 specs fail without it, 0 with.
(seam always eval!          "evaluate without env save/restore -- how a lang's define binds in its caller")
(seam always x-lib-version  "the platform library's version, for a lang that reports it")

(seam installed %install-root "the installed tree's root; ABSENT in a checkout, so a lang must guard it")

; %lang-root IS NOT %install-root, and conflating them is the whole reason it
; has a row.  %install-root is where the PLATFORM lives; a bundle lives
; wherever it was installed or pinned to, which is under langs/ in one case and
; a project's deps/ in another.  A bundle that shipped a data file and reached
; for %install-root would find the platform's tree and read nothing.
;
; MODULES DO NOT NEED THIS.  `import` resolves through the root the wrapper
; arms, and a sibling source file is reached with a ./-relative include-once;
; both work without knowing an absolute path, which is why five bundles got
; this far without one.  DATA is the case neither covers: x-logo's serve.x
; hands viewer.html to a browser, and there is no import that means "the bytes
; of that file".
(seam bundle %lang-root "the bundle's own directory; how a lang reaches DATA it ships, not modules")
