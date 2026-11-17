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
; A kernel is a function in the Metal Shading Language marked `kernel`.
; run binds the buffers to it in order, the first to [[buffer(0)]], and
; calls it once for each point of a WIDTH by HEIGHT grid; the kernel reads
; its point from a `uint2` parameter marked [[thread_position_in_grid]],
; x across the width and y down the height.  Numbers a kernel needs beside
; its data -- a matrix's dimensions -- go in a buffer of their own.  The
; language has no double: a kernel's floats are 32-bit.
;
; run returns when the GPU has finished, so the bytes it wrote are there to
; read.  Each message that makes Objective-C objects runs inside an
; autorelease pool of its own, so a kernel run many times leaves nothing
; behind.
;
; The module loads on any host, and available? answers #f where Metal is
; not: off macOS, and on a Mac that is not arm64, where the sizes run hands
; Metal would be passed another way than ptr call passes them.

(module x/sys/darwin/metal)
(import x/type/class)
(import x/core/list)
(import x/core/doors ffi-dlopen ffi-dlsym int->ptr ptr->str ptr-call ptr-ref-word ptr-set-word! str->ptr str-make)

(def-class Metal ()
  (doc "Buffers the GPU and x share, and kernels compiled from Metal Shading Language source and run over them, through macOS's Metal framework loaded with dlopen."
    (note "The module loads on any host; available? answers #f off macOS and on a Mac that is not arm64, and the other messages raise a label 'io there.")
    (note "A kernel's floats are 32-bit: the Metal Shading Language has no double.")
    (example "(boolean? (Metal available?))" "#t")
    (see available?) (see buffer) (see compile) (see run))
  (static
    (%framework "/System/Library/Frameworks/Metal.framework/Metal")
    (%runtime "/usr/lib/libobjc.A.dylib")
    (%completed 4)

    (method %objc (self (param name STRING "A function of the Objective-C runtime"))
      (doc "The named function of the Objective-C runtime."
        (returns POINTER "The function pointer")
        (sample "(Metal %objc \"objc_msgSend\")" "a function pointer"))
      (ffi-dlsym (ffi-dlopen (Metal %runtime) 1) name))

    (method %selector (self (param name STRING "A selector's name, colons included"))
      (doc "The selector of that name."
        (returns INTEGER "The selector, as an integer")
        (sample "(Metal %selector \"contents\")" "the selector"))
      (ptr-call (Metal %objc "sel_registerName") name))

    (method %send (self (param to INTEGER "The receiving object")
                        (param name STRING "The selector's name")
                        . (param args LIST "Up to four integer or pointer arguments"))
      (doc "Send the object a message and answer its integer or pointer result."
        (returns INTEGER "The result, 0 for nil")
        (sample "(Metal %send buf \"length\")" "the buffer's byte length"))
      (apply ptr-call (pair (Metal %objc "objc_msgSend") (pair to (pair (Metal %selector name) args)))))

    (method %text (self (param s STRING "The text"))
      (doc "An autoreleased NSString holding the text."
        (returns INTEGER "The NSString")
        (sample "(Metal %text \"matmul\")" "an NSString"))
      (Metal %send (ptr-call (Metal %objc "objc_getClass") "NSString") "stringWithUTF8String:" s))

    (method %string (self (param ns INTEGER "An NSString"))
      (doc "The NSString's text as an x string."
        (returns STRING "A copy of the text")
        (sample "(Metal %string (Metal %text \"a\"))" "\"a\""))
      (Str8 append (ptr->str (int->ptr (Metal %send ns "UTF8String"))) ""))

    (method %pooled (self (param body CALLABLE "A function of no arguments"))
      (doc "Call body inside an autorelease pool and answer its result. body must not raise: the pool would stay open."
        (returns ANY "What body answers")
        (sample "(Metal %pooled (fn (_) 1))" "1"))
      (def pool (ptr-call (Metal %objc "objc_autoreleasePoolPush")))
      (def result (body))
      (ptr-call (Metal %objc "objc_autoreleasePoolPop") pool)
      result)

    (method %device (self)
      (doc "The default Metal device, retained, or 0 when this host has none."
        (returns INTEGER "The device; the caller releases it")
        (sample "(Metal %device)" "the device"))
      (def h (if arch-arm64? (ffi-dlopen (Metal %framework) 1) ()))
      (if (null? h) 0 (ptr-call (ffi-dlsym h "MTLCreateSystemDefaultDevice"))))

    (method %need-device (self)
      (doc "The default Metal device, retained; raises a label 'io when this host has none."
        (returns INTEGER "The device; the caller releases it")
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
      (if (= e 0) "" (Metal %string (Metal %send e "localizedDescription"))))

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
      (if (= device 0) #f
        (do (Metal %send device "release") #t)))

    (method device-name (self)
      (doc "The name of the default Metal device."
        (returns STRING "The name")
        (sample "(Metal device-name)" "\"Apple M2 Pro\""))
      (def device (Metal %need-device))
      (def name (Metal %pooled (fn (_) (Metal %string (Metal %send device "name")))))
      (Metal %send device "release")
      name)

    (method buffer (self (param bytes INTEGER "The buffer's length in bytes, above 0"))
      (doc "A buffer of that many zero bytes that the GPU and x both address."
        (returns INTEGER "The buffer; give it back with release")
        (sample "(Metal buffer 4096)" "a buffer"))
      (def device (Metal %need-device))
      (def buf (Metal %send device "newBufferWithLength:options:" bytes 0))
      (Metal %send device "release")
      (when (= buf 0)
        (Err raise (lit io) "Metal buffer: the device made none" bytes))
      buf)

    (method pointer (self (param buf INTEGER "A buffer from buffer"))
      (doc "The buffer's bytes: what x reads and writes, and what a kernel bound to the buffer sees."
        (returns POINTER "The first byte; it stays where it is until the buffer is released")
        (sample "(ptr-ref-word (Metal pointer buf) 0)" "the buffer's first word"))
      (int->ptr (Metal %send buf "contents")))

    (method compile (self (param source STRING "Metal Shading Language source")
                          (param name STRING "The kernel function to run"))
      (doc "Compile the source and answer a pipeline that runs its kernel NAME. Raises a label 'value with the compiler's message when the source does not compile, and when it has no kernel of that name."
        (returns LIST "The pipeline; give it back with release")
        (sample "(Metal compile \"kernel void k(device uint* a [[buffer(0)]], uint2 at [[thread_position_in_grid]]) { a[at.x] *= 2; }\" \"k\")" "a pipeline"))
      (def device (Metal %need-device))
      (def cell (str-make 8))
      ; the pipeline state and its queue, or the message to raise with
      (def made
        (Metal %pooled
          (fn (_)
            (ptr-set-word! (str->ptr cell) 0 0)
            (def library (Metal %send device "newLibraryWithSource:options:error:"
                                (Metal %text source) 0 (str->ptr cell)))
            (if (= library 0) (Metal %error-text cell)
              (let ((function (Metal %send library "newFunctionWithName:" (Metal %text name))))
                (Metal %send library "release")
                (if (= function 0) (Str8 append "no kernel named " name)
                  (do (ptr-set-word! (str->ptr cell) 0 0)
                      (let ((state (Metal %send device "newComputePipelineStateWithFunction:error:"
                                          function (str->ptr cell))))
                        (Metal %send function "release")
                        (if (= state 0) (Metal %error-text cell)
                          (list state (Metal %send device "newCommandQueue")))))))))))
      (Metal %send device "release")
      (when (str? made)
        (Err raise (lit value) (Str8 append "Metal compile: " made) name))
      made)

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
            (def commands (Metal %send (List ref 1 pipeline) "commandBuffer"))
            (def encoder (Metal %send commands "computeCommandEncoder"))
            (Metal %send encoder "setComputePipelineState:" state)
            (let bind ((bufs buffers) (i 0))
              (when (pair? bufs)
                (do (Metal %send encoder "setBuffer:offset:atIndex:" (first bufs) 0 i)
                    (bind (rest bufs) (+ i 1)))))
            ; a group as wide as the device runs together, and as tall as
            ; that leaves of the most a group may hold
            (def across (Metal %send state "threadExecutionWidth"))
            (def down (/ (Metal %send state "maxTotalThreadsPerThreadgroup") across))
            (def grid (Metal %size width height))
            (def group (Metal %size across down))
            (Metal %send encoder "dispatchThreads:threadsPerThreadgroup:" (str->ptr grid) (str->ptr group))
            (Metal %send encoder "endEncoding")
            (Metal %send commands "commit")
            (Metal %send commands "waitUntilCompleted")
            (if (= (Metal %send commands "status") (Metal %completed)) ()
              (let ((e (Metal %send commands "error")))
                (if (= e 0) "the run did not complete"
                  (Metal %string (Metal %send e "localizedDescription"))))))))
      (when (str? failure)
        (Err raise (lit io) (Str8 append "Metal run: " failure) ()))
      ())

    (method release (self (param x INTEGER|LIST "A buffer from buffer, or a pipeline from compile"))
      (doc "Give a buffer or a pipeline back to Metal. A buffer's pointer, and the pipeline, must not be used afterwards."
        (returns ANY "nil")
        (sample "(Metal release buf)" "nil"))
      (if (pair? x)
        (List for-each (fn (_ part) (Metal %send part "release")) x)
        (Metal %send x "release"))
      ())))

(doc (provide x/sys/darwin/metal Metal)
  (example "(boolean? (Metal available?))" "#t")
  "Buffers shared with the GPU, and kernels compiled from Metal Shading Language source and run over them, through macOS's Metal framework over the dlopen FFI.")
