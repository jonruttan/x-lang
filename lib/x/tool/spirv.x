; spirv.x -- Spirv: a grid form as a SPIR-V module, the code Vulkan takes.
;
; SPIR-V is a list of 32-bit words: a header, then instructions, each a
; word of its length and its number followed by its operands.  A value is
; named by an id, a number given once.  Spirv writes the module a grid
; form's plan (x/tool/grid-form) means, as a compute shader:
;
;   - each buffer is a storage buffer, binding I of descriptor set 0 for
;     the form's parameter I, holding singles or 32-bit words;
;   - a variable of the plan is a variable of the function, loaded and
;     stored, so no value is carried between blocks any other way;
;   - an if is a selection and a loop is a loop, as SPIR-V's structured
;     control flow has them; a break branches to the loop's merge block
;     and a continue to its continue block.
;
; Vulkan runs a shader in groups of a size fixed in the module, and runs
; whole groups.  A form with no team is given a group ACROSS by DOWN
; threads, and the grid is covered by as many groups as reach it: the grid's
; width and height are two words of push constants, and a thread past
; either does nothing.  at-x and at-y are the thread's place in the grid.
;
; A form with a team is given a group of 32 by 1, a group to a grid
; point: at-x and at-y are the group's place, member the thread's place in
; it, and team-sum writes each member's value into memory the group
; shares, waits for all, and adds the 32 up.  The module is version 1.3,
; which Vulkan 1.1 and later take.
;
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(module x/tool/spirv)
(import x/type/class)
(import x/type/list)
(import x/num/float libm-fn)
(import x/tool/grid-form grid-form-plan)
(import x/core/doors int& int* int+ int- int< int<< int= int>> int| ptr-set! str->ptr str-byte-ref str-byte-len str-make)

; An instruction: its first word holds its length and its number.
(def %sv-op
  (fn (_ number . operands)
    (pair (int| (int<< (int+ 1 (List length operands)) 16) number) operands)))

; A string's words: its bytes, a zero byte, and zeros to the word's end,
; the first byte lowest.
(def %sv-text
  (fn (_ s)
    (let ((n (str-byte-len s)))
      (let go ((i 0))
        (if (int< n i) ()
          (let ((byte (fn (_ k) (if (int< k n) (int& (str-byte-ref s k) 255) 0))))
            (pair (int| (byte i)
                    (int| (int<< (byte (int+ i 1)) 8)
                      (int| (int<< (byte (int+ i 2)) 16) (int<< (byte (int+ i 3)) 24))))
                  (go (int+ i 4)))))))))

; The words as bytes, each word's lowest byte first: (BYTES . COUNT).
(def %sv-pack
  (fn (_ words)
    (let ((s (str-make (int* 4 (List length words)))))
      (let go ((ws words) (at 0))
        (if (null? ws) (pair s at)
          (do (ptr-set! (str->ptr s) at (first ws) 4)
              (go (rest ws) (int+ at 4))))))))

; double bits -> single bits, made the first time a module has a float
; constant.
(def %sv-single-cell (pair () ()))
(def %sv-single
  (fn (_ float)
    (if (null? (first %sv-single-cell))
      (%set-first! %sv-single-cell (libm-fn (lit %spirv-single) "d->f" ()))
      ())
    ; the bits are the word's low 32
    (let ((bits ((first %sv-single-cell) (first float))))
      (if (int= %word-size 8) (int>> (int<< bits 32) 32) bits))))

; The operators' instructions: a number, or (ext N) for a function of
; the GLSL.std.450 set.
(def %sv-ops
  (lit ((+ . 128) (- . 130) (* . 132) (/ . 135) (>> . 195) (<< . 196) (& . 199) (< . 177) (= . 170)
        (f+ . 129) (f- . 131) (f* . 133) (f/ . 136) (f< . 184) (f= . 180)
        (i->f . 111) (f->i . 110)
        (f-sqrt ext 31) (f-exp ext 27) (f-tanh ext 21))))

; A module being written, each part a cell: the last id, the constants as
; ((KEY . ID) ...), and the instructions of the globals, the function's
; variables and its body, each list last first.
(def %sv-new (fn (_) (list (pair 0 ()) (pair () ()) (pair () ()) (pair () ()) (pair () ()))))

(def %sv-id!
  (fn (_ b) (let ((c (first b))) (%set-first! c (int+ (first c) 1)) (first c))))

(def %sv-push! (fn (_ cell op) (%set-first! cell (pair op (first cell)))))
(def %sv-global! (fn (_ b op) (%sv-push! (List ref 2 b) op)))
(def %sv-local! (fn (_ b op) (%sv-push! (List ref 3 b) op)))
(def %sv-emit! (fn (_ b op) (%sv-push! (List ref 4 b) op)))

