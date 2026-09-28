; private-reads.x -- the cross-file private-read budget, per reader file:
; (file "PATH" COUNT).  May only shrink (tools/check/private-reads.sh).
;
; COUNT is the number of distinct % names the file reads that some OTHER
; unscoped file defines at its top level and the file does not define
; itself.  Each is a coupling that scoping the owner breaks, and step 4 of
; x-lang#719 is spent replacing them with doors: a class static where the
; owner has a class, a catalog entry where it loads before the object
; system, an export the reader imports where the owner is scoped.  A row
; goes down as its file's reads become doors, and a file absent here reads
; none.
;
; Recorded 2026-09-21 at 0c7f67b0: 127 files, 954 reads.  The largest rows
; are the number tower reading its neighbours (tower, complex, decimal,
; bigint, float, rational), boot/tower-compiled and the compiler's stages,
; which resolve free names in the root by design, and the dev tools
; (image-write, lint), which drive the library's internals directly.
;
; A name that tools/contract/shared-privates.x lists is not counted, and
; neither is a % name of the seam (tools/contract/seam.x): those are read
; across files by decision (2026-09-24 and 2026-09-27, docs/namespaces.md).
; By the count before that the rows came to 673 reads in 121 files.  What
; is counted since is the reads that still want a door: 183, in 40 files.
; A selector in a send, (self %walk ...), stopped counting as a read on
; 2026-09-28, which took seven from that: 176, in 36 files.
; A read of a boot file's name that has no row in that manifest is not
; budgeted here; the gate refuses it.
(file "lib/x/doc/doc-gen.x" 4)
(file "lib/x/num/bigint.x" 1)
(file "lib/x/repl/ansi.x" 10)
(file "lib/x/repl/line.x" 4)
(file "lib/x/repl/loop.x" 1)
(file "lib/x/repl/paint.x" 1)
(file "lib/x/tool/asm-cache.x" 6)
(file "lib/x/tool/asm-compile.x" 6)
(file "lib/x/tool/asm/arm64.x" 4)
(file "lib/x/tool/asm/x86_64.x" 7)
(file "lib/x/tool/pin.x" 1)
(file "lib/x/tool/profile.x" 1)
(file "lib/x/type/assoc.x" 3)
(file "lib/x/type/block.x" 7)
(file "lib/x/type/class.x" 2)
(file "lib/x/type/generic.x" 1)
(file "lib/x/type/iter.x" 2)
(file "lib/x/type/list.x" 2)
(file "lib/x/type/record.x" 1)
(file "lib/x/type/trait.x" 2)
(file "lib/x/type/type.x" 2)
(file "tools/check/doc-forms.x" 1)
(file "tools/check/doctest.x" 4)
(file "tools/check/engine-contract.x" 8)
(file "tools/dev/bench-sha256.x" 7)
(file "tools/dev/cov-report.x" 1)
(file "tools/dev/doc.x" 2)
(file "tools/dev/fmt.x" 2)
(file "tools/dev/highlight.x" 1)
(file "tools/dev/image-foreign.x" 13)
(file "tools/dev/image-inspect.x" 8)
(file "tools/dev/image-name.x" 4)
(file "tools/dev/image-read.x" 1)
(file "tools/dev/image-write.x" 39)
(file "tools/dev/lint.x" 16)
(file "tools/dev/nul-escape.x" 1)
