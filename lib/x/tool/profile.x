; profile.x -- Performance profiling and smart garbage collection
;
; Reads the interpreter's internal performance counters from the base
; object's profile list. Each counter tracks a different aspect of
; evaluation: allocation, eval calls, tail-call optimizations, symbol
; lookups, and GC activity.
;
; Also provides a smart heap-collect that skips collection when heap
; pressure is low, and a forced variant that always collects.

(module x/tool/profile)
(def %profile
  (fn (_ ) (%reflect-base-cell (lit profile))))

; --- Counter accessors ---

(doc (def alloc-count (fn (_ ) (%cell-int (first (first (%profile))))))
  (returns INTEGER "Total heap allocations since last reset")
  "Return the number of heap objects allocated.")

(doc (def eval-count (fn (_ ) (%cell-int (first (first (rest (%profile)))))))
  (returns INTEGER "Total eval calls since last reset")
  "Return the number of eval invocations.")

(doc (def tco-count
  (fn (_ ) (%cell-int (first (first (rest (rest (%profile))))))))
  (returns INTEGER "Total tail-call optimizations since last reset")
  "Return the number of tail-call optimizations performed.")

(doc (def assoc-calls-count
  (fn (_ ) (%cell-int (first (first (rest (rest (rest (%profile)))))))))
  (returns INTEGER "Total alist lookup calls")
  "Return the number of association list lookup operations.")

(doc (def assoc-steps-count
  (fn (_ ) (%cell-int (first (first (rest (rest (rest (rest (%profile))))))))))
  (returns INTEGER "Total alist walk steps")
  "Return the total steps walked during alist lookups.")

(doc (def sym-find-calls-count
  (fn (_ ) (%cell-int (first (first (rest (rest (rest (rest (rest (%profile)))))))))))
  (returns INTEGER "Total symbol-find calls")
  "Return the number of symbol lookup operations.")

(doc (def sym-find-steps-count
  (fn (_ ) (%cell-int (first (first (rest (rest (rest (rest (rest (rest (%profile))))))))))))
  (returns INTEGER "Total symbol-find steps")
  "Return the total steps walked during symbol lookups.")

(doc (def gc-runs-count
  (fn (_ ) (%cell-int (first (first (rest (rest (rest (rest (rest (rest (rest (%profile)))))))))))))
  (returns INTEGER "Total GC mark/sweep cycles")
  "Return the number of garbage collection runs.")

(doc (def bst-hits-count
  (fn (_ ) (%cell-int (first (first (rest (rest (rest (rest (rest (rest (rest (rest (%profile))))))))))))))
  (returns INTEGER "BST cache hits")
  "Return the number of successful BST (binary search tree) lookups.")

(doc (def bst-misses-count
  (fn (_ ) (%cell-int (first (first (rest (rest (rest (rest (rest (rest (rest (rest (rest (%profile)))))))))))))))
  (returns INTEGER "BST cache misses")
  "Return the number of BST lookups that fell through to alist walk.")

; --- Reset ---

(doc (def profile-reset
  (fn (_ )
    (%set-cell-int! (first (first (%profile))) 0)
    (%set-cell-int! (first (first (rest (%profile)))) 0)
    (%set-cell-int! (first (first (rest (rest (%profile))))) 0)
    (%set-cell-int! (first (first (rest (rest (rest (%profile)))))) 0)
    (%set-cell-int! (first (first (rest (rest (rest (rest (%profile))))))) 0)
    (%set-cell-int! (first (first (rest (rest (rest (rest (rest (%profile)))))))) 0)
    (%set-cell-int! (first (first (rest (rest (rest (rest (rest (rest (%profile))))))))) 0)
    (%set-cell-int! (first (first (rest (rest (rest (rest (rest (rest (rest (%profile)))))))))) 0)
    (%set-cell-int! (first (first (rest (rest (rest (rest (rest (rest (rest (rest (%profile))))))))))) 0)
    (%set-cell-int! (first (first (rest (rest (rest (rest (rest (rest (rest (rest (rest (%profile)))))))))))) 0)))
  "Reset all performance counters to zero.")

