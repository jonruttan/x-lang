; sys/darwin/metal.x -- Metal: buffers the GPU and x share, and kernels
; compiled from source and run over them, through macOS's Metal framework.
;
; Metal is bound the way sys/sdl.x binds SDL3: dlopen, dlsym and ptr call
; from x/core/doors, no new C.  Metal's interface is Objective-C, and every
; message goes through the runtime's objc_msgSend, which takes the receiver,
; the selector and then integers and pointers only.
;
;   (Metal available?)          -> #t when this host has a Metal device
;   (Metal device-name)         -> the device's name
;   (Metal buffer bytes)        -> a zeroed buffer of that many bytes
;   (Metal pointer buf)         -> the buffer's bytes, to read and write
;   (Metal compile source name) -> a pipeline: the kernel NAME in SOURCE
;   (Metal run pipeline buffers width height)
;                               -> the kernel run over the grid, and waited for
;   (Metal release x)           -> a buffer or a pipeline given back
;
; A buffer is memory the processor and the GPU both address: x reads and
; writes it through its pointer with ptr ref and ptr set!, and a kernel
; reads and writes the same bytes, so nothing is copied either way.
;
; A kernel is a grid form (x/tool/grid-form), which %kernel turns into the
; Metal Shading Language, or a function written in that language marked
; `kernel`, which compile takes as it stands.
; run binds the buffers to it in order, the first to [[buffer(0)]], and
; calls it once for each point of a WIDTH by HEIGHT grid; the kernel reads
; its point from a `uint2` parameter marked [[thread_position_in_grid]],
; x across the width and y down the height.  Numbers a kernel needs beside
; its data -- a matrix's dimensions -- go in a buffer of their own.  The
; language has no double: a kernel's floats are 32-bit.
;
; run returns when the GPU has finished, so the bytes it wrote are there to
; read.
;
; What a message needs is looked up once in a process and kept: the
; runtime's functions, each selector, and the default device, which is
; retained for the life of the process.  They are process state, so they
; are dropped before a state image is written, and looked up again when
; next wanted.  Each message that makes Objective-C objects runs inside an
; autorelease pool of its own, so a kernel run many times leaves nothing
; behind.
;
; The module loads on any host, and available? answers #f where Metal is
; not: off macOS, and on a Mac that is not arm64, where the sizes run hands
; Metal would be passed another way than ptr call passes them.

(module x/sys/darwin/metal)
(import x/type/class)
(import x/core/list)
(import x/tool/grid-form grid-form-plan grid-form-metal)
(import x/core/doors ffi-dlopen ffi-dlsym image-transient! int+ int->ptr ptr->str ptr-call ptr-ref-word ptr-set-word! str->ptr str-make)

; The runtime's functions by name, ((NAME . POINTER) ...), and the
; selectors by name, ((NAME . SELECTOR) ...), each looked up the first time
; it is wanted; and the default device, nil until it is asked for and 0 on
; a host with none.
(def %mt-fns (pair () ()))
(def %mt-sels (pair () ()))
(def %mt-device (pair () ()))

