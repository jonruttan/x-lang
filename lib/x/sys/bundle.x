; # x-lang
;
; ## lib/x/sys/bundle.x -- Bundle: the bundles a session can reach, and where each is
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A bundle is a directory holding a bundle.xon and its modules under
; lib/NAME/ (docs/lang-contract.md).  Its name is the first segment of every
; module it holds, so a module's name says which bundle it belongs to.
;
; The directory bundles are installed under is the wrapper's to know: x.sh
; defines %bundle-dir ahead of the library, as it defines %install-root.  An
; official bundle sits directly under it; a third party's sits under its
; author's directory.
;
; Two questions are answered here.  Where a LOADED bundle is, so a bundle can
; reach a file it ships that is not a module: (Bundle root "logo").  And
; which installed bundle holds a module no import root does, so `import` can
; arm it: (Bundle arm! "crypto"), which x/boot/module.x asks on a miss.
;
; lint-known: %bundle-dir

(module x/sys/bundle)

(import x/type/class)
(import x/core/list)
(import x/sys/file)
(import x/codec/xon)

(def-class Bundle ()
  (doc "The bundles a session can reach: (Bundle dir) is where they are installed, (Bundle root NAME) the directory of one that is loaded, (Bundle installed NAME) the installed ones of that name, and (Bundle arm! NAME) makes one's modules importable. A missed import asks arm! for the bundle its first segment names."
    (sample "(Bundle root \"logo\")" "\"/usr/local/share/x/bundles/logo\""))

  (static
    ; The directory a session was told with dir!, in a cell: a program's
    ; own definition does not reach this module.
    (%told (pair () ()))

    (method dir (self)
      (doc "The directory bundles are installed under: the one dir! gave, else the one the wrapper named in %bundle-dir, else nil."
        (returns STRING "A directory, or nil when the session was told none")
        (sample "(Bundle dir)" "\"/usr/local/share/x/bundles\""))
      (if (null? (first (Bundle %told)))
        (guard (_ ()) %bundle-dir)
        (first (Bundle %told))))

    (method dir! (self (param path STRING "The directory bundles are installed under"))
      (doc "Name the directory bundles are installed under, in place of the wrapper's."
        (returns STRING "The directory")
        (sample "(Bundle dir! \"deps/bundles\")" "\"deps/bundles\""))
      (%set-first! (Bundle %told) path)
      path)

    (method %name-of (self (param path STRING "A directory"))
      (doc "The name the bundle.xon in a directory declares; nil where there is none or it does not read."
        (returns STRING "The bundle's name, or nil")
        (sample "(Bundle %name-of \"/usr/local/share/x/bundles/logo\")" "\"logo\""))
      (let ((manifest (%path-join path "bundle.xon")))
        (if (not (File exists? manifest)) ()
          (guard (_ ())
            (let ((row (List find (fn (_ f) (if (pair? f) (eq? (first f) (lit name)) #f))
                         (Xon parse (File read-all manifest)))))
              (if (null? row) () (first (rest row))))))))

    (method %named-in (self (param name STRING "A bundle's name") (param path STRING "A directory of bundles"))
      (doc "The directories directly under path whose bundle.xon declares name."
        (returns LIST "Directories, in the order the directory lists them")
        (sample "(Bundle %named-in \"logo\" \"/usr/local/share/x/bundles\")" "(\"/usr/local/share/x/bundles/logo\")"))
      (List filter (fn (_ d) (let ((n (Bundle %name-of d))) (if (null? n) #f (str=? n name))))
        (List map (fn (_ k) (%path-join path k))
          (List filter (fn (_ k) (not (Str8 starts? "." k)))
            (guard (_ ()) (File list-dir path))))))

    (method installed (self (param name STRING "A bundle's name"))
      (doc "The installed bundles of that name. One directly under (Bundle dir) is an official bundle and is the whole answer; with none there, each author's directory is searched, and every bundle of that name is answered."
        (returns LIST "Directories; empty when no bundle of that name is installed")
        (sample "(Bundle installed \"crypto\")" "(\"/usr/local/share/x/bundles/crypto\")"))
      (let ((d (Bundle dir)))
        (if (null? d) ()
          (let ((own (Bundle %named-in name d)))
            (if (not (null? own)) own
              (List flat-map (fn (_ k) (Bundle %named-in name (%path-join d k)))
                (List filter
                  (fn (_ k) (if (Str8 starts? "." k) #f
                              (not (File exists? (%path-join (%path-join d k) "bundle.xon")))))
                  (guard (_ ()) (File list-dir d)))))))))

    (method root (self (param name STRING "A bundle's name"))
      (doc "The directory of a loaded bundle: the one holding the lib/ that is an import root and holds NAME/. A bundle reaches a file it ships through this. Nil for a bundle that is not loaded."
        (returns STRING "The bundle's directory, or nil")
        (sample "(Bundle root \"logo\")" "\"/usr/local/share/x/bundles/logo\""))
      (let ((r (List find
                 (fn (_ r) (if (Str8 ends? "/lib" r) (File exists? (%path-join r name)) #f))
                 (first %import-roots-cell))))
        (if (null? r) () (Str8 sub 0 (- (Str8 length r) 4) r))))

    (method arm! (self (param name STRING "A bundle's name"))
      (doc "Make an installed bundle's modules importable: its lib/ becomes an import root. One already loaded is left as it is. With several installed bundles of the name and none official, raises a label 'value naming them: which is meant is for a (requires-bundle ...) to say."
        (returns STRING "The bundle's directory, or nil when no bundle of that name is installed")
        (sample "(Bundle arm! \"crypto\")" "\"/usr/local/share/x/bundles/crypto\""))
      (let ((loaded (Bundle root name)))
        (if (not (null? loaded)) loaded
          (let ((found (Bundle installed name)))
            (match
              ((null? found) ())
              ((null? (rest found))
                (do (import-path! (%path-join (first found) "lib"))
                    (first found)))
              (#t (Err raise (lit value)
                    "Bundle: several installed bundles have that name; a (requires-bundle \"AUTHOR/NAME\") says which"
                    found)))))))

    (method arm-module! (self (param module STRING "A module's name, as crypto/aes"))
      (doc "Arm the bundle a module's name says it belongs to: the one named by its first segment. The platform's own modules, x/..., belong to no bundle."
        (returns STRING "The bundle's directory, or nil when there is none to arm")
        (sample "(Bundle arm-module! \"crypto/aes\")" "\"/usr/local/share/x/bundles/crypto\""))
      (let ((i (Str8 index-of "/" module)))
        (if (null? i) ()
          (let ((name (Str8 sub 0 i module)))
            (if (str=? name "x") () (Bundle arm! name))))))))

(provide x/sys/bundle Bundle)
