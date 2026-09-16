; repl/term.x -- Term: the tty, and the only file that knows it is a tty.
;
; Two jobs, both of them facts about a DESCRIPTOR rather than about a line:
; putting the terminal into raw mode and taking it back out, and turning the
; bytes that arrive there into keys.  repl/edit.x holds the buffer those keys
; act on and never touches a descriptor; this file never touches a buffer.
;
; Raw mode is borrowed, not taken.  The terminal belongs to the user's shell
; and has to go back the way it came -- a session that dies with ISIG and
; ECHO still off leaves a shell where ctrl-c does nothing and nothing types
; back, which is the classic way a line editor ruins an afternoon.  So the
; borrow is scoped as narrowly as it can be: repl/line.x enters raw mode to
; read one line and leaves before the form is evaluated, which also means
; that evaluated code -- anything that prints, reads, or spawns a child --
; runs in the cooked terminal it expects, and that ctrl-c during a long
; evaluation is still a signal handled by the boot's SIGINT handler rather
; than a byte nobody is reading.
;
; The escape-sequence timing problem, stated rather than solved.  A bare
; Escape and the start of an arrow key are the same byte, and telling them
; apart means waiting to see whether more bytes follow.  This file does what
; linenoise does and blocks for the rest of the sequence, because the
; alternative -- a timed read -- costs a poll(2) on every keystroke to
; disambiguate a key the REPL has no binding for anyway.  The cost is that a
; lone Escape appears to do nothing until the next key is pressed.
;
; Zero top-level %-globals (new-file budget 0).

(module x/repl/term)
(import x/type/class)
(import x/type/str)
(import x/sys/posix)
(import x/platform/syscall)

