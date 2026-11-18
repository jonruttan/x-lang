; diff.x -- the diff and patch highlighting grammar
;
; x/tool/syntax's catalogue names this module for .diff and .patch files
; and imports it the first time a file needs the grammar.
;
; A token is a line, classed by how it starts: a file's header (diff,
; index, ---, +++, ***, and git's mode, rename and similarity lines) a
; class, a hunk's header (@@, or a context diff's *** n,m ****) a keyword,
; an added line a string, a removed line an error, a changed line of a
; context diff an operator, and "\ No newline at end of file" a comment.
; Every other line is plain.  A removed line whose text starts with -- reads
; as a file's header: a line alone cannot tell them apart.  Every line
; starts a token, so a window colours without reading from the start.

(module x/tool/syntax/diff)
(import x/type/list)
(import x/type/str)
(import x/reader/lexer)
(import x/tool/syntax)

(def %sxd-line-bytes (list (pair 1 9) (pair 11 255) (pair -128 -1)))

(def %sxd-rules
  (fn (_)
    (list (Lexer table (lit nl) (list "\n"))
          (Lexer run (lit line) %sxd-line-bytes %sxd-line-bytes)
          (Lexer any (lit other)))))

(def %sxd-headers
  (list "diff " "index " "--- " "+++ " "Index: " "Only in " "Binary files "
        "new file mode" "deleted file mode" "old mode" "new mode"
        "similarity index" "dissimilarity index" "rename from" "rename to"
        "copy from" "copy to"))

; A line's class, by its first bytes.
(def %sxd-line
  (fn (_ t)
    (match ((Str8 starts? "@@" t) (lit keyword))
           ((if (Str8 starts? "*** " t) (Str8 ends? " ****" t) #f) (lit keyword))
           ((if (Str8 starts? "--- " t) (Str8 ends? " ----" t) #f) (lit keyword))
           ((List any? (fn (_ h) (Str8 starts? h t)) %sxd-headers) (lit class))
           ((Str8 starts? "***************" t) (lit punct))
           ((Str8 starts? "+" t) (lit string))
           ((Str8 starts? "-" t) (lit error))
           ((Str8 starts? "!" t) (lit operator))
           ((Str8 starts? "\\" t) (lit comment))
           (#t ()))))

(Syntax register!
  (let ((g (Syntax make (lit diff) (%sxd-rules) (list (pair (lit line) %sxd-line)))))
    (g sync (fn (_ _ _) #t))
    (g end "\n")
    (g files (list ".diff" ".patch"))
    g))

(doc (provide x/tool/syntax/diff)
  (note "Imported by x/tool/syntax the first time a .diff or .patch file needs the grammar; (Syntax named 'diff) loads it.")
  (example "((Syntax named 'diff) spans \"--- a\\n+++ b\\n@@ -1 +1 @@\\n-x\\n+y\\n z\\n\")" "((0 5 'class) (6 5 'class) (12 11 'keyword) (24 2 'error) (27 2 'string))")
  "The diff and patch highlighting grammar: file and hunk headers, added, removed and changed lines.")
