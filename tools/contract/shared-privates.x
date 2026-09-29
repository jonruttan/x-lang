; shared-privates.x -- the private names that may be read across files.
;
; A % name is private to the file that defines it.  A scoped module holds its
; own, and nothing outside can read them.  An unscoped file's % names are
; root globals, and tools/check/private-reads.sh budgets every read of one
; from another file (tools/contract/private-reads.x).  The names listed here
; are read across files by decision: the gate does not count a read of one,
; and the list changes only by an edit to this file.
;
; Format (one form per line, closed vocabulary -- an unknown form is an
; error, and nothing follows the closing parenthesis):
;
;   (boot FILE "why")
;       FILE cannot take a module header.  A read of one of its % names
;       from another file is refused unless the name has a row below.
;
;   (shared FILE NAME "what it is")
;       NAME is defined at the top level of FILE, and files in lib/, apps/
;       or tools/ read it.  A row fails the gate once FILE no longer defines
;       the name, or once no other file reads it, until the row is deleted.
;
;   (promised FILE NAME DOC "what it is")
;       NAME belongs to a protocol that DOC describes to the author of a
;       lang, so most of its readers are in other repositories.  FILE has
;       to define it and DOC has to mention it.
;
; The names a lang is promised by contract are in tools/contract/seam.x.  The
; gate reads the % names there as well, and they are not repeated here.
;
; A row is not a promise to a lang.  It says that files in this tree read
; the name, and that a rename has those readers to move.
;
; Decisions, in docs/namespaces.md: the walkers on 2026-09-24; the boot
; names, the seams and the reader protocol on 2026-09-27.

; --- the boot files ---------------------------------------------------------
(boot "lib/x/boot/engine.x" "loads before boot/module.x defines the module form")
(boot "lib/x/boot/registry.x" "loads before boot/module.x defines the module form")
(boot "lib/x/boot/operatives.x" "loads before boot/module.x defines the module form")
(boot "lib/x/boot/data.x" "loads before boot/module.x defines the module form")
(boot "lib/x/boot/reflect.x" "loads before boot/module.x defines the module form")
(boot "lib/x/boot/printer.x" "loads before boot/module.x defines the module form")
(boot "lib/x/boot/string.x" "loads before boot/module.x defines the module form")
(boot "lib/x/boot/module.x" "is the loader, and defines the module form")

; --- boot/engine.x ----------------------------------------------------------
(shared "lib/x/boot/engine.x" %engine-root "the engine's root, as a path")

; --- boot/registry.x: the walk from the base to a cell -----------------------
(shared "lib/x/boot/registry.x" %reflect-base-cell "the object a base path name addresses: how a file reaches an engine cell")
(shared "lib/x/boot/registry.x" %reflect-path "the step list filed under a path name")
(shared "lib/x/boot/registry.x" %reflect-path-parent "a step list without its final step: the node that holds the slot")
(shared "lib/x/boot/registry.x" %reflect-step "walks a step list from an object")
(shared "lib/x/boot/registry.x" %registry-assoc-rest "the value under a key in one level of the catalog")
(shared "lib/x/boot/registry.x" %registry-domain-pair "the entry pair under a key in one level of the catalog")
(shared "lib/x/boot/registry.x" %registry-prims-cell "the cell that holds the catalog")

; --- boot/data.x: raw words, cells and pair slots ----------------------------
(shared "lib/x/boot/data.x" %cell-int "reads the machine integer in an object's first data word")
(shared "lib/x/boot/data.x" %set-cell-int! "writes the machine integer in an object's first data word")
(shared "lib/x/boot/data.x" %data-off-0 "the byte offset of data word 0")
(shared "lib/x/boot/data.x" %data-word-off "the byte offset of data word i")
(shared "lib/x/boot/data.x" %int->ptr "the catalog's int ->ptr, fetched once")
(shared "lib/x/boot/data.x" %obj->ptr "the catalog's obj ->ptr, fetched once")
(shared "lib/x/boot/data.x" %ptr->int "the catalog's ptr ->int, fetched once")
(shared "lib/x/boot/data.x" %ptr-ref-word "the catalog's ptr ref-word, fetched once")
(shared "lib/x/boot/data.x" %ptr-set-word! "the catalog's ptr set-word!, fetched once")
(shared "lib/x/boot/data.x" %obj-set! "writes a data slot of an object")
(shared "lib/x/boot/data.x" %set-first! "replaces a pair's first in place")
(shared "lib/x/boot/data.x" %set-rest! "replaces a pair's rest in place")
(shared "lib/x/boot/data.x" %word-size "the machine word's size in bytes, computed once at boot")

; --- boot/reflect.x: type words, and what a state image has to remake --------
(shared "lib/x/boot/reflect.x" %image-recache! "runs the recache hooks once a state image has loaded")
(shared "lib/x/boot/reflect.x" %image-recache-hooks "the thunks that recompute cached addresses after a state image loads; a module adds its own")
(shared "lib/x/boot/reflect.x" %image-transients "the names and thunks a state image leaves out; a module adds its own")
(shared "lib/x/boot/reflect.x" %ptr->obj "the catalog's ptr ->obj, fetched once")
(shared "lib/x/boot/reflect.x" %reflect-satom-tw "the type word a type handle carries")
(shared "lib/x/boot/reflect.x" %reflect-spair-tw "the type word a registered type carries")
(shared "lib/x/boot/reflect.x" %reflect-sym->str "the catalog's sym ->str, fetched once")
(shared "lib/x/boot/reflect.x" %reflect-type-alist-cell "the cell that holds the registered types")
(shared "lib/x/boot/reflect.x" %reflect-type-name "the name of a value's type, as a string")
(shared "lib/x/boot/reflect.x" %reflect-type-name-atom "the name atom of a type")
(shared "lib/x/boot/reflect.x" %reflect-type-word "an object's type slot, as an integer")

