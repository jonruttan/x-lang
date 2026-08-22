; tools/contract/constraints.x -- per-module platform-parameter constraints.
;
; THE ROW KIND THIS FILE HOLDS.  The evaluator contract has three kinds of row:
; CAPABILITIES (a primitive group is present -- set membership, compared by
; superset), GUARANTEES (a behaviour the engine promises, compared by must-hold),
; and PARAMETERS (values the engine REPORTS: word size, endianness, OS, arch).
; A parameter must never appear in a requires-list: `word-size = 8` as a global
; requirement locks out the 32-bit Pi, which is a supported target.  The core
; language does not care -- tools/contract/obj-layout.x is expressed in WORDS and
; lib/x/boot/data.x probes the width at boot -- so a width requirement would be
; false as well as harmful.
;
; But it is not true that NOTHING cares.  The syscall and FFI layer decodes C
; structs at byte offsets, and those offsets came from 64-bit headers.  Until
; this file those assumptions were prose comments beside the code, invisible to
; every gate.  A row here says: THIS MODULE does not work when THIS PARAMETER
; takes another value.  A 32-bit engine then gets a precise list of the modules
; it cannot load, instead of decoding garbage into a plausible-looking alist.
;
; WHAT THIS RATCHET PROVES, AND WHAT IT DOES NOT.  It diffs the rows below
; against `; constraint:` markers in the source, in BOTH directions: a marker
; with no row fails, a row with no marker fails.  So an assumption cannot be
; added silently and a row cannot outlive its subject -- the same discipline
; tools/check/prim-coverage.sh applies to its exemptions.  It does NOT prove a
; module is correct at some other parameter value; only running there does, and
; that needs a 32-bit engine (the evaluator-contract arc's phase 7).  Undeclared
; assumptions are still found by reading, not by this gate.
;
; PARAMETERS IN USE:
;   word-size   bytes per machine word AND per fixnum -- ext/x-expr/include/x.h
;               asserts sizeof(x_int_t) == sizeof(void *) at compile time, so the
;               two cannot diverge and one key covers both
;   endian      byte order of a widening (ptr ref) read
;
; FORMAT (rigid, one entry per line -- the awk parses the same bytes):
;   (constraint "PATH" param op value)
; op is `=` today; `>=` is reserved for a parameter with an order.

(def %constraints (lit (
  ; --- struct decoding: 64-bit layouts, no width branch -------------------
  ; %stat-decode carries ONE spec per OS and both are 64-bit: Darwin
  ; mode u16@4 / mtime i64@48 / size i64@96 (stat64), Linux mode u32@24 /
  ; size i64@48 / mtime i64@88.  A 32-bit build's struct stat64 packs its
  ; fields at different offsets, so the decode reads neighbouring fields.
  (constraint "lib/x/sys/file.x" word-size = 8)

  ; struct addrinfo's POINTER members move with the word: ai_addr rides @32
  ; (Darwin) / @24 (glibc) and ai_next @40 only on 64-bit; the result cell is
  ; allocated 8 bytes wide to hold one.  ai_family @4 is width-stable, but it
  ; is read as a 4-byte value out of an i32 field, which is the endian half.
  (constraint "lib/x/sys/socket.x" word-size = 8)
  (constraint "lib/x/sys/socket.x" endian = little)

  ; The timeval decode reads tv_sec as an 8-byte value at 0 and tv_usec as a
  ; 4-byte value at 8 -- the 64-bit layout on both OSes.  A 32-bit timeval
  ; puts tv_usec at 4.
  (constraint "lib/x/sys/posix.x" word-size = 8)
  (constraint "lib/x/sys/posix.x" endian = little)

  ; The sign-fold builds its half/span constants as (<< 1 (- (* 8 w) 1)) --
  ; for a 4-byte field that is (<< 1 31), which overflows a 32-bit fixnum, and
  ; the 8-byte case relies on the accumulation wrapping to the two's-complement
  ; value in a 64-bit machine int.  Byte assembly itself is endian-NEUTRAL here
  ; (%le and %be both build the value arithmetically), so only the width binds.
  (constraint "lib/x/codec/struct.x" word-size = 8)

  ; (Ptr ref p off width) is a memcpy of `width` bytes into the low end of a
  ; zeroed machine int -- x_prim_ptr_ref in the engine's src/x-prim/ffi.c.  On a
  ; big-endian host those bytes land in the HIGH end and the value is wrong for
  ; any width below the full word.  The primitive's own doc already says
  ; "little-endian"; this row is that sentence made checkable.  ref-word is
  ; exempt: a full-width copy has no byte-order question.
  (constraint "lib/x/type/ptr.x" endian = little)
)))
