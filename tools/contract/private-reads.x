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
; The names of the files that stay unscoped were listed the same day, and
; seven readers of %stderr moved to (Stream with-fd 2 ...), with the name
; listed for the three that cannot load the door: 78, in 11 files.
; What is left is the tool scripts reading one another, and a few aliases.
; A read of a boot file's name that has no row in that manifest is not
; budgeted here; the gate refuses it.
; Five reads of a catalog alias that another file happened to bind went to
; the public doors, and a member a class body declares stopped counting:
; 70, in 5 files.
(file "tools/check/engine-contract.x" 6)
(file "tools/dev/image-foreign.x" 13)
(file "tools/dev/image-inspect.x" 8)
(file "tools/dev/image-name.x" 4)
(file "tools/dev/image-write.x" 39)
