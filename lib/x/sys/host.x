; host.x -- Host: what the running kernel reports about the machine
;
; Boot time, load, memory, CPU time, the process table and the logged-in
; users, as records that read the same on Linux and Darwin.  Programs such
; as uptime, free, ps and top format these and never ask which kernel
; answered.
;
; Linux reads what BusyBox reads: sysinfo(2) for uptime, load and the
; memory totals; /proc/meminfo for cached, reclaimable and available;
; /proc/stat for CPU time and the boot time; /proc/PID/stat for a process.
; Darwin reads sysctl (kern.boottime, vm.loadavg, hw.memsize,
; vm.swapusage, kern.proc.all, kern.procargs2), the Mach host statistics
; and proc_pidinfo, all through the dlopen FFI.  Both read the users
; through libc's getutxent, as BusyBox does.
;
; A record is an alist keyed by symbols.  A field the kernel does not
; report, or will not report to this user, is nil: Darwin refuses another
; user's process memory and CPU time without root, which is why its
; ps and top are setuid.
;
; Times of day are unix seconds; CPU times are nanoseconds; sizes are
; bytes.
;
; Two static fields choose the source: `source` ('linux or 'darwin; nil
; means this kernel's) and `proc-root` (the /proc the Linux reader opens).
; A spec points them at a fixture tree to run the Linux reader anywhere.

(module x/sys/host)
(import x/type/class)
(import x/core/list)
(import x/sys/posix)
(import x/sys/file)
(import x/num/float)
(import x/codec/struct)
(import x/platform/syscall stat-layout)

(def-class Host ()
  (doc "The machine as the kernel reports it: boot time, load, memory, CPU time, processes and logged-in users, the same records on Linux and Darwin."
    (note "A field the kernel does not report is nil. Darwin reports another user's process memory and CPU time only to root.")
    (see boot-time) (see load) (see memory) (see cpu) (see processes) (see process) (see args) (see users))
  (static
    (source    ()      "'linux or 'darwin: which reader answers; nil means this kernel's")
    (proc-root "/proc" "The /proc tree the Linux reader opens")

    ; --- plumbing -------------------------------------------------------------

    (method %backend (self)
      (doc "The reader that answers: the source field, or this kernel's."
        (returns SYMBOL "'linux or 'darwin"))
      (if (null? (Host source)) (if os-darwin? (lit darwin) (lit linux)) (Host source)))

    (method %sym (self (param name STRING "libc function name"))
      (doc "The named libc function, resolved through the process's own handle."
        (returns POINTER "The function pointer"))
      ((prim-ref (lit ffi) (lit dlsym)) ((prim-ref (lit ffi) (lit dlopen)) () 1) name))

    (method %call (self (param name STRING "libc function name") . (param argv LIST "Its arguments"))
      (doc "Call a libc function and fold its int result to a signed value."
        (returns INTEGER "The result, negative on failure"))
      (Sys %sign-fold (apply (prim-ref (lit ptr) (lit call)) (pair (Host %sym name) argv))))

    (method %buf (self (param n INTEGER "Size in bytes"))
      (doc "A GC-owned region of n bytes. Its contents are not zeroed: read only what a call wrote."
        (returns STRING "The region"))
      ((prim-ref (lit str) (lit make)) n))

    (method %ptr (self (param buf STRING "A region from %buf"))
      (doc "The region's address, for a C argument."
        (returns POINTER "The address"))
      ((prim-ref (lit str) (lit ->ptr)) buf))

    (method %int-at (self (param buf STRING "A region") (param off INTEGER "Byte offset")
                          (param n INTEGER "Width: 1, 2, 4 or 8"))
      (doc "The unsigned little-endian integer of n bytes at off."
        (returns INTEGER "The value"))
      ((prim-ref (lit ptr) (lit ref)) (Host %ptr buf) off n))

    (method %signed-at (self (param buf STRING "A region") (param off INTEGER "Byte offset")
                             (param n INTEGER "Width: 1, 2 or 4"))
      (doc "The two's-complement integer of n bytes at off."
        (returns INTEGER "The value"))
      (def v (Host %int-at buf off n))
      (def top (<< 1 (- (* 8 n) 1)))
      (if (< v top) v (- v (* 2 top))))

    (method %cstr-at (self (param buf STRING "A region") (param off INTEGER "Byte offset")
                           (param n INTEGER "Most bytes to read"))
      (doc "The NUL-terminated string at off, at most n bytes. Read through its address: a region's own length stops at its first NUL, so Str8 sub cannot reach past one."
        (returns STRING "The string"))
      (def cvt (prim-ref (lit convert) (lit to)))
      (def s (Host %cstr-ptr (cvt (+ (cvt (Host %ptr buf) (Type named INTEGER)) off) (Type named POINTER))))
      (if (> (Str8 length s) n) (Str8 sub 0 n s) s))

    (method %cstr-ptr (self (param p POINTER "Address of a NUL-terminated string"))
      (doc "The C string at an address."
        (returns STRING "The string"))
      ((prim-ref (lit convert) (lit to)) p (Type named STRING)))

    (method %int (self (param s STRING "Decimal digits, optionally signed"))
      (doc "The integer a decimal field spells; nil when it spells none."
        (returns ANY "INTEGER, or nil"))
      (def at (prim-ref (lit str) (lit byte-ref)))
      (def n (Str8 length s))
      (def neg (if (> n 0) (= (at s 0) 45) #f))
      (def go
        (fn (self i acc)
          (match
            ((>= i n) acc)
            ((if (>= (at s i) 48) (<= (at s i) 57) #f)
              (self (+ i 1) (+ (* acc 10) (- (at s i) 48))))
            (#t acc))))
      (def start (if neg 1 0))
      (if (>= start n) ()
        (if (if (>= (at s start) 48) (<= (at s start) 57) #f)
          (let ((v (go start 0))) (if neg (- 0 v) v))
          ())))

    (method %read (self (param path STRING "A file under /proc"))
      (doc "The whole of a /proc file, or nil when it cannot be opened. /proc files stat as empty, so this reads to end of file rather than sizing by stat. Text only: a NUL ends the string."
        (returns ANY "STRING, or nil"))
      (def fd (File open path (lit rdonly)))
      (if (< fd 0) ()
        (let ((buf (Host %buf 4096)))
          (def go
            (fn (self acc)
              (def n (File read fd buf 4096))
              (if (> n 0) (self (pair (Str8 sub 0 n buf) acc)) acc)))
          (def parts (go ()))
          (File close fd)
          (Str8 join "" (List reverse parts)))))

    (method %fields (self (param s STRING "A line"))
      (doc "The line's fields, split on runs of spaces."
        (returns LIST "Field strings"))
      (List reject (fn (_ f) (str=? f "")) (Str8 split " " s)))

    (method %line-value (self (param lines LIST "Lines of a /proc file") (param key STRING "Leading word, e.g. \"btime\" or \"Cached:\""))
      (doc "The integer after a line's leading key, or nil when no line has it."
        (returns ANY "INTEGER, or nil"))
      (def hit (List find (fn (_ l) (Str8 starts? (Str8 append key " ") l)) lines))
      (if (null? hit) () (Host %int (first (rest (Host %fields hit))))))

    (method %lines (self (param name STRING "File under the /proc root"))
      (doc "A /proc file's lines, or nil when it cannot be read."
        (returns LIST "Line strings"))
      (def s (Host %read (Str8 append (Host proc-root) "/" name)))
      (if (null? s) () (Str8 split "\n" s)))

    (method %sysconf (self (param linux INTEGER "The name's number on Linux") (param darwin INTEGER "Its number on Darwin"))
      (doc "A sysconf value; the name numbers differ between the two libcs."
        (returns INTEGER "The value"))
      (Host %call "sysconf" (if os-darwin? darwin linux)))

    (method %hz (self)
      (doc "Clock ticks a second (_SC_CLK_TCK), the unit of /proc's CPU times."
        (returns INTEGER "Ticks a second"))
      (Host %sysconf 2 3))

    (method %ticks->ns (self (param t INTEGER "Clock ticks"))
      (doc "Clock ticks in nanoseconds."
        (returns INTEGER "Nanoseconds"))
      (/ (* t 1000000000) (Host %hz)))

    ; --- Linux: sysinfo(2) ----------------------------------------------------

    (method %sysinfo (self)
      (doc "struct sysinfo as an alist of the fields read here."
        (returns ALIST "uptime, three loads (scaled by 65536), memory fields in units, unit"))
      (def b (Host %buf 128))
      (if (< (Host %call "sysinfo" (Host %ptr b)) 0) ()
        (let ((unit (Host %int-at b 104 4)))
          (list (pair (lit uptime) (Host %int-at b 0 8))
                (pair (lit loads) (list (Host %int-at b 8 8) (Host %int-at b 16 8) (Host %int-at b 24 8)))
                (pair (lit totalram) (Host %int-at b 32 8)) (pair (lit freeram) (Host %int-at b 40 8))
                (pair (lit sharedram) (Host %int-at b 48 8)) (pair (lit bufferram) (Host %int-at b 56 8))
                (pair (lit totalswap) (Host %int-at b 64 8)) (pair (lit freeswap) (Host %int-at b 72 8))
                (pair (lit unit) (if (= unit 0) 1 unit))))))

    ; --- Darwin: sysctl -------------------------------------------------------

    (method %sysctl (self (param name STRING "A sysctl name, e.g. \"vm.loadavg\"") (param n INTEGER "Buffer size"))
      (doc "The value of a sysctl name as a region, or nil when the kernel refuses."
        (returns ANY "STRING region, or nil"))
      (def b (Host %buf n))
      (def len (Host %buf 8))
      ((prim-ref (lit ptr) (lit set-word!)) (Host %ptr len) 0 n)
      (if (< (Host %call "sysctlbyname" name (Host %ptr b) (Host %ptr len) 0 0) 0) () b))

    (method %sysctl-size (self (param name STRING "A sysctl name"))
      (doc "How many bytes the sysctl name's value currently needs."
        (returns INTEGER "Bytes, 0 when the kernel refuses"))
      (def len (Host %buf 8))
      (if (< (Host %call "sysctlbyname" name 0 (Host %ptr len) 0 0) 0) 0 (Host %int-at len 0 8)))

    (method %page-size (self)
      (doc "The page size (sysconf _SC_PAGESIZE), the unit of /proc's rss and of the Mach page counts."
        (returns INTEGER "Bytes"))
      (Host %sysconf 30 29))

    (method %mach-ns (self (param t INTEGER "Mach absolute time units"))
      (doc "Mach time units in nanoseconds, by mach_timebase_info."
        (returns INTEGER "Nanoseconds"))
      (def tb (Host %buf 8))
      (Host %call "mach_timebase_info" (Host %ptr tb))
      (/ (* t (Host %int-at tb 0 4)) (Host %int-at tb 4 4)))

    ; --- boot time and load ---------------------------------------------------

    (method boot-time (self)
      (doc "When the machine booted, in unix seconds. Linux answers now less sysinfo's uptime, as BusyBox's uptime -s does; Darwin answers kern.boottime."
        (returns INTEGER "Unix seconds")
        (sample "(Host boot-time)" "1790652922"))
      (if (eq? (Host %backend) (lit darwin))
        (Host %int-at (Host %sysctl "kern.boottime" 16) 0 8)
        (- (Sys now) (Assoc get (lit uptime) (Host %sysinfo)))))

    (method load (self)
      (doc "The 1, 5 and 15 minute load averages. Each is the kernel's fixed-point value divided by its scale, so it is exact: sysinfo's 65536 on Linux, vm.loadavg's fscale on Darwin."
        (returns LIST "Three floats")
        (sample "(Host load)" "(3.85 4.5 6.27)"))
      (if (eq? (Host %backend) (lit darwin))
        (Host %darwin-loads)
        (List map (fn (_ l) (Float / l 65536)) (Assoc get (lit loads) (Host %sysinfo)))))

    (method %darwin-loads (self)
      (doc "vm.loadavg's three averages, each divided by its fscale."
        (returns LIST "Three floats"))
      ; struct loadavg: three fixpt_t, then the long fscale at 16
      (def b (Host %sysctl "vm.loadavg" 24))
      (def scale (Host %int-at b 16 8))
      (list (Float / (Host %int-at b 0 4) scale)
            (Float / (Host %int-at b 4 4) scale)
            (Float / (Host %int-at b 8 4) scale)))

    ; --- memory ---------------------------------------------------------------

    (method memory (self)
      (doc "Memory and swap in bytes: total free shared buffers cached reclaimable available swap-total swap-free. Linux takes the totals from sysinfo and cached (Cached), reclaimable (SReclaimable) and available (MemAvailable) from /proc/meminfo, as BusyBox's free does. Darwin takes total from hw.memsize, free and cached (file-backed pages) from the Mach VM statistics and swap from vm.swapusage; it reports no shared, buffers, reclaimable or available."
        (returns ALIST "((total . N) (free . N) ... (swap-free . N)); a field not reported is nil")
        (sample "(Assoc get 'total (Host memory))" "17179869184"))
      (if (eq? (Host %backend) (lit darwin)) (Host %darwin-memory) (Host %linux-memory)))

    (method %linux-memory (self)
      (doc "memory, from sysinfo and /proc/meminfo."
        (returns ALIST "The memory record"))
      (def si (Host %sysinfo))
      (def u (Assoc get (lit unit) si))
      (def m (Host %lines "meminfo"))
      (def kb (fn (_ key) (let ((v (Host %line-value m key))) (if (null? v) () (* v 1024)))))
      (list (pair (lit total) (* u (Assoc get (lit totalram) si)))
            (pair (lit free) (* u (Assoc get (lit freeram) si)))
            (pair (lit shared) (* u (Assoc get (lit sharedram) si)))
            (pair (lit buffers) (* u (Assoc get (lit bufferram) si)))
            (pair (lit cached) (kb "Cached:"))
            (pair (lit reclaimable) (kb "SReclaimable:"))
            (pair (lit available) (kb "MemAvailable:"))
            (pair (lit swap-total) (* u (Assoc get (lit totalswap) si)))
            (pair (lit swap-free) (* u (Assoc get (lit freeswap) si)))))

    (method %darwin-memory (self)
      (doc "memory, from sysctl and host_statistics64 (HOST_VM_INFO64)."
        (returns ALIST "The memory record"))
      (def page (Host %page-size))
      (def vm (Host %buf 416))
      (def count (Host %buf 8))
      ((prim-ref (lit ptr) (lit set-word!)) (Host %ptr count) 0 104)
      (def ok (= 0 (Host %call "host_statistics64" (Host %call "mach_host_self") 4
                     (Host %ptr vm) (Host %ptr count))))
      (def swap (Host %sysctl "vm.swapusage" 32))
      (list (pair (lit total) (Host %int-at (Host %sysctl "hw.memsize" 8) 0 8))
            (pair (lit free) (if ok (* page (Host %int-at vm 0 4)) ()))
            (pair (lit shared) ()) (pair (lit buffers) ())
            (pair (lit cached) (if ok (* page (Host %int-at vm 136 4)) ()))
            (pair (lit reclaimable) ()) (pair (lit available) ())
            (pair (lit swap-total) (if (null? swap) () (Host %int-at swap 0 8)))
            (pair (lit swap-free) (if (null? swap) () (Host %int-at swap 8 8)))))

    ; --- CPU time -------------------------------------------------------------

    (method cpu (self)
      (doc "CPU time since boot across all processors, in nanoseconds: user nice system idle iowait irq softirq steal. Linux reads /proc/stat's cpu line; Darwin reads HOST_CPU_LOAD_INFO, which reports the first four. Differences between two readings give the percentages top shows."
        (returns ALIST "((user . NS) (nice . NS) ... (steal . NS)); a field not reported is nil")
        (sample "(Assoc get 'idle (Host cpu))" "1566821170000000"))
      (def keys (list (lit user) (lit nice) (lit system) (lit idle)
                      (lit iowait) (lit irq) (lit softirq) (lit steal)))
      (def ticks
        (if (eq? (Host %backend) (lit darwin))
          (Host %darwin-ticks)
          (let ((hit (List find (fn (_ l) (Str8 starts? "cpu " l)) (Host %lines "stat"))))
            (if (null? hit) () (List map (fn (_ f) (Host %int f)) (rest (Host %fields hit)))))))
      (def go
        (fn (self ks ts)
          (if (null? ks) ()
            (pair (pair (first ks) (if (null? ts) () (Host %ticks->ns (first ts))))
                  (self (rest ks) (if (null? ts) () (rest ts)))))))
      (go keys ticks))

    (method %darwin-ticks (self)
      (doc "HOST_CPU_LOAD_INFO's ticks, in cpu's order: user, nice, system, idle."
        (returns LIST "Four tick counts"))
      (def b (Host %buf 16))
      (def count (Host %buf 8))
      ((prim-ref (lit ptr) (lit set-word!)) (Host %ptr count) 0 4)
      (Host %call "host_statistics" (Host %call "mach_host_self") 3 (Host %ptr b) (Host %ptr count))
      ; the kernel's order is CPU_STATE_USER, SYSTEM, IDLE, NICE
      (list (Host %int-at b 0 4) (Host %int-at b 12 4) (Host %int-at b 4 4) (Host %int-at b 8 4)))

    ; --- processes ------------------------------------------------------------

    (method processes (self)
      (doc "Every process, one record each: pid ppid pgid sid uid gid ruid rgid state comm tty tty-major tty-minor nice start threads vsz rss utime stime. uid and gid are the effective ids, ruid and rgid the real ones. state is a Linux state letter (R S D T Z); start is unix seconds; vsz and rss are bytes; utime and stime are nanoseconds; tty is the terminal's device number, nil for none, and tty-major and tty-minor its two halves as this kernel packs them. Darwin answers state (unless zombie or stopped), threads, vsz, rss, utime and stime only for this user's processes unless running as root."
        (returns LIST "Process records")
        (sample "(List length (Host processes))" "772"))
      (if (eq? (Host %backend) (lit darwin)) (Host %darwin-processes) (Host %linux-processes)))

    (method process (self (param pid INTEGER "Process ID"))
      (doc "One process's record, as processes gives it, or nil when there is no such process."
        (returns ANY "A process record, or nil")
        (sample "(Assoc get 'comm (Host process 1))" "\"launchd\""))
      (if (eq? (Host %backend) (lit darwin))
        (let ((b (Host %sysctl-mib (list 1 14 1 pid) 648)))
          (if (null? b) () (Host %darwin-record (first b) 0)))
        (Host %linux-record (Host %linux-btime) (Str8 str pid))))

    (method args (self (param pid INTEGER "Process ID"))
      (doc "The process's argument vector, or nil when the kernel will not give it: a kernel thread on Linux, another user's process on Darwin."
        (returns ANY "LIST of strings, or nil")
        (sample "(Host args (Sys getpid))" "(\"x-bin\" \"--batch\")"))
      (if (eq? (Host %backend) (lit darwin)) (Host %darwin-args pid) (Host %linux-args pid)))

    (method %linux-btime (self)
      (doc "The boot time /proc/stat records, the base of a process's start time."
        (returns INTEGER "Unix seconds"))
      (Host %line-value (Host %lines "stat") "btime"))

    (method %linux-processes (self)
      (doc "processes, from /proc/PID/stat; a process that exits mid-walk is left out."
        (returns LIST "Process records"))
      (def btime (Host %linux-btime))
      (def pids (List filter (fn (_ name) (not (null? (Host %int name))))
                  (File list-dir (Host proc-root))))
      (List reject null? (List map (fn (_ name) (Host %linux-record btime name)) pids)))

    (method %linux-record (self (param btime INTEGER "Boot time, unix seconds") (param name STRING "The pid, as its /proc directory is named"))
      (doc "One process's record from /proc/PID/stat, or nil when it is gone. comm is read between the first ( and the last ), since a name may hold either."
        (returns ANY "A process record, or nil"))
      (def dir (Str8 append (Host proc-root) "/" name))
      (def s (Host %read (Str8 append dir "/stat")))
      (if (null? s) ()
        (let ((open (Str8 index-of "(" s)) (close (Str8 last-index-of ")" s)))
          (def f (Host %fields (Str8 sub (+ close 2) (Str8 length s) s)))
          (def at (fn (_ i) (Host %int (List ref i f))))
          (def tty (at 4))
          (def owner (Host %owner dir))
          (def real (Host %real-ids dir))
          (list (pair (lit pid) (Host %int name))
                (pair (lit ppid) (at 1))
                (pair (lit pgid) (at 2))
                (pair (lit sid) (at 3))
                (pair (lit uid) (if (null? owner) () (first owner)))
                (pair (lit gid) (if (null? owner) () (rest owner)))
                (pair (lit ruid) (if (null? real) () (first real)))
                (pair (lit rgid) (if (null? real) () (rest real)))
                (pair (lit state) (Str8 sub 0 1 (first f)))
                (pair (lit comm) (Str8 sub (+ open 1) (- close (+ open 1)) s))
                (pair (lit tty) (if (= tty 0) () tty))
                ; tty_nr: the major in bits 8-19, the minor in 0-7 and 20-31
                (pair (lit tty-major) (if (= tty 0) () (& (>> tty 8) 4095)))
                (pair (lit tty-minor) (if (= tty 0) () (| (& tty 255) (& (>> tty 12) 1048320))))
                (pair (lit nice) (at 16))
                (pair (lit start) (+ btime (/ (at 19) (Host %hz))))
                (pair (lit threads) (at 17))
                (pair (lit vsz) (at 20))
                (pair (lit rss) (* (at 21) (Host %page-size)))
                (pair (lit utime) (Host %ticks->ns (at 11)))
                (pair (lit stime) (Host %ticks->ns (at 12)))))))

    (method %owner (self (param path STRING "A /proc/PID directory"))
      (doc "The uid and gid owning a path, as BusyBox's ps reads a process's user and group."
        (returns ANY "PAIR (uid . gid), or nil"))
      (def b (Host %buf 160))
      (if (< ((syscall-door (if os-darwin? (lit stat64) (lit stat))) path b) 0) ()
        (let ((st (Struct unpack stat-layout b)))
          (pair (Assoc get (lit uid) st) (Assoc get (lit gid) st)))))

    (method %real-ids (self (param dir STRING "A /proc/PID directory"))
      (doc "The real uid and gid, the first number of /proc/PID/status's Uid: and Gid: lines, as BusyBox's ps reads ruser and rgroup."
        (returns ANY "PAIR (ruid . rgid), or nil"))
      (def s (Host %read (Str8 append dir "/status")))
      (def first-of
        (fn (_ key)
          (def hit (List find (fn (_ l) (Str8 starts? key l)) (Str8 split "\n" s)))
          (if (null? hit) ()
            (Host %int (Str8 trim (Str8 sub (Str8 length key) (Str8 length hit) hit))))))
      (if (null? s) ()
        (let ((u (first-of "Uid:")) (g (first-of "Gid:")))
          (if (if (null? u) #t (null? g)) () (pair u g)))))

    (method %linux-args (self (param pid INTEGER "Process ID"))
      (doc "args, from /proc/PID/cmdline: the strings between its NUL bytes, split as each read lands, since a string holding a NUL cannot be carried whole."
        (returns ANY "LIST of strings, or nil"))
      (def fd (File open (Str8 append (Host proc-root) "/" (Str8 str pid) "/cmdline") (lit rdonly)))
      (if (< fd 0) ()
        (let ((buf (Host %buf 4096)) (at (prim-ref (lit str) (lit byte-ref))))
          ; one read's bytes onto (cur . done): cur is the argument being
          ; built, reversed bytes; done the finished ones, reversed
          (def chunk
            (fn (self i n cur done)
              (match
                ((>= i n) (pair cur done))
                ((= (at buf i) 0) (self (+ i 1) n () (pair (bytes->str (List reverse cur)) done)))
                (#t (self (+ i 1) n (pair (at buf i) cur) done)))))
          (def go
            (fn (self cur done)
              (def n (File read fd buf 4096))
              (if (> n 0)
                (let ((r (chunk 0 n cur done))) (self (first r) (rest r)))
                (List reverse (if (null? cur) done (pair (bytes->str (List reverse cur)) done))))))
          (def r (go () ()))
          (File close fd)
          (if (null? r) () r))))

    (method %nul-split (self (param s STRING "Bytes holding NUL-terminated strings")
                             (param from INTEGER "Where to start") (param end INTEGER "Where to stop")
                             (param most INTEGER "Most strings to take"))
      (doc "The first most NUL-terminated strings between from and end."
        (returns LIST "Strings"))
      (def go
        (fn (self i k acc)
          (if (if (>= i end) #t (>= k most)) (List reverse acc)
            (let ((piece (Host %cstr-at s i (- end i))))
              (self (+ i (Str8 length piece) 1) (+ k 1) (pair piece acc))))))
      (go from 0 ()))

    (method %sysctl-mib (self (param mib LIST "The name as integers") (param n INTEGER "Buffer size"))
      (doc "A sysctl value by numeric name, as (region . length), or nil when the kernel refuses or answers nothing (no such process)."
        (returns ANY "PAIR (region . length), or nil"))
      (def set (prim-ref (lit ptr) (lit set!)))
      (def name (Host %buf (* 4 (List length mib))))
      (List for-each
        (fn (_ i) (set (Host %ptr name) (* 4 i) (List ref i mib) 4))
        (List range 0 (List length mib)))
      (def b (Host %buf n))
      (def len (Host %buf 8))
      ((prim-ref (lit ptr) (lit set-word!)) (Host %ptr len) 0 n)
      (if (< (Host %call "sysctl" (Host %ptr name) (List length mib) (Host %ptr b) (Host %ptr len) 0 0) 0) ()
        (let ((got (Host %int-at len 0 8))) (if (= 0 got) () (pair b got)))))

    (method %darwin-processes (self)
      (doc "processes, from kern.proc.all and proc_pidinfo. The table is asked for its size first and given room for a few more processes, since it can grow between the two calls."
        (returns LIST "Process records"))
      (def need (+ (Host %sysctl-size "kern.proc.all") (* 64 648)))
      (def len (Host %buf 8))
      (def b (Host %buf need))
      ((prim-ref (lit ptr) (lit set-word!)) (Host %ptr len) 0 need)
      (if (< (Host %call "sysctlbyname" "kern.proc.all" (Host %ptr b) (Host %ptr len) 0 0) 0) ()
        (List map (fn (_ i) (Host %darwin-record b (* i 648)))
          (List range 0 (/ (Host %int-at len 0 8) 648)))))

    (method %darwin-record (self (param b STRING "kinfo_proc rows") (param o INTEGER "This row's offset"))
      (doc "One process's record from its kinfo_proc row, with proc_pidinfo's task info where the kernel gives it. state is Z or T from p_stat (SZOMB, SSTOP); otherwise p_stat reads SRUN for nearly every process, so R or S comes from the task info's running-thread count, as Darwin's ps decides it, and is nil where the task info is refused."
        (returns ALIST "A process record"))
      (def pid (Host %int-at b (+ o 40) 4))
      (def stat (Host %int-at b (+ o 36) 1))
      (def tdev (Host %signed-at b (+ o 572) 4))
      (def ti (Host %buf 96))
      (def ok (= 96 (Host %call "proc_pidinfo" pid 4 0 (Host %ptr ti) 96)))
      (def task (fn (_ off n) (if ok (Host %int-at ti off n) ())))
      (def sid (Host %call "getsid" pid))
      (list (pair (lit pid) pid)
            (pair (lit ppid) (Host %int-at b (+ o 560) 4))
            (pair (lit pgid) (Host %int-at b (+ o 564) 4))
            (pair (lit sid) (if (< sid 0) () sid))
            ; e_ucred's uid and first group are the effective ids; e_pcred
            ; holds the real ones
            (pair (lit uid) (Host %int-at b (+ o 420) 4))
            (pair (lit gid) (Host %int-at b (+ o 428) 4))
            (pair (lit ruid) (Host %int-at b (+ o 392) 4))
            (pair (lit rgid) (Host %int-at b (+ o 400) 4))
            (pair (lit state) (match ((= stat 5) "Z") ((= stat 4) "T") ((not ok) ()) ((> (task 88 4) 0) "R") (#t "S")))
            (pair (lit comm) (Host %cstr-at b (+ o 243) 17))
            (pair (lit tty) (if (= tdev -1) () tdev))
            ; dev_t: the major in the top 8 bits, the minor in the low 24
            (pair (lit tty-major) (if (= tdev -1) () (& (>> tdev 24) 255)))
            (pair (lit tty-minor) (if (= tdev -1) () (& tdev 16777215)))
            (pair (lit nice) (Host %signed-at b (+ o 242) 1))
            (pair (lit start) (Host %int-at b o 8))
            (pair (lit threads) (task 84 4))
            (pair (lit vsz) (task 0 8))
            (pair (lit rss) (task 8 8))
            (pair (lit utime) (if ok (Host %mach-ns (task 16 8)) ()))
            (pair (lit stime) (if ok (Host %mach-ns (task 24 8)) ()))))

    (method %darwin-args (self (param pid INTEGER "Process ID"))
      (doc "args, from kern.procargs2: argc, the executable's path, padding NULs, then the argc strings."
        (returns ANY "LIST of strings, or nil"))
      (def max (Host %int-at (Host %sysctl "kern.argmax" 4) 0 4))
      (def got (Host %sysctl-mib (list 1 49 pid) max))
      (if (null? got) ()
        (let ((b (first got)) (end (rest got)) (at (prim-ref (lit str) (lit byte-ref))))
          (def skip-path (fn (self i) (if (if (< i end) (> (at b i) 0) #f) (self (+ i 1)) i)))
          (def skip-nuls (fn (self i) (if (if (< i end) (= (at b i) 0) #f) (self (+ i 1)) i)))
          (Host %nul-split b (skip-nuls (skip-path 4)) end (Host %int-at b 0 4)))))

    ; --- users ----------------------------------------------------------------

    (method users (self)
      (doc "The logged-in sessions, from libc's utmpx database (setutxent/getutxent, as BusyBox reads it): user tty host time pid, for each USER_PROCESS entry with a user name. time is the login, in unix seconds."
        (returns LIST "Session records")
        (sample "(List map (fn (_ u) (Assoc get 'tty u)) (Host users))" "(\"console\" \"ttys000\")"))
      ; struct utmpx, (field offset width): Darwin's and glibc's differ
      (def lay
        (if os-darwin?
          (lit ((type 296 2) (pid 292 4) (line 260 32) (user 0 256) (host 320 256) (sec 304 8)))
          (lit ((type 0 2) (pid 4 4) (line 8 32) (user 44 32) (host 76 256) (sec 340 4)))))
      (def row (fn (_ k) (rest (Assoc entry k lay))))
      ; getutxent answers its record's address as an integer, 0 at the end
      (def cvt (prim-ref (lit convert) (lit to)))
      (def ->ptr (fn (_ a) (cvt a (Type named POINTER))))
      (def int-at (fn (_ p k) (def r (row k)) ((prim-ref (lit ptr) (lit ref)) (->ptr p) (first r) (first (rest r)))))
      (def str-at (fn (_ p k)
        (def r (row k))
        (def s (Host %cstr-ptr (->ptr (+ p (first r)))))
        (if (> (Str8 length s) (first (rest r))) (Str8 sub 0 (first (rest r)) s) s)))
      (Host %call "setutxent")
      (def go
        (fn (self acc)
          (def p ((prim-ref (lit ptr) (lit call)) (Host %sym "getutxent")))
          (if (= 0 p) (List reverse acc)
            (self
              (if (if (= 7 (int-at p (lit type))) (not (str=? "" (str-at p (lit user)))) #f)
                (pair (list (pair (lit user) (str-at p (lit user)))
                            (pair (lit tty) (str-at p (lit line)))
                            (pair (lit host) (str-at p (lit host)))
                            (pair (lit time) (int-at p (lit sec)))
                            (pair (lit pid) (int-at p (lit pid))))
                      acc)
                acc)))))
      (def all (go ()))
      (Host %call "endutxent")
      all)))

(doc (provide x/sys/host Host)
  (note "Linux reads sysinfo(2) and /proc; Darwin reads sysctl, the Mach host statistics and proc_pidinfo over the dlopen FFI; both read utmpx through libc.")
  (sample "(Host load)" "(3.85 4.5 6.27)")
  "Host: boot time, load, memory, CPU time, processes and users, the same records on Linux and Darwin.")
