; sys/vulkan.x -- Vulkan: buffers the GPU and x share, and grid forms
; compiled and run over them, through the host's Vulkan library.
;
; Vulkan is bound the way sys/sdl.x binds SDL3: dlopen, dlsym and ptr call
; from x/core/doors, no new C.  Its functions take integers, handles and
; pointers to structures, which are built here in strings, a field at a
; time.  It answers the messages x/sys/darwin/metal answers, so x/num/gpu
; runs on either.
;
;   (Vulkan available?)        -> #t when this host has a Vulkan 1.3 device
;   (Vulkan device-name)       -> the device's name
;   (Vulkan buffer bytes)      -> a zeroed buffer of that many bytes
;   (Vulkan pointer buf)       -> the buffer's bytes, to read and write
;   (Vulkan run pipeline buffers width height)
;                              -> the kernel run over the grid, and waited for
;   (Vulkan release x)         -> a buffer or a pipeline given back
;
; A buffer is memory the device lets the processor see, mapped once for
; the buffer's life: x reads and writes it through its pointer, and a
; kernel reads and writes the same bytes.  On a device with memory of its
; own, a discrete card, that memory is the host's and the card reaches it
; across the bus.
;
; A kernel is a grid form (x/tool/grid-form), written as SPIR-V by
; x/tool/spirv: Vulkan takes no source text.  A device runs a kernel in
; groups whose size is fixed when it is compiled, so a pipeline holds the
; form's plan and compiles it for the shape of grid it is first run on: a
; row, a grid one point down, in groups of 64 by 1; any other in groups of
; 8 by 8; and a form with a team in groups of 32 by 1, a group to a point.
;
; The steps of a run are recorded into one command buffer with a barrier
; after each, so a step sees what those before it wrote, and run returns
; when the device has finished.
;
; The device asked for is version 1.3: the barrier between steps is that
; version's, the earlier one taking more arguments than ptr call passes.
; Of several devices a discrete GPU is taken first, then an integrated
; one, a virtual one, and last a software device, which runs kernels on
; the processor: lavapipe is one, and answers available? as any other.
;
; What a message needs is looked up once in a process and kept: the
; library's functions, and the instance, device, queue and command buffer.
; They are process state, dropped before a state image is written and made
; again when next wanted, so a buffer or a pipeline is not to be kept
; across the writing of one.
;
; The module loads on any host, and available? answers #f where no device
; is reached: with no Vulkan library, with no device of version 1.3, and
; on a 4-byte word, where a handle is two words and the functions take
; more of them than ptr call passes.
;
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(module x/sys/vulkan)
(import x/type/class)
(import x/core/list)
(import x/tool/grid-form grid-form-plan)
(import x/tool/spirv)
(import x/core/doors ffi-dlopen ffi-dlsym image-transient! int& int* int+ int- int/ int< int<< int= int>> int->ptr mem-set ptr->int ptr->str ptr-call ptr-ref ptr-ref-word ptr-set! ptr-set-word! str->ptr str-make)

; The library's functions by name, ((NAME . POINTER) ...), each looked up
; the first time it is wanted; and the device's state, nil until it is
; asked for and 0 on a host with none.
(def %vk-fns (pair () ()))
(def %vk-state (pair () ()))

(image-transient! (fn (_) (%set-first! %vk-fns ()) (%set-first! %vk-state ())))

; The library's handle, or nil where none opens.
(def %vk-handle
  (fn (_)
    (let try ((names (list "libvulkan.so.1" "libvulkan.so" "libvulkan.1.dylib")))
      (if (null? names) ()
        (let ((h (ffi-dlopen (first names) 1)))
          (if h h (try (rest names))))))))

