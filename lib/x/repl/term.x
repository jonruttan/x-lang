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
(import x/core/doors mem-set)

(def-class Term ()
  (doc "The terminal a REPL line is read on: raw mode, window size, and byte-to-key decoding. Every method takes the descriptor explicitly -- this class holds no ambient tty."
    (note "raw! returns a saved-state token to hand back to restore!; the pair is meant to bracket one line read, so evaluated code runs in a cooked terminal.")
    (note "key decodes one keystroke from a byte-reading function, so it is testable against a canned byte source with no terminal present.")
    (example "(Term key (fn (_) 9))" "'complete")
    (see raw!) (see raw-with-signals!) (see restore!) (see key) (see window) (see measure) (see window!) (see modes))

  (static
    ; --- libc, resolved once ------------------------------------------------
    ; Static fields, not file globals: the percent-global budget for a new
    ; file is zero and these are this class's business anyway.
    (libc      ()  "The libc handle (dlopen), resolved at class definition")
    (c-tcget   ()  "tcgetattr")
    (c-tcset   ()  "tcsetattr")
    (c-cfraw   ()  "cfmakeraw")
    (c-igetsp  ()  "cfgetispeed")
    (c-ogetsp  ()  "cfgetospeed")
    (c-isetsp  ()  "cfsetispeed")
    (c-osetsp  ()  "cfsetospeed")
    (mode-rows ()  "The named modes this OS has, as (NAME WHERE VALUE): WHERE a flag word 0-3 and VALUE its bits, 'cc and VALUE the character's index, 'field and VALUE (WORD MASK SETTING), or 'byte and VALUE the byte's offset")

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
    (tiocswinsz () "The TIOCSWINSZ ioctl request for this OS")
    (ioctl-id  () "The ioctl syscall number for this OS, from the platform table")

    (method %resolve! (self)
      (doc "Resolve the libc entry points this class rides. Called at class definition, and again from the image recache hook -- a dlopen handle is a fact of the PROCESS, and a state image carries the heap of whichever process wrote it."
        (returns NIL "Nothing; the handles are installed as a side effect")
        (sample "(Term %resolve!)" "re-reads the libc handles and the ioctl number for this process"))
      (let ((dlopen (prim-ref (lit ffi) (lit dlopen)))
            (dlsym  (prim-ref (lit ffi) (lit dlsym))))
        (let ((L (dlopen () 1)))
          (Term libc L)
          (Term c-tcget (dlsym L "tcgetattr"))
          (Term c-tcset (dlsym L "tcsetattr"))
          (Term c-cfraw (dlsym L "cfmakeraw"))
          (Term c-igetsp (dlsym L "cfgetispeed"))
          (Term c-ogetsp (dlsym L "cfgetospeed"))
          (Term c-isetsp (dlsym L "cfsetispeed"))
          (Term c-osetsp (dlsym L "cfsetospeed"))))
      (Term mode-rows (Term %mode-rows))
      (Term tiocgwinsz (if os-darwin? 0x40087468 0x5413))
      (Term tiocswinsz (if os-darwin? 0x80087467 0x5414))
      ; -1 when this platform's table has no ioctl, which `size` reads as
      ; "ask the environment instead".
      (Term ioctl-id (syscall-id (lit ioctl)))
      ())

    ; --- raw mode -----------------------------------------------------------

    (method tty? (self (param fd INTEGER "Descriptor to test"))
      (doc "Whether fd is a terminal and this build can drive one -- the two questions a caller actually has, answered together, so nothing has to test for a nil libc symbol."
        (returns BOOL "True when fd is a tty and termios resolved")
        (example "(Term tty? -1)" "#f"))
      (and (Sys isatty fd)
           (and (not (null? (Term c-tcget))) (not (null? (Term c-cfraw))))))

    (method raw! (self (param fd INTEGER "Descriptor to put into raw mode"))
      (doc "Put fd into raw mode (cfmakeraw: no echo, no line discipline, no signal keys) and return a token holding the previous settings. Returns nil when fd is not a terminal, which is the caller's signal to fall back to line-at-a-time reading."
        (returns ANY "A saved-state token for restore!, or nil")
        (note "cfmakeraw also clears OPOST, so a newline no longer implies a carriage return: everything written while raw must spell \\r\\n itself.")
        (sample "(Term raw! 0)" "a token, or nil when stdin is a pipe"))
      (Term %raw! fd #f))

    (method raw-with-signals! (self (param fd INTEGER "Descriptor to put into raw mode"))
      (doc "Raw mode as raw! makes it, but with the terminal's signal keys still signalling: ^C sends SIGINT, ^Z SIGTSTP and ^\\ SIGQUIT, as an editor that catches them wants. Returns raw!'s token, or nil."
        (returns ANY "A saved-state token for restore!, or nil")
        (sample "(Term raw-with-signals! 0)" "a token, or nil when stdin is a pipe"))
      (Term %raw! fd #t))

    ; ISIG in c_lflag, the fourth tcflag_t: 8 bytes wide on Darwin and 4 on
    ; Linux, so it sits at byte 24 or byte 12.  Its low four bytes are read and
    ; written either way; both are little-endian here.
    (method %isig-on! (self (param p POINTER "A struct termios"))
      (doc "Turn ISIG on in the termios at p." (returns NIL "Nothing")
        (sample "(Term %isig-on! p)" "the termios at p has ISIG set; the terminal is unchanged until it is applied"))
      (let ((pref (prim-ref (lit ptr) (lit ref)))
            (pset (prim-ref (lit ptr) (lit set!)))
            (at (if os-darwin? 24 12))
            (isig (if os-darwin? 128 1)))
        (pset p at (| (pref p at 4) isig) 4)
        ()))

    (method %raw! (self (param fd INTEGER "Descriptor to put into raw mode")
                        (param signals? BOOL "Whether the signal keys still signal"))
      (doc "raw! and raw-with-signals!: the terminal's settings saved, then made raw."
        (returns ANY "A saved-state token for restore!, or nil")
        (sample "(Term %raw! 0 #t)" "a token, or nil when stdin is a pipe"))
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
              (if (< (Sys %sign-fold (call (Term c-tcget) fd sp)) 0) ()
                (do
                  ; Fill the second region from the terminal too, rather than
                  ; copying bytes between them: one more cheap syscall buys
                  ; freedom from the struct's size and padding.
                  (call (Term c-tcget) fd rp)
                  (call (Term c-cfraw) rp)
                  (if signals? (Term %isig-on! rp) ())
                  (if (< (Sys %sign-fold (call (Term c-tcset) fd (Term tcsadrain) rp)) 0) ()
                    saved))))))))

    (method restore! (self (param fd INTEGER "Descriptor to restore")
                           (param saved ANY "The token raw! returned"))
      (doc "Put fd back the way raw! found it. A nil token is a no-op, so the unwind path can call this unconditionally."
        (returns BOOL "True when the terminal was restored")
        (example "(Term restore! 0 ())" "#f"))
      (if (null? saved) #f
        (let ((call (prim-ref (lit ptr) (lit call)))
              (toptr (prim-ref (lit str) (lit ->ptr))))
          (>= (Sys %sign-fold (call (Term c-tcset) fd (Term tcsadrain) (toptr saved))) 0))))

    ; --- modes ----------------------------------------------------------------
    ;
    ; The one place this file knows struct termios's layout, because a mode
    ; by name is a field: the four flag words are tcflag_t, 8 bytes on Darwin
    ; and 4 on Linux, and c_cc follows them, after Linux's one-byte c_line.
    ; Only a flag word's low four bytes are read and written; every bit named
    ; here sits in them, and both OSes are little-endian here.  The speeds go
    ; through cfgetispeed and its kin, which answer a baud on Darwin and a
    ; B-code on Linux.  The names are the modes busybox's stty names, which
    ; include every one RFC 4254 gives a pseudo-terminal request, that this
    ; OS has; the values are the OS's own headers' (Darwin's sys/termios.h,
    ; Linux's asm-generic/termbits.h).  A field is a setting of several bits
    ; under one mask: the character size, and the output delays.

    (method %mode-rows (self)
      (doc "This OS's named modes, as (NAME WHERE VALUE): WHERE a flag word, 0 c_iflag to 3 c_lflag, and VALUE its bits; 'cc and VALUE the character's index in c_cc; 'field and VALUE (WORD MASK SETTING), the setting the name stands for; or 'byte and VALUE the offset of a byte that is a count, never turned off: vmin, vtime, and Linux's c_line."
        (returns LIST "The rows, a field's settings in ascending order")
        (example "(List find (fn (_ r) (eq? (first r) 'echo)) (Term %mode-rows))" "('echo 3 8)")
        (sample "(List find (fn (_ r) (eq? (first r) 'cs8)) (Term %mode-rows))" "('cs8 'field (2 768 768)) on Darwin, ('cs8 'field (2 48 48)) on Linux"))
      (let ((cc (fn (_ name i) (list name (lit cc) i)))
            (flag (fn (_ name word bits) (list name word bits)))
            (byte (fn (_ name at) (list name (lit byte) at)))
            (field (fn (_ name word mask v) (list name (lit field) (list word mask v)))))
        (if os-darwin?
          (list (cc (lit vintr) 8) (cc (lit vquit) 9) (cc (lit verase) 3) (cc (lit vkill) 5)
                (cc (lit veof) 0) (cc (lit veol) 1) (cc (lit veol2) 2) (cc (lit vstart) 12)
                (cc (lit vstop) 13) (cc (lit vsusp) 10) (cc (lit vdsusp) 11) (cc (lit vreprint) 6)
                (cc (lit vwerase) 4) (cc (lit vlnext) 14) (cc (lit vdiscard) 15) (cc (lit vstatus) 18)
                (byte (lit vmin) (Term %cc-at 16)) (byte (lit vtime) (Term %cc-at 17))
                (flag (lit ignbrk) 0 0x1) (flag (lit brkint) 0 0x2) (flag (lit ignpar) 0 0x4)
                (flag (lit parmrk) 0 0x8) (flag (lit inpck) 0 0x10) (flag (lit istrip) 0 0x20)
                (flag (lit inlcr) 0 0x40) (flag (lit igncr) 0 0x80) (flag (lit icrnl) 0 0x100)
                (flag (lit ixon) 0 0x200) (flag (lit ixoff) 0 0x400) (flag (lit ixany) 0 0x800)
                (flag (lit imaxbel) 0 0x2000) (flag (lit iutf8) 0 0x4000)
                (flag (lit opost) 1 0x1) (flag (lit onlcr) 1 0x2) (flag (lit ocrnl) 1 0x10)
                (flag (lit onocr) 1 0x20) (flag (lit onlret) 1 0x40) (flag (lit ofill) 1 0x80)
                (flag (lit ofdel) 1 0x20000)
                (field (lit nl0) 1 0x300 0x0) (field (lit nl1) 1 0x300 0x100)
                (field (lit tab0) 1 0xC04 0x0) (field (lit tab1) 1 0xC04 0x400)
                (field (lit tab2) 1 0xC04 0x800) (field (lit tab3) 1 0xC04 0x4)
                (field (lit cr0) 1 0x3000 0x0) (field (lit cr1) 1 0x3000 0x1000)
                (field (lit cr2) 1 0x3000 0x2000) (field (lit cr3) 1 0x3000 0x3000)
                (field (lit ff0) 1 0x4000 0x0) (field (lit ff1) 1 0x4000 0x4000)
                (field (lit bs0) 1 0x8000 0x0) (field (lit bs1) 1 0x8000 0x8000)
                (field (lit vt0) 1 0x10000 0x0) (field (lit vt1) 1 0x10000 0x10000)
                (field (lit cs5) 2 0x300 0x0) (field (lit cs6) 2 0x300 0x100)
                (field (lit cs7) 2 0x300 0x200) (field (lit cs8) 2 0x300 0x300)
                (flag (lit cstopb) 2 0x400) (flag (lit cread) 2 0x800) (flag (lit parenb) 2 0x1000)
                (flag (lit parodd) 2 0x2000) (flag (lit hupcl) 2 0x4000) (flag (lit clocal) 2 0x8000)
                (flag (lit crtscts) 2 0x30000)
                (flag (lit echoke) 3 0x1) (flag (lit echoe) 3 0x2) (flag (lit echok) 3 0x4)
                (flag (lit echo) 3 0x8) (flag (lit echonl) 3 0x10) (flag (lit echoprt) 3 0x20)
                (flag (lit echoctl) 3 0x40) (flag (lit isig) 3 0x80) (flag (lit icanon) 3 0x100)
                (flag (lit iexten) 3 0x400) (flag (lit extproc) 3 0x800) (flag (lit tostop) 3 0x400000)
                (flag (lit flusho) 3 0x800000) (flag (lit pendin) 3 0x20000000)
                (flag (lit noflsh) 3 0x80000000))
          (list (cc (lit vintr) 0) (cc (lit vquit) 1) (cc (lit verase) 2) (cc (lit vkill) 3)
                (cc (lit veof) 4) (byte (lit vtime) (Term %cc-at 5)) (byte (lit vmin) (Term %cc-at 6))
                (cc (lit vswtch) 7) (cc (lit vstart) 8) (cc (lit vstop) 9) (cc (lit vsusp) 10)
                (cc (lit veol) 11) (cc (lit vreprint) 12) (cc (lit vdiscard) 13) (cc (lit vwerase) 14)
                (cc (lit vlnext) 15) (cc (lit veol2) 16)
                (byte (lit line) 16)
                (flag (lit ignbrk) 0 0x1) (flag (lit brkint) 0 0x2) (flag (lit ignpar) 0 0x4)
                (flag (lit parmrk) 0 0x8) (flag (lit inpck) 0 0x10) (flag (lit istrip) 0 0x20)
                (flag (lit inlcr) 0 0x40) (flag (lit igncr) 0 0x80) (flag (lit icrnl) 0 0x100)
                (flag (lit iuclc) 0 0x200) (flag (lit ixon) 0 0x400) (flag (lit ixany) 0 0x800)
                (flag (lit ixoff) 0 0x1000) (flag (lit imaxbel) 0 0x2000) (flag (lit iutf8) 0 0x4000)
                (flag (lit opost) 1 0x1) (flag (lit olcuc) 1 0x2) (flag (lit onlcr) 1 0x4)
                (flag (lit ocrnl) 1 0x8) (flag (lit onocr) 1 0x10) (flag (lit onlret) 1 0x20)
                (flag (lit ofill) 1 0x40) (flag (lit ofdel) 1 0x80)
                (field (lit nl0) 1 0x100 0x0) (field (lit nl1) 1 0x100 0x100)
                (field (lit cr0) 1 0x600 0x0) (field (lit cr1) 1 0x600 0x200)
                (field (lit cr2) 1 0x600 0x400) (field (lit cr3) 1 0x600 0x600)
                (field (lit tab0) 1 0x1800 0x0) (field (lit tab1) 1 0x1800 0x800)
                (field (lit tab2) 1 0x1800 0x1000) (field (lit tab3) 1 0x1800 0x1800)
                (field (lit bs0) 1 0x2000 0x0) (field (lit bs1) 1 0x2000 0x2000)
                (field (lit vt0) 1 0x4000 0x0) (field (lit vt1) 1 0x4000 0x4000)
                (field (lit ff0) 1 0x8000 0x0) (field (lit ff1) 1 0x8000 0x8000)
                (field (lit cs5) 2 0x30 0x0) (field (lit cs6) 2 0x30 0x10)
                (field (lit cs7) 2 0x30 0x20) (field (lit cs8) 2 0x30 0x30)
                (flag (lit cstopb) 2 0x40) (flag (lit cread) 2 0x80) (flag (lit parenb) 2 0x100)
                (flag (lit parodd) 2 0x200) (flag (lit hupcl) 2 0x400) (flag (lit clocal) 2 0x800)
                (flag (lit cmspar) 2 0x40000000) (flag (lit crtscts) 2 0x80000000)
                (flag (lit isig) 3 0x1) (flag (lit icanon) 3 0x2) (flag (lit xcase) 3 0x4)
                (flag (lit echo) 3 0x8) (flag (lit echoe) 3 0x10) (flag (lit echok) 3 0x20)
                (flag (lit echonl) 3 0x40) (flag (lit noflsh) 3 0x80) (flag (lit tostop) 3 0x100)
                (flag (lit echoctl) 3 0x200) (flag (lit echoprt) 3 0x400) (flag (lit echoke) 3 0x800)
                (flag (lit flusho) 3 0x1000) (flag (lit pendin) 3 0x4000) (flag (lit iexten) 3 0x8000)
                (flag (lit extproc) 3 0x10000)))))

    (method %flag-at (self (param word INTEGER "A flag word, 0 c_iflag to 3 c_lflag"))
      (doc "The byte offset of a flag word in struct termios." (returns INTEGER "The offset")
        (example "(Term %flag-at 0)" "0")
        (sample "(Term %flag-at 3)" "24 on Darwin, 12 on Linux"))
      (* word (if os-darwin? 8 4)))

    (method %cc-at (self (param index INTEGER "An index in c_cc"))
      (doc "The byte offset of a control character in struct termios." (returns INTEGER "The offset")
        (example "(- (Term %cc-at 5) (Term %cc-at 0))" "5")
        (sample "(Term %cc-at 0)" "32 on Darwin, 17 on Linux"))
      (+ index (if os-darwin? 32 17)))

    (method %vdisable (self)
      (doc "_POSIX_VDISABLE: the c_cc value that turns a character off." (returns INTEGER "The value")
        (sample "(Term %vdisable)" "255 on Darwin, 0 on Linux"))
      (if os-darwin? 255 0))

    (method %bauds (self)
      (doc "Linux's speed codes as (BAUD . CODE); Darwin's speed is the baud itself." (returns LIST "The table")
        (example "(first (Term %bauds))" "(0 . 0)"))
      (list (pair 0 0) (pair 50 1) (pair 75 2) (pair 110 3) (pair 134 4) (pair 150 5) (pair 200 6)
            (pair 300 7) (pair 600 8) (pair 1200 9) (pair 1800 10) (pair 2400 11) (pair 4800 12)
            (pair 9600 13) (pair 19200 14) (pair 38400 15) (pair 57600 4097) (pair 115200 4098)
            (pair 230400 4099) (pair 460800 4100) (pair 500000 4101) (pair 576000 4102)
            (pair 921600 4103) (pair 1000000 4104) (pair 1152000 4105) (pair 1500000 4106)
            (pair 2000000 4107) (pair 2500000 4108) (pair 3000000 4109) (pair 3500000 4110)
            (pair 4000000 4111)))

    (method bauds (self)
      (doc "The bauds a terminal's speed is set to by name: the ones Linux has a B-code for. Darwin's libc takes any baud; these are the standard ones there too."
        (returns LIST "The bauds, ascending")
        (example "(List ref 13 (Term bauds))" "9600"))
      (List map (fn (_ r) (first r)) (Term %bauds)))

    (method %baud (self (param speed INTEGER "What cfgetospeed answered"))
      (doc "A speed as a baud: Darwin's as it is, Linux's B-code looked up; nil for a code with no baud."
        (returns ANY "The baud, or nil")
        (example "(Term %baud 0)" "0"))
      (if os-darwin? speed
        (let ((code (& speed 0xFFFFFFFF)))
          (let ((row (List find (fn (_ r) (= (rest r) code)) (Term %bauds))))
            (if (null? row) () (first row))))))

    (method %speed (self (param baud INTEGER "A baud"))
      (doc "The speed cfsetospeed takes for a baud: Darwin's the baud, Linux's its B-code; nil for a baud Linux has no code for."
        (returns ANY "The speed, or nil")
        (example "(Term %baud (Term %speed 9600))" "9600")
        (sample "(Term %speed 9600)" "9600 on Darwin, 13 on Linux"))
      (if os-darwin? baud
        (let ((row (List find (fn (_ r) (= (first r) baud)) (Term %bauds))))
          (if (null? row) () (rest row)))))

    (method %mode (self (param p POINTER "A struct termios")
                        (param row LIST "A mode row"))
      (doc "A mode's value in the termios at p: a flag's BOOL, whether every one of its bits is set; a character's code, nil when it is turned off; a count; or whether a field holds the row's setting."
        (returns ANY "The value")
        (example "(let ((b ((prim-ref 'str 'make) 128))) (let ((p ((prim-ref 'str '->ptr) b)) (row (List find (fn (_ r) (eq? (first r) 'echo)) (Term mode-rows)))) (Term %mode! p row #f) (Term %mode p row)))" "#f"))
      (let ((pref (prim-ref (lit ptr) (lit ref)))
            (where (List ref 1 row)) (v (List ref 2 row)))
        (match
          ((eq? where (lit cc))
            (let ((c (pref p (Term %cc-at v) 1))) (if (= c (Term %vdisable)) () c)))
          ((eq? where (lit byte)) (pref p v 1))
          ((eq? where (lit field))
            (= (& (pref p (Term %flag-at (first v)) 4) (List ref 1 v)) (List ref 2 v)))
          (#t (= (& (pref p (Term %flag-at where) 4) v) v)))))

    (method %mode! (self (param p POINTER "A struct termios")
                         (param row LIST "A mode row")
                         (param value ANY "A flag's BOOL, a character's code or nil, a count, or a field's BOOL"))
      (doc "Set a mode in the termios at p. A field set #f is left as it is: cs7 #f says what the size is not, not what it is."
        (returns NIL "Nothing")
        (example "(let ((b ((prim-ref 'str 'make) 128))) (let ((p ((prim-ref 'str '->ptr) b)) (row (List find (fn (_ r) (eq? (first r) 'echo)) (Term mode-rows)))) (Term %mode! p row #t) (Term %mode p row)))" "#t"))
      (let ((pref (prim-ref (lit ptr) (lit ref)))
            (pset (prim-ref (lit ptr) (lit set!)))
            (where (List ref 1 row)) (v (List ref 2 row)))
        (match
          ((eq? where (lit cc))
            (pset p (Term %cc-at v) (if (null? value) (Term %vdisable) (& value 255)) 1))
          ((eq? where (lit byte)) (pset p v (& value 255) 1))
          ((eq? where (lit field))
            (if value
              (let ((at (Term %flag-at (first v))) (mask (List ref 1 v)))
                (let ((f (pref p at 4)))
                  (pset p at (| (- f (& f mask)) (List ref 2 v)) 4)))
              ()))
          (#t
            (let ((at (Term %flag-at where)))
              (let ((f (pref p at 4)))
                (pset p at (if value (| f v) (- f (& f v))) 4)))))
        ()))

    ; --- settings -------------------------------------------------------------
    ;
    ; A terminal's settings as a value: the struct termios tcgetattr fills, in
    ; a GC-owned region, read and edited by name and applied when done -- what
    ; raw! saves and restore! applies is one of these.  modes and modes! are
    ; a settings read whole and a settings edited and applied.

    (method nccs (self)
      (doc "NCCS: the number of control characters in this libc's struct termios."
        (returns INTEGER "The count")
        (sample "(Term nccs)" "20 on Darwin, 32 on Linux"))
      (if os-darwin? 20 32))

    (method settings (self (param fd INTEGER "A terminal's descriptor"))
      (doc "The terminal's settings, read with tcgetattr, as a value setting, setting!, words and apply! take. Answers nil when fd is not a terminal."
        (returns ANY "The settings, or nil")
        (see apply!) (see setting) (see words)
        (sample "(Term setting (Term settings 0) 'echo)" "#t, at a cooked terminal"))
      ; Cleared first: a new string's bytes are spaces, and Linux's TCGETS writes
      ; the kernel's 19 control characters of the 32 musl's termios holds.
      (if (not (Term tty? fd)) ()
        (let ((buf ((prim-ref (lit str) (lit make)) 128)))
          (do (mem-set ((prim-ref (lit str) (lit ->ptr)) buf) 0 128)
              (if (< (Sys %sign-fold ((prim-ref (lit ptr) (lit call)) (Term c-tcget) fd ((prim-ref (lit str) (lit ->ptr)) buf))) 0) ()
                buf)))))

    (method apply! (self (param fd INTEGER "A terminal's descriptor")
                         (param settings ANY "Settings, as settings answers them"))
      (doc "Apply settings to the terminal with tcsetattr once pending output has drained. Answers #f when fd is not a terminal or the change is refused; a terminal may still keep some of its own, which a second settings read shows."
        (returns BOOL "Whether tcsetattr took them")
        (see settings)
        (sample "(Term apply! 0 (Term settings 0))" "#t, at a terminal"))
      (if (not (Term tty? fd)) #f
        (>= (Sys %sign-fold ((prim-ref (lit ptr) (lit call)) (Term c-tcset) fd (Term tcsadrain) ((prim-ref (lit str) (lit ->ptr)) settings))) 0)))

    (method setting (self (param settings ANY "Settings, as settings answers them")
                          (param name SYMBOL "A mode's name, or ispeed or ospeed"))
      (doc "One mode's value in settings, as modes names them; nil for a name this OS does not have."
        (returns ANY "The value")
        (see setting!) (see modes)
        (sample "(Term setting (Term settings 0) 'ospeed)" "38400, at a terminal"))
      (let ((p ((prim-ref (lit str) (lit ->ptr)) settings))
            (call (prim-ref (lit ptr) (lit call)))
            (row (List find (fn (_ r) (eq? (first r) name)) (Term mode-rows))))
        (match
          ((not (null? row)) (Term %mode p row))
          ((eq? name (lit ispeed)) (Term %baud (call (Term c-igetsp) p)))
          ((eq? name (lit ospeed)) (Term %baud (call (Term c-ogetsp) p)))
          (#t ()))))

    (method setting! (self (param settings ANY "Settings, as settings answers them")
                           (param name SYMBOL "A mode's name, or ispeed or ospeed")
                           (param value ANY "The value, as modes! takes it"))
      (doc "Set one mode in settings, leaving the terminal as it is until they are applied. A name this OS does not have is passed over, as is a speed it has no code for."
        (returns BOOL "Whether the name was one this OS has and the value one it takes")
        (see setting) (see apply!)
        (sample "(Term setting! s 'echo #f)" "#t; s no longer echoes once applied"))
      (let ((p ((prim-ref (lit str) (lit ->ptr)) settings))
            (call (prim-ref (lit ptr) (lit call)))
            (row (List find (fn (_ r) (eq? (first r) name)) (Term mode-rows))))
        (match
          ((not (null? row)) (do (Term %mode! p row value) #t))
          ((eq? name (lit ispeed))
            (let ((s (Term %speed value))) (if (null? s) #f (do (call (Term c-isetsp) p s) #t))))
          ((eq? name (lit ospeed))
            (let ((s (Term %speed value))) (if (null? s) #f (do (call (Term c-osetsp) p s) #t))))
          (#t #f))))

    (method words (self (param settings ANY "Settings, as settings answers them"))
      (doc "Settings as numbers: the four flag words, c_iflag, c_oflag, c_cflag and c_lflag, then each of the nccs control characters' bytes."
        (returns LIST "The numbers")
        (see words!)
        (sample "(List ref 3 (Term words (Term settings 0)))" "c_lflag, at a terminal"))
      (let ((p ((prim-ref (lit str) (lit ->ptr)) settings))
            (pref (prim-ref (lit ptr) (lit ref))))
        (List append
          (List map (fn (_ w) (pref p (Term %flag-at w) 4)) (list 0 1 2 3))
          (List map (fn (_ i) (pref p (Term %cc-at i) 1)) (List range 0 (Term nccs))))))

    (method words! (self (param settings ANY "Settings, as settings answers them")
                         (param words LIST "Four flag words, then nccs bytes, as words answers them"))
      (doc "Set settings from numbers as words answers them. Answers #f, leaving the settings as they were, unless there are four words and nccs bytes."
        (returns BOOL "Whether the numbers were taken")
        (see words)
        (example "(Term words! ((prim-ref 'str 'make) 128) (list 1 2 3))" "#f"))
      (if (not (= (List length words) (+ 4 (Term nccs)))) #f
        (let ((p ((prim-ref (lit str) (lit ->ptr)) settings))
              (pset (prim-ref (lit ptr) (lit set!))))
          (do (List for-each (fn (_ w) (pset p (Term %flag-at w) (List ref w words) 4)) (list 0 1 2 3))
              (List for-each (fn (_ i) (pset p (Term %cc-at i) (& (List ref (+ 4 i) words) 255) 1))
                (List range 0 (Term nccs)))
              #t))))

    (method modes (self (param fd INTEGER "A terminal's descriptor"))
      (doc "The terminal's modes by name, as (NAME . VALUE): each control character's code, nil when it is turned off; vmin, vtime and Linux's line as counts; each flag's BOOL; each field's setting -- cs5 to cs8, nl0, tab3 and the other delays -- whether the field holds it; and ispeed and ospeed in baud. Only the modes this OS has are named. Answers nil when fd is not a terminal."
        (returns ANY "The modes, or nil")
        (note "The names are busybox stty's, the RFC 4254 ones among them lower-cased: vintr, icrnl, echo, opost, cs8, hupcl, tab0 and the rest.")
        (see modes!) (see settings)
        (sample "(Assoc get 'vintr (Term modes 0))" "3, at a terminal"))
      (let ((s (Term settings fd)))
        (if (null? s) ()
          (List map (fn (_ name) (pair name (Term setting s name)))
            (List append (List map (fn (_ r) (first r)) (Term mode-rows)) (list (lit ispeed) (lit ospeed)))))))

    (method modes! (self (param fd INTEGER "A terminal's descriptor")
                         (param modes LIST "(NAME . VALUE) pairs, as modes answers them"))
      (doc "Set the terminal's modes by name, in order, and apply them once pending output has drained. A name this OS does not have is passed over, as is a speed it has no code for. Answers #f when fd is not a terminal or the change is refused."
        (returns BOOL "Whether the modes were applied")
        (note "A flag takes a BOOL, a character its code or nil to turn it off, vmin, vtime and line a count, a field's setting #t to set it (cs8, tab0), ispeed and ospeed a baud.")
        (note "The terminal may keep its own: a Linux pseudo-terminal is CS8 without parity whatever is asked.")
        (see modes) (see setting!)
        (sample "(Term modes! 0 (list (pair 'echo #f) (pair 'vintr 7)))" "#t, at a terminal"))
      (let ((s (Term settings fd)))
        (if (null? s) #f
          (do (List for-each (fn (_ m) (Term setting! s (first m) (rest m))) modes)
              (Term apply! fd s)))))

    ; --- geometry -----------------------------------------------------------
    ; Named `window`, not `size`: `size` is a retired spelling in this tree,
    ; and two dimensions are not a count.

    (method window (self (param fd INTEGER "Descriptor to measure"))
      (doc "The terminal window's (columns . rows), from TIOCGWINSZ. Falls back to COLUMNS/LINES in the environment and then to 80x24, because a width is needed on every redraw and a wrong one is better than a failed one."
        (returns PAIR "(columns . rows)")
        (note "Reached as a SYSCALL, not through the FFI: ioctl is variadic, and on Apple arm64 a variadic argument goes on the stack where a fixed one goes in a register -- through the fixed-signature ffi door the winsize pointer never reached the kernel and every terminal measured 80x24.")
        (sample "(Term window 0)" "(120 . 40)"))
      (let ((m (Term measure fd)))
        (let ((cols (if (null? m) 0 (first m)))
              (rows (if (null? m) 0 (rest m))))
          (pair (if (> cols 0) cols (Term %env-int "COLUMNS" 80))
                (if (> rows 0) rows (Term %env-int "LINES" 24))))))

    (method measure (self (param fd INTEGER "Descriptor to measure"))
      (doc "The terminal window's (columns . rows) as TIOCGWINSZ reports them, or nil when it reports nothing: the ioctl failed, or answered zero rows, as a serial console does. A caller that can ask the terminal itself does so on nil; window falls back instead."
        (returns ANY "(columns . rows), or nil")
        (sample "(Term measure 0)" "(120 . 40), or nil when stdin is no terminal"))
      (let ((mkstr (prim-ref (lit str) (lit make)))
            (toptr (prim-ref (lit str) (lit ->ptr)))
            (pref (prim-ref (lit ptr) (lit ref))))
        ; struct winsize is four unsigned shorts: rows, cols, then two pixel
        ; fields nothing has set meaningfully since the 1980s.
        (let ((w (mkstr 16)))
          (let ((p (toptr w)))
            (let ((r (if (< (Term ioctl-id) 0) -1
                       (Sys %sign-fold (syscall (Term ioctl-id) fd (Term tiocgwinsz) w)))))
              (if (< r 0) ()
                (let ((rows (pref p 0 2)))
                  (if (> rows 0) (pair (pref p 2 2) rows) ()))))))))

    (method window! (self (param fd INTEGER "A terminal's descriptor")
                          (param cols ANY "The columns, or nil to keep them")
                          (param rows ANY "The rows, or nil to keep them"))
      (doc "Set the terminal window's columns and rows with TIOCSWINSZ, keeping whichever is nil and the pixel sizes as TIOCGWINSZ reports them. The terminal's foreground process group is sent SIGWINCH when the size changes. Answers #f when fd is not a terminal or the change is refused."
        (returns BOOL "Whether the size was set")
        (see measure)
        (sample "(Term window! 0 100 30)" "#t, at a terminal, which then measures (100 . 30)"))
      (let ((mkstr (prim-ref (lit str) (lit make)))
            (toptr (prim-ref (lit str) (lit ->ptr)))
            (pset (prim-ref (lit ptr) (lit set!))))
        (let ((w (mkstr 16)))
          (let ((p (toptr w)))
            (if (< (Term ioctl-id) 0) #f
              (if (< (Sys %sign-fold (syscall (Term ioctl-id) fd (Term tiocgwinsz) w)) 0) #f
                (do (if (null? rows) () (pset p 0 rows 2))
                    (if (null? cols) () (pset p 2 cols 2))
                    (>= (Sys %sign-fold (syscall (Term ioctl-id) fd (Term tiocswinsz) w)) 0))))))))

    (method %env-int (self (param name STRING "Environment variable")
                           (param dflt INTEGER "Value when unset or unparseable"))
      (doc "An environment variable read as a positive integer, or the default."
        (returns INTEGER "The parsed value, or dflt")
        (example "(Term %env-int \"X_HELP_EXAMPLE_UNSET\" 80)" "80"))
      (let ((v (Sys getenv name)))
        (if (null? v) dflt
          (guard (_ dflt)
            (let ((n ((prim-ref (lit convert) (lit to)) v (Type named INTEGER) 10))) (if (and (not (null? n)) (> n 0)) n dflt))))))

    ; --- output --------------------------------------------------------------

    (method emit (self (param fd INTEGER "Descriptor to write to")
                       (param s STRING "Bytes to write"))
      (doc "Write bytes straight to the descriptor, bypassing the printer. A redraw is a burst of escape sequences and must not be interleaved with whatever the evaluator is writing to stdout."
        (returns INTEGER "Bytes written")
        (sample "(Term emit 1 \"\\r\\n\")" "2, the bytes written"))
      (Sys fd-write fd s))

    ; --- keys -----------------------------------------------------------------
    ;
    ; `key` returns one of three types, and the caller tells them apart with
    ; the ordinary predicates:
    ;
    ;   a STRING  -- literal text to insert (one whole character, UTF-8 included)
    ;   a SYMBOL  -- a named key: 'up 'down 'left 'right 'home 'end 'delete
    ;                'page-up 'page-down 'enter 'backspace 'tab 'interrupt 'eof 'clear 'kill-eol
    ;                'kill-bol 'kill-word 'yank 'word-left 'word-right 'escape
    ;                'complete 'quoted-insert 'search-back 'search-forward 'abort
    ;                'f1 to 'f12, and 'kp0 to 'kp9 from a keypad in
    ;                application mode
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
            ((= b 7)   (lit abort))
            ((= b 8)   (lit backspace))
            ((= b 9)   (lit complete))
            ((= b 10)  (lit enter))
            ((= b 11)  (lit kill-eol))
            ((= b 12)  (lit clear))
            ((= b 14)  (lit down))
            ((= b 16)  (lit up))
            ((= b 18)  (lit search-back))
            ((= b 19)  (lit search-forward))
            ((= b 13)  (lit enter))
            ((= b 21)  (lit kill-bol))
            ((= b 22)  (lit quoted-insert))
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

    (method %one-byte (self (param b INTEGER "A byte value 0-255"))
      (doc "A one-byte string holding b." (returns STRING "The byte as text")
        (example "(Term %one-byte 65)" "\"A\""))
      (bytes->str (list b)))

    (method %utf8 (self (param read-byte CALLABLE "Byte reader")
                        (param lead INTEGER "The leading byte"))
      (doc "Read the continuation bytes of a UTF-8 sequence whose leading byte is `lead`, and return the whole character. A truncated or malformed sequence yields what arrived, which the redraw will render as the terminal sees fit."
        (returns STRING "One character")
        (example "(Term %utf8 (fn (_) 169) 195)" "\"é\""))
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
        (returns ANY "A key symbol, or 'escape")
        (example "(Term %escape (fn (_) 98))" "'word-left"))
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
      (doc "Decode an SS3 sequence (ESC O x) -- what a terminal in application-cursor mode sends for the arrows, what most send for F1 to F4, and what a keypad in application mode sends for its digits."
        (returns ANY "A key symbol")
        (example "(Term %ss3 (fn (_) 80))" "'f1"))
      (let ((b (read-byte)))
        (match
          ((null? b) (lit escape))
          ((= b 65) (lit up))
          ((= b 66) (lit down))
          ((= b 67) (lit right))
          ((= b 68) (lit left))
          ((= b 72) (lit home))
          ((= b 70) (lit end))
          ((= b 80) (lit f1))
          ((= b 81) (lit f2))
          ((= b 82) (lit f3))
          ((= b 83) (lit f4))
          ; ESC O p to ESC O y: keypad 0 to 9
          ((and (>= b 112) (<= b 121)) (Term %keypad (- b 112)))
          (#t (lit unbound)))))

    (method %keypad (self (param n INTEGER "The keypad digit, 0 to 9"))
      (doc "The key symbol for keypad digit n."
        (returns SYMBOL "'kp0 to 'kp9")
        (example "(Term %keypad 7)" "'kp7"))
      (match
        ((= n 0) (lit kp0)) ((= n 1) (lit kp1)) ((= n 2) (lit kp2)) ((= n 3) (lit kp3))
        ((= n 4) (lit kp4)) ((= n 5) (lit kp5)) ((= n 6) (lit kp6)) ((= n 7) (lit kp7))
        ((= n 8) (lit kp8)) (#t (lit kp9))))

    (method %csi (self (param read-byte CALLABLE "Byte reader"))
      (doc "Decode a CSI sequence (ESC [ ...): the arrows, Home/End, Delete, and the modified arrows terminals spell ESC [ 1 ; 5 C."
        (returns ANY "A key symbol")
        (example "(let ((bs (list 49 59 53 67))) (Term %csi (fn (_) (let ((b (first bs))) (set! bs (rest bs)) b))))" "'word-right"))
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

    (method %csi-final (self (param final INTEGER "The sequence's final byte")
                             (param params LIST "The parameter bytes, in order"))
      (doc "Name the key a CSI sequence's final byte and parameters stand for."
        (returns ANY "A key symbol")
        (example "(Term %csi-final 67 (list 49 59 53))" "'word-right"))
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
          ; F1 to F4 with a modifier: ESC [ 1 ; m P to S
          ((= final 80) (lit f1))
          ((= final 81) (lit f2))
          ((= final 82) (lit f3))
          ((= final 83) (lit f4))
          ((= final 126) (Term %tilde (Term %csi-number params)))
          (#t (lit unbound)))))

    (method %csi-number (self (param params LIST "The parameter bytes, in order"))
      (doc "A CSI sequence's first parameter as a number: its digits up to the first ';', 0 when there are none."
        (returns INTEGER "The number")
        (example "(Term %csi-number (list 49 53 59 53))" "15"))
      (let ((go (fn (self ps n)
                  (if (or (null? ps) (or (< (first ps) 48) (> (first ps) 57))) n
                    (self (rest ps) (+ (* n 10) (- (first ps) 48)))))))
        (go params 0)))

    (method %tilde (self (param n INTEGER "The first parameter of ESC [ N ~"))
      (doc "Name the key ESC [ N ~ stands for: Home, End, Delete, Page Up and Page Down, and the function keys, whose numbers skip 16 and 22."
        (returns ANY "A key symbol")
        (example "(Term %tilde 3)" "'delete"))
      ; The number is read whole: 15~ is F5, which a test for the byte '1'
      ; among the parameters would take for Home.
      (match
        ((= n 1) (lit home)) ((= n 7) (lit home))
        ((= n 4) (lit end)) ((= n 8) (lit end))
        ((= n 3) (lit delete))
        ((= n 5) (lit page-up)) ((= n 6) (lit page-down))
        ((= n 11) (lit f1)) ((= n 12) (lit f2)) ((= n 13) (lit f3)) ((= n 14) (lit f4))
        ((= n 15) (lit f5)) ((= n 17) (lit f6)) ((= n 18) (lit f7)) ((= n 19) (lit f8))
        ((= n 20) (lit f9)) ((= n 21) (lit f10)) ((= n 23) (lit f11)) ((= n 24) (lit f12))
        (#t (lit unbound)))))

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
  (example "(Term key (fn (_) 127))" "'backspace")
  "Term: raw mode, terminal size, and byte-to-key decoding for the REPL line editor.")
