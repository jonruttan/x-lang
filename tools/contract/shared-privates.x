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
; names, the seams and the reader protocol on 2026-09-27; the names of the
; files that stay unscoped on 2026-09-28.

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
(shared "lib/x/boot/registry.x" %registry-assoc-rest "the value under a key in one level of the catalogue")
(shared "lib/x/boot/registry.x" %registry-domain-pair "the entry pair under a key in one level of the catalogue")
(shared "lib/x/boot/registry.x" %registry-prims-cell "the cell that holds the catalogue")

; --- boot/data.x: raw words, cells and pair slots ----------------------------
(shared "lib/x/boot/data.x" %cell-int "reads the machine integer in an object's first data word")
(shared "lib/x/boot/data.x" %set-cell-int! "writes the machine integer in an object's first data word")
(shared "lib/x/boot/data.x" %data-off-0 "the byte offset of data word 0")
(shared "lib/x/boot/data.x" %data-word-off "the byte offset of data word i")
(shared "lib/x/boot/data.x" %int->ptr "the catalogue's int ->ptr, fetched once")
(shared "lib/x/boot/data.x" %obj->ptr "the catalogue's obj ->ptr, fetched once")
(shared "lib/x/boot/data.x" %ptr->int "the catalogue's ptr ->int, fetched once")
(shared "lib/x/boot/data.x" %ptr-ref-word "the catalogue's ptr ref-word, fetched once")
(shared "lib/x/boot/data.x" %ptr-set-word! "the catalogue's ptr set-word!, fetched once")
(shared "lib/x/boot/data.x" %obj-set! "writes a data slot of an object")
(shared "lib/x/boot/data.x" %set-first! "replaces a pair's first in place")
(shared "lib/x/boot/data.x" %set-rest! "replaces a pair's rest in place")
(shared "lib/x/boot/data.x" %word-size "the machine word's size in bytes, computed once at boot")

; --- boot/reflect.x: type words, and what a state image has to remake --------
(shared "lib/x/boot/reflect.x" %image-recache! "runs the recache hooks once a state image has loaded")
(shared "lib/x/boot/reflect.x" %image-recache-hooks "the thunks that recompute cached addresses after a state image loads; a module adds its own")
(shared "lib/x/boot/reflect.x" %image-transients "the names and thunks a state image leaves out; a module adds its own")
(shared "lib/x/boot/reflect.x" %ptr->obj "the catalogue's ptr ->obj, fetched once")
(shared "lib/x/boot/reflect.x" %reflect-satom-tw "the type word a type handle carries")
(shared "lib/x/boot/reflect.x" %reflect-spair-tw "the type word a registered type carries")
(shared "lib/x/boot/reflect.x" %reflect-sym->str "the catalogue's sym ->str, fetched once")
(shared "lib/x/boot/reflect.x" %reflect-type-alist-cell "the cell that holds the registered types")
(shared "lib/x/boot/reflect.x" %reflect-type-name "the name of a value's type, as a string")
(shared "lib/x/boot/reflect.x" %reflect-type-name-atom "the name atom of a type")
(shared "lib/x/boot/reflect.x" %reflect-type-word "an object's type slot, as an integer")

; --- boot/string.x: the byte-level string layer ------------------------------
(shared "lib/x/boot/string.x" %char->integer "the catalogue's char ->int, fetched once")
(shared "lib/x/boot/string.x" %sc-int+ "the catalogue's int +, fetched once")
(shared "lib/x/boot/string.x" %str-append "the catalogue's str append, fetched once")
(shared "lib/x/boot/string.x" %str-byte-len "the catalogue's str byte-len, fetched once")
(shared "lib/x/boot/string.x" %str-byte-ref "the catalogue's str byte-ref, fetched once")
(shared "lib/x/boot/string.x" %str-byte-sub "the catalogue's str byte-sub, fetched once")
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

; --- the files that stay unscoped by decision or by measurement ---------------
; These keep their names in the root (docs/namespaces.md), so a door in front
; of one would hide nothing and cost a dispatch.  The rows are the names
; other files read today.  The files are not boot files: a read of another
; of their % names is counted against its reader.  Decision of 2026-09-28.