(def-class Term ()
  (doc "The terminal a REPL line is read on: raw mode, window size, and byte-to-key decoding. Every method takes the descriptor explicitly -- this class holds no ambient tty."
    (note "raw! returns a saved-state token to hand back to restore!; the pair is meant to bracket one line read, so evaluated code runs in a cooked terminal.")
    (note "key decodes one keystroke from a byte-reading function, so it is testable against a canned byte source with no terminal present.")
    (see raw!) (see restore!) (see key) (see window))

  (static
    ; --- libc, resolved once ------------------------------------------------
    ; Static members, not file globals: the percent-global budget for a new
    ; file is zero and these are this class's business anyway.
    (libc      ()  "The libc handle (dlopen), resolved at class definition")
    (c-tcget   ()  "tcgetattr")
    (c-tcset   ()  "tcsetattr")
    (c-cfraw   ()  "cfmakeraw")

    ; TCSADRAIN: apply the change once pending output has drained, and keep
    ; input that has arrived but not been read.  1 on both Linux and Darwin.
    ;
    ; Not TCSAFLUSH, which is the other obvious choice and discards that
    ; input.  Between two lines the terminal is cooked -- that is the whole
    ; point of borrowing it per line -- so anything typed while a form is
    ; being evaluated is sitting unread when the next raw! runs.  Flushing
    ; there discards type-ahead, which anyone who types faster than the
    ; evaluator will notice immediately and be unable to explain.  Draining
    ; keeps it, and the keys arrive in the next line as though nothing had
    ; happened.
    (tcsadrain 1   "tcsetattr's optional_actions: drain output, keep unread input")

    ; TIOCGWINSZ genuinely differs, because Darwin encodes the direction and
    ; the payload size into the request number and Linux does not.  The OS
    ; predicate comes from the platform layer (tools/check/platform-seam.sh:
    ; USING the triple's verdict is the sanctioned route; parsing it here
    ; would not be).
    (tiocgwinsz () "The TIOCGWINSZ ioctl request for this OS")
    (ioctl-id  () "The ioctl syscall number for this OS, from the platform table")

    (method %resolve! (self)
      (doc "Resolve the libc entry points this class rides. Called at class definition, and again from the image recache hook -- a dlopen handle is a fact of the PROCESS, and a state image carries the heap of whichever process wrote it."
        (returns NIL "Nothing; the handles are installed as a side effect"))
      (let ((dlopen (prim-ref (lit ffi) (lit dlopen)))
            (dlsym  (prim-ref (lit ffi) (lit dlsym))))
        (let ((L (dlopen () 1)))
          (Term libc L)
          (Term c-tcget (dlsym L "tcgetattr"))
          (Term c-tcset (dlsym L "tcsetattr"))
          (Term c-cfraw (dlsym L "cfmakeraw"))))
      (Term tiocgwinsz (if os-darwin? 1074295912 21523))
      ; -1 when this platform's table has no ioctl, which `size` reads as
      ; "ask the environment instead".
      (Term ioctl-id (syscall-id (lit ioctl)))
      ())

    ; --- raw mode -----------------------------------------------------------

    (method tty? (self (param fd INT "Descriptor to test"))
      (doc "Whether fd is a terminal and this build can drive one -- the two questions a caller actually has, answered together, so nothing has to test for a nil libc symbol."
        (returns BOOL "True when fd is a tty and termios resolved"))
      (and (Sys isatty fd)
           (and (not (null? (Term c-tcget))) (not (null? (Term c-cfraw))))))

    (method raw! (self (param fd INT "Descriptor to put into raw mode"))
      (doc "Put fd into raw mode (cfmakeraw: no echo, no line discipline, no signal keys) and return a token holding the previous settings. Returns nil when fd is not a terminal, which is the caller's signal to fall back to line-at-a-time reading."
        (returns ANY "A saved-state token for restore!, or nil")
        (note "cfmakeraw also clears OPOST, so a newline no longer implies a carriage return: everything written while raw must spell \\r\\n itself.")
        (sample "(Term raw! 0)" "a token, or nil when stdin is a pipe"))
      (if (not (Term tty? fd)) ()
        (let ((call (prim-ref (lit ptr) (lit call)))
              (mkstr (prim-ref (lit str) (lit make)))
              (toptr (prim-ref (lit str) (lit ->ptr))))
          ; Two GC-owned regions, deliberately oversized: struct termios is
          ; 72 bytes on Darwin and 60 on Linux, and this file would rather
          ; not know that.  Nothing here reads a FIELD -- cfmakeraw does the
          ; editing -- so the layout stays libc's business.  The saved one is
          ; returned, which is what keeps it alive until restore!.
          (let ((saved (mkstr 128)) (raw (mkstr 128)))
            (let ((sp (toptr saved)) (rp (toptr raw)))
              (if (< (%sys-fold (call (Term c-tcget) fd sp)) 0) ()
                (do
                  ; Fill the second region from the terminal too, rather than
                  ; copying bytes between them: one more cheap syscall buys
                  ; freedom from the struct's size and padding.
                  (call (Term c-tcget) fd rp)
                  (call (Term c-cfraw) rp)
                  (if (< (%sys-fold (call (Term c-tcset) fd (Term tcsadrain) rp)) 0) ()
                    saved))))))))

    (method restore! (self (param fd INT "Descriptor to restore")
                           (param saved ANY "The token raw! returned"))
      (doc "Put fd back the way raw! found it. A nil token is a no-op, so the unwind path can call this unconditionally."
        (returns BOOL "True when the terminal was restored"))
      (if (null? saved) #f
        (let ((call (prim-ref (lit ptr) (lit call)))
              (toptr (prim-ref (lit str) (lit ->ptr))))
          (>= (%sys-fold (call (Term c-tcset) fd (Term tcsadrain) (toptr saved))) 0))))

    ; --- geometry -----------------------------------------------------------
    ; Named `window`, not `size`: `size` is a retired spelling in this tree
    ; (check-doc-vocab holds the line), and two dimensions are not a count.

    (method window (self (param fd INT "Descriptor to measure"))
      (doc "The terminal window's (columns . rows), from TIOCGWINSZ. Falls back to COLUMNS/LINES in the environment and then to 80x24, because a width is needed on every redraw and a wrong one is better than a failed one."
        (returns PAIR "(columns . rows)")
        (note "Reached as a SYSCALL, not through the FFI: ioctl is variadic, and on Apple arm64 a variadic argument goes on the stack where a fixed one goes in a register -- through the fixed-signature ffi door the winsize pointer never reached the kernel and every terminal measured 80x24.")
        (sample "(Term window 0)" "(120 . 40)"))
      (let ((call (prim-ref (lit ptr) (lit call)))
            (mkstr (prim-ref (lit str) (lit make)))
            (toptr (prim-ref (lit str) (lit ->ptr)))
            (pref (prim-ref (lit ptr) (lit ref))))
        ; struct winsize is four unsigned shorts: rows, cols, then two pixel
        ; fields nothing has set meaningfully since the 1980s.
        (let ((w (mkstr 16)))
          (let ((p (toptr w)))
            (let ((r (if (< (Term ioctl-id) 0) -1
                       (%sys-fold (syscall (Term ioctl-id) fd (Term tiocgwinsz) w)))))
              (let ((cols (if (< r 0) 0 (pref p 2 2)))
                    (rows (if (< r 0) 0 (pref p 0 2))))
                (pair (if (> cols 0) cols (Term %env-int "COLUMNS" 80))
                      (if (> rows 0) rows (Term %env-int "LINES" 24)))))))))

    (method %env-int (self (param name STRING "Environment variable")
                           (param dflt INT "Value when unset or unparseable"))
      (doc "An environment variable read as a positive integer, or the default."
        (returns INT "The parsed value, or dflt"))
      (let ((v (Sys getenv name)))
        (if (null? v) dflt
          (guard (_ dflt)
            (let ((n (Str8 ->int v))) (if (and (not (null? n)) (> n 0)) n dflt))))))

    ; --- output --------------------------------------------------------------

    (method emit (self (param fd INT "Descriptor to write to")
                       (param s STRING "Bytes to write"))
      (doc "Write bytes straight to the descriptor, bypassing the printer. A redraw is a burst of escape sequences and must not be interleaved with whatever the evaluator is writing to stdout."
        (returns INT "Bytes written"))
      (Sys fd-write fd s))

    ; --- keys -----------------------------------------------------------------
    ;
    ; `key` returns one of three shapes, and the caller tells them apart with
    ; the ordinary predicates:
    ;
    ;   a STRING  -- literal text to insert (one whole character, UTF-8 included)
    ;   a SYMBOL  -- a named key: 'up 'down 'left 'right 'home 'end 'delete
    ;                'enter 'backspace 'tab 'interrupt 'eof 'clear 'kill-eol
    ;                'kill-bol 'kill-word 'yank 'word-left 'word-right 'escape
    ;                'complete
    ;   nil       -- the descriptor ended (EOF on the read itself)
    ;
    ; read-byte is a function of no arguments returning a byte value or nil.
    ; Passing it in rather than reading fd here is what makes this decodable
    ; from a canned list in a spec, with no terminal anywhere.

    (method key (self (param read-byte CALLABLE "Zero-argument reader returning a byte, or nil at end of input"))
      (doc "Decode one keystroke: a STRING of literal text, a SYMBOL naming a key, or nil at end of input."
        (returns ANY "String, symbol, or nil")
        (note "Control bytes map to readline's names. ESC is followed blockingly, so a lone Escape resolves only when the next key arrives.")
        (sample "(Term key (fn (_) 65))" "\"A\""))
      (let ((b (read-byte)))
        (if (null? b) ()
          (match
            ((= b 27)  (Term %escape read-byte))
            ((= b 1)   (lit home))
            ((= b 2)   (lit left))
            ((= b 3)   (lit interrupt))
            ((= b 4)   (lit eof))
            ((= b 5)   (lit end))
            ((= b 6)   (lit right))
            ((= b 8)   (lit backspace))
            ((= b 9)   (lit complete))
            ((= b 10)  (lit enter))
            ((= b 11)  (lit kill-eol))
            ((= b 12)  (lit clear))
            ((= b 14)  (lit down))
            ((= b 16)  (lit up))
            ((= b 13)  (lit enter))
            ((= b 21)  (lit kill-bol))
            ((= b 23)  (lit kill-word))
            ((= b 25)  (lit yank))
            ((= b 127) (lit backspace))
            ; Any other C0 byte is a chord this REPL does not bind.  Dropping
            ; it is deliberate: inserting it would put an unprintable byte in
            ; the buffer that the redraw cannot measure and the reader cannot
            ; parse.
            ((< b 32)  (lit unbound))
            ((< b 128) (Term %one-byte b))
            ; A leading byte of a UTF-8 sequence: pull the continuation bytes
            ; so that the buffer only ever holds whole characters.
            (#t (Term %utf8 read-byte b))))))

    (method %one-byte (self (param b INT "A byte value 0-255"))
      (doc "A one-byte string holding b." (returns STRING "The byte as text"))
      (bytes->str (list b)))

    (method %utf8 (self (param read-byte CALLABLE "Byte reader")
                        (param lead INT "The leading byte"))
      (doc "Read the continuation bytes of a UTF-8 sequence whose leading byte is `lead`, and return the whole character. A truncated or malformed sequence yields what arrived, which the redraw will render as the terminal sees fit."
        (returns STRING "One character"))
      (let ((need (match ((= 192 (& lead 224)) 1)
                         ((= 224 (& lead 240)) 2)
                         ((= 240 (& lead 248)) 3)
                         (#t 0))))
        (let ((go (fn (self k acc)
                    (if (<= k 0) (bytes->str (List reverse acc))
                      (let ((c (read-byte)))
                        (if (null? c) (bytes->str (List reverse acc))
                          (self (- k 1) (pair c acc))))))))
          (go need (list lead)))))

    (method %escape (self (param read-byte CALLABLE "Byte reader"))
      (doc "Decode the tail of an escape sequence: CSI (ESC [), SS3 (ESC O), or meta-<char>."
        (returns ANY "A key symbol, or 'escape"))
      (let ((b (read-byte)))
        (match
          ((null? b) (lit escape))
          ((= b 91) (Term %csi read-byte))     ; ESC [
          ((= b 79) (Term %ss3 read-byte))     ; ESC O
          ((= b 98) (lit word-left))           ; meta-b
          ((= b 102) (lit word-right))         ; meta-f
          ((= b 127) (lit kill-word))          ; meta-backspace
          (#t (lit escape)))))

    (method %ss3 (self (param read-byte CALLABLE "Byte reader"))
      (doc "Decode an SS3 sequence (ESC O x) -- what a terminal in application-cursor mode sends for the arrows."
        (returns ANY "A key symbol"))
      (let ((b (read-byte)))
        (match
          ((null? b) (lit escape))
          ((= b 65) (lit up))
          ((= b 66) (lit down))
          ((= b 67) (lit right))
          ((= b 68) (lit left))
          ((= b 72) (lit home))
          ((= b 70) (lit end))
          (#t (lit unbound)))))

    (method %csi (self (param read-byte CALLABLE "Byte reader"))
      (doc "Decode a CSI sequence (ESC [ ...): the arrows, Home/End, Delete, and the modified arrows terminals spell ESC [ 1 ; 5 C."
        (returns ANY "A key symbol"))
      ; Parameter bytes (digits and ';') are collected until a final byte in
      ; 0x40-0x7E arrives.  Only the modifier matters here -- ctrl+arrow --
      ; so the parameters are kept as a byte list and inspected at the end
      ; rather than parsed into numbers.
      (let ((go (fn (self params)
                  (let ((b (read-byte)))
                    (match
                      ((null? b) (lit escape))
                      ((and (>= b 48) (<= b 63)) (self (pair b params)))
                      (#t (Term %csi-final b (List reverse params))))))))
        (go ())))

    (method %csi-final (self (param final INT "The sequence's final byte")
                             (param params LIST "The parameter bytes, in order"))
      (doc "Name the key a CSI sequence's final byte and parameters stand for."
        (returns ANY "A key symbol"))
      ; A ctrl-modified arrow carries ";5" among its parameters (";6" is
      ; ctrl-shift, which this treats the same -- the motion is what matters).
      (let ((ctrl? (or (List includes? 53 params) (List includes? 54 params))))
        (match
          ((= final 65) (lit up))
          ((= final 66) (lit down))
          ((= final 67) (if ctrl? (lit word-right) (lit right)))
          ((= final 68) (if ctrl? (lit word-left) (lit left)))
          ((= final 72) (lit home))
          ((= final 70) (lit end))
          ((= final 126)
            ; ESC [ N ~ -- N is the first parameter byte run.
            (match
              ((List includes? 51 params) (lit delete))   ; 3~
              ((List includes? 49 params) (lit home))     ; 1~
              ((List includes? 55 params) (lit home))     ; 7~
              ((List includes? 52 params) (lit end))      ; 4~
              ((List includes? 56 params) (lit end))      ; 8~
              (#t (lit unbound))))
          (#t (lit unbound))))))

  )

; The libc handles and the OS's ioctl number are facts of this process, so
; they are resolved at load and again after a state image is loaded into a
; different one -- the same rule repl/ansi.x follows for whether there is a
; terminal at all.
(Term %resolve!)
(set! %image-recache-hooks (pair (fn (_) (Term %resolve!)) %image-recache-hooks))

(doc (provide x/repl/term Term)
  (note "Raw mode is meant to bracket a single line read: repl/line.x restores the terminal before the form it read is evaluated.")
  (note "key takes a byte-reading function rather than a descriptor, so key decoding is testable with no tty.")
  "Term: raw mode, terminal size, and byte-to-key decoding for the REPL line editor.")
