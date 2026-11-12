; str.x -- The string library entry point.
;
; The string API is the protocol CLASSES, not a set of str-* functions:
;
;   Str8     (x/protocol/str/str8)  -- the 8-bit byte protocol
;   StrUtf8  (x/protocol/str/utf8)  -- the UTF-8 code-point protocol
;   Str                            -- the ACTIVE protocol (StrUtf8 by default)
;
; Use (Str append a b), (Str length s), (Str upcase s), (Str split sep s), ...
; and (help Str8 <method>) / (help StrUtf8 <method>) for per-method docs.
; To switch the active protocol for everything that goes through Str, rebind it:
; (def Str Str8) makes the bare string call and Str-based code byte-oriented.
;
; Importing this module makes Str8 / StrUtf8 / Str available. (The classes are
; also preloaded at boot, so they are globally available without an import.)
;
; The str-* helper functions are gone from the top level: the byte view is
; the Str8 class, and the class methods are the full API.

(import x/protocol/str/utf8)   ; provides Str8, StrUtf8, and the Str alias

; --- Byte equality ---
; str=? is the byte-level equality primitive.  The byte accessors str-length,
; str-ref and substring are %-private in boot/string.x (#108); the byte view
; is (Str8 length s), (Str8 ref i s) and (Str8 sub start count s), and the
; active-protocol view is (Str length s), (Str ref i s).

(doc str=?
  (param a STRING "First string") (param b STRING "Second string")
  (returns BOOL "#t if a and b are equal")
  (example "(str=? \"ab\" \"ab\")" "#t")
  "String equality (byte-level; the same result as code-point equality).")

(doc (provide x/type/str)
  (note "The string library is the protocol classes Str8 / StrUtf8, with Str naming the active protocol (StrUtf8 by default). Use (Str append a b), (Str length s), etc.; (help Str8 method) for per-method docs.")
  (note "str=? is always byte-level; the byte view of a string is the Str8 class.")
  (example "(list (Str length \"héllo\") (Str8 length \"héllo\"))" "(5 6)")
  "String library: the Str8 / StrUtf8 protocol classes and byte equality.")