; --- boot/string.x: the byte-level string layer ------------------------------
(shared "lib/x/boot/string.x" %char->integer "the catalog's char ->int, fetched once")
(shared "lib/x/boot/string.x" %sc-int+ "the catalog's int +, fetched once")
(shared "lib/x/boot/string.x" %str-append "the catalog's str append, fetched once")
(shared "lib/x/boot/string.x" %str-byte-len "the catalog's str byte-len, fetched once")
(shared "lib/x/boot/string.x" %str-byte-ref "the catalog's str byte-ref, fetched once")
(shared "lib/x/boot/string.x" %str-byte-sub "the catalog's str byte-sub, fetched once")
(shared "lib/x/boot/string.x" %str-length "a string's length in bytes")
(shared "lib/x/boot/string.x" %str-ref "the byte at an index")
(shared "lib/x/boot/string.x" %substring "the bytes from a start index to an end index")
(shared "lib/x/boot/string.x" %str-concat "joins a list of strings in one pass")
(shared "lib/x/boot/string.x" %number->str "an integer to its digits, base 10 or a given radix")
(shared "lib/x/boot/string.x" %str->number "digits to an integer, or nil")

; --- boot/module.x: the registries, the resolver and the path helpers --------
(shared "lib/x/boot/module.x" %include-dir-cell "the cell that holds the directory of the file being included")
(shared "lib/x/boot/module.x" %include-list-cell "the cell that holds the list of included files")
(shared "lib/x/boot/module.x" %module-registry-cell "the cell that holds the module registry")
(shared "lib/x/boot/module.x" %doc-registry-cell "the cell that holds the documentation registry")
(shared "lib/x/boot/module.x" %module-loaded-cell "the cell that holds the names of the loaded modules")
(shared "lib/x/boot/module.x" %import-roots-cell "the cell that holds the import roots")
(shared "lib/x/boot/module.x" %module-resolve "a module name to the path of its file")
(shared "lib/x/boot/module.x" %module-resolve-file "a relative file name to its path under the import roots")
(shared "lib/x/boot/module.x" %module-parse-spec "a version spec string to its parsed form")
(shared "lib/x/boot/module.x" %module-resolve-version "a name and a parsed spec to a version and a path")
(shared "lib/x/boot/module.x" %module-scan-dir "the versioned candidates for a name in a directory")
(shared "lib/x/boot/module.x" %path-dir "a path's directory, byte for byte")
(shared "lib/x/boot/module.x" %path-join "a directory and a relative part joined, not normalised")
(shared "lib/x/boot/module.x" %rewrite "overwrites a pair's first and rest")
(shared "lib/x/boot/module.x" %expanded "marks a form whose expansion is cached in place")

; --- core/list.x: the walkers the List class stands on -----------------------
; The two walker files are not boot files: a read of one of their other %
; names is counted against its reader's row, as any private read is.
(shared "lib/x/core/list.x" %fold "folds a function over a list; the class door is (List fold)")
(shared "lib/x/core/list.x" %map "maps a function over lists; the class door is (List map)")
(shared "lib/x/core/list.x" %map1 "maps a function over one list")
(shared "lib/x/core/list.x" %for-each "calls a function on each element; the class door is (List for-each)")
(shared "lib/x/core/list.x" %filter "the elements a predicate accepts; the class door is (List filter)")
(shared "lib/x/core/list.x" %find "the first element a predicate accepts; the class door is (List find)")
(shared "lib/x/core/list.x" %length "a list's length; the class door is (List length)")
(shared "lib/x/core/list.x" %reverse "a list reversed; the class door is (List reverse)")
(shared "lib/x/core/list.x" %rev-onto "a list reversed onto another")
(shared "lib/x/core/list.x" %append "lists appended; the class door is (List append)")
(shared "lib/x/core/list.x" %append2 "two lists appended")
(shared "lib/x/core/list.x" %memq? "whether a list holds a value, by eq?; the class door is (List includes?)")
(shared "lib/x/core/list.x" %member-str? "whether a list holds a string, by str=?")

; --- core/alist.x: the walkers the Assoc class stands on ---------------------
(shared "lib/x/core/alist.x" %assoc-get "the value under a key, or nil; the class door is (Assoc get)")
(shared "lib/x/core/alist.x" %assoc-has? "whether a key is present; the class door is (Assoc has?)")
(shared "lib/x/core/alist.x" %assoc-keys "the keys; the class door is (Assoc keys)")
(shared "lib/x/core/alist.x" %assq "the entry under a key, by eq?, or nil; the class door is (Assoc entry)")
(shared "lib/x/core/alist.x" %assoc-str "the entry under a string key, by str=?, or nil")

; --- reader/intrinsics.x: the analyse protocol -------------------------------
(promised "lib/x/reader/intrinsics.x" %score-set "docs/crafting-a-lang.md" "accepts a token, the current character included")
(promised "lib/x/reader/intrinsics.x" %buffer-unread "docs/crafting-a-lang.md" "gives the current character back before an accept")
(promised "lib/x/reader/intrinsics.x" %score-label! "docs/crafting-a-lang.md" "declares which variant the accepting state saw")
(promised "lib/x/reader/intrinsics.x" %read-label "docs/crafting-a-lang.md" "the label, as the type's reader recovers it")