; --- core/list.x and core/alist.x: read by the class that is their door -------
(shared "lib/x/core/list.x" %for-each1 "calls a function on each element of one list; read by the List class")
(shared "lib/x/core/list.x" %any-null? "whether any of several lists is empty; read by the List class")
(shared "lib/x/core/alist.x" %assoc-put "an association list with a key set; the class door is (Assoc put)")
(shared "lib/x/core/alist.x" %assoc-del "an association list without a key; the class door is (Assoc del)")
(shared "lib/x/core/alist.x" %opt-get-or-else "the lookup a let-opts expansion names; the class door is (Assoc opt-get-or-else)")
(shared "lib/x/core/alist.x" %opt-cell "an option's value in a box, or nil when absent; read by the class system")

; --- type/class.x: the dispatcher's parts, read by the types built on it ------
(shared "lib/x/type/class.x" %class-hot "a class's method tables, as the dispatcher holds them")
(shared "lib/x/type/class.x" %tab-find! "finds a selector's entry in a method table")
(shared "lib/x/type/class.x" %entry-method "the callable method of a table entry, or nil")
(shared "lib/x/type/class.x" %selector "a quoted selector as the bare symbol")
(shared "lib/x/type/class.x" %find-form "the tail of the form with a given head in a class body")
(shared "lib/x/type/class.x" %obj-fields "an instance's fields")
(shared "lib/x/type/class.x" %object "the OBJECT type")

; --- doc/doc.x: the registry's parts, and the colour stubs ansi.x sets --------
(shared "lib/x/doc/doc.x" %doc-commit! "files the documentation that is pending")
(shared "lib/x/doc/doc.x" %doc-lookup "the entry documented under a name")
(shared "lib/x/doc/doc.x" %doc-pending-cell "the cell that holds documentation not yet filed")
(shared "lib/x/doc/doc.x" %doc-find-last-string "the last string in a list")
(shared "lib/x/doc/doc.x" %doc-entry-name "an entry's name")
(shared "lib/x/doc/doc.x" %doc-entry-params "an entry's parameters")
(shared "lib/x/doc/doc.x" %doc-entry-examples "an entry's examples")
(shared "lib/x/doc/doc.x" %doc-entry-notes "an entry's notes")
(shared "lib/x/doc/doc.x" %doc-entry-samples "an entry's samples")
(shared "lib/x/doc/doc.x" %highlight-code "prints code; display until repl/ansi.x sets it")
(shared "lib/x/doc/doc.x" %c-reset "a colour code, empty until repl/ansi.x sets it")
(shared "lib/x/doc/doc.x" %c-bold "a colour code, empty until repl/ansi.x sets it")
(shared "lib/x/doc/doc.x" %c-dim "a colour code, empty until repl/ansi.x sets it")
(shared "lib/x/doc/doc.x" %c-name "a colour code, empty until repl/ansi.x sets it")
(shared "lib/x/doc/doc.x" %c-type "a colour code, empty until repl/ansi.x sets it")
(shared "lib/x/doc/doc.x" %c-param "a colour code, empty until repl/ansi.x sets it")
(shared "lib/x/doc/doc.x" %c-example "a colour code, empty until repl/ansi.x sets it")
(shared "lib/x/doc/doc.x" %c-error "a colour code, empty until repl/ansi.x sets it")
(shared "lib/x/doc/doc.x" %c-module "a colour code, empty until repl/ansi.x sets it")

; --- tool/asm-code.x: the buffers, the relocator, and the slots the JIT fills ---
(shared "lib/x/tool/asm-code.x" %arch "the architecture's table and encoder; the backend sets it at load")
(shared "lib/x/tool/asm-code.x" %asm-reloc "the host's relocator; the backend lists it in its table")
(shared "lib/x/tool/asm-code.x" %asm-arm64? "whether the host is A64, which picks the backend")
(shared "lib/x/tool/asm-code.x" %ptr-set! "the catalogue's ptr set!, fetched once")
(shared "lib/x/tool/asm-code.x" %asm-compiler "the compiler, once asm-compile.x has loaded and filed it")
(shared "lib/x/tool/asm-code.x" %asm-emit "the emitter, once asm.x has loaded and filed it")
(shared "lib/x/tool/asm-code.x" %jit-missing "the runtime helpers the compiler could not resolve")
(shared "lib/x/tool/asm-code.x" %asm-last-relocs "the relocations of the function produced last")
(shared "lib/x/tool/asm-code.x" %asm-last-size "the size of the function produced last")
(shared "lib/x/tool/asm-code.x" %asm-last-buf "the code buffer of the function produced last")
(shared "lib/x/tool/asm-code.x" %obj-ref "the catalogue's obj ref, fetched once")