; --- Heap collection ---

; ns `heap` is de-registered (R5): fetch the raw collector from the catalog.
; The instrumented heap-collect / heap-collect-force ops below are this
; tool's own exports, defined fresh (nothing bare to shadow anymore).
(def %heap-collect-prim (prim-ref (lit heap) (lit collect)))
(def %hc-last-allocs 0)
(def %hc-last-surviving 10000)

(doc (def heap-collect-force
  (op ()
    _
    (def %hcf-before (Heap count))
    (%heap-collect-prim)
    (def %hcf-after (Heap count))
    (set! %hc-last-allocs (alloc-count))
    (set! %hc-last-surviving %hcf-after)
    (- %hcf-before %hcf-after)))
  (returns INTEGER "Number of objects freed")
  "Force a full GC mark/sweep cycle, returning the number of objects freed.")

(doc (def heap-collect
  (op ()
    _
    (if (> (- (alloc-count) %hc-last-allocs) %hc-last-surviving)
      (heap-collect-force)
      0)))
  (returns INTEGER "Number of objects freed, or 0 if skipped")
  "Smart GC: only collect when allocations since last run exceed surviving objects.")

; --- Eval counts per object ---
;
; A profiling engine counts, in each object's flags word, how many times
; evaluation reached it: every expression it evaluated and every body cell
; it stepped onto.  The rows %obj-evals-shift and %obj-evals-bits of the
; engine's layout contract (engine/tools/contract/obj-layout.x) say where.
; The count stops at its maximum and does not wrap.  An engine built
; without the profiling flag never writes it, and it reads zero.
;
; Only pairs are counted here.  A symbol is interned, so its count is every
; evaluation of that name anywhere; the forms hold the counts that belong
; to one place in the source.
;
; The rows are read when a function here is called and not when this module
; loads, so the module loads on an engine whose contract has no such rows,
; and the counters and the collector above work there.
(import x/type/list)
(import x/tool/cov cov-flags cov-cons? cov-body cov-word-size)

; The walks below run once per pair of every body and once per object on
; the heap, so they take the integer primitives from the catalog: under the
; numeric tower the bare names dispatch on their operands' types first.
;
; They also run between the moment the counts are cleared and the moment
; they are read, and a library function they called would be counted with
; the program they measure: a heap walk would add a call of `if` and of
; `null?` for every object.  So what runs from profile-clear! to the end of
; profile-rows is the engine's own forms -- fn, match, first, rest, pair,
; eq? -- the catalog primitives, and the functions of this module and of
; x/tool/cov, whose rows the report leaves out.  What is computed once, at
; load, may use anything.
(def %profile-int+ (prim-ref (lit int) (lit +)))
(def %profile-int- (prim-ref (lit int) (lit -)))
(def %profile-int< (prim-ref (lit int) (lit <)))
(def %profile-int& (prim-ref (lit int) (lit &)))
(def %profile-int>> (prim-ref (lit int) (lit >>)))
(def %profile-int<< (prim-ref (lit int) (lit <<)))
(def %profile-o->p (prim-ref (lit obj) (lit ->ptr)))
(def %profile-p->o (prim-ref (lit ptr) (lit ->obj)))
(def %profile-i->p (prim-ref (lit int) (lit ->ptr)))
(def %profile-rw (prim-ref (lit ptr) (lit ref-word)))
(def %profile-sw (prim-ref (lit ptr) (lit set-word!)))
(def %profile-chain-clear! (prim-ref (lit heap) (lit chain-clear!)))

; Byte offsets in an object, from the layout contract's word offsets.  The
; meta words are prepended, word i at -(i+1) words, and the reader keeps a
; line in meta word 0 and a file id in meta word 1.
(def %profile-word (cov-word-size))
(def %profile-heap-off (* %obj-slot-heap %profile-word))
(def %profile-type-off (* %obj-slot-type %profile-word))
(def %profile-flags-off (* %obj-slot-flags %profile-word))
(def %profile-data-off (* %obj-meta-len %profile-word))
(def %profile-line-off (- 0 %profile-word))
(def %profile-file-off (- 0 (* 2 %profile-word)))