(def %vk-fn
  (fn (_ name)
    (let find ((es (first %vk-fns)))
      (match
        ((null? es)
          (let ((p (ffi-dlsym (%vk-handle) name)))
            (%set-first! %vk-fns (pair (pair name p) (first %vk-fns)))
            p))
        ((str=? (first (first es)) name) (rest (first es)))
        (#t (find (rest es)))))))

(def %vk-call
  (fn (_ name . args) (apply ptr-call (pair (%vk-fn name) args))))

; A result is 32 bits, 0 for success; the rest of the word is not its.
(def %vk-ok?
  (fn (_ result) (int= (int<< result 32) 0)))

(def %vk-need
  (fn (_ result what)
    (if (%vk-ok? result) ()
      (Err raise (lit io) (Str8 append "Vulkan " what ": the device refused") (int>> (int<< result 32) 32)))))

; A zeroed region of BYTES bytes.
(def %vk-room
  (fn (_ bytes)
    (let ((s (str-make bytes)))
      (mem-set (str->ptr s) 0 bytes)
      s)))

(def %vk-at (fn (_ s) (ptr->int (str->ptr s))))

; A structure: BYTES zero bytes with FIELDS, ((OFFSET WIDTH VALUE) ...),
; stored.  A value is an integer; a region's address is (%vk-at region).
(def %vk-struct
  (fn (_ bytes fields)
    (let ((s (%vk-room bytes)))
      (let go ((fs fields))
        (if (null? fs) s
          (let ((f (first fs)))
            (ptr-set! (str->ptr s) (first f) (List ref 2 f) (List ref 1 f))
            (go (rest fs))))))))

; The word a call left in an 8-byte region.
(def %vk-word (fn (_ s) (ptr-ref-word (str->ptr s) 0)))

(def-class Vulkan ()
  (doc "Buffers the GPU and x share, and grid forms compiled to SPIR-V and run over them, through the host's Vulkan library loaded with dlopen."
    (note "The module loads on any host; available? answers #f with no Vulkan library, with no device of version 1.3, and on a 4-byte word, and the other messages raise a label 'io there.")
    (note "A software device answers available? as a GPU does: where lavapipe is the only device, kernels run on the processor.")
    (example "(boolean? (Vulkan available?))" "#t")
    (see available?) (see buffer) (see run))
  (static
    (%version-1-3 4206592)
    (%storage-buffer 7)
    (%compute-stage 32)
    (%whole-size -1)
    (%most-groups 65535)

    (method %rank (self (param kind INTEGER "A device's type, as Vulkan numbers them"))
      (doc "How soon a device of that type is taken, the lowest first: a discrete GPU, an integrated one, a virtual one, a software device, any other."
        (returns INTEGER "0 to 4")
        (example "(List map (fn (_ k) (Vulkan %rank k)) (list 2 1 3 4 0))" "(0 1 2 3 4)"))
      (match ((int= kind 2) 0) ((int= kind 1) 1) ((int= kind 3) 2) ((int= kind 4) 3) (#t 4)))

    (method %compute-family (self (param physical INTEGER "A physical device"))
      (doc "The first of the device's queue families that runs compute work, or nil when none does."
        (returns INTEGER|NIL "The family's index")
        (sample "(Vulkan %compute-family physical)" "0"))
      (def count (%vk-room 8))
      (%vk-call "vkGetPhysicalDeviceQueueFamilyProperties" physical (str->ptr count) ())
      (def n (ptr-ref (str->ptr count) 0 4))
      (def families (%vk-room (int* 24 (if (int< n 1) 1 n))))
      (%vk-call "vkGetPhysicalDeviceQueueFamilyProperties" physical (str->ptr count) (str->ptr families))
      (let find ((i 0))
        (match
          ((int= i n) ())
          ((int= (int& (ptr-ref (str->ptr families) (int* 24 i) 4) 2) 2) i)
          (#t (find (int+ i 1))))))

    (method %pick (self (param instance INTEGER "The instance"))
      (doc "The device to use: of those of version 1.3 with a compute queue, the one whose type ranks first. Answers (PHYSICAL FAMILY NAME), or nil when there is none."
        (returns LIST "The physical device, its compute queue family and its name")
        (sample "(Vulkan %pick instance)" "(a device 0 \"llvmpipe (LLVM 17.0.6, 256 bits)\")"))
      (def count (%vk-room 8))
      (def found (%vk-call "vkEnumeratePhysicalDevices" instance (str->ptr count) ()))
      (def n (ptr-ref (str->ptr count) 0 4))
      (if (if (%vk-ok? found) (int< 0 n) #f)
        (let ((devices (%vk-room (int* 8 n))) (properties (%vk-room 1024)))
          (%vk-call "vkEnumeratePhysicalDevices" instance (str->ptr count) (str->ptr devices))
          (let each ((i 0) (best ()) (rank 5))
            (if (int= i (ptr-ref (str->ptr count) 0 4)) best
              (let ((physical (ptr-ref-word (str->ptr devices) (int* 8 i))))
                (%vk-call "vkGetPhysicalDeviceProperties" physical (str->ptr properties))
                (let ((version (ptr-ref (str->ptr properties) 0 4))
                      (r (Vulkan %rank (ptr-ref (str->ptr properties) 16 4)))
                      (family (Vulkan %compute-family physical)))
                  (if (if (int< version (Vulkan %version-1-3)) #f (if (null? family) #f (int< r rank)))
                    (each (int+ i 1)
                          (list physical family
                                (Str8 append (ptr->str (int->ptr (int+ (%vk-at properties) 20))) ""))
                          r)
                    (each (int+ i 1) best rank)))))))
        ()))

    (method %open (self)
      (doc "The instance, the device picked, and what a run needs of it, made now: (INSTANCE PHYSICAL DEVICE QUEUE FAMILY COMMANDS NAME MEMORY LAYOUTS), or 0 when this host has no device to use."
        (returns LIST|INTEGER "The state, or 0")
        (sample "(Vulkan %open)" "the state"))
      (if (if (int= %word-size 8) (not (null? (%vk-handle))) #f)
        (let ((application (%vk-struct 48 (list (list 44 4 (Vulkan %version-1-3)))))
              (out (%vk-room 8)))
          (let ((made (%vk-call "vkCreateInstance"
                        (str->ptr (%vk-struct 64 (list (list 0 4 1) (list 24 8 (%vk-at application)))))
                        () (str->ptr out))))
            (if (%vk-ok? made)
              (let ((instance (%vk-word out)))
                (let ((picked (Vulkan %pick instance)))
                  (if (null? picked)
                    (do (%vk-call "vkDestroyInstance" instance ()) 0)
                    (Vulkan %open-device instance picked))))
              0)))
        0))

    (method %open-device (self (param instance INTEGER "The instance")
                               (param picked LIST "A device from %pick"))
      (doc "The picked device opened: its queue, a command buffer and its memory types."
        (returns LIST|INTEGER "The state, or 0 when the device does not open")
        (sample "(Vulkan %open-device instance picked)" "the state"))
      (def physical (first picked))
      (def family (List ref 1 picked))
      (def out (%vk-room 8))
      (def priority (%vk-struct 4 (list (list 0 4 1065353216))))
      (def queue-info
        (%vk-struct 40 (list (list 0 4 2) (list 20 4 family) (list 24 4 1) (list 32 8 (%vk-at priority)))))
      ; the barrier between steps is synchronization2's
      (def barriers (%vk-struct 24 (list (list 0 4 1000314007) (list 16 4 1))))
      (def made
        (%vk-call "vkCreateDevice" physical
          (str->ptr (%vk-struct 72 (list (list 0 4 3) (list 8 8 (%vk-at barriers))
                                         (list 20 4 1) (list 24 8 (%vk-at queue-info)))))
          () (str->ptr out)))
      (if (%vk-ok? made)
        (let ((device (%vk-word out)) (memory (%vk-room 520)))
          (%vk-call "vkGetDeviceQueue" device family 0 (str->ptr out))
          (let ((queue (%vk-word out)))
            (%vk-need (%vk-call "vkCreateCommandPool" device
                        (str->ptr (%vk-struct 24 (list (list 0 4 39) (list 16 4 2) (list 20 4 family))))
                        () (str->ptr out))
                      "command pool")
            (let ((pool (%vk-word out)))
              (%vk-need (%vk-call "vkAllocateCommandBuffers" device
                          (str->ptr (%vk-struct 32 (list (list 0 4 40) (list 16 8 pool) (list 28 4 1))))
                          (str->ptr out))
                        "command buffer")
              (%vk-call "vkGetPhysicalDeviceMemoryProperties" physical (str->ptr memory))
              (list instance physical device queue family (%vk-word out) (List ref 2 picked) memory (pair () ())))))
        (do (%vk-call "vkDestroyInstance" instance ()) 0)))

    (method %state (self)
      (doc "The device's state, or 0 when this host has no device to use. It is made the first time it is asked for and kept for the process."
        (returns LIST|INTEGER "The state, or 0")
        (sample "(Vulkan %state)" "the state"))
      (when (null? (first %vk-state))
        (%set-first! %vk-state (Vulkan %open)))
      (first %vk-state))

    (method %need-state (self)
      (doc "The device's state; raises a label 'io when this host has no device to use."
        (returns LIST "The state")
        (sample "(Vulkan %need-state)" "the state"))
      (def state (Vulkan %state))
      (when (not (pair? state))
        (Err raise (lit io) "Vulkan: no device on this host" ()))
      state)

    (method available? (self)
      (doc "Whether this host has a Vulkan device of version 1.3 with a compute queue."
        (returns BOOL "#t where a device is reached, a software one included")
        (sample "(Vulkan available?)" "#t on a Linux machine with a GPU and its driver"))
      (pair? (Vulkan %state)))

    (method device-name (self)
      (doc "The name of the device in use."
        (returns STRING "The name")
        (sample "(Vulkan device-name)" "\"Intel(R) UHD Graphics 770 (ADL-S GT1)\""))
      (List ref 6 (Vulkan %need-state)))

    (method %memory-type (self (param state LIST "The state")
                               (param allowed INTEGER "The memory types a buffer may use, a bit each"))
      (doc "A memory type the processor sees and need not flush, of those allowed: one the processor also caches when there is one."
        (returns INTEGER "The type's index; raises a label 'io when there is none")
        (sample "(Vulkan %memory-type state 15)" "1"))
      (def memory (str->ptr (List ref 7 state)))
      (def n (ptr-ref memory 0 4))
      (def find
        (fn (find i want)
          (match
            ((int= i n) ())
            ((if (int= (int& (int>> allowed i) 1) 1)
               (int= (int& (ptr-ref memory (int+ 4 (int* 8 i)) 4) want) want)
               #f)
              i)
            (#t (find (int+ i 1) want)))))
      (def cached (find 0 14))
      (def any (if (null? cached) (find 0 6) cached))
      (when (null? any)
        (Err raise (lit io) "Vulkan buffer: the device has no memory the processor sees" allowed))
      any)

    (method buffer (self (param bytes INTEGER "The buffer's length in bytes, above 0"))
      (doc "A buffer of that many zero bytes that the GPU and x both address."
        (returns STRING "The buffer, a record of its handles; give it back with release")
        (sample "(Vulkan buffer 4096)" "a buffer"))
      (def state (Vulkan %need-state))
      (def device (List ref 2 state))
      (def out (%vk-room 8))
      (%vk-need (%vk-call "vkCreateBuffer" device
                  (str->ptr (%vk-struct 56 (list (list 0 4 12) (list 24 8 bytes) (list 32 4 32))))
                  () (str->ptr out))
                "buffer")
      (def handle (%vk-word out))
      (def needs (%vk-room 24))
      (%vk-call "vkGetBufferMemoryRequirements" device handle (str->ptr needs))
      (def made
        (%vk-call "vkAllocateMemory" device
          (str->ptr (%vk-struct 32 (list (list 0 4 5) (list 16 8 (ptr-ref-word (str->ptr needs) 0))
                                         (list 24 4 (Vulkan %memory-type state (ptr-ref (str->ptr needs) 16 4))))))
          () (str->ptr out)))
      (when (not (%vk-ok? made))
        (%vk-call "vkDestroyBuffer" device handle ())
        (%vk-need made "buffer"))
      (def memory (%vk-word out))
      (%vk-need (%vk-call "vkBindBufferMemory" device handle memory 0) "buffer")
      (%vk-need (%vk-call "vkMapMemory" device memory 0 (Vulkan %whole-size) 0 (str->ptr out)) "buffer")
      (mem-set (int->ptr (%vk-word out)) 0 bytes)
      (%vk-struct 32 (list (list 0 8 handle) (list 8 8 memory) (list 16 8 (%vk-word out)) (list 24 8 bytes))))

    (method pointer (self (param buf STRING "A buffer from buffer"))
      (doc "The buffer's bytes: what x reads and writes, and what a kernel bound to the buffer sees."
        (returns POINTER "The first byte; it stays where it is until the buffer is released")
        (sample "(ptr-ref-word (Vulkan pointer buf) 0)" "the buffer's first word"))
      (int->ptr (ptr-ref-word (str->ptr buf) 16)))

    (method %kernel (self (param form LIST "A grid form")
                          (param name STRING "The kernel's name"))
      (doc "A pipeline that runs a grid form: (PLAN NAME COMPILED), the form's plan and a cell of what it has been compiled to, by shape of grid. Nothing is compiled until a step is made of it. Raises a label 'value for a form that is not a grid form."
        (returns LIST "The pipeline; give it back with release")
        (sample "(Vulkan %kernel (lit (fn (_ a) (f32-set! a at-x (f* (f32-ref a at-x) (f32-ref a at-x))))) \"square\")" "a pipeline"))
      (list (grid-form-plan form) name (pair () ())))

    (method %layout (self (param state LIST "The state")
                          (param count INTEGER "How many buffers a kernel has"))
      (doc "The layouts of a kernel of that many buffers, made the first time they are asked for: (SET-LAYOUT . PIPELINE-LAYOUT), each buffer a storage buffer at the binding of its place, and two words of push constants."
        (returns LIST "The descriptor set layout and the pipeline layout")
        (sample "(Vulkan %layout state 3)" "the layouts"))
      (def cell (List ref 8 state))
      (def kept (Assoc entry count (first cell)))
      (if (null? kept)
        (let ((device (List ref 2 state)) (out (%vk-room 8))
              (bindings (%vk-room (int* 24 (if (int< count 1) 1 count)))))
          (let each ((i 0))
            (if (int< i count)
              (let ((at (int* 24 i)) (p (str->ptr bindings)))
                (ptr-set! p at i 4)
                (ptr-set! p (int+ at 4) (Vulkan %storage-buffer) 4)
                (ptr-set! p (int+ at 8) 1 4)
                (ptr-set! p (int+ at 12) (Vulkan %compute-stage) 4)
                (each (int+ i 1)))))
          (%vk-need (%vk-call "vkCreateDescriptorSetLayout" device
                      (str->ptr (%vk-struct 32 (list (list 0 4 32) (list 20 4 count) (list 24 8 (%vk-at bindings)))))
                      () (str->ptr out))
                    "layout")
          (let ((sets (%vk-word out)))
            (let ((set-list (%vk-struct 8 (list (list 0 8 sets))))
                  (range (%vk-struct 12 (list (list 0 4 (Vulkan %compute-stage)) (list 8 4 8)))))
              (%vk-need (%vk-call "vkCreatePipelineLayout" device
                          (str->ptr (%vk-struct 48 (list (list 0 4 30) (list 20 4 1) (list 24 8 (%vk-at set-list))
                                                         (list 32 4 1) (list 40 8 (%vk-at range)))))
                          () (str->ptr out))
                        "layout")
              (let ((made (pair sets (%vk-word out))))
                (%set-first! cell (pair (pair count made) (first cell)))
                made))))
        (rest kept)))

    (method %shape (self (param pipeline LIST "A pipeline from %kernel")
                         (param height INTEGER "The grid's points down"))
      (doc "The group a kernel is compiled with for a grid of that height: (NAME ACROSS DOWN). A form with a team has a group to a point, 32 by 1; a row is covered 64 by 1, any other grid 8 by 8."
        (returns LIST "The shape's name, team, row or block, and a group's threads across and down")
        (example "(Vulkan %shape (Vulkan %kernel (lit (fn (_ a) (i32-set! a at-x at-y))) \"place\") 1)" "('row 64 1)"))
      (match
        ((List ref 4 (first pipeline)) (lit (team 32 1)))
        ((int= height 1) (lit (row 64 1)))
        (#t (lit (block 8 8)))))

    (method %compiled (self (param pipeline LIST "A pipeline from %kernel")
                            (param shape LIST "A shape from %shape"))
      (doc "The kernel compiled for a shape of grid, kept after the first time: (PIPELINE . MODULE), Vulkan's pipeline and the shader module it was made from. Raises a label 'io when the device refuses the module."
        (returns LIST "The compiled pipeline and its module")
        (sample "(Vulkan %compiled pipeline (Vulkan %shape pipeline 1))" "the compiled kernel"))
      (def cell (List ref 2 pipeline))
      (def kept (Assoc entry (first shape) (first cell)))
      (if (null? kept)
        (let ((state (Vulkan %need-state)) (plan (first pipeline)) (out (%vk-room 8)))
          (let ((device (List ref 2 state))
                (code (Spirv %kernel plan (List ref 1 shape) (List ref 2 shape)))
                (layout (rest (Vulkan %layout state (first plan))))
                (entry "main"))
            (%vk-need (%vk-call "vkCreateShaderModule" device
                        (str->ptr (%vk-struct 40 (list (list 0 4 16) (list 24 8 (rest code))
                                                       (list 32 8 (%vk-at (first code))))))
                        () (str->ptr out))
                      "kernel")
            (let ((module (%vk-word out)))
              (let ((made (%vk-call "vkCreateComputePipelines" device 0 1
                            (str->ptr (%vk-struct 96 (list (list 0 4 29)
                                                           (list 24 4 18) (list 44 4 (Vulkan %compute-stage))
                                                           (list 48 8 module) (list 56 8 (%vk-at entry))
                                                           (list 72 8 layout) (list 88 4 -1))))
                            () (str->ptr out))))
                (when (not (%vk-ok? made))
                  (%vk-call "vkDestroyShaderModule" device module ())
                  (%vk-need made (Str8 append "kernel " (List ref 1 pipeline))))
                (let ((compiled (pair (%vk-word out) module)))
                  (%set-first! cell (pair (pair (first shape) compiled) (first cell)))
                  compiled)))))
        (rest kept)))

    ; --- steps ------------------------------------------------------------------
    ; A step is a kernel's run made ready: (PIPELINE LAYOUTS COUNT INFOS
    ; ACROSS DOWN GRID), Vulkan's pipeline, the layouts for its count of
    ; buffers, the buffers as the descriptors a set is written from, the
    ; groups to run across and down, and the grid's width and height as the
    ; push constants, nil for a form with a team.
    (method %step (self (param pipeline LIST "A pipeline from %kernel")
                        (param buffers LIST "The buffers the kernel reads and writes, in the order of the form's parameters")
                        (param width INTEGER "The grid's points across, above 0")
                        (param height INTEGER "The grid's points down, above 0"))
      (doc "A kernel's run made ready for %run-steps, the kernel compiled for the grid's shape the first time. Raises a label 'value when the buffers are not as many as the form's, and when the grid takes more groups than a device runs, 65535 either way."
        (returns LIST "The step")
        (sample "(Vulkan %step pipeline (list buf) 1024 1)" "a step"))
      (def state (Vulkan %need-state))
      (def count (first (first pipeline)))
      (when (not (int= count (List length buffers)))
        (Err raise (lit value) "Vulkan: a kernel is given a buffer for each of its form's" (List ref 1 pipeline)))
      (def shape (Vulkan %shape pipeline height))
      ; a team's group is a point's; any other grid is covered by whole groups
      (def team (List ref 4 (first pipeline)))
      (def across (if team width (int/ (int+ width (int- (List ref 1 shape) 1)) (List ref 1 shape))))
      (def down (if team height (int/ (int+ height (int- (List ref 2 shape) 1)) (List ref 2 shape))))
      (when (if (int< (Vulkan %most-groups) across) #t (int< (Vulkan %most-groups) down))
        (Err raise (lit value) "Vulkan: the grid takes more groups than a device runs" (list width height)))
      (def infos (%vk-room (int* 24 (if (int< count 1) 1 count))))
      (let each ((bs buffers) (at 0))
        (if (pair? bs)
          (do (ptr-set-word! (str->ptr infos) at (ptr-ref-word (str->ptr (first bs)) 0))
              (ptr-set-word! (str->ptr infos) (int+ at 16) (Vulkan %whole-size))
              (each (rest bs) (int+ at 24)))))
      (list (first (Vulkan %compiled pipeline shape)) (Vulkan %layout state count) count infos across down
            (if team ()
              (%vk-struct 8 (list (list 0 4 width) (list 4 4 height))))))

    (method %barrier (self (param commands INTEGER "The command buffer")
                           (param from-stage INTEGER "The stage that wrote")
                           (param from-access INTEGER "How it wrote")
                           (param to-stage INTEGER "The stages that read or write next")
                           (param to-access INTEGER "How they do"))
      (doc "Record a memory barrier: what the first stage wrote is there for the next to read."
        (returns ANY "nil")
        (sample "(Vulkan %barrier commands 2048 64 2048 96)" "nil"))
      (def barrier
        (%vk-struct 48 (list (list 0 4 1000314000) (list 16 8 from-stage) (list 24 8 from-access)
                             (list 32 8 to-stage) (list 40 8 to-access))))
      (%vk-call "vkCmdPipelineBarrier2" commands
        (str->ptr (%vk-struct 64 (list (list 0 4 1000314003) (list 20 4 1) (list 24 8 (%vk-at barrier))))))
      ())

    (method %run-steps (self (param steps LIST "Steps from %step, at least one"))
      (doc "Run the steps' kernels in order in one command buffer, each seeing what those before it wrote, and wait until the device has finished them all. Raises a label 'io when the device refuses the run."
        (returns ANY "nil")
        (sample "(Vulkan %run-steps (list step))" "nil, every step's kernel run"))
      (def state (Vulkan %need-state))
      (def device (List ref 2 state))
      (def queue (List ref 3 state))
      (def commands (List ref 5 state))
      (def n (List length steps))
      (def out (%vk-room 8))
      ; a descriptor set for each step, from a pool made for this run
      (def size
        (%vk-struct 8 (list (list 0 4 (Vulkan %storage-buffer))
                            (list 4 4 (List fold (fn (_ sum s) (int+ sum (if (int< (List ref 2 s) 1) 1 (List ref 2 s)))) 0 steps)))))
      (%vk-need (%vk-call "vkCreateDescriptorPool" device
                  (str->ptr (%vk-struct 40 (list (list 0 4 33) (list 20 4 n) (list 24 4 1) (list 32 8 (%vk-at size)))))
                  () (str->ptr out))
                "run")
      (def pool (%vk-word out))
      (def layouts (%vk-room (int* 8 n)))
      (def sets (%vk-room (int* 8 n)))
      (def writes (%vk-room (int* 64 n)))
      (let each ((ss steps) (i 0))
        (if (pair? ss)
          (do (ptr-set-word! (str->ptr layouts) (int* 8 i) (first (List ref 1 (first ss))))
              (each (rest ss) (int+ i 1)))))
      (def failure
        (let ((made (%vk-call "vkAllocateDescriptorSets" device
                      (str->ptr (%vk-struct 40 (list (list 0 4 34) (list 16 8 pool) (list 24 4 n)
                                                     (list 32 8 (%vk-at layouts)))))
                      (str->ptr sets))))
          (if (%vk-ok? made)
            (do
              (let each ((ss steps) (i 0))
                (if (pair? ss)
                  (let ((at (int* 64 i)) (p (str->ptr writes)) (s (first ss)))
                    (ptr-set! p at 35 4)
                    (ptr-set-word! p (int+ at 16) (ptr-ref-word (str->ptr sets) (int* 8 i)))
                    (ptr-set! p (int+ at 32) (List ref 2 s) 4)
                    (ptr-set! p (int+ at 36) (Vulkan %storage-buffer) 4)
                    (ptr-set-word! p (int+ at 48) (%vk-at (List ref 3 s)))
                    (each (rest ss) (int+ i 1)))))
              (%vk-call "vkUpdateDescriptorSets" device n (str->ptr writes) 0 ())
              (let ((begun (%vk-call "vkBeginCommandBuffer" commands
                             (str->ptr (%vk-struct 32 (list (list 0 4 42) (list 16 4 1)))))))
                (if (%vk-ok? begun)
                  (do
                    ; what x wrote is there for the first kernel
                    (Vulkan %barrier commands 16384 16384 2048 96)
                    (let each ((ss steps) (i 0))
                      (if (pair? ss)
                        (let ((s (first ss)))
                          (%vk-call "vkCmdBindPipeline" commands 1 (first s))
                          (%vk-call "vkCmdBindDescriptorSets" commands 1 (rest (List ref 1 s)) 0 1
                            (int->ptr (int+ (%vk-at sets) (int* 8 i))) 0 ())
                          (if (null? (List ref 6 s)) ()
                            (%vk-call "vkCmdPushConstants" commands (rest (List ref 1 s)) (Vulkan %compute-stage) 0 8
                              (str->ptr (List ref 6 s))))
                          (%vk-call "vkCmdDispatch" commands (List ref 4 s) (List ref 5 s) 1)
                          ; what it wrote is there for the next kernel, and for x
                          (Vulkan %barrier commands 2048 64 18432 8288)
                          (each (rest ss) (int+ i 1)))))
                    (let ((ended (%vk-call "vkEndCommandBuffer" commands)))
                      (if (%vk-ok? ended)
                        (let ((list-of (%vk-struct 8 (list (list 0 8 commands)))))
                          (let ((sent (%vk-call "vkQueueSubmit" queue 1
                                        (str->ptr (%vk-struct 72 (list (list 0 4 4) (list 40 4 1)
                                                                       (list 48 8 (%vk-at list-of)))))
                                        0)))
                            (if (%vk-ok? sent) (%vk-call "vkQueueWaitIdle" queue) sent)))
                        ended)))
                  begun)))
            made)))
      (%vk-call "vkDestroyDescriptorPool" device pool ())
      (%vk-need failure "run")
      ())

    (method run (self (param pipeline LIST "A pipeline from %kernel")
                      (param buffers LIST "The buffers the kernel reads and writes, in the order of the form's parameters")
                      (param width INTEGER "The grid's points across, above 0")
                      (param height INTEGER "The grid's points down, above 0"))
      (doc "Run the pipeline's kernel once for each point of the width by height grid, with the buffers bound in order, and wait until the device has finished. Raises a label 'io when the device refuses the run."
        (returns ANY "nil")
        (sample "(Vulkan run pipeline (list buf) 1024 1)" "nil, the kernel run on 1024 points"))
      (Vulkan %run-steps (list (Vulkan %step pipeline buffers width height))))

    (method release (self (param x STRING|LIST "A buffer from buffer, or a pipeline from %kernel"))
      (doc "Give a buffer or a pipeline back to the device. A buffer's pointer, and the pipeline, must not be used afterwards."
        (returns ANY "nil")
        (sample "(Vulkan release buf)" "nil"))
      (def device (List ref 2 (Vulkan %need-state)))
      (if (pair? x)
        (do (List for-each
              (fn (_ made)
                (%vk-call "vkDestroyPipeline" device (first (rest made)) ())
                (%vk-call "vkDestroyShaderModule" device (rest (rest made)) ()))
              (first (List ref 2 x)))
            (%set-first! (List ref 2 x) ()))
        (do (%vk-call "vkDestroyBuffer" device (ptr-ref-word (str->ptr x) 0) ())
            ; freeing the memory unmaps it
            (%vk-call "vkFreeMemory" device (ptr-ref-word (str->ptr x) 8) ())))
      ())))

(doc (provide x/sys/vulkan Vulkan)
  (example "(boolean? (Vulkan available?))" "#t")
  "Buffers shared with the GPU, and grid forms compiled to SPIR-V and run over them, through the host's Vulkan library over the dlopen FFI.")