; --- tool/asm.x: what a backend emits through ---------------------------------
(shared "lib/x/tool/asm.x" %op-type "an operand's type")
(shared "lib/x/tool/asm.x" %op-value "an operand's value")
(shared "lib/x/tool/asm.x" %emit-u8! "emits one byte")
(shared "lib/x/tool/asm.x" %emit-bytes! "emits a list of bytes")
(shared "lib/x/tool/asm.x" %emit-u32-le! "emits a 32-bit word, low byte first")
(shared "lib/x/tool/asm.x" %emit-u64-le! "emits a 64-bit word, low byte first")

; --- tool/lint.x: the hooks and analysers its driver sets and routes to -------
(shared "lib/x/tool/lint.x" %lint-binds? "a hook: whether a form binds a name; the driver sets it")
(shared "lib/x/tool/lint.x" %lint-dispatch "a hook: the analysis of one list form; the driver sets it")
(shared "lib/x/tool/lint.x" %lint-head-cell "the head of the form in hand, as a string")
(shared "lib/x/tool/lint.x" %lint-string-type "the string type's handle")
(shared "lib/x/tool/lint.x" %lint-def "the analyser of a definition")
(shared "lib/x/tool/lint.x" %lint-set "the analyser of an assignment")
(shared "lib/x/tool/lint.x" %lint-fn "the analyser of a function")
(shared "lib/x/tool/lint.x" %lint-op "the analyser of an operative")
(shared "lib/x/tool/lint.x" %lint-let "the analyser of a let")
(shared "lib/x/tool/lint.x" %lint-guard "the analyser of a guard")
(shared "lib/x/tool/lint.x" %lint-quasi "the analyser of a quasiquoted form")
(shared "lib/x/tool/lint.x" %lint-first-rest "the analyser of first and rest")
(shared "lib/x/tool/lint.x" %lint-match "the analyser of a match")
(shared "lib/x/tool/lint.x" %lint-method-ref "the analyser of a method-ref")
(shared "lib/x/tool/lint.x" %lint-call "the analyser of a call")

; --- codec/sha256.x: what the benchmark and the pin tool read ----------------
(shared "lib/x/codec/sha256.x" %sha-jit-threshold "the input size from which a digest builds the compiled engine")
(shared "lib/x/codec/sha256.x" %sha-k "the round constants")
(shared "lib/x/codec/sha256.x" %sha-ih "the initial hash values")
(shared "lib/x/codec/sha256.x" %sha-word "one message word, read from the input")
(shared "lib/x/codec/sha256.x" %sha-oref "the catalogue's obj ref, fetched once")
(shared "lib/x/codec/sha256.x" %sha+ "the catalogue's int +, fetched once")

; --- repl/loop.x: beside the seam, what the line editor reads ----------------
(shared "lib/x/repl/loop.x" %error-loc-prefix "the file and line an error message opens with")
(shared "lib/x/repl/loop.x" %repl-platform-repl "the platform's own repl, to tell it from one a lang installed")

; --- reader/intrinsics.x: beside the analyse protocol -------------------------
(shared "lib/x/reader/intrinsics.x" %buffer-len "the length of what the tokenizer buffer has taken in")
(shared "lib/x/reader/intrinsics.x" %stderr "displays to the error stream; the door is (Stream with-fd 2 thunk), for a reader that can load x/sys/stream")

; --- type/unit-label-rows.x: data, which the img dialect includes on a bare base ---
(shared "lib/x/type/unit-label-rows.x" %type-unit-labels "the engine's codes for a unit's label")
(shared "lib/x/type/unit-label-rows.x" %type-unit-label-rows "each engine type's units, as rows")