; The type words of a procedure and of an operative, and the cell the loader
; files source paths in, which stays where it is for the life of the base.
(def %profile-proc-tw (%profile-rw (%profile-o->p (fn (_) ())) %profile-type-off))
(def %profile-op-tw (%profile-rw (%profile-o->p (op () _ ())) %profile-type-off))
(def %profile-registry (%reflect-base-cell (lit file-registry)))

; The meta word at off, or 0 when obj carries none.
(def %profile-meta
  (fn (_ obj off)
    (match ((eq? (%profile-int& (cov-flags obj) %obj-flag-meta) 0) 0)
           (#t (%profile-rw (%profile-o->p obj) off)))))

(doc (def profile-evals-max
  (fn (_) (%profile-int- (%profile-int<< 1 %obj-evals-bits) 1)))
  (returns INTEGER "The value an eval count stops at")
  "Return the largest eval count an object can hold.")

(doc (def profile-evals
  (fn (_ obj)
    (%profile-int& (%profile-int>> (cov-flags obj) %obj-evals-shift)
                   (profile-evals-max))))
  (param obj ANY "Object to read")
  (returns INTEGER "Times evaluation reached obj, at most (profile-evals-max)")
  "Return how many times evaluation reached an object.")

; One step of a walk.  acc is (evals nodes saturated): n joins the sum, the
; node count goes up by one, and the third element turns true once a count
; is at its maximum, where the sum is a lower bound.
(def %profile-add
  (fn (_ n max acc)
    (pair (%profile-int+ (first acc) n)
      (pair (%profile-int+ (first (rest acc)) 1)
        (pair (match ((eq? (%profile-int- n max) 0) #t)
                     (#t (first (rest (rest acc)))))
              ())))))

; The rest of a cell is a tail call and the first is not, so the walk runs
; along a list of any length and recurses only as deep as the forms nest.
(def %profile-walk
  (fn (self obj shift max stop acc)
    (match ((cov-cons? obj)
            ((fn (_ flags)
               (match ((eq? (%profile-int& flags stop) 0)
                       (self (rest obj) shift max stop
                         (self (first obj) shift max stop
                           (%profile-add (%profile-int& (%profile-int>> flags shift) max)
                                         max acc))))
                      (#t acc)))
             (cov-flags obj)))
           (#t acc))))

(doc (def profile-tree
  (fn (_ expr stop)
    (match ((cov-cons? expr)
            ((fn (_ shift max)
               (%profile-walk (rest expr) shift max stop
                 (%profile-walk (first expr) shift max stop
                   (%profile-add (profile-evals expr) max
                                 (pair 0 (pair 0 (pair #f ())))))))
             %obj-evals-shift (profile-evals-max)))
           (#t (pair 0 (pair 0 (pair #f ())))))))
  (param expr ANY "Body or form to walk")
  (param stop INTEGER "Flag bits that end the walk at a pair below expr which carries one of them; 0 walks everything")
  (returns LIST "(evals nodes saturated): the counts summed, the pairs visited, and #t when a count was at its maximum")
  "Sum the eval counts through a body or a form.")

; A function's calls.  A procedure steps onto its body's first cell once a
; call, and the engine counts that cell.  It never counts an operative's body
; cells, but every call evaluates an operative's first form once, and that
; form is counted when it is a pair; a name or a constant is shared, and not
; counted by place.  For a procedure the two agree whenever the first form is
; a pair, so the larger of the two is the calls of either kind.
(def %profile-calls
  (fn (_ body)
    ((fn (_ cell form)
       (match ((%profile-int< cell form) form)
              (#t cell)))
     (profile-evals body)
     (match ((cov-cons? (first body)) (profile-evals (first body)))
            (#t 0)))))

(doc (def profile-fn
  (fn (_ f)
    ((fn (_ body)
       (match ((cov-cons? body) (pair (%profile-calls body) (profile-tree body 0)))
              (#t ())))
     (cov-body f))))
  (param f CALLABLE "Procedure or operative made by fn or op")
  (returns LIST "(calls evals nodes saturated), or nil when f has no body")
  (sample "(profile-fn (fn (_ n) (+ n 1)))" "(0 0 4 #f)")
  (note "An operative's calls are counted on its first form, so one whose body starts with a name or a constant reads 0 calls.")
  "Return a function's calls and the evaluation its body did, as a profiling engine counted them.")

; --- The whole process, by function ---
;
; Every procedure and operative is an object on the heap chain, named or
; not, so one walk of the chain finds every body.  A body is reported once
; however many closures share it, and a function made inside another is
; reported on its own row when one made from it is alive: its body is then
; left out of the enclosing function's sum, so the rows divide the counts
; between them and none is counted twice.  The trace flag on a body's first
; cell is what records that the body has a row; profile-rows sets it and
; clears it again.
;
; The cursor of a walk is an object and its successor is read after any
; collection, for the reasons tools/dev/image-walk.x gives.

; How many objects, or pairs of bodies, a walk passes between collections,
; less one so that it serves as a mask.  A step leaves garbage behind -- the
; frames of the calls it makes, a few dozen objects -- and nothing collects
; unless asked, so a walk of a booted heap would otherwise hold gigabytes; a
; collection marks the whole live heap, so it cannot run at every step
; either.  At this interval a walk holds some tens of megabytes between
; collections.
(def %profile-collect-mask 16383)

; How far down the firsts of a body's first form to look for a pair the
; reader stamped with its line.  The first form is nearly always one.
(def %profile-where-depth 8)

; No source file has this many lines, so a larger number in a pair's line
; slot is not a line.
(def %profile-line-limit 1000000)

; The object after cur on the heap chain, read after any collection, which
; may free the object that followed it.
(def %profile-after
  (fn (_ cur n)
    (match ((eq? (%profile-int& n %profile-collect-mask) 0) (%heap-collect-prim))
           (#t ()))
    (%profile-next-of (%profile-rw (%profile-o->p cur) %profile-heap-off))))
(def %profile-next-of
  (fn (_ word)
    (match ((eq? word 0) ())
           (#t (%profile-p->o (%profile-i->p word))))))

(def %profile-each
  (fn (self cur f acc n)
    (match ((eq? cur ()) acc)
           (#t (self (%profile-after cur n) f (f cur acc) (%profile-int+ n 1))))))

; body joins acc unless its first cell is already claimed.
(def %profile-claim
  (fn (_ body acc trace)
    (match ((cov-cons? body)
            ((fn (_ flags)
               (match ((eq? (%profile-int& flags trace) 0)
                       ((fn (_ written) (pair body acc))
                        (%profile-sw (%profile-o->p body) %profile-flags-off
                                     (%profile-int+ flags trace))))
                      (#t acc)))
             (cov-flags body)))
           (#t acc))))

(def %profile-release
  (fn (self bodies trace)
    (match ((eq? bodies ()) ())
           (#t ((fn (_ flags)
                  (%profile-sw (%profile-o->p (first bodies)) %profile-flags-off
                               (%profile-int- flags (%profile-int& flags trace)))
                  (self (rest bodies) trace))
                (cov-flags (first bodies)))))))

(def %profile-body-of
  (fn (_ obj acc trace word)
    (match ((eq? (%profile-int- word %profile-proc-tw) 0)
            (%profile-claim (cov-body obj) acc trace))
           ((eq? (%profile-int- word %profile-op-tw) 0)
            (%profile-claim (cov-body obj) acc trace))
           (#t acc))))
(def %profile-bodies
  (fn (_ trace)
    (%profile-each (pair () ())
      (fn (_ obj acc)
        (%profile-body-of obj acc trace
                          (%profile-rw (%profile-o->p obj) %profile-type-off)))
      () 1)))

; The path the loader filed a file id under, or nil for an id it never
; filed.  The registry holds (id . path) with the id in an int cell, and id
; 0 is input that was not a file, which has the empty path.
(def %profile-file
  (fn (self id reg)
    (match ((eq? id 0) "")
           ((eq? reg ()) ())
           ((eq? (%profile-int- (%profile-rw (%profile-o->p (first (first reg)))
                                             %profile-data-off)
                                id)
                 0)
            (rest (first reg)))
           (#t (self id (rest reg))))))

; Where a body starts, (file-id . line), or (0 . 0) when nothing near its
; start says.  The reader stamps one object for each thing it reads with the
; line and file it began on -- for a list, its first cell.  The list's other
; cells are never stamped, and every procedure's body cell is one of them:
; each holds whatever its allocation left there, which can be the stamp of
; an object freed before it.  So the search starts at the body's first form,
; not at the body, and even there a stamp is believed only when its line is
; in range and its file is one the loader filed.
(def %profile-stamped?
  (fn (_ obj reg)
    ((fn (_ line)
       (match ((%profile-int< 0 line)
               (match ((%profile-int< line %profile-line-limit)
                       (match ((eq? (%profile-file (%profile-meta obj %profile-file-off) reg) ())
                               #f)
                              (#t #t)))
                      (#t #f)))
              (#t #f)))
     (%profile-meta obj %profile-line-off))))
(def %profile-where
  (fn (self obj reg depth)
    (match ((cov-cons? obj)
            (match ((%profile-stamped? obj reg)
                    (pair (%profile-meta obj %profile-file-off)
                          (%profile-meta obj %profile-line-off)))
                   ((%profile-int< depth %profile-where-depth)
                    (self (first obj) reg (%profile-int+ depth 1)))
                   (#t (pair 0 0))))
           (#t (pair 0 0)))))
(def %profile-body-where
  (fn (_ body reg)
    (match ((cov-cons? body) (%profile-where (first body) reg 0))
           (#t (pair 0 0)))))

; A row while it is being gathered: (file-id line calls evals nodes saturated).
(def %profile-row
  (fn (_ body trace reg)
    ((fn (_ at)
       (pair (first at)
         (pair (rest at)
           (pair (%profile-calls body) (profile-tree body trace)))))
     (%profile-body-where body reg))))
(def %profile-row-evals (fn (_ row) (first (rest (rest (rest row))))))
(def %profile-row-nodes (fn (_ row) (first (rest (rest (rest (rest row)))))))

; The rows of this module and of x/tool/cov are left out: what their bodies
; hold by the time they are read is the report's own work.  File 0 is input
; that was not a file, and is never one of the two.
(def %profile-keep?
  (fn (_ row own cov)
    (match ((eq? (%profile-row-evals row) 0) #f)
           ((eq? (first row) 0) #t)
           ((eq? (%profile-int- (first row) own) 0) #f)
           ((eq? (%profile-int- (first row) cov) 0) #f)
           (#t #t))))

(def %profile-gather
  (fn (self bodies trace reg own cov acc walked)
    (match ((eq? bodies ()) acc)
           (#t ((fn (_ row)
                  ((fn (_ walked)
                     (match ((%profile-int< %profile-collect-mask walked)
                             (%heap-collect-prim))
                            (#t ()))
                     (self (rest bodies) trace reg own cov
                       (match ((%profile-keep? row own cov) (pair row acc))
                              (#t acc))
                       (match ((%profile-int< %profile-collect-mask walked) 0)
                              (#t walked))))
                   (%profile-int+ walked (%profile-row-nodes row))))
                (%profile-row (first bodies) trace reg))))))

(def %profile-named
  (fn (self rows reg acc)
    (match ((eq? rows ()) acc)
           (#t (self (rest rows) reg
                 (pair (pair (%profile-file (first (first rows)) reg)
                             (rest (first rows)))
                       acc))))))

(doc (def profile-rows
  (fn (_)
    (%heap-collect-prim)
    ((fn (_ reg)
       ((fn (_ own cov bodies)
          ((fn (_ rows)
             (%profile-release bodies %obj-flag-trace)
             (%profile-named rows reg ()))
           (%profile-gather bodies %obj-flag-trace reg own cov () 0)))
        (first (%profile-body-where (cov-body %profile-row) reg))
        (first (%profile-body-where (cov-body cov-body) reg))
        (%profile-bodies %obj-flag-trace)))
     (first %profile-registry))))
  (returns LIST "One (file line calls evals nodes saturated) row for each function body evaluation reached, in no order")
  "Return the calls and evaluation of every function on the heap, by the file and line its body starts on.")

; The engine clears the count's bits across the whole allocation chain in one
; pass, and leaves every other flag bit as it was.
(doc (def profile-clear!
  (fn (_)
    (%profile-chain-clear! (%profile-int<< (profile-evals-max) %obj-evals-shift))))
  (returns NIL "nil")
  "Set the eval count of every object on the heap to zero, so that what is counted next belongs to what runs next.")

(def %profile-print
  (fn (self rows n)
    (if (null? rows)
      ()
      (if (%profile-int< 0 n)
        ((fn (_ row)
           (display (first (rest (rest (rest row))))
                    (if (first (rest (rest (rest (rest (rest row)))))) "+" "")
                    "\t" (first (rest (rest row)))
                    "\t" (first (rest (rest (rest (rest row)))))
                    "\t" (first row) ":" (first (rest row)) "\n")
           (self (rest rows) (%profile-int- n 1)))
         (first rows))
        ()))))

(doc (def profile-report
  (fn (_ n)
    ; The rows are read before anything prints: the printer is library code,
    ; and what it ran first would be counted into them.
    ((fn (_ rows)
       (display "evals\tcalls\tpairs\twhere\n")
       (%profile-print
         (List sort
           (fn (_ a b)
             (%profile-int< (first (rest (rest (rest b))))
                            (first (rest (rest (rest a))))))
           rows)
         n))
     (profile-rows))))
  (param n INTEGER "Rows to print")
  (returns ANY "nil")
  (note "A + after a row's evals says a count in that body was at its maximum, so the sum is a lower bound.")
  "Print the n functions whose bodies evaluation reached most, most first.")

; --- Output ---

; READER-NEUTRAL ON PURPOSE.  A lang bundle imports this module through its
; OWN reader (x-sweet does), and #"..." interpolation is a he/xe reader
; feature: sweet's reader mangled the literal silently (then spelled $"..."),
; and the mangled body crashed the engine when evaluated (found live,
; 2026-09-01).  Plain prims and 2-arg appends read identically under every
; reader this module can arrive through.
; The helpers are BODY defs, not globals (the percent-globals budget holds
; this file at 4) -- dump runs once, so the defs-at-depth cost is nothing.
(doc (def profile-dump
  (fn (_ )
    (def %prof-sa (prim-ref (lit str) (lit append)))
    (def %prof-w (prim-ref (lit io) (lit write-to-str)))
    (def %prof-kv
      (fn (_ label value rest)
        (%prof-sa label (%prof-sa (%prof-w value) rest))))
    (%stderr
      (%prof-kv "allocs=" (alloc-count)
        (%prof-kv " evals=" (eval-count)
          (%prof-kv " tco=" (tco-count)
            (%prof-kv " assoc-calls=" (assoc-calls-count)
              (%prof-kv " assoc-steps=" (assoc-steps-count)
                (%prof-kv " sym-find-calls=" (sym-find-calls-count)
                  (%prof-kv " sym-find-steps=" (sym-find-steps-count)
                    (%prof-kv " gc-runs=" (gc-runs-count)
                      (%prof-kv " bst-hits=" (bst-hits-count)
                        (%prof-kv " bst-misses=" (bst-misses-count)
                          (%prof-kv " heap=" (Heap count) "\n"))))))))))))))
  "Dump all profile counters to stderr.")

(doc (provide x/tool/profile
  alloc-count eval-count tco-count
  assoc-calls-count assoc-steps-count
  sym-find-calls-count sym-find-steps-count
  gc-runs-count bst-hits-count bst-misses-count
  profile-reset profile-dump
  profile-evals-max profile-evals profile-tree profile-fn
  profile-rows profile-clear! profile-report
  heap-collect heap-collect-force)
  "Performance profiling and smart garbage collection.")
