; doc.x -- Offline documentation generator (entry script)
;
; ONE file: a pure filter, Markdown to stdout, exactly as ever.
;   sh x.sh --no-pin -q -f tools/dev/doc.x -- FILE
; SEVERAL files (#321): every page streams to stdout, each preceded by
; a "%%DOC-X-PAGE%% <source>" sentinel line; tools/dev/doc-sweep.sh
; splits the stream.  The whole point is boot amortization -- the old
; per-file loop paid ~98 engine boots per sweep -- so per-FILE state is
; deliberately identical to the one-process-per-file days: a fresh
; scratch base and a fresh doc-prims parse per file, never shared
; (cross-base data must not mix; the re-parse is the same work each old
; process did anyway).
;
; Inputs are read by path (no stdin data channel under x.sh -f):
;   1. lib/x/doc/doc-prims.x (retroactive docs for boot modules; an
;      empty table when the file IS doc-prims.x)
;   2. the source file being documented
;
; Tokenizes both, builds a lookup alist from doc-prims.x, then walks
; the source tokens using the alist as fallback for bare (def ...) forms.

; Fetch the tokenizer prims from the catalog (ns `buf`/`tok` are de-registered, R5).

(do
  (import x/doc/doc-gen)
  (import x/codec/xon)
  (import x/tool/contract)

  (Contract alloc-guard!)

  (def %argv (Contract argv))
  (when (null? %argv)
    (do (%stderr "Usage: x.sh --no-pin -q -f tools/dev/doc.x -- FILE...\n")
        (Sys exit 1)))

  (def %prims-path "lib/x/doc/doc-prims.x")

  ; One file's page to stdout.  A fresh scratch base and fresh
  ; doc-prims tokens per file (see header): only the boot is shared.
  (def %doc-one
    (fn (_ %file)
      (unless (File exists? %file)
        (do (%stderr (Str8 append "Error: " (Str8 append %file " not found\n")))
            (Sys exit 1)))
      ; --- Tokenize both with a fresh base ---
      ; (Base make): make-base retired when the constructors homed on the Base class
      ; A scratch base has no reader macros: arm it (once, before the first
      ; read) so a $"..." literal survives as its own text instead of
      ; shattering at its first space -- see (Xon arm-source!).
      (let ((%prims-input (if (str=? %file %prims-path) "" (File read-all %prims-path))))
        (let ((%source-input (File read-all %file)))
          (let ((%doc-base (Base make)))
            (Xon arm-source! %doc-base)
            (let ((%prims-tokens (Xon parse %prims-input %doc-base)))
              (let ((%source-tokens (Xon parse %source-input %doc-base)))
                ; --- Lookup alist from doc-prims tokens, then the walk ---
                (%doc-walk-with-prims %source-tokens
                                      (%doc-build-lookup %prims-tokens)))))))))

  (if (null? (rest %argv))
    (%doc-one (first %argv))
    (List for-each
      (fn (_ %f)
        (do (display "%%DOC-X-PAGE%% ")
            (display %f)
            (newline)
            (%doc-one %f)))
      %argv)))