; The value kept under name in the cell's list, made by make the first time.
(def %mt-kept
  (fn (_ cell name make)
    (let find ((es (first cell)))
      (match
        ((null? es)
          (let ((v (make name)))
            (%set-first! cell (pair (pair name v) (first cell)))
            v))
        ((str=? (first (first es)) name) (rest (first es)))
        (#t (find (rest es)))))))

(def %mt-runtime "/usr/lib/libobjc.A.dylib")
(def %mt-fn
  (fn (_ name)
    (%mt-kept %mt-fns name (fn (_ n) (ffi-dlsym (ffi-dlopen %mt-runtime 1) n)))))

(def %mt-sel
  (fn (_ name) (%mt-kept %mt-sels name (fn (_ n) (ptr-call (%mt-fn "sel_registerName") n)))))

; A message to the object to: its integer or pointer result.
(def %mt-send
  (fn (_ to name . args)
    (apply ptr-call (pair (%mt-fn "objc_msgSend") (pair to (pair (%mt-sel name) args))))))

(image-transient!
  (fn (_) (%set-first! %mt-fns ()) (%set-first! %mt-sels ()) (%set-first! %mt-device ())))

(def-class Metal ()
  (doc "Buffers the GPU and x share, and kernels compiled from grid forms or Metal Shading Language source and run over them, through macOS's Metal framework loaded with dlopen."
    (note "The module loads on any host; available? answers #f off macOS and on a Mac that is not arm64, and the other messages raise a label 'io there.")
    (note "A kernel's floats are 32-bit: the Metal Shading Language has no double.")
    (example "(boolean? (Metal available?))" "#t")
    (see available?) (see buffer) (see compile) (see run))
  (static
    (%framework "/System/Library/Frameworks/Metal.framework/Metal")
    (%completed 4)

    (method %objc (self (param name STRING "A function of the Objective-C runtime"))
      (doc "The named function of the Objective-C runtime."
        (returns POINTER "The function pointer")
        (sample "(Metal %objc \"objc_msgSend\")" "a function pointer"))
      (%mt-fn name))

    (method %selector (self (param name STRING "A selector's name, colons included"))
      (doc "The selector of that name."
        (returns INTEGER "The selector, as an integer")
        (sample "(Metal %selector \"contents\")" "the selector"))
      (%mt-sel name))

    (method %send (self (param to INTEGER "The receiving object")
                        (param name STRING "The selector's name")
                        . (param args LIST "Up to four integer or pointer arguments"))
      (doc "Send the object a message and answer its integer or pointer result."
        (returns INTEGER "The result, 0 for nil")
        (sample "(Metal %send buf \"length\")" "the buffer's byte length"))
      (apply %mt-send (pair to (pair name args))))

    (method %text (self (param s STRING "The text"))
      (doc "An autoreleased NSString holding the text."
        (returns INTEGER "The NSString")
        (sample "(Metal %text \"matmul\")" "an NSString"))
      (%mt-send (ptr-call (%mt-fn "objc_getClass") "NSString") "stringWithUTF8String:" s))

    (method %string (self (param ns INTEGER "An NSString"))
      (doc "The NSString's text as an x string."
        (returns STRING "A copy of the text")
        (sample "(Metal %string (Metal %text \"a\"))" "\"a\""))
      (Str8 append (ptr->str (int->ptr (%mt-send ns "UTF8String"))) ""))

    (method %pooled (self (param body CALLABLE "A function of no arguments"))
      (doc "Call body inside an autorelease pool and answer its result. body must not raise: the pool would stay open."
        (returns ANY "What body answers")
        (sample "(Metal %pooled (fn (_) 1))" "1"))
      (def pool (ptr-call (%mt-fn "objc_autoreleasePoolPush")))
      (def result (body))
      (ptr-call (%mt-fn "objc_autoreleasePoolPop") pool)
      result)

    (method %device (self)
      (doc "The default Metal device, or 0 when this host has none. It is made the first time it is asked for and kept for the process."
        (returns INTEGER "The device, which the caller does not release")
        (sample "(Metal %device)" "the device"))
      (when (null? (first %mt-device))
        (%set-first! %mt-device
          (let ((h (if arch-arm64? (ffi-dlopen (Metal %framework) 1) ())))
            (if (null? h) 0 (ptr-call (ffi-dlsym h "MTLCreateSystemDefaultDevice"))))))
      (first %mt-device))

    (method %need-device (self)
      (doc "The default Metal device, kept for the process; raises a label 'io when this host has none."
        (returns INTEGER "The device, which the caller does not release")
        (sample "(Metal %need-device)" "the device"))
      (def device (Metal %device))
      (when (= device 0)
        (Err raise (lit io) "Metal: no device on this host" ()))
      device)

    (method %error-text (self (param cell STRING "The word an error: argument pointed at"))
      (doc "The description of the NSError a call left in the cell, or an empty string when it left none."
        (returns STRING "The description")
        (sample "(Metal %error-text cell)" "the compiler's message"))
      (def e (ptr-ref-word (str->ptr cell) 0))
      (if (= e 0) "" (Metal %string (%mt-send e "localizedDescription"))))

    (method %size (self (param width INTEGER "Points across") (param height INTEGER "Points down"))
      (doc "An MTLSize of width, height and a depth of 1: three words."
        (returns STRING "The 24-byte region")
        (sample "(Metal %size 8 8)" "a 24-byte region"))
      (def s (str-make 24))
      (ptr-set-word! (str->ptr s) 0 width)
      (ptr-set-word! (str->ptr s) 8 height)
      (ptr-set-word! (str->ptr s) 16 1)
      s)

    (method available? (self)
      (doc "Whether this host has a Metal device."
        (returns BOOL "#t on an arm64 Mac with a GPU Metal reaches")
        (sample "(Metal available?)" "#t on an Apple silicon Mac"))
      (def device (Metal %device))
      (not (= device 0)))

    (method device-name (self)
      (doc "The name of the default Metal device."
        (returns STRING "The name")
        (sample "(Metal device-name)" "\"Apple M2 Pro\""))
      (def device (Metal %need-device))
      (Metal %pooled (fn (_) (Metal %string (%mt-send device "name")))))

    (method buffer (self (param bytes INTEGER "The buffer's length in bytes, above 0"))
      (doc "A buffer of that many zero bytes that the GPU and x both address."
        (returns INTEGER "The buffer; give it back with release")
        (sample "(Metal buffer 4096)" "a buffer"))
      (def device (Metal %need-device))
      (def buf (%mt-send device "newBufferWithLength:options:" bytes 0))
      (when (= buf 0)
        (Err raise (lit io) "Metal buffer: the device made none" bytes))
      buf)

    (method pointer (self (param buf INTEGER "A buffer from buffer"))
      (doc "The buffer's bytes: what x reads and writes, and what a kernel bound to the buffer sees."
        (returns POINTER "The first byte; it stays where it is until the buffer is released")
        (sample "(ptr-ref-word (Metal pointer buf) 0)" "the buffer's first word"))
      (int->ptr (%mt-send buf "contents")))

    (method compile (self (param source STRING "Metal Shading Language source")
                          (param name STRING "The kernel function to run"))
      (doc "Compile the source and answer a pipeline that runs its kernel NAME. Raises a label 'value with the compiler's message when the source does not compile, and when it has no kernel of that name."
        (returns LIST "The pipeline, (STATE QUEUE THREADS): the compiled kernel, its command queue, and the threads across for each grid point, 1; give it back with release")
        (sample "(Metal compile \"kernel void k(device uint* a [[buffer(0)]], uint2 at [[thread_position_in_grid]]) { a[at.x] *= 2; }\" \"k\")" "a pipeline"))
      (def device (Metal %need-device))
      (def cell (str-make 8))
      ; the pipeline state and its queue, or the message to raise with
      (def made
        (Metal %pooled
          (fn (_)
            (ptr-set-word! (str->ptr cell) 0 0)
            (def library (%mt-send device "newLibraryWithSource:options:error:"
                                (Metal %text source) 0 (str->ptr cell)))
            (if (= library 0) (Metal %error-text cell)
              (let ((function (%mt-send library "newFunctionWithName:" (Metal %text name))))
                (%mt-send library "release")
                (if (= function 0) (Str8 append "no kernel named " name)
                  (do (ptr-set-word! (str->ptr cell) 0 0)
                      (let ((state (%mt-send device "newComputePipelineStateWithFunction:error:"
                                          function (str->ptr cell))))
                        (%mt-send function "release")
                        (if (= state 0) (Metal %error-text cell)
                          (list state (%mt-send device "newCommandQueue") 1))))))))))
      (when (str? made)
        (Err raise (lit value) (Str8 append "Metal compile: " made) name))
      made)

    (method %kernel (self (param form LIST "A grid form")
                          (param name STRING "The kernel's name, any text"))
      (doc "Compile a grid form and answer a pipeline that runs it: the form's parameters are its buffers, bound in order from index 0. A form that names a team runs 32 threads, a simdgroup, at each grid point. Raises a label 'value for a form that is not a grid form."
        (returns LIST "The pipeline; give it back with release")
        (sample "(Metal %kernel (lit (fn (_ a) (f32-set! a at-x (f* (f32-ref a at-x) (f32-ref a at-x))))) \"square\")" "a pipeline"))
      (def plan (grid-form-plan form))
      ; the function is named apart from the kernel, whose name need not be one Metal takes
      (def made (Metal compile (grid-form-metal form "grid") "grid"))
      (list (first made) (List ref 1 made) (if (List ref 4 plan) 32 1)))

    (method run (self (param pipeline LIST "A pipeline from compile")
                      (param buffers LIST "The buffers the kernel reads and writes, in the order of its buffer indexes")
                      (param width INTEGER "The grid's points across, above 0")
                      (param height INTEGER "The grid's points down, above 0"))
      (doc "Run the pipeline's kernel once for each point of the width by height grid, with the buffers bound in order from index 0, and wait until the GPU has finished. Raises a label 'io with Metal's message when the run fails."
        (returns ANY "nil")
        (sample "(Metal run pipeline (list buf) 1024 1)" "nil, the kernel run on 1024 points"))
      (def state (first pipeline))
      (def failure
        (Metal %pooled
          (fn (_)
            (def commands (%mt-send (List ref 1 pipeline) "commandBuffer"))
            (def encoder (%mt-send commands "computeCommandEncoder"))
            (%mt-send encoder "setComputePipelineState:" state)
            (let bind ((bufs buffers) (i 0))
              (when (pair? bufs)
                (do (%mt-send encoder "setBuffer:offset:atIndex:" (first bufs) 0 i)
                    (bind (rest bufs) (+ i 1)))))
            ; a group as wide as the device runs together, and as tall as
            ; that leaves of the most a group may hold
            (def across (%mt-send state "threadExecutionWidth"))
            (def down (/ (%mt-send state "maxTotalThreadsPerThreadgroup") across))
            (def grid (Metal %size (* width (List ref 2 pipeline)) height))
            (def group (Metal %size across down))
            (%mt-send encoder "dispatchThreads:threadsPerThreadgroup:" (str->ptr grid) (str->ptr group))
            (%mt-send encoder "endEncoding")
            (%mt-send commands "commit")
            (%mt-send commands "waitUntilCompleted")
            (if (= (%mt-send commands "status") (Metal %completed)) ()
              (let ((e (%mt-send commands "error")))
                (if (= e 0) "the run did not complete"
                  (Metal %string (%mt-send e "localizedDescription"))))))))
      (when (str? failure)
        (Err raise (lit io) (Str8 append "Metal run: " failure) ()))
      ())

    ; --- many kernels in one command buffer -----------------------------------
    ; A run costs its command buffer and its wait whatever it works out, and
    ; a message sent through %mt-send costs its lookups.  A step is a
    ; kernel's run made ready, (STATE QUEUE BUFFERS GRID GROUP), and
    ; %run-steps encodes a list of them into one command buffer, each
    ; message sent with its selector already found, and waits once.  The
    ; steps run in order, each seeing what those before it wrote.
    (method %step (self (param pipeline LIST "A pipeline from compile")
                        (param buffers LIST "The buffers the kernel reads and writes, in the order of its buffer indexes")
                        (param width INTEGER "The grid's points across, above 0")
                        (param height INTEGER "The grid's points down, above 0"))
      (doc "A kernel's run made ready for %run-steps: the grid and the group it runs in are worked out now."
        (returns LIST "The step")
        (sample "(Metal %step pipeline (list buf) 1024 1)" "a step"))
      (def state (first pipeline))
      (def across (%mt-send state "threadExecutionWidth"))
      (def down (/ (%mt-send state "maxTotalThreadsPerThreadgroup") across))
      (list state (List ref 1 pipeline) buffers
            (Metal %size (* width (List ref 2 pipeline)) height) (Metal %size across down)))

    (method %run-steps (self (param steps LIST "Steps from %step, at least one"))
      (doc "Run the steps' kernels in order in one command buffer, and wait until the GPU has finished them all. Raises a label 'io with Metal's message when the run fails."
        (returns ANY "nil")
        (sample "(Metal %run-steps (list step))" "nil, every step's kernel run"))
      (def msg (%mt-fn "objc_msgSend"))
      (def pipe (%mt-sel "setComputePipelineState:"))
      (def bind (%mt-sel "setBuffer:offset:atIndex:"))
      (def dispatch (%mt-sel "dispatchThreads:threadsPerThreadgroup:"))
      (def failure
        (Metal %pooled
          (fn (_)
            (def commands (%mt-send (List ref 1 (first steps)) "commandBuffer"))
            (def encoder (%mt-send commands "computeCommandEncoder"))
            ((fn (go l)
               (if (null? l) ()
                 (let ((step (first l)))
                   (ptr-call msg encoder pipe (first step))
                   ((fn (each bufs i)
                      (if (null? bufs) ()
                        (do (ptr-call msg encoder bind (first bufs) 0 i)
                            (each (rest bufs) (int+ i 1)))))
                     (first (rest (rest step))) 0)
                   (ptr-call msg encoder dispatch
                     (str->ptr (first (rest (rest (rest step)))))
                     (str->ptr (first (rest (rest (rest (rest step)))))))
                   (go (rest l)))))
              steps)
            (%mt-send encoder "endEncoding")
            (%mt-send commands "commit")
            (%mt-send commands "waitUntilCompleted")
            (if (= (%mt-send commands "status") (Metal %completed)) ()
              (let ((e (%mt-send commands "error")))
                (if (= e 0) "the run did not complete"
                  (Metal %string (%mt-send e "localizedDescription"))))))))
      (when (str? failure)
        (Err raise (lit io) (Str8 append "Metal run: " failure) ()))
      ())

    (method release (self (param x INTEGER|LIST "A buffer from buffer, or a pipeline from compile"))
      (doc "Give a buffer or a pipeline back to Metal. A buffer's pointer, and the pipeline, must not be used afterwards."
        (returns ANY "nil")
        (sample "(Metal release buf)" "nil"))
      (if (pair? x)
        (do (%mt-send (first x) "release") (%mt-send (List ref 1 x) "release"))
        (%mt-send x "release"))
      ())))

(doc (provide x/sys/darwin/metal Metal)
  (example "(boolean? (Metal available?))" "#t")
  "Buffers shared with the GPU, and kernels compiled from grid forms or Metal Shading Language source and run over them, through macOS's Metal framework over the dlopen FFI.")