; An instruction with a result: emitted into the body, its id answered.
(def %sv-value!
  (fn (_ b number type . operands)
    (let ((id (%sv-id! b)))
      (%sv-emit! b (apply %sv-op (pair number (pair type (pair id operands)))))
      id)))

; The constant of TYPE whose word is WORD, written once.
(def %sv-const
  (fn (_ b type word)
    (let ((cell (List ref 1 b)))
      (let find ((es (first cell)))
        (match
          ((null? es)
            (let ((id (%sv-id! b)))
              (%sv-global! b (%sv-op 43 type id word))
              (%set-first! cell (pair (list type word id) (first cell)))
              id))
          ((if (int= (first (first es)) type) (int= (List ref 1 (first es)) word) #f) (List ref 2 (first es)))
          (#t (find (rest es))))))))

(def-class Spirv ()
  (doc "A grid form as a SPIR-V module, the code a Vulkan device takes: a compute shader whose storage buffers are the form's parameters."
    (note "Every method is private for now: x/sys/vulkan is the caller.")
    (example "(do (import x/tool/grid-form grid-form-plan) (import x/core/doors ptr-ref str->ptr) (ptr-ref (str->ptr (first (Spirv %kernel (grid-form-plan (lit (fn (_ a) (i32-set! a at-x at-y)))) 64 1))) 0 4))" "119734787"))
  (static
    (method %kernel (self (param plan LIST "A grid form's plan, from grid-form-plan")
                          (param across INTEGER "A group's threads across, for a form with no team")
                          (param down INTEGER "A group's threads down, for a form with no team"))
      (doc "The plan as a SPIR-V module, version 1.3: a compute shader with the entry point main. Buffer I is binding I of descriptor set 0. With no team the group is across by down and the push constants are the grid's width and height, two words; with a team the group is 32 by 1 and there are no push constants."
        (returns LIST "(BYTES . COUNT): the module's bytes in a string, and how many they are, a multiple of 4")
        (sample "(Spirv %kernel (grid-form-plan (lit (fn (_ a) (i32-set! a at-x at-y)))) 64 1)" "a module of 4-byte words, the first 0x07230203"))
      (def b (%sv-new))
      (def team (List ref 4 plan))
      (def id (fn (_) (%sv-id! b)))
      (def g (fn (_ . words) (%sv-global! b (apply %sv-op words))))
      (def decorations (pair () ()))
      (def d (fn (_ . words) (%sv-push! decorations (apply %sv-op words))))
      ; the types every module has
      (def void (id)) (def fn-type (id)) (def bool (id)) (def int (id)) (def uint (id)) (def float (id))
      (def uint3 (id)) (def in-uint3 (id))
      (def var-int (id)) (def var-float (id)) (def var-bool (id))
      (g 19 void) (g 33 fn-type void) (g 20 bool) (g 21 int 32 1) (g 21 uint 32 0) (g 22 float 32)
      (g 23 uint3 uint 3) (g 32 in-uint3 1 uint3)
      (g 32 var-int 7 int) (g 32 var-float 7 float) (g 32 var-bool 7 bool)
      (def type-of (fn (_ t) (match ((eq? t (lit f)) float) ((eq? t (lit i)) int) (#t bool))))
      (def var-of (fn (_ t) (match ((eq? t (lit f)) var-float) ((eq? t (lit i)) var-int) (#t var-bool))))
      (def int-const (fn (_ n) (%sv-const b int n)))
      (def uint-const (fn (_ n) (%sv-const b uint n)))
      ; a buffer of an element type: (STRUCT-POINTER ELEMENT-POINTER)
      (def storage
        (fn (_ element)
          (let ((array (id)) (struct (id)) (to-struct (id)) (to-element (id)))
            (g 29 array element) (g 30 struct array) (g 32 to-struct 12 struct) (g 32 to-element 12 element)
            (d 71 array 6 4) (d 72 struct 0 35 0) (d 71 struct 2)
            (list to-struct to-element))))
      (def floats (storage float))
      (def words (storage int))
      (def buffer-type
        (fn (_ i) (let ((e (Assoc entry i (List ref 1 plan)))) (if (null? e) (lit f) (rest e)))))
      ; the buffers' variables, in order
      (def buffers
        (List map
          (fn (_ i)
            (let ((v (id)))
              (g 59 (first (if (eq? (buffer-type i) (lit f)) floats words)) v 12)
              (d 71 v 34 0) (d 71 v 33 i)
              v))
          (List range 0 (first plan))))
      ; the plan's variables: ((N . ID) ...)
      (def vars
        (List map
          (fn (_ v)
            (let ((p (id)))
              (%sv-local! b (%sv-op 59 (var-of (rest v)) p 7))
              (pair (first v) p)))
          (List ref 2 plan)))
      (def var (fn (_ n) (rest (Assoc entry n vars))))
      ; a built-in input, three unsigned words
      (def input
        (fn (_ which) (let ((v (id))) (g 59 in-uint3 v 1) (d 71 v 11 which) v)))
      (def part
        (fn (_ from i) (%sv-value! b 81 uint (%sv-value! b 61 uint3 from) i)))
      (def std (id))
      (def main (id))
      (def entry (id))
      ; the team's shared memory
      (def share
        (if team
          (let ((array (id)) (to-array (id)) (to-float (id)) (v (id)))
            (g 28 array float (uint-const 32)) (g 32 to-array 4 array) (g 32 to-float 4 float)
            (g 59 to-array v 4)
            (pair v to-float))
          ()))
      (def barrier
        (fn (_) (%sv-emit! b (%sv-op 224 (uint-const 2) (uint-const 2) (uint-const 264)))))
      ; where the run is: at-x, at-y and member as ids, set in the entry block
      (def place (pair () ()))
      (def expr
        (fn (expr x)
          (let ((k (first x)))
            (match
              ((eq? k (lit i)) (int-const (List ref 1 x)))
              ((eq? k (lit f)) (%sv-const b float (%sv-single (List ref 1 x))))
              ((eq? k (lit b))
                (let ((word (if (List ref 1 x) 1 0)))
                  (let ((cell (List ref 1 b)))
                    (let find ((es (first cell)))
                      (match
                        ((null? es)
                          (let ((c (id)))
                            (g (if (int= word 1) 41 42) bool c)
                            (%set-first! cell (pair (list bool word c) (first cell)))
                            c))
                        ((if (int= (first (first es)) bool) (int= (List ref 1 (first es)) word) #f)
                          (List ref 2 (first es)))
                        (#t (find (rest es))))))))
              ((eq? k (lit v)) (%sv-value! b 61 (type-of (List ref 2 x)) (var (List ref 1 x))))
              ((eq? k (lit at))
                (let ((name (List ref 1 x)))
                  (if (eq? name (lit team)) (int-const 32) (rest (Assoc entry name (first place))))))
              ((eq? k (lit ld))
                (let ((t (List ref 2 x)))
                  (%sv-value! b 61 (type-of t)
                    (%sv-value! b 65 (List ref 1 (if (eq? t (lit f)) floats words))
                      (List ref (List ref 1 x) buffers) (int-const 0) (expr (List ref 3 x))))))
              (#t
                (let ((op (rest (Assoc entry (List ref 1 x) %sv-ops)))
                      (args (List map expr (rest (rest (rest x)))))
                      (t (type-of (List ref 2 x))))
                  (if (pair? op)
                    (apply %sv-value! (pair b (pair 12 (pair t (pair std (pair (List ref 1 op) args))))))
                    (apply %sv-value! (pair b (pair op (pair t args)))))))))))
      (def label (fn (_ l) (%sv-emit! b (%sv-op 248 l))))
      (def branch (fn (_ l) (%sv-emit! b (%sv-op 249 l))))
      ; The statements written; answers whether the block they end is
      ; closed, by a break or a continue.  LP is the loop they are in,
      ; (MERGE . CONTINUE).
      (def stmts
        (fn (stmts ss lp)
          (if (null? ss) #f
            (let ((s (first ss)))
              (let ((k (first s)))
                (let ((closed
                        (match
                          ((eq? k (lit set))
                            (do (%sv-emit! b (%sv-op 62 (var (List ref 1 s)) (expr (List ref 2 s)))) #f))
                          ((eq? k (lit store))
                            (let ((t (List ref 2 s)))
                              (let ((at (%sv-value! b 65 (List ref 1 (if (eq? t (lit f)) floats words))
                                          (List ref (List ref 1 s) buffers) (int-const 0) (expr (List ref 3 s)))))
                                (%sv-emit! b (%sv-op 62 at (expr (List ref 4 s))))
                                #f)))
                          ((eq? k (lit if))
                            (let ((test (expr (List ref 1 s))) (yes (id)) (merge (id)))
                              (let ((no (if (null? (List ref 3 s)) merge (id))))
                                (%sv-emit! b (%sv-op 247 merge 0))
                                (%sv-emit! b (%sv-op 250 test yes no))
                                (label yes)
                                (let ((a (stmts (List ref 2 s) lp)))
                                  (if a () (branch merge))
                                  (let ((c (if (null? (List ref 3 s)) #f
                                             (do (label no)
                                                 (let ((c (stmts (List ref 3 s) lp)))
                                                   (if c () (branch merge))
                                                   c)))))
                                    (label merge)
                                    ; with both arms closed nothing reaches the merge block
                                    (if (if a c #f) (do (%sv-emit! b (%sv-op 255)) #t) #f))))))
                          ((eq? k (lit loop))
                            (let ((head (id)) (body (id)) (continue (id)) (merge (id)))
                              (branch head)
                              (label head)
                              (%sv-emit! b (%sv-op 246 merge continue 0))
                              (branch body)
                              (label body)
                              (if (stmts (List ref 1 s) (pair merge continue)) () (branch continue))
                              (label continue)
                              (branch head)
                              (label merge)
                              #f))
                          ((eq? k (lit break)) (do (branch (first lp)) #t))
                          ((eq? k (lit continue)) (do (branch (rest lp)) #t))
                          (#t
                            ; team-sum: each member's value into the share, then all added up
                            (let ((value (expr (List ref 2 s)))
                                  (member (rest (Assoc entry (lit member) (first place)))))
                              (%sv-emit! b (%sv-op 62 (%sv-value! b 65 (rest share) (first share) member) value))
                              (barrier)
                              (let ((total
                                      (let add ((i 1)
                                                (sum (%sv-value! b 61 float
                                                       (%sv-value! b 65 (rest share) (first share) (int-const 0)))))
                                        (if (int< i 32)
                                          (add (int+ i 1)
                                               (%sv-value! b 129 float sum
                                                 (%sv-value! b 61 float
                                                   (%sv-value! b 65 (rest share) (first share) (int-const i)))))
                                          sum))))
                                (barrier)
                                (%sv-emit! b (%sv-op 62 (var (List ref 1 s)) total))
                                #f))))))
                  (if closed #t (stmts (rest ss) lp))))))))
      ; the function's body
      (label entry)
      (def inputs
        (if team
          (let ((group (input 26)) (local (input 27)))
            (%set-first! place
              (list (pair (lit at-x) (%sv-value! b 124 int (part group 0)))
                    (pair (lit at-y) (%sv-value! b 124 int (part group 1)))
                    (pair (lit member) (%sv-value! b 124 int (part local 0)))))
            (stmts (List ref 3 plan) ())
            (list group local))
          (let ((global (input 28)) (grid (id)) (to-grid (id)) (to-uint (id)) (v (id))
                (inside (id)) (merge (id)))
            (g 30 grid uint uint) (g 32 to-grid 9 grid) (g 32 to-uint 9 uint) (g 59 to-grid v 9)
            (d 71 grid 2) (d 72 grid 0 35 0) (d 72 grid 1 35 4)
            (let ((x (part global 0)) (y (part global 1)))
              (%set-first! place
                (list (pair (lit at-x) (%sv-value! b 124 int x)) (pair (lit at-y) (%sv-value! b 124 int y))))
              (let ((test (%sv-value! b 167 bool
                            (%sv-value! b 176 bool x (%sv-value! b 61 uint (%sv-value! b 65 to-uint v (int-const 0))))
                            (%sv-value! b 176 bool y (%sv-value! b 61 uint (%sv-value! b 65 to-uint v (int-const 1)))))))
                (%sv-emit! b (%sv-op 247 merge 0))
                (%sv-emit! b (%sv-op 250 test inside merge))
                (label inside)
                (stmts (List ref 3 plan) ())
                (branch merge)
                (label merge)))
            (list global))))
      (%sv-emit! b (%sv-op 253))
      (%sv-emit! b (%sv-op 56))
      (let ((body (List reverse (first (List ref 4 b)))))
        (%sv-pack
          (List append
            (list 119734787 66304 0 (int+ (first (first b)) 1) 0)
            (%sv-op 17 1)
            (apply %sv-op (pair 11 (pair std (%sv-text "GLSL.std.450"))))
            (%sv-op 14 0 1)
            (apply %sv-op (pair 15 (pair 5 (pair main (List append (%sv-text "main") inputs)))))
            (if team (%sv-op 16 main 17 32 1 1) (%sv-op 16 main 17 across down 1))
            (List flat-map (fn (_ op) op) (List reverse (first decorations)))
            (List flat-map (fn (_ op) op) (List reverse (first (List ref 2 b))))
            (%sv-op 54 void main 0 fn-type)
            ; the entry block's label, the variables, then the rest
            (first body)
            (List flat-map (fn (_ op) op) (List reverse (first (List ref 3 b))))
            (List flat-map (fn (_ op) op) (rest body))))))))

(doc (provide x/tool/spirv Spirv)
  (example "(do (import x/tool/grid-form grid-form-plan) (= 0 (% (rest (Spirv %kernel (grid-form-plan (lit (fn (_ a) (i32-set! a at-x at-y)))) 8 8)) 4)))" "#t")
  "Spirv: a grid form (x/tool/grid-form) written as a SPIR-V module, the compute shader a Vulkan device takes.")
