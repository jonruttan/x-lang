; str.x -- The string library entry point.
;
; The string API is the protocol CLASSES, not a set of str-* functions:
;
;   Str8     (x/protocol/str/str8)  -- the 8-bit byte protocol
;   StrUTF8  (x/protocol/str/utf8)  -- the UTF-8 code-point protocol
;   Str                            -- the ACTIVE protocol (StrUTF8 by default)
;
; Use (Str append a b), (Str length s), (Str upcase s), (Str split sep s), ...
; and (help Str8 <method>) / (help StrUTF8 <method>) for per-method docs.
; To switch the active protocol for everything that goes through Str, rebind it:
; (def Str Str8) makes the bare string call and Str-based code byte-oriented.
;
; Importing this module makes Str8 / StrUTF8 / Str available. (The classes are
; also preloaded at boot, so they are globally available without an import.)
;
; The deprecated str-* helper functions have been removed; use the byte
; accessors below and the class methods for the full API.

(import x/protocol/str/utf8)   ; provides Str8, StrUTF8, and the Str alias

; --- Byte accessors (the raw 8-bit view) ---
; str-length / str-ref / substring are defined in boot (bound to the str-byte-*
; C primitives) and are ALWAYS byte-level, independent of the active protocol --
; the low-level octet API the readers/tokenizers rely on. str=? is the byte-level
; equality primitive. Documented here for discoverability; for the active-protocol
; element view use the Str methods (e.g. (Str length s), (Str ref i s)) or the
; explicit (Str8 ...) / (StrUTF8 ...).

(doc str-length
  (param s STRING "String to measure")
  (returns INT "Byte length of s")
  (example "(str-length \"$¢€\")" "6")
  "Byte length (raw octets). For element count in the active protocol use (Str length s).")

(doc str-ref
  (param s STRING "String to index")
  (param i INT "Byte offset (negative counts from the end)")
  (returns CHAR "The byte at offset i, as a CHARACTER (0-255)")
  (example "(str-ref \"$¢€\" 1)" "#\\Â")
  "Byte at offset i, UNCHECKED: an out-of-range offset reads out of bounds -- use (Str8 ref i s) for the checked byte view (which rejects negatives instead of wrapping). For the i-th code point use (StrUTF8 ref i s), or the bare (s i) which also takes negative i as from-the-end.")

(doc substring
  (param s STRING "Source string")
  (param start INT "Start byte offset")
  (param end INT "End byte offset (exclusive)")
  (returns STRING "The bytes [start, end) of s")
  (example "(substring \"abcdef\" 1 4)" "\"bcd\"")
  "Byte substring [start, end). Always byte-level.")

(doc str=?
  (param a STRING "First string") (param b STRING "Second string")
  (returns BOOL "#t if a and b are equal")
  (example "(str=? \"ab\" \"ab\")" "#t")
  "String equality (byte-level; the same result as code-point equality).")

(doc (provide x/type/str)
  (note "The string library is the protocol classes Str8 / StrUTF8, with Str naming the active protocol (StrUTF8 by default). Use (Str append a b), (Str length s), etc.; (help Str8 method) for per-method docs.")
  (note "Byte accessors str-length, str-ref, substring, str=? are always byte-level.")
  "String library: the Str8 / StrUTF8 protocol classes and the byte accessors.")
