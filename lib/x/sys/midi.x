; sys/midi.x -- Midi: a MIDI keyboard's messages, read as a descriptor
;
; A MIDI input is a file descriptor that delivers the device's raw bytes,
; so one Sys poll waits on a keyboard and a terminal together, and
; (m messages) decodes what has come: notes on and off, controllers,
; programs, pressure and the pitch bend, running status kept between
; reads.
;
;   (Midi devices)       -> the inputs' names
;   (Midi open NAME)     -> an input; (m fd) is what to poll
;   (m messages)         -> the messages that came, ((note-on 1 60 100) ...)
;   (m close!)           -> nil
;   (Midi decode BYTES)  -> the same, from bytes in hand
;
; Linux: a device is a raw MIDI node, /dev/snd/midiCnDm, read without
; waiting.
;
; macOS: CoreMIDI, loaded with dlopen as sys/sdl loads SDL3, gives a
; source's packets only to a read callback, on a thread of its own.  The
; interpreter is not entered from that thread: the callback is a small
; native stub, written with x/tool/asm, that writes each packet's bytes
; to a pipe and returns.  The pipe's read end is the descriptor.  Its
; write end does not wait, so a full pipe drops bytes rather than hold
; CoreMIDI up.
;
; Channels are numbered 1 to 16, as a player counts them.

(module x/sys/midi)
(import x/type/class)
(import x/sys/posix)
(import x/sys/file)
(import x/tool/asm)
(import x/platform/syscall)
(import x/core/doors ffi-dlopen ffi-dlsym image-transient! ptr->int ptr->str ptr-call ptr-ref ptr-ref-word str->ptr str-make)

