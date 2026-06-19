; Test harness: x-core.x (which loads x/sys/token -> the Token class and the
; catalog-registered terminators) + cached terminator refs for the cases.
;
; The terminators (accept/reject) live under catalog ns `token` rather than as
; globals -- reader-context callers fetch them. The spec runs cold, so it fetches
; them here once and the cases use %acc / %rej.
(include "lib/x-core.x")
(def %acc (prim-ref (lit token) (lit accept)))
(def %rej (prim-ref (lit token) (lit reject)))
