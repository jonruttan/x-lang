; doc.x -- Offline documentation generator (entry script)
;
; Reads a source file (as a quoted string on stdin), tokenizes it,
; walks the token tree to extract (doc ...) and (note ...) forms,
; and outputs Markdown.

(do
  (import x/doc/doc-gen)

  ; --- Tokenize source ---
  (def %input (read))
  (def %doc-base (make-base))
  (def %tokens (token-read-string %doc-base %input))

  ; --- Generate ---
  (doc-walk %tokens))