(def-class Midi ()
  (doc "A MIDI input: a descriptor that delivers a device's bytes, and its messages decoded."
    (note "On Linux a device is a raw MIDI node under /dev/snd. On macOS it is a CoreMIDI source, its packets written to a pipe by a native read callback that never enters the interpreter.")
    (note "A message is (note-on CH NOTE VEL), (note-off CH NOTE VEL), (poly-pressure CH NOTE V), (cc CH N V), (program CH N), (pressure CH V) or (bend CH V), CH 1 to 16 and V of a bend -8192 to 8191. A note-on of velocity 0 is a note-off.")
    (example "(Midi decode (list 144 60 100 60 0))" "(('note-on 1 60 100) ('note-off 1 60 0))")
    (see devices) (see open) (see decode))
  (doc (fd -1) "The descriptor the bytes arrive on: what Sys poll waits on"
    (example "((new Midi) fd)" "-1"))
  (doc (name "") "The device's name, as devices gives it"
    (example "((new Midi name \"keys\") name)" "\"keys\""))
  (doc (pending ()) "The decoder's state between reads: the running status and the data bytes of a message not yet whole"
    (example "(null? ((new Midi) pending))" "#t"))
  (doc (writer -1) "macOS: the pipe's write end, the callback's; -1 on Linux"
    (example "((new Midi) writer)" "-1"))
  (doc (port 0) "macOS: the CoreMIDI input port; 0 on Linux"
    (example "((new Midi) port)" "0"))
  (doc (client 0) "macOS: the CoreMIDI client; 0 on Linux"
    (example "((new Midi) client)" "0"))
  (doc (stub ()) "macOS: the read callback's assembler buffer; nil on Linux"
    (example "(null? ((new Midi) stub))" "#t"))

  (method messages (self)
    (doc "The messages that have come since the last call, without waiting: nil when none has."
      (returns LIST "Messages, in the order they came")
      (sample "(m messages)" "(('note-on 1 60 100))"))
    (def got (Midi %drain (self fd) ()))
    (if (null? got) ()
      ((fn (_ r) (self pending (rest r)) (first r))
       (Midi %decode got (self pending)))))

  (method close! (self)
    (doc "Close the input: the device, or the CoreMIDI port and client and the pipe."
      (returns ANY "nil")
      (example "(let ((m (new Midi))) (m close!) (m fd))" "-1"))
    (unless (= (self port) 0) (ptr-call (Midi %core "MIDIPortDispose") (self port)))
    (unless (= (self client) 0) (ptr-call (Midi %core "MIDIClientDispose") (self client)))
    (unless (null? (self stub)) (asm-free! (self stub)))
    (unless (< (self writer) 0) (Sys close (self writer)))
    (unless (< (self fd) 0) (Sys close (self fd)))
    (self port 0) (self client 0) (self stub ()) (self writer -1) (self fd -1)
    ())

  (static
    (%core-path "/System/Library/Frameworks/CoreMIDI.framework/CoreMIDI")
    (%cf-path "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
    (%utf8 134217984)

    (method devices (self)
      (doc "The MIDI inputs there are, by name: a raw MIDI node's path on Linux, a source's display name on macOS."
        (returns LIST "Names, for open")
        (sample "(Midi devices)" "(\"/dev/snd/midiC1D0\") on Linux, (\"Keystation 49\") on macOS"))
      (match
        (os-darwin?
          (List map (fn (_ i) (Midi %source-name (ptr-call (Midi %core "MIDIGetSource") i)))
            (List range 0 (ptr-call (Midi %core "MIDIGetNumberOfSources")))))
        ((File exists? "/dev/snd")
          (List map (fn (_ n) (Str8 append "/dev/snd/" n))
            (List filter (fn (_ n) (Str8 starts? "midiC" n)) (File list-dir "/dev/snd"))))
        (#t ())))

    (method open (self (param name STRING "A device, as devices names it"))
      (doc "Open a MIDI input. Raises a label 'io when there is no such device or it cannot be opened."
        (returns Midi "The input; poll its fd, then take its messages")
        (sample "(Midi open \"/dev/snd/midiC1D0\")" "an input"))
      (if os-darwin? (Midi %open-core name) (Midi %open-raw name)))

    (method decode (self (param bytes LIST "Byte values, as a device sends them"))
      (doc "The messages in BYTES, which start a stream: running status kept, real-time bytes and system messages passed over."
        (returns LIST "Messages, in order")
        (example "(Midi decode (list 144 60 100 64 90 128 60 0))" "(('note-on 1 60 100) ('note-on 1 64 90) ('note-off 1 60 0))")
        (example "(Midi decode (list 185 7 100 224 0 64 248 201 5))" "(('cc 10 7 100) ('bend 1 0) ('program 10 5))"))
      (first (Midi %decode bytes ())))

    ; Every byte waiting on FD, read without waiting.
    (method %drain (self fd acc)
      (def got (if (< fd 0) () (Sys fd-read fd 256)))
      (if (null? got) acc (Midi %drain fd (List append acc got))))

    ; BYTES decoded from the state ST, (STATUS DATA ...): answers
    ; (MESSAGES . STATE).  STATUS is the running status, 240 inside a
    ; system exclusive, 0 for none; DATA the bytes of a message not yet
    ; whole, last first.
    (method %decode (self bytes st)
      ((fn (walk bs status data acc)
         (match
           ((null? bs) (pair (List reverse acc) (pair status data)))
           (#t ((fn (_ b)
                  (match
                    ((< 247 b) (walk (rest bs) status data acc))           ; real time
                    ((= b 240) (walk (rest bs) 240 () acc))                ; sysex starts
                    ((= b 247) (walk (rest bs) 0 () acc))                  ; sysex ends
                    ((< 240 b) (walk (rest bs) 0 () acc))                  ; system common
                    ((< 127 b) (walk (rest bs) b () acc))                  ; a status
                    ((if (= status 240) #t (= status 0)) (walk (rest bs) status data acc))
                    (#t ((fn (_ d)
                           (if (< (List length d) (Midi %data-count status))
                             (walk (rest bs) status d acc)
                             (walk (rest bs) status () (pair (Midi %message status (List reverse d)) acc))))
                         (pair b data)))))
                (first bs)))))
       bytes (if (null? st) 0 (first st)) (if (null? st) () (rest st)) ()))

    (method %data-count (self status)
      ((fn (_ kind) (if (if (= kind 192) #t (= kind 208)) 1 2)) (- status (% status 16))))

    (method %message (self status d)
      (def ch (+ (% status 16) 1))
      (def kind (- status (% status 16)))
      (match
        ((= kind 128) (list (lit note-off) ch (first d) (List ref 1 d)))
        ((= kind 144) (list (if (= (List ref 1 d) 0) (lit note-off) (lit note-on)) ch (first d) (List ref 1 d)))
        ((= kind 160) (list (lit poly-pressure) ch (first d) (List ref 1 d)))
        ((= kind 176) (list (lit cc) ch (first d) (List ref 1 d)))
        ((= kind 192) (list (lit program) ch (first d)))
        ((= kind 208) (list (lit pressure) ch (first d)))
        (#t (list (lit bend) ch (- (+ (first d) (* 128 (List ref 1 d))) 8192)))))

    ; --- Linux ---------------------------------------------------------------

    (method %open-raw (self name)
      (def fd (File open name (list (lit rdonly) (lit nonblock))))
      (when (< fd 0) (Err raise (lit io) "Midi: the device cannot be opened" name))
      (new Midi fd fd name name))

    ; --- macOS ---------------------------------------------------------------

    (method %core (self name)
      (def h (ffi-dlopen (Midi %core-path) 1))
      (when (null? h) (Err raise (lit io) "Midi: CoreMIDI not found" (Midi %core-path)))
      (ffi-dlsym h name))

    (method %cf (self name)
      (def h (ffi-dlopen (Midi %cf-path) 1))
      (when (null? h) (Err raise (lit io) "Midi: CoreFoundation not found" (Midi %cf-path)))
      (ffi-dlsym h name))

    (method %cf-string (self s)
      (ptr-call (Midi %cf "CFStringCreateWithCString") 0 s (Midi %utf8)))

    ; A source's display name, or "source N" for one with none.
    (method %source-name (self src)
      (def out (str-make 8))
      (def key (ptr-ref-word (ffi-dlsym (ffi-dlopen (Midi %core-path) 1) "kMIDIPropertyDisplayName") 0))
      (if (not (= 0 (ptr-call (Midi %core "MIDIObjectGetStringProperty") src key out)))
        (Str8 append "source " (Str8 str src))
        ((fn (_ cf)
           (def buf (str-make 256))
           (def ok (ptr-call (Midi %cf "CFStringGetCString") cf buf 256 (Midi %utf8)))
           (ptr-call (Midi %cf "CFRelease") cf)
           (if (= 0 (% ok 256)) (Str8 append "source " (Str8 str src)) (ptr->str (str->ptr buf))))
         (ptr-ref-word (str->ptr out) 0))))

    (method %open-core (self name)
      (def names (Midi devices))
      (def at (List index-of name names))
      (when (null? at) (Err raise (lit io) "Midi: no such source" name))
      (def fds (Sys pipe))
      (def fd (first fds))
      (def writer (rest fds))
      (Sys nonblock! fd)
      (Sys nonblock! writer)
      (def stub (Midi %write-stub))
      (def m (new Midi fd fd writer writer name name stub stub))
      (image-transient! (fn (_) (m close!)))
      (def out (str-make 8))
      (def label (Midi %cf-string "x-lang"))
      (unless (= 0 (ptr-call (Midi %core "MIDIClientCreate") label 0 0 out))
        (do (m close!) (Err raise (lit io) "Midi: CoreMIDI would not make a client" name)))
      (m client (ptr-ref (str->ptr out) 0 4))
      (unless (= 0 (ptr-call (Midi %core "MIDIInputPortCreate") (m client) label
                     (ptr->int (asm-finalize! stub)) writer out))
        (do (m close!) (Err raise (lit io) "Midi: CoreMIDI would not make an input port" name)))
      (m port (ptr-ref (str->ptr out) 0 4))
      (unless (= 0 (ptr-call (Midi %core "MIDIPortConnectSource") (m port)
                     (ptr-call (Midi %core "MIDIGetSource") at) 0))
        (do (m close!) (Err raise (lit io) "Midi: CoreMIDI would not connect the source" name)))
      m)

    ; The read callback, void (const MIDIPacketList *list, void *fd, void
    ; *source): for each packet, write(fd, data, length).  A packet list is
    ; a 32-bit count, then the packets from byte 4: a 64-bit time, a 16-bit
    ; length at 8, the data from 10.  The next packet follows the data, on
    ; arm64 at the next multiple of 4 (CoreMIDI's MIDIPacketNext).
    (method %write-stub (self)
      (if (not (asm-backend?))
        (Err raise (lit state) "Midi: no assembler backend for this platform" ()))
      (def write-at (ptr->int (ffi-dlsym (ffi-dlopen () 1) "write")))
      (def a (asm-new 512))
      (asm-prologue! a)
      (asm-emit! a (lit mov) x19 x1)                     ; the pipe
      (asm-emit! a (lit ldrw) x20 (mem x0 0))            ; packets left
      (asm-emit! a (lit add) x21 x0 (imm 4))             ; the packet
      (asm-label! a (lit %midi-next))
      (asm-emit! a (lit cbz) x20 (label (lit %midi-done)))
      (asm-emit! a (lit mov) x0 x19)
      (asm-emit! a (lit add) x1 x21 (imm 10))
      (asm-emit! a (lit ldrh) x2 (mem x21 8))
      (asm-load-imm64! a x8 write-at)
      (asm-emit! a (lit blr) x8)
      (asm-emit! a (lit ldrh) x8 (mem x21 8))
      (asm-emit! a (lit add) x21 x21 x8)
      (asm-emit! a (lit add) x21 x21 (imm 10))
      (when arch-arm64?
        (do (asm-emit! a (lit add) x21 x21 (imm 3))
            (asm-emit! a (lit mov) x2 (imm 2))
            (asm-emit! a (lit lsrv) x21 x21 x2)
            (asm-emit! a (lit lslv) x21 x21 x2)))
      (asm-emit! a (lit sub) x20 x20 (imm 1))
      (asm-emit! a (lit b) (label (lit %midi-next)))
      (asm-label! a (lit %midi-done))
      (asm-emit! a (lit mov) x0 (imm 0))
      (asm-epilogue! a)
      a)))

(doc (provide x/sys/midi Midi)
  (example "(Midi decode (list 153 36 127))" "(('note-on 10 36 127))")
  (sample "(Midi devices)" "the MIDI inputs there are, by name")
  "MIDI input: a keyboard's bytes on a descriptor, through raw MIDI on Linux and CoreMIDI on macOS, and its messages decoded.")
