; host.x -- Host: what the running kernel reports about the machine
;
; Boot time, load, memory, CPU time, the system-wide counters, disk,
; network and interrupt totals, the process table and the logged-in users,
; as records that read the same on Linux and Darwin.  Programs such as
; uptime, free, ps, top, vmstat and iostat format these and never ask which
; kernel answered.
;
; Linux reads what BusyBox reads: sysinfo(2) for uptime, load and the
; memory totals; /proc/meminfo for cached, reclaimable and available;
; /proc/stat for CPU time, the boot time and the event counts; /proc/vmstat
; for paging; /proc/loadavg for the run queue; /proc/diskstats,
; /proc/net/dev, /proc/interrupts and /proc/softirqs for the devices;
; /proc/PID/stat for a process, /proc/PID/task for its threads and
; /proc/PID/smaps for its mappings.  Darwin reads sysctl (kern.boottime,
; vm.loadavg, hw.memsize, vm.swapusage, kern.proc.all, kern.procargs2,
; NET_RT_IFLIST2), the Mach host and processor statistics, IOKit's block
; storage statistics and proc_pidinfo, all through the dlopen FFI.  Both
; read utmpx through libc's getutxent, as BusyBox does.
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
  (doc "The machine as the kernel reports it: boot time, load, memory, CPU time, system-wide counters, disk, network and interrupt totals, processes and logged-in users, the same records on Linux and Darwin."
    (note "A field the kernel does not report is nil. Darwin reports another user's process memory and CPU time only to root.")
    (see boot-time) (see load) (see tasks) (see memory) (see cpu) (see cpus) (see counters) (see disks) (see interfaces) (see interrupts) (see processes) (see process) (see args) (see exe) (see threads) (see maps) (see utmp) (see users))
  (static
    (source    ()      "'linux or 'darwin: which reader answers; nil means this kernel's")
    (proc-root "/proc" "The /proc tree the Linux reader opens")
    (types     ()      "The STRING, POINTER and INTEGER type handles, once %types has looked them up")
    (ctx       ()      "What %darwin-ctx resolves, once it has; cleared when an image is loaded")

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

    (method %types (self)
      (doc "The STRING, POINTER and INTEGER type handles, looked up once: a (Type named) lookup costs tens of thousands of objects, and a C string is read for every argument of every process."
        (returns LIST "(STRING POINTER INTEGER)"))
      (when (null? (Host types))
        (Host types (list (Type named STRING) (Type named POINTER) (Type named INTEGER))))
      (Host types))

    (method %cstr-at (self (param buf STRING "A region") (param off INTEGER "Byte offset")
                           (param n INTEGER "Most bytes to read"))
      (doc "The NUL-terminated string at off, at most n bytes. Read through its address: a region's own length stops at its first NUL, so a substring of it cannot reach past one."
        (returns STRING "The string"))
      (def cvt (prim-ref (lit convert) (lit to)))
      (def t (Host %types))
      (def at (cvt (+ (cvt ((prim-ref (lit str) (lit ->ptr)) buf) (first (rest (rest t)))) off) (first (rest t))))
      (def s (cvt at (first t)))
      ; the primitives, not Str8: s is a C string, so its byte length is its
      ; length, and a Str8 call on it costs a hundred thousand objects
      (if (> ((prim-ref (lit str) (lit byte-len)) s) n) ((prim-ref (lit str) (lit byte-sub)) s 0 n) s))

    (method %cstr-ptr (self (param p POINTER "Address of a NUL-terminated string"))
      (doc "The C string at an address."
        (returns STRING "The string"))
      ((prim-ref (lit convert) (lit to)) p (first (Host %types))))
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

    (method %hex (self (param s STRING "Hexadecimal digits"))
      (doc "The integer a run of hex digits spells, read up to the first byte that is not one; 0 for none."
        (returns INTEGER "The value"))
      (def at (prim-ref (lit str) (lit byte-ref)))
      (def n ((prim-ref (lit str) (lit byte-len)) s))
      (def digit
        (fn (_ b)
          (match
            ((if (>= b 48) (<= b 57) #f) (- b 48))
            ((if (>= b 97) (<= b 102) #f) (- b 87))
            ((if (>= b 65) (<= b 70) #f) (- b 55))
            (#t ()))))
      (def go
        (fn (self i acc)
          (if (>= i n) acc
            (let ((d (digit (at s i))))
              (if (null? d) acc (self (+ i 1) (+ (* acc 16) d)))))))
      (go 0 0))

    (method %fold-lines (self (param path STRING "A file") (param f CALLABLE "(f line acc) answers the next acc; line has no newline")
                              (param init ANY "The first acc"))
      (doc "Fold f over a file's lines, read a piece at a time, so a long /proc file is never held whole."
        (returns ANY "The last acc, or nil when the file cannot be opened"))
      (def fd (File open path (lit rdonly)))
      (if (< fd 0) ()
        (let ((buf (Host %buf 4096)))
          ; the lines of one piece, all but its last, which the next piece may finish
          (def most
            (fn (me ps acc) (if (null? (rest ps)) (pair (first ps) acc) (me (rest ps) (f (first ps) acc)))))
          ; carry is the start of a line the last piece cut off
          (def go
            (fn (self carry acc)
              (def n (File read fd buf 4096))
              (if (<= n 0)
                (if (str=? carry "") acc (f carry acc))
                (let ((r (most (Str8 split "\n" (Str8 append carry (Str8 sub 0 n buf))) acc)))
                  (self (first r) (rest r))))))
          (def r (go "" init))
          (File close fd)
          r)))

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
      ; the int door: the tower's / would answer a fraction for a timebase like 125/3
      ((prim-ref (lit int) (lit /)) (* t (Host %int-at tb 0 4)) (Host %int-at tb 4 4)))

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

    (method tasks (self)
      (doc "The scheduler's counts: running (entities runnable now), total (entities that exist) and last-pid (the pid most recently handed out). Linux reads /proc/loadavg's fourth and fifth fields, which top prints after the load averages; Darwin reports none of them."
        (returns ALIST "((running . N) (total . N) (last-pid . N)); a field not reported is nil")
        (sample "(Assoc get 'running (Host tasks))" "2"))
      (def record
        (fn (_ running total last)
          (list (pair (lit running) running) (pair (lit total) total) (pair (lit last-pid) last))))
      (def s (if (eq? (Host %backend) (lit darwin)) ()
               (Host %read (Str8 append (Host proc-root) "/loadavg"))))
      (def f (if (null? s) () (Host %fields (first (Str8 split "\n" s)))))
      (if (< (List length f) 5) (record () () ())
        (let ((rt (Str8 split "/" (List ref 3 f))))
          (record (Host %int (first rt))
                  (if (null? (rest rt)) () (Host %int (first (rest rt))))
                  (Host %int (List ref 4 f))))))

    ; --- memory ---------------------------------------------------------------

    (method memory (self)
      (doc "Memory and swap in bytes: total free shared buffers cached reclaimable available swap-total swap-free anon mapped slab dirty writeback. Linux takes the totals from sysinfo and cached (Cached), reclaimable (SReclaimable), available (MemAvailable), anon (AnonPages), mapped (Mapped), slab (Slab), dirty (Dirty) and writeback (Writeback) from /proc/meminfo, as BusyBox's free and top -m do. Darwin takes total from hw.memsize, free, cached (file-backed pages) and anon (anonymous pages) from the Mach VM statistics and swap from vm.swapusage; it reports no shared, buffers, reclaimable, available, mapped, slab, dirty or writeback."
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
            (pair (lit swap-free) (* u (Assoc get (lit freeswap) si)))
            (pair (lit anon) (kb "AnonPages:"))
            (pair (lit mapped) (kb "Mapped:"))
            (pair (lit slab) (kb "Slab:"))
            (pair (lit dirty) (kb "Dirty:"))
            (pair (lit writeback) (kb "Writeback:"))))

    (method %darwin-memory (self)
      (doc "memory, from sysctl and host_statistics64 (HOST_VM_INFO64)."
        (returns ALIST "The memory record"))
      (def page (Host %page-size))
      (def vm (Host %darwin-vm))
      (def ok (not (null? vm)))
      (def swap (Host %sysctl "vm.swapusage" 32))
      (list (pair (lit total) (Host %int-at (Host %sysctl "hw.memsize" 8) 0 8))
            (pair (lit free) (if ok (* page (Host %int-at vm 0 4)) ()))
            (pair (lit shared) ()) (pair (lit buffers) ())
            (pair (lit cached) (if ok (* page (Host %int-at vm 136 4)) ()))
            (pair (lit reclaimable) ()) (pair (lit available) ())
            (pair (lit swap-total) (if (null? swap) () (Host %int-at swap 0 8)))
            (pair (lit swap-free) (if (null? swap) () (Host %int-at swap 8 8)))
            ; internal_page_count, the anonymous pages
            (pair (lit anon) (if ok (* page (Host %int-at vm 140 4)) ()))
            (pair (lit mapped) ()) (pair (lit slab) ()) (pair (lit dirty) ()) (pair (lit writeback) ())))

    (method %darwin-vm (self)
      (doc "host_statistics64's HOST_VM_INFO64, a struct vm_statistics64, or nil when the kernel refuses."
        (returns ANY "STRING region, or nil"))
      (def vm (Host %buf 416))
      (def count (Host %buf 8))
      ((prim-ref (lit ptr) (lit set-word!)) (Host %ptr count) 0 104)
      (if (= 0 (Host %call "host_statistics64" (Host %call "mach_host_self") 4
                 (Host %ptr vm) (Host %ptr count)))
        vm ()))

    ; --- system-wide counters -------------------------------------------------

    (method counters (self)
      (doc "The kernel's running totals since boot: context-switches interrupts softirqs forks running blocked paged-in paged-out swap-ins swap-outs faults major-faults open-files max-files. running and blocked are the processes runnable now and waiting on I/O now (the running count includes the reader); paged-in and paged-out are bytes; swap-ins and swap-outs are pages; open-files is the file handles in use and max-files the kernel's limit. Linux reads /proc/stat (ctxt intr softirq processes procs_running procs_blocked), /proc/vmstat (pgpgin pgpgout pswpin pswpout pgfault pgmajfault) and /proc/sys/fs/file-nr, as BusyBox's vmstat and nmeter do. Darwin reads the Mach VM statistics (pageins pageouts swapins swapouts faults) and kern.num_files and kern.maxfiles; it reports no context switches, interrupts, softirqs, forks, run queue or major faults. Differences between two readings give the rates vmstat shows."
        (returns ALIST "((context-switches . N) (interrupts . N) ... (max-files . N)); a field not reported is nil")
        (sample "(< 0 (Assoc get 'faults (Host counters)))" "#t"))
      (if (eq? (Host %backend) (lit darwin)) (Host %darwin-counters) (Host %linux-counters)))

    (method %linux-counters (self)
      (doc "counters, from /proc/stat, /proc/vmstat and /proc/sys/fs/file-nr."
        (returns ALIST "The counters record"))
      (def st (Host %lines "stat"))
      (def vm (Host %lines "vmstat"))
      (def from-vm (fn (_ k) (Host %line-value vm k)))
      ; pgpgin and pgpgout count KiB
      (def kb (fn (_ k) (let ((v (from-vm k))) (if (null? v) () (* v 1024)))))
      ; file-nr: allocated, allocated but unused, the maximum; tab-separated
      (def nr (let ((s (Host %read (Str8 append (Host proc-root) "/sys/fs/file-nr"))))
                (if (null? s) () (List map (fn (_ f) (Host %int f)) (Host %fields (Str8 join " " (Str8 split "\t" (Str8 trim s))))))))
      (def files (if (< (List length nr) 3) () nr))
      (list (pair (lit context-switches) (Host %line-value st "ctxt"))
            (pair (lit interrupts) (Host %line-value st "intr"))
            (pair (lit softirqs) (Host %line-value st "softirq"))
            (pair (lit forks) (Host %line-value st "processes"))
            (pair (lit running) (Host %line-value st "procs_running"))
            (pair (lit blocked) (Host %line-value st "procs_blocked"))
            (pair (lit paged-in) (kb "pgpgin"))
            (pair (lit paged-out) (kb "pgpgout"))
            (pair (lit swap-ins) (from-vm "pswpin"))
            (pair (lit swap-outs) (from-vm "pswpout"))
            (pair (lit faults) (from-vm "pgfault"))
            (pair (lit major-faults) (from-vm "pgmajfault"))
            (pair (lit open-files) (if (null? files) () (- (first files) (first (rest files)))))
            (pair (lit max-files) (if (null? files) () (first (rest (rest files)))))))

    (method %darwin-counters (self)
      (doc "counters, from host_statistics64's HOST_VM_INFO64 and sysctl."
        (returns ALIST "The counters record"))
      (def page (Host %page-size))
      (def vm (Host %darwin-vm))
      ; struct vm_statistics64: pageins at 32, pageouts 40, faults 48, swapins
      ; 112, swapouts 120, each a 64-bit count of pages
      (def at (fn (_ off) (if (null? vm) () (Host %int-at vm off 8))))
      (def bytes (fn (_ off) (if (null? vm) () (* page (at off)))))
      (def int (fn (_ name) (let ((b (Host %sysctl name 4))) (if (null? b) () (Host %int-at b 0 4)))))
      (list (pair (lit context-switches) ()) (pair (lit interrupts) ()) (pair (lit softirqs) ())
            (pair (lit forks) ()) (pair (lit running) ()) (pair (lit blocked) ())
            (pair (lit paged-in) (bytes 32))
            (pair (lit paged-out) (bytes 40))
            (pair (lit swap-ins) (at 112))
            (pair (lit swap-outs) (at 120))
            (pair (lit faults) (at 48))
            (pair (lit major-faults) ())
            (pair (lit open-files) (int "kern.num_files"))
            (pair (lit max-files) (int "kern.maxfiles"))))

    (method interrupts (self)
      (doc "The interrupt counts since boot, one record a source: name counts total description soft?. name is the kernel's label (an IRQ number, or NMI, LOC, TIMER and the like); counts pairs each processor's number with its count, nil for a source the kernel counts only once; total is their sum; description is the rest of the line (controller, trigger, devices), nil when there is none; soft? is #t for a softirq. Linux reads /proc/interrupts and then /proc/softirqs, as BusyBox's mpstat -I does. Darwin reports none, and answers nil."
        (returns ANY "LIST of interrupt records, or nil")
        (sample "(Assoc get 'name (first (Host interrupts)))" "\"0\""))
      (if (eq? (Host %backend) (lit darwin)) ()
        (List append (Host %irq-table "interrupts" #f) (Host %irq-table "softirqs" #t))))

    (method %irq-table (self (param name STRING "interrupts or softirqs, under the /proc root")
                             (param soft BOOL "Whether its sources are softirqs"))
      (doc "The records of one /proc interrupt table: a header naming the processors (CPU0 CPU1 ...), then a line a source, NAME: then a count a processor."
        (returns LIST "Interrupt records"))
      (def ls (Host %lines name))
      (if (null? ls) ()
        (let ((columns (List map (fn (_ f) (Host %int (Str8 sub 3 (- (Str8 length f) 3) f)))
                      (Host %fields (first ls)))))
          (def n (List length columns))
          ; the leading counts of a line's fields, at most n: (counts . rest)
          (def take
            (fn (self fs k acc)
              (if (if (null? fs) #t (if (>= k n) #t (not (Host %digits? (first fs)))))
                (pair (List reverse acc) fs)
                (self (rest fs) (+ k 1) (pair (Host %int (first fs)) acc)))))
          (def one
            (fn (_ l)
              (def colon (Str8 index-of ":" l))
              (if (null? colon) ()
                (let ((r (take (Host %fields (Str8 sub (+ colon 1) (- (Str8 length l) (+ colon 1)) l)) 0 ())))
                  (def counts (first r))
                  (list (pair (lit name) (Str8 trim (Str8 sub 0 colon l)))
                        (pair (lit counts) (if (= (List length counts) n) (List zip columns counts) ()))
                        (pair (lit total) (List fold + 0 counts))
                        (pair (lit description) (if (null? (rest r)) () (Str8 join " " (rest r))))
                        (pair (lit soft?) soft))))))
          (List reject null? (List map one (rest ls))))))

    (method %digits? (self (param s STRING "A field"))
      (doc "Whether a field is all decimal digits, and at least one."
        (returns BOOL "#t or #f"))
      (def at (prim-ref (lit str) (lit byte-ref)))
      (def n ((prim-ref (lit str) (lit byte-len)) s))
      (def go (fn (self i) (if (>= i n) #t (if (if (>= (at s i) 48) (<= (at s i) 57) #f) (self (+ i 1)) #f))))
      (if (= n 0) #f (go 0)))

    (method disks (self)
      (doc "The block devices' I/O totals since boot, one record a device: name major minor reads reads-merged read-bytes read-time writes writes-merged write-bytes write-time in-flight io-time queue-time. Times are nanoseconds: read-time and write-time the time spent on each, io-time the time the device was busy, queue-time the busy time weighted by the requests in flight. Linux reads /proc/diskstats, as BusyBox's iostat and nmeter do, every device and partition it lists (a sector there is 512 bytes); an old kernel's four-figure partition line gives only reads, read-bytes, writes and write-bytes. Darwin reads each IOBlockStorageDriver's Statistics through IOKit, named by its media's BSD name, and reports no merges, in-flight, io-time or queue-time."
        (returns LIST "Disk records")
        (sample "(Assoc get 'name (first (Host disks)))" "\"disk0\""))
      (if (eq? (Host %backend) (lit darwin)) (Host %darwin-disks) (Host %linux-disks)))

    (method %disk-record (self (param name STRING "Device name") (param v LIST "major minor and the twelve totals, in disks' order"))
      (doc "The disk record for a name and its figures."
        (returns ALIST "The disk record"))
      (def go (fn (self ks vs) (if (null? ks) () (pair (pair (first ks) (if (null? vs) () (first vs))) (self (rest ks) (if (null? vs) () (rest vs)))))))
      (pair (pair (lit name) name)
        (go (lit (major minor reads reads-merged read-bytes read-time writes writes-merged write-bytes
                  write-time in-flight io-time queue-time))
            v)))

    (method %linux-disks (self)
      (doc "disks, from /proc/diskstats: major minor name, then reads merged sectors ms, writes merged sectors ms, in-flight, io ms and weighted ms."
        (returns LIST "Disk records"))
      (def sectors (fn (_ v) (if (null? v) () (* v 512))))
      (def ms (fn (_ v) (if (null? v) () (* v 1000000))))
      (def one
        (fn (_ l)
          (def f (Host %fields l))
          (def n (List length f))
          (def at (fn (_ i) (if (< i n) (Host %int (List ref i f)) ())))
          (match
            ((< n 7) ())
            ((< n 14)
              (Host %disk-record (List ref 2 f)
                (list (at 0) (at 1) (at 3) () (sectors (at 4)) () (at 5) () (sectors (at 6)))))
            (#t
              (Host %disk-record (List ref 2 f)
                (list (at 0) (at 1) (at 3) (at 4) (sectors (at 5)) (ms (at 6))
                      (at 7) (at 8) (sectors (at 9)) (ms (at 10))
                      (at 11) (ms (at 12)) (ms (at 13))))))))
      (List reject null? (List map one (Host %lines "diskstats"))))

    (method %darwin-disks (self)
      (doc "disks, from IOKit: each IOBlockStorageDriver's Statistics dictionary (Operations, Bytes and Total Time, read and write, the times in nanoseconds), and the BSD Name, Major and Minor of the media under it. A driver with no media, an empty reader, is left out. nil when IOKit will not load."
        (returns LIST "Disk records"))
      (def h ((prim-ref (lit ffi) (lit dlopen)) "/System/Library/Frameworks/IOKit.framework/IOKit" 1))
      (if (not h) ()
        (let ((call (prim-ref (lit ptr) (lit call))) (dlsym (prim-ref (lit ffi) (lit dlsym))))
          ; a CoreFoundation or IOKit function, by name: dlsym on IOKit's
          ; handle also searches the frameworks it loads
          (def c (fn (_ name args) (apply call (pair (dlsym h name) args))))
          ; mach ports and kern_return_t are 32 bits wide
          (def u32 (fn (_ v) (& v 4294967295)))
          (def release (fn (_ p) (if (= p 0) () (c "CFRelease" (list p)))))
          ; a CFString of an ASCII name (kCFStringEncodingUTF8)
          (def cfstr (fn (_ s) (c "CFStringCreateWithCString" (list 0 s 134217984))))
          (def prop
            (fn (_ e key)
              (def k (cfstr key))
              (def v (c "IORegistryEntryCreateCFProperty" (list e k 0 0)))
              (release k)
              v))
          ; a CFNumber as a 64-bit integer (kCFNumberSInt64Type)
          (def number
            (fn (_ v)
              (def b (Host %buf 8))
              (if (= v 0) () (if (= 0 (& 255 (c "CFNumberGetValue" (list v 4 (Host %ptr b))))) () (Host %int-at b 0 8)))))
          (def owned-number (fn (_ v) (def r (number v)) (release v) r))
          (def stat
            (fn (_ d key)
              (if (= d 0) ()
                (let ((k (cfstr key)))
                  (def v (c "CFDictionaryGetValue" (list d k)))
                  (release k)
                  (number v)))))
          (def bsd-name
            (fn (_ m)
              (def s (prop m "BSD Name"))
              (def b (Host %buf 64))
              (def ok (if (= s 0) #f (not (= 0 (& 255 (c "CFStringGetCString" (list s (Host %ptr b) 64 134217984)))))))
              (release s)
              (if ok (Host %cstr-at b 0 64) ())))
          (def one
            (fn (_ d)
              (def mb (Host %buf 8))
              (def media (if (= 0 (u32 (c "IORegistryEntryGetChildEntry" (list d "IOService" (Host %ptr mb)))))
                           (Host %int-at mb 0 4) 0))
              (def name (if (= media 0) () (bsd-name media)))
              (def r
                (if (null? name) ()
                  (let ((st (prop d "Statistics")))
                    (def v (list (owned-number (prop media "BSD Major")) (owned-number (prop media "BSD Minor"))
                                 (stat st "Operations (Read)") () (stat st "Bytes (Read)") (stat st "Total Time (Read)")
                                 (stat st "Operations (Write)") () (stat st "Bytes (Write)") (stat st "Total Time (Write)")))
                    (release st)
                    (Host %disk-record name v))))
              (if (= media 0) () (c "IOObjectRelease" (list media)))
              r))
          (def itb (Host %buf 8))
          (if (not (= 0 (u32 (c "IOServiceGetMatchingServices"
                               (list 0 (c "IOServiceMatching" (list "IOBlockStorageDriver")) (Host %ptr itb))))))
            ()
            (let ((it (Host %int-at itb 0 4)))
              (def go
                (fn (self acc)
                  (def d (u32 (c "IOIteratorNext" (list it))))
                  (if (= d 0) (List reverse acc)
                    (let ((r (one d)))
                      (c "IOObjectRelease" (list d))
                      (self (if (null? r) acc (pair r acc)))))))
              (def all (go ()))
              (c "IOObjectRelease" (list it))
              all)))))

    (method interfaces (self)
      (doc "The network interfaces' traffic totals since boot, one record an interface: name rx-bytes rx-packets rx-errors rx-dropped rx-fifo rx-frame rx-compressed rx-multicast tx-bytes tx-packets tx-errors tx-dropped tx-fifo tx-collisions tx-carrier tx-compressed. rx counts what arrived, tx what was sent. Linux reads /proc/net/dev, as BusyBox's nmeter and ifconfig do. Darwin reads each interface's ifmibdata sysctl, as netstat -i does, with tx-dropped its send queue's drops; it reports no fifo, frame, compressed or carrier counts."
        (returns LIST "Interface records")
        (sample "(Assoc get 'name (first (Host interfaces)))" "\"lo0\""))
      (if (eq? (Host %backend) (lit darwin)) (Host %darwin-interfaces) (Host %linux-interfaces)))

    (method %interface-record (self (param name STRING "Interface name") (param v LIST "The sixteen totals, in interfaces' order"))
      (doc "The interface record for a name and its totals."
        (returns ALIST "The interface record"))
      (def go (fn (self ks vs) (if (null? ks) () (pair (pair (first ks) (if (null? vs) () (first vs))) (self (rest ks) (if (null? vs) () (rest vs)))))))
      (pair (pair (lit name) name)
        (go (lit (rx-bytes rx-packets rx-errors rx-dropped rx-fifo rx-frame rx-compressed rx-multicast
                  tx-bytes tx-packets tx-errors tx-dropped tx-fifo tx-collisions tx-carrier tx-compressed))
            v)))

    (method %linux-interfaces (self)
      (doc "interfaces, from /proc/net/dev: two header lines, then NAME: and sixteen totals, received then sent. The first total may follow the colon with no space."
        (returns LIST "Interface records"))
      (def one
        (fn (_ l)
          (def colon (Str8 index-of ":" l))
          (if (null? colon) ()
            (Host %interface-record (Str8 trim (Str8 sub 0 colon l))
              (List map (fn (_ f) (Host %int f))
                (Host %fields (Str8 sub (+ colon 1) (- (Str8 length l) (+ colon 1)) l)))))))
      (def ls (Host %lines "net/dev"))
      (List reject null? (List map one (if (< (List length ls) 2) () (rest (rest ls))))))

    (method %darwin-interfaces (self)
      (doc "interfaces, as netstat -i reads them: the indexes from the RTM_IFINFO2 messages of sysctl CTL_NET PF_ROUTE 0 0 NET_RT_IFLIST2 0, then each interface's struct ifmibdata from CTL_NET PF_LINK NETLINK_GENERIC IFMIB_IFDATA INDEX IFDATA_GENERAL. The routing messages' own if_data64 counts bytes in 32 bits for a user without privileges; the ifmibdata's counts are whole."
        (returns LIST "Interface records"))
      (def r (Host %sysctl-mib (list 4 17 0 0 6 0) ()))
      ; ifmibdata: the name at 0, snd_drops at 32, if_data64 at 52; in that,
      ; the 64-bit counts from ipackets at 24
      (def one
        (fn (_ i)
          (def m (Host %sysctl-mib (list 4 18 0 2 i 1) 180))
          (if (null? m) ()
            (let ((b (first m)))
              (def at (fn (_ off) (Host %int-at b (+ 52 off) 8)))
              (Host %interface-record (Host %cstr-at b 0 16)
                (list (at 64) (at 24) (at 32) (at 96) () () () (at 80)
                      (at 72) (at 40) (at 48) (Host %int-at b 32 4) () (at 56) () ()))))))
      (if (null? r) ()
        (let ((b (first r)) (end (rest r)))
          ; if_msghdr2: msglen at 0, type at 3 (RTM_IFINFO2 is 18), index at 12
          (def go
            (fn (self o acc)
              (if (>= o end) (List reverse acc)
                (let ((len (Host %int-at b o 2)))
                  (if (= len 0) (List reverse acc)
                    (self (+ o len)
                      (if (= 18 (Host %int-at b (+ o 3) 1))
                        (let ((rec (one (Host %int-at b (+ o 12) 2)))) (if (null? rec) acc (pair rec acc)))
                        acc)))))))
          (go 0 ()))))

    ; --- CPU time -------------------------------------------------------------

    (method cpu (self)
      (doc "CPU time since boot across all processors, in nanoseconds: user nice system idle iowait irq softirq steal guest guest-nice. Linux reads /proc/stat's cpu line; Darwin reads HOST_CPU_LOAD_INFO, which reports the first four. Differences between two readings give the percentages top shows."
        (returns ALIST "((user . NS) (nice . NS) ... (guest-nice . NS)); a field not reported is nil")
        (sample "(Assoc get 'idle (Host cpu))" "1566821170000000"))
      (Host %cpu-record
        (if (eq? (Host %backend) (lit darwin))
          (Host %darwin-ticks)
          (let ((hit (List find (fn (_ l) (Str8 starts? "cpu " l)) (Host %lines "stat"))))
            (if (null? hit) () (List map (fn (_ f) (Host %int f)) (rest (Host %fields hit))))))))

    (method cpus (self)
      (doc "CPU time since boot for each processor, one record each in the kernel's order, with cpu's fields. Linux reads /proc/stat's cpuN lines; Darwin reads host_processor_info's PROCESSOR_CPU_LOAD_INFO, which reports user, nice, system and idle."
        (returns LIST "One cpu record a processor")
        (sample "(List length (Host cpus))" "12"))
      (if (eq? (Host %backend) (lit darwin))
        (List map (fn (_ t) (Host %cpu-record t)) (Host %darwin-cpu-ticks))
        (List map (fn (_ l) (Host %cpu-record (List map (fn (_ f) (Host %int f)) (rest (Host %fields l)))))
          (List filter (fn (_ l) (if (Str8 starts? "cpu" l) (not (Str8 starts? "cpu " l)) #f))
            (Host %lines "stat")))))

    (method %cpu-record (self (param ticks LIST "Tick counts in /proc/stat's order; fewer than ten leave the rest nil"))
      (doc "A cpu record from clock ticks: user nice system idle iowait irq softirq steal guest guest-nice, in nanoseconds. guest and guest-nice are also counted in user and nice, as the kernel counts them."
        (returns ALIST "The cpu record"))
      (def go
        (fn (self ks ts)
          (if (null? ks) ()
            (pair (pair (first ks) (if (null? ts) () (Host %ticks->ns (first ts))))
                  (self (rest ks) (if (null? ts) () (rest ts)))))))
      (go (list (lit user) (lit nice) (lit system) (lit idle)
                (lit iowait) (lit irq) (lit softirq) (lit steal) (lit guest) (lit guest-nice))
          ticks))

    (method %darwin-cpu-ticks (self)
      (doc "host_processor_info's PROCESSOR_CPU_LOAD_INFO ticks for each processor, in cpu's order: user, nice, system, idle. The kernel hands back an array it allocated, which is returned to it with vm_deallocate."
        (returns LIST "Four tick counts a processor"))
      (def ref (prim-ref (lit ptr) (lit ref)))
      (def cvt (prim-ref (lit convert) (lit to)))
      (def pointer-type (first (rest (Host %types))))
      (def count (Host %buf 8))
      (def info (Host %buf 8))
      (def info-count (Host %buf 8))
      (if (not (= 0 (Host %call "host_processor_info" (Host %call "mach_host_self") 2
                      (Host %ptr count) (Host %ptr info) (Host %ptr info-count))))
        ()
        (let ((n (Host %int-at count 0 4)) (at (Host %int-at info 0 8)))
          (def p (cvt at pointer-type))
          ; [CPU_STATE_MAX] natural_t a processor: USER, SYSTEM, IDLE, NICE
          (def one (fn (_ i) (def o (* i 16))
                     (list (ref p o 4) (ref p (+ o 12) 4) (ref p (+ o 4) 4) (ref p (+ o 8) 4))))
          (def go (fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (one i) acc)))))
          (def r (go (- n 1) ()))
          ; mach_task_self() is the value of the mach_task_self_ port variable
          (Host %call "vm_deallocate" (ref (Host %sym "mach_task_self_") 0 4) at
            (* 4 (Host %int-at info-count 0 4)))
          r)))

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
      (doc "Every process, one record each: pid ppid pgid sid uid gid ruid rgid state comm tty tty-major tty-minor nice start threads vsz rss utime stime processor. uid and gid are the effective ids, ruid and rgid the real ones. state is a Linux state letter (R S D T Z); start is unix seconds; vsz and rss are bytes; utime and stime are nanoseconds; tty is the terminal's device number, nil for none, and tty-major and tty-minor its two halves as this kernel packs them; processor is the CPU it last ran on. Darwin answers state (unless zombie or stopped), threads, vsz, rss, utime and stime only for this user's processes unless running as root, and reports no processor."
        (returns LIST "Process records")
        (sample "(List length (Host processes))" "772"))
      (if (eq? (Host %backend) (lit darwin)) (Host %darwin-processes) (Host %linux-processes)))

    (method process (self (param pid INTEGER "Process ID"))
      (doc "One process's record, as processes gives it, or nil when there is no such process."
        (returns ANY "A process record, or nil")
        (sample "(Assoc get 'comm (Host process 1))" "\"launchd\""))
      (if (eq? (Host %backend) (lit darwin))
        (let ((b (Host %sysctl-mib (list 1 14 1 pid) 648)))
          (if (null? b) () (Host %darwin-record (first b) 0 (Host %darwin-ctx))))
        (Host %linux-record (Host %linux-btime) (Str8 str pid))))

    (method args (self (param pid INTEGER "Process ID"))
      (doc "The process's argument vector, or nil when the kernel will not give it: a kernel thread on Linux, another user's process on Darwin."
        (returns ANY "LIST of strings, or nil")
        (sample "(Host args (Sys getpid))" "(\"x-bin\" \"--batch\")"))
      (if (eq? (Host %backend) (lit darwin)) (Host %darwin-args pid) (Host %linux-args pid)))

    (method exe (self (param pid INTEGER "Process ID"))
      (doc "The process's executable, as an absolute path, or nil when the kernel will not give it. Linux reads the /proc/PID/exe link, which only the process's owner or root may read; Darwin asks proc_pidpath, which answers for any process."
        (returns ANY "STRING, or nil")
        (sample "(Host exe 1)" "\"/sbin/launchd\""))
      (if (eq? (Host %backend) (lit darwin))
        (let ((b (Host %buf 4096)))
          (def n (Host %call "proc_pidpath" pid (Host %ptr b) 4096))
          (if (<= n 0) () (Host %cstr-at b 0 n)))
        (guard (e ()) (File readlink (Str8 append (Host proc-root) "/" (Str8 str pid) "/exe")))))

    (method threads (self (param pid INTEGER "Process ID"))
      (doc "The process's threads, one record each with the process record's fields, pid the thread's id and comm its name. Linux reads /proc/PID/task/TID/stat, so each thread's state, CPU time and processor are its own; Darwin lists the threads with proc_pidinfo and reads each one's state, name and CPU time, the other fields being the process's, and answers only for this user's processes unless running as root. nil when the process is gone or the kernel will not say."
        (returns ANY "LIST of thread records, or nil")
        (sample "(List length (Host threads (Sys getpid)))" "1"))
      (if (eq? (Host %backend) (lit darwin))
        (Host %darwin-threads pid)
        (let ((dir (Str8 append (Host proc-root) "/" (Str8 str pid) "/task"))
              (btime (Host %linux-btime)))
          (def tids (guard (e ()) (List filter (fn (_ n) (not (null? (Host %int n)))) (File list-dir dir))))
          (if (null? tids) ()
            (List sort-by (fn (_ r) (Assoc get (lit pid) r))
              (List reject null?
                (List map (fn (_ n) (Host %linux-record-at btime (Str8 append dir "/" n) (Host %int n))) tids)))))))

    (method %darwin-threads (self (param pid INTEGER "Process ID"))
      (doc "threads, from proc_pidinfo: PROC_PIDLISTTHREADIDS for the ids, then PROC_PIDTHREADID64INFO for each thread's struct proc_threadinfo."
        (returns ANY "LIST of thread records, or nil"))
      ; the context's primitives and the int doors, as %darwin-maps reads: a
      ; class call a field cost a thread hundreds of thousands of objects
      (def c (Host %darwin-ctx))
      (def ref (first c))
      (def call (first (rest c)))
      (def make (first (rest (rest c))))
      (def ->ptr (first (rest (rest (rest c)))))
      (def pidinfo (first (rest (rest (rest (rest c))))))
      (def more (rest (rest (rest (rest (rest (rest (rest (rest (rest (rest c))))))))))) ; from cvt on
      (def cvt (first more))
      (def string-type (first (rest more)))
      (def pointer-type (first (rest (rest more))))
      (def integer-type (first (rest (rest (rest more)))))
      (def byte-len (first (rest (rest (rest (rest more))))))
      (def i+ (prim-ref (lit int) (lit +)))
      (def i- (prim-ref (lit int) (lit -)))
      (def i* (prim-ref (lit int) (lit *)))
      (def i< (prim-ref (lit int) (lit <)))
      (def i= (prim-ref (lit int) (lit =)))
      (def proc (Host process pid))
      (def n (if (null? proc) () (Assoc get (lit threads) proc)))
      (if (null? n) ()
        (let ((ids (make (i* 8 (i+ n 16)))) (ti (make 112)))
          (def ip (->ptr ids))
          (def tp (->ptr ti))
          (def got (call pidinfo pid 28 0 ip (i* 8 (i+ n 16))))
          (def states (lit ((1 . "R") (2 . "T") (3 . "S") (4 . "D") (5 . "Z"))))
          ; pth_name: a C string of at most 64 bytes, read through its address
          (def name
            (fn (_)
              (def s (cvt (cvt (i+ (cvt tp integer-type) 48) pointer-type) string-type))
              (if (i< 64 (byte-len s)) ((prim-ref (lit str) (lit byte-sub)) s 0 64) s)))
          ; the process record with the thread's own fields in its place
          (def thread
            (fn (self es tid nm)
              (if (null? es) ()
                (let ((k (first (first es))))
                  (pair (match
                          ((eq? k (lit pid)) (pair k tid))
                          ((eq? k (lit state)) (pair k (Assoc get (ref tp 24 4) states)))
                          ((eq? k (lit comm)) (if (str=? nm "") (first es) (pair k nm)))
                          ((eq? k (lit utime)) (pair k (ref tp 0 8)))
                          ((eq? k (lit stime)) (pair k (ref tp 8 8)))
                          (#t (first es)))
                        (self (rest es) tid nm))))))
          ; pth_user_time, pth_system_time (ns), pth_run_state at 24, pth_name at 48
          (def one
            (fn (_ tid)
              (if (i= 112 (call pidinfo pid 15 tid tp 112)) (thread proc tid (name)) ())))
          (def go
            (fn (self i acc)
              (if (i< i 0) acc
                (self (i- i 1) (let ((r (one (ref ip (i* 8 i) 8)))) (if (null? r) acc (pair r acc)))))))
          ; got is the bytes PROC_PIDLISTTHREADIDS wrote, a uint64 an id
          (if (if (i< 0 got) (i< got 1000000000) #f) (go (i- ((prim-ref (lit int) (lit /)) got 8) 1) ()) ()))))

    (method maps (self (param pid INTEGER "Process ID"))
      (doc "The process's memory mappings, summed as BusyBox's top -m sums /proc/PID/smaps, in bytes: mapped-rw and mapped-ro, the size of the writable mappings and of the readable or executable rest (a device mapping other than /dev/zero, and a ---p guard gap, counted in neither); stack, the [stack] mapping's size; and the resident shared-clean, shared-dirty, private-clean and private-dirty. Darwin walks the regions with proc_pidinfo's PROC_PIDREGIONINFO, takes protection, the stack tag and the private and shared resident pages from the kernel, and counts a region's dirtied pages as private for a private or copy-on-write region and shared otherwise; it answers only for this user's processes unless running as root. nil when the process is gone or the kernel will not say."
        (returns ANY "((mapped-ro . B) (mapped-rw . B) (stack . B) (shared-clean . B) (shared-dirty . B) (private-clean . B) (private-dirty . B)), or nil")
        (sample "(< 0 (Assoc get 'mapped-ro (Host maps (Sys getpid))))" "#t"))
      (if (eq? (Host %backend) (lit darwin)) (Host %darwin-maps pid) (Host %linux-maps pid)))

    (method %maps-record (self (param v LIST "mapped-ro mapped-rw stack shared-clean shared-dirty private-clean private-dirty, bytes"))
      (doc "The maps record for seven sums in its order."
        (returns ALIST "The maps record"))
      (def go (fn (self ks vs) (if (null? ks) () (pair (pair (first ks) (first vs)) (self (rest ks) (rest vs))))))
      (go (lit (mapped-ro mapped-rw stack shared-clean shared-dirty private-clean private-dirty)) v))

    (method %linux-maps (self (param pid INTEGER "Process ID"))
      (doc "maps, from /proc/PID/smaps, read a line at a time, BusyBox's procps_read_smaps over the same lines."
        (returns ANY "The maps record, or nil"))
      ; the byte primitives and the int doors: a Str8 or class call on each of
      ; thousands of lines cost a process millions of objects
      (def len (prim-ref (lit str) (lit byte-len)))
      (def sub (prim-ref (lit str) (lit byte-sub)))
      (def at (prim-ref (lit str) (lit byte-ref)))
      (def i+ (prim-ref (lit int) (lit +)))
      (def i- (prim-ref (lit int) (lit -)))
      (def i* (prim-ref (lit int) (lit *)))
      (def i< (prim-ref (lit int) (lit <)))
      (def i= (prim-ref (lit int) (lit =)))
      ; L begins with P, compared a byte at a time
      (def starts?
        (fn (_ p l)
          (def n (len p))
          (def go (fn (self i) (if (i< i n) (if (i= (at p i) (at l i)) (self (i+ i 1)) #f) #t)))
          (if (i< (len l) n) #f (go 0))))
      ; the first byte at or after I that is (or, with SPACE? #f, is not) a space
      (def skip
        (fn (self l i space?)
          (if (i< i (len l)) (if (eq? (i= (at l i) 32) space?) (self l (i+ i 1) space?) i) i)))
      ; the decimal at I's first digit, past the spaces
      (def num
        (fn (self l i acc)
          (if (i< i (len l))
            (let ((b (at l i)))
              (if (if (i< b 48) #t (i< 57 b)) acc (self l (i+ i 1) (i+ (i* acc 10) (i- b 48)))))
            acc)))
      (def kb (fn (_ l key) (i* 1024 (num l (skip l (len key) #t) 0))))
      ; the sums, in %maps-record's order; ADD answers them with one grown by n
      (def add
        (fn (self i n v)
          (if (i= i 0) (pair (i+ n (first v)) (rest v)) (pair (first v) (self (i- i 1) n (rest v))))))
      (def dash
        (fn (self l i) (if (i< i (len l)) (if (i= (at l i) 45) i (self l (i+ i 1))) ())))
      ; a mapping's header: START-END PERMS OFFSET DEV INODE [PATH]
      (def header
        (fn (_ l d v)
          (def size (i- (Host %hex (sub l (i+ d 1) (i- (len l) (i+ d 1)))) (Host %hex l)))
          (def perms (skip l (skip l 0 #f) #t))
          ; past PERMS, OFFSET, DEV and INODE and the spaces after each
          (def field (fn (self i k) (if (i= k 0) i (self (skip l (skip l i #f) #t) (i- k 1)))))
          (def from (field perms 4))
          (def path (sub l from (i- (len l) from)))
          (def device? (if (starts? "/dev/" path) (not (str=? path "/dev/zero")) #f))
          (def v2
            (match
              (device? v)
              ((i= (at l (i+ perms 1)) 119) (add 1 size v))
              ((if (i= (at l perms) 114) #t (i= (at l (i+ perms 2)) 120)) (add 0 size v))
              (#t v)))
          (if (str=? path "[stack]") (add 2 size v2) v2)))
      (def line
        (fn (_ l v)
          (match
            ((starts? "Private_Dirty:" l) (add 6 (kb l "Private_Dirty:") v))
            ((starts? "Private_Clean:" l) (add 5 (kb l "Private_Clean:") v))
            ((starts? "Shared_Dirty:" l) (add 4 (kb l "Shared_Dirty:") v))
            ((starts? "Shared_Clean:" l) (add 3 (kb l "Shared_Clean:") v))
            (#t (let ((d (dash l 0))) (if (null? d) v (header l d v)))))))
      (def sums (Host %fold-lines (Str8 append (Host proc-root) "/" (Str8 str pid) "/smaps") line
                  (list 0 0 0 0 0 0 0)))
      (if (null? sums) () (Host %maps-record sums)))

    (method %darwin-maps (self (param pid INTEGER "Process ID"))
      (doc "maps, from proc_pidinfo's PROC_PIDREGIONINFO, one struct proc_regioninfo a region from address 0 up."
        (returns ANY "The maps record, or nil"))
      ; straight off the context's primitives and the int doors: a class call
      ; a field cost a region thousands of objects, and a process has hundreds
      ; of regions
      (def c (Host %darwin-ctx))
      (def ref (first c))
      (def call (first (rest c)))
      (def pidinfo (first (rest (rest (rest (rest c))))))
      (def i+ (prim-ref (lit int) (lit +)))
      (def i- (prim-ref (lit int) (lit -)))
      (def i* (prim-ref (lit int) (lit *)))
      (def i< (prim-ref (lit int) (lit <)))
      (def i= (prim-ref (lit int) (lit =)))
      (def i& (prim-ref (lit int) (lit &)))
      (def page (Host %page-size))
      (def ri ((first (rest (rest c))) 96))
      (def p ((first (rest (rest (rest c)))) ri))
      (def at (fn (_ off n) (ref p off n)))
      (def least (fn (_ a b) (if (i< a b) a b)))
      ; one region onto the sums; then the next, from the end of this one
      (def region
        (fn (_ next ro rw stack sc sd pc pd)
          (def prot (at 0 4))
          (def size (at 88 8))
          (def mode (at 60 4))
          (def priv-res (i* page (at 64 4)))
          (def shared-res (i* page (at 68 4)))
          (def dirty (i* page (at 48 4)))
          ; SM_COW 1, SM_PRIVATE 2, SM_EMPTY 3, SM_PRIVATE_ALIASED 6: the region's own pages
          (def private? (if (i= mode 1) #t (if (i= mode 2) #t (if (i= mode 3) #t (i= mode 6)))))
          (def pdirty (if private? (least dirty priv-res) 0))
          (def sdirty (if private? 0 (least dirty shared-res)))
          (def writable? (not (i= 0 (i& prot 2))))
          (next (i+ (at 80 8) size)
            (if writable? ro (if (i= 0 (i& prot 5)) ro (i+ ro size)))
            (if writable? (i+ rw size) rw)
            ; VM_MEMORY_STACK
            (if (i= 30 (at 32 4)) (i+ stack size) stack)
            (i+ sc (i- shared-res sdirty)) (i+ sd sdirty)
            (i+ pc (i- priv-res pdirty)) (i+ pd pdirty)
            #t)))
      (def go
        (fn (self addr ro rw stack sc sd pc pd seen)
          ; proc_pidinfo answers the bytes it wrote: a whole struct, or
          ; nothing; the walk ends there, or at a region that does not end
          ; past the address asked for, which would ask for it again
          (if (if (i= 96 (call pidinfo pid 7 addr p 96)) (i< addr (i+ (at 80 8) (at 88 8))) #f)
            (region self ro rw stack sc sd pc pd)
            (if seen (Host %maps-record (list ro rw stack sc sd pc pd)) ()))))
      (go 0 0 0 0 0 0 0 0 #f))

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
      (doc "One process's record from /proc/PID/stat, or nil when it is gone."
        (returns ANY "A process record, or nil"))
      (Host %linux-record-at btime (Str8 append (Host proc-root) "/" name) (Host %int name)))

    (method %linux-record-at (self (param btime INTEGER "Boot time, unix seconds") (param dir STRING "A /proc/PID or /proc/PID/task/TID directory")
                                   (param id INTEGER "The pid or thread id the directory is named for"))
      (doc "A record from a directory's stat file, or nil when it is gone. comm is read between the first ( and the last ), since a name may hold either. A field past the end of a short line is nil."
        (returns ANY "A process record, or nil"))
      (def s (Host %read (Str8 append dir "/stat")))
      (if (null? s) ()
        (let ((open (Str8 index-of "(" s)) (close (Str8 last-index-of ")" s)))
          (def f (Host %fields (Str8 sub (+ close 2) (Str8 length s) s)))
          (def n (List length f))
          (def at (fn (_ i) (if (< i n) (Host %int (List ref i f)) ())))
          (def tty (at 4))
          (def owner (Host %owner dir))
          (def real (Host %real-ids dir))
          (list (pair (lit pid) id)
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
                (pair (lit stime) (Host %ticks->ns (at 12)))
                ; field 39, past rss and fourteen more, as BusyBox's top reads it
                (pair (lit processor) (at 36))))))

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

    (method %sysctl-mib (self (param mib LIST "The name as integers") (param n ANY "Buffer size, or nil to ask the kernel how much the value needs"))
      (doc "A sysctl value by numeric name, as (region . length), or nil when the kernel refuses or answers nothing (no such process). With no size, the kernel is asked first, so the region is as large as the value and no larger."
        (returns ANY "PAIR (region . length), or nil"))
      (def set (prim-ref (lit ptr) (lit set!)))
      (def set-word (prim-ref (lit ptr) (lit set-word!)))
      (def words ((fn (self l n) (if (null? l) n (self (rest l) (+ n 1)))) mib 0))
      (def name (Host %buf (* 4 words)))
      ; the name a word at a time, by hand: a List method costs a call tens of
      ; thousands of objects to enter
      (def put (fn (self ns off) (if (null? ns) () (do (set (Host %ptr name) off (first ns) 4) (self (rest ns) (+ off 4))))))
      (put mib 0)
      (def len (Host %buf 8))
      (def ask
        (fn (_ b size)
          (set-word (Host %ptr len) 0 size)
          (Host %call "sysctl" (Host %ptr name) words (if (null? b) 0 (Host %ptr b)) (Host %ptr len) 0 0)))
      (def size (if (null? n) (if (< (ask () 0) 0) 0 (Host %int-at len 0 8)) n))
      (if (= size 0) ()
        (let ((b (Host %buf size)))
          (if (< (ask b size) 0) ()
            (let ((got (Host %int-at len 0 8))) (if (= 0 got) () (pair b got)))))))

    (method %darwin-processes (self)
      (doc "processes, from kern.proc.all and proc_pidinfo. The table is asked for its size first and given room for a few more processes, since it can grow between the two calls."
        (returns LIST "Process records"))
      (def need (+ (Host %sysctl-size "kern.proc.all") (* 64 648)))
      (def len (Host %buf 8))
      (def b (Host %buf need))
      ((prim-ref (lit ptr) (lit set-word!)) (Host %ptr len) 0 need)
      (if (< (Host %call "sysctlbyname" "kern.proc.all" (Host %ptr b) (Host %ptr len) 0 0) 0) ()
        (let ((ctx (Host %darwin-ctx)) (n (/ (Host %int-at len 0 8) 648)))
          (def go (fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (Host %darwin-record b (* i 648) ctx) acc)))))
          (go (- n 1) ()))))

    (method %darwin-ctx (self)
      (doc "What reading Darwin's process records needs, fetched once a process rather than once a field: the pointer and conversion primitives, the type handles, proc_pidinfo, getsid and sysctl resolved, and the Mach timebase. Cached in ctx; the image recache hook clears it, since a resolved symbol is a fact of the process that resolved it."
        (returns LIST "(ref call make ->ptr proc_pidinfo getsid numer denom sysctl set! cvt string-type pointer-type integer-type byte-len byte-ref)"))
      (when (null? (Host ctx))
        (let ((ref (prim-ref (lit ptr) (lit ref)))
              (call (prim-ref (lit ptr) (lit call)))
              (make (prim-ref (lit str) (lit make)))
              (->ptr (prim-ref (lit str) (lit ->ptr)))
              (t (Host %types)))
          (def tb (make 8))
          (call (Host %sym "mach_timebase_info") (->ptr tb))
          (Host ctx
            (list ref call make ->ptr (Host %sym "proc_pidinfo") (Host %sym "getsid")
                  (ref (->ptr tb) 0 4) (ref (->ptr tb) 4 4)
                  (Host %sym "sysctl") (prim-ref (lit ptr) (lit set!))
                  (prim-ref (lit convert) (lit to))
                  (first t) (first (rest t)) (first (rest (rest t)))
                  (prim-ref (lit str) (lit byte-len)) (prim-ref (lit str) (lit byte-ref))))))
      (Host ctx))

    (method %darwin-record (self (param b STRING "kinfo_proc rows") (param o INTEGER "This row's offset")
                                 (param ctx LIST "What %darwin-ctx answers"))
      (doc "One process's record from its kinfo_proc row, with proc_pidinfo's task info where the kernel gives it. state is Z or T from p_stat (SZOMB, SSTOP); otherwise p_stat reads SRUN for nearly every process, so R or S comes from the task info's running-thread count, as Darwin's ps decides it, and is nil where the task info is refused."
        (returns ALIST "A process record"))
      ; every field a ptr ref at its offset: a class call a field cost a
      ; record hundreds of thousands of objects
      (def ref (first ctx))
      (def call (first (rest ctx)))
      (def make (first (rest (rest ctx))))
      (def ->ptr (first (rest (rest (rest ctx)))))
      (def more (rest (rest (rest (rest ctx)))))
      (def p (->ptr b))
      (def at (fn (_ off n) (ref p (+ o off) n)))
      (def signed (fn (_ v top) (if (< v top) v (- v (* 2 top)))))
      (def pid (at 40 4))
      (def stat (at 36 1))
      (def tdev (signed (at 572 4) 2147483648))
      (def ti (make 96))
      (def tp (->ptr ti))
      (def ok (= 96 (Sys %sign-fold (call (first more) pid 4 0 tp 96))))
      (def task (fn (_ off n) (if ok (ref tp off n) ())))
      (def numer (first (rest (rest more))))
      (def denom (first (rest (rest (rest more)))))
      ; whole nanoseconds, by the int door: with the tower loaded / answers a fraction
      (def ns (fn (_ t) (if ok ((prim-ref (lit int) (lit /)) (* t numer) denom) ())))
      (def sid (Sys %sign-fold (call (first (rest more)) pid)))
      (list (pair (lit pid) pid)
            (pair (lit ppid) (at 560 4))
            (pair (lit pgid) (at 564 4))
            (pair (lit sid) (if (< sid 0) () sid))
            ; e_ucred's uid and first group are the effective ids; e_pcred
            ; holds the real ones
            (pair (lit uid) (at 420 4))
            (pair (lit gid) (at 428 4))
            (pair (lit ruid) (at 392 4))
            (pair (lit rgid) (at 400 4))
            (pair (lit state) (match ((= stat 5) "Z") ((= stat 4) "T") ((not ok) ()) ((> (task 88 4) 0) "R") (#t "S")))
            (pair (lit comm) (Host %cstr-at b (+ o 243) 17))
            (pair (lit tty) (if (= tdev -1) () tdev))
            ; dev_t: the major in the top 8 bits, the minor in the low 24
            (pair (lit tty-major) (if (= tdev -1) () (& (>> tdev 24) 255)))
            (pair (lit tty-minor) (if (= tdev -1) () (& tdev 16777215)))
            (pair (lit nice) (signed (at 242 1) 128))
            (pair (lit start) (at 0 8))
            (pair (lit threads) (task 84 4))
            (pair (lit vsz) (task 0 8))
            (pair (lit rss) (task 8 8))
            (pair (lit utime) (ns (task 16 8)))
            (pair (lit stime) (ns (task 24 8)))
            (pair (lit processor) ())))

    (method %darwin-args (self (param pid INTEGER "Process ID"))
      (doc "args, from kern.procargs2: argc, the executable's path, padding NULs, then the argc strings."
        (returns ANY "LIST of strings, or nil"))
      ; straight off the context's primitives: ps reads this for every
      ; process, and a class call a step cost each read tens of thousands
      ; of objects
      (def c (Host %darwin-ctx))
      (def ref (first c))
      (def call (first (rest c)))
      (def make (first (rest (rest c))))
      (def ->ptr (first (rest (rest (rest c)))))
      (def more (rest (rest (rest (rest (rest (rest (rest (rest c)))))))))
      (def sysctl (first more))
      (def set (first (rest more)))
      (def cvt (first (rest (rest more))))
      (def string-type (first (rest (rest (rest more)))))
      (def pointer-type (first (rest (rest (rest (rest more))))))
      (def integer-type (first (rest (rest (rest (rest (rest more)))))))
      (def byte-len (first (rest (rest (rest (rest (rest (rest more))))))))
      (def byte-at (first (rest (rest (rest (rest (rest (rest (rest more)))))))))
      (def name (make 12))
      (set (->ptr name) 0 1 4) (set (->ptr name) 4 49 4) (set (->ptr name) 8 pid 4)
      (def len (make 8))
      (def ask
        (fn (_ b size)
          ((prim-ref (lit ptr) (lit set-word!)) (->ptr len) 0 size)
          (Sys %sign-fold (call sysctl (->ptr name) 3 (if (null? b) 0 (->ptr b)) (->ptr len) 0 0))))
      (def size (if (< (ask () 0) 0) 0 (ref (->ptr len) 0 8)))
      (def b (if (= size 0) () (make size)))
      (if (if (null? b) #t (< (ask b size) 0)) ()
        (let ((end (ref (->ptr len) 0 8)) (base (cvt (->ptr b) integer-type)))
          ; the path is a C string: its length is one byte-len, not a walk
          (def skip-path (fn (_ i) (+ i (byte-len (cvt (cvt (+ base i) pointer-type) string-type)))))
          (def skip-nuls (fn (self i) (if (if (< i end) (= (byte-at b i) 0) #f) (self (+ i 1)) i)))
          ; each argument a C string at its address; its byte length is
          ; its length, and the next starts one past its NUL
          (def go
            (fn (self i k acc)
              (if (if (>= i end) #t (= k 0)) (List reverse acc)
                (let ((s (cvt (cvt (+ base i) pointer-type) string-type)))
                  (self (+ i (byte-len s) 1) (- k 1) (pair s acc))))))
          (go (skip-nuls (skip-path 4)) (ref (->ptr b) 0 4) ()))))

    ; --- users ----------------------------------------------------------------

    (method users (self)
      (doc "The logged-in sessions: utmp's user-process entries, as BusyBox's who and uptime count them: user tty host time pid. time is the login, in unix seconds."
        (returns LIST "Session records")
        (sample "(List map (fn (_ u) (Assoc get 'tty u)) (Host users))" "(\"console\" \"ttys000\")"))
      (List map (fn (_ e) (List reject (fn (_ f) (eq? (first f) (lit type))) e))
        (List filter (fn (_ e) (eq? (Assoc get (lit type) e) (lit user-process))) (Host utmp))))

    (method utmp (self)
      (doc "Every entry in libc's utmpx database with a user name (setutxent/getutxent, as BusyBox's who -a reads it): user tty host time pid type. type is the entry's kind: run-level, boot-time, new-time, old-time, init-process, login-process, user-process, dead-process, accounting, signature or shutdown-time (the last two Darwin's), or nil for one this table does not know. time is unix seconds."
        (returns LIST "Entry records")
        (sample "(List map (fn (_ e) (Assoc get 'type e)) (Host utmp))" "(user-process user-process)"))
      ; struct utmpx, (field offset width): Darwin's and glibc's differ
      (def lay
        (if os-darwin?
          (lit ((type 296 2) (pid 292 4) (line 260 32) (user 0 256) (host 320 256) (sec 304 8)))
          (lit ((type 0 2) (pid 4 4) (line 8 32) (user 44 32) (host 76 256) (sec 340 4)))))
      ; ut_type's numbers: the two libcs swap OLD_TIME and NEW_TIME
      (def types
        (if os-darwin?
          (lit ((1 . run-level) (2 . boot-time) (3 . old-time) (4 . new-time) (5 . init-process)
                (6 . login-process) (7 . user-process) (8 . dead-process) (9 . accounting)
                (10 . signature) (11 . shutdown-time)))
          (lit ((1 . run-level) (2 . boot-time) (3 . new-time) (4 . old-time) (5 . init-process)
                (6 . login-process) (7 . user-process) (8 . dead-process) (9 . accounting)))))
      (def row (fn (_ k) (rest (Assoc entry k lay))))
      ; getutxent answers its record's address as an integer, 0 at the end
      (def cvt (prim-ref (lit convert) (lit to)))
      (def pointer-type (first (rest (Host %types))))
      (def ->ptr (fn (_ a) (cvt a pointer-type)))
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
              (if (str=? "" (str-at p (lit user))) acc
                (pair (list (pair (lit user) (str-at p (lit user)))
                            (pair (lit tty) (str-at p (lit line)))
                            (pair (lit host) (str-at p (lit host)))
                            (pair (lit time) (int-at p (lit sec)))
                            (pair (lit pid) (int-at p (lit pid)))
                            (pair (lit type) (Assoc get (int-at p (lit type)) types)))
                      acc))))))
      (def all (go ()))
      (Host %call "endutxent")
      all)))

; A resolved symbol is a fact of the process that resolved it: a process
; restored from an image resolves its own the first time it asks.
(set! %image-recache-hooks (pair (fn (_) (Host ctx ())) %image-recache-hooks))

(doc (provide x/sys/host Host)
  (note "Linux reads sysinfo(2) and /proc; Darwin reads sysctl, the Mach host statistics, IOKit and proc_pidinfo over the dlopen FFI; both read utmpx through libc.")
  (sample "(Host load)" "(3.85 4.5 6.27)")
  "Host: boot time, load, memory, CPU time, counters, disks, interfaces, interrupts, processes and users, the same records on Linux and Darwin.")
