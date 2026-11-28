; grid-form.x -- a (fn ...) form over 32-bit words and singles, run once
; for each point of a grid on a GPU.
;
; A grid form is a word form (x/tool/word-form) for the GPU.  It is
; written once, and each GPU backend is handed the text or the code its
; device takes: grid-form-metal answers the Metal Shading Language, and
; x/tool/spirv the SPIR-V that Vulkan takes.  Both are made from one plan,
; so a kernel means the same on each.
;
;   (fn (_ a b c dims) body ...)
;
; The parameters after the first are the buffers the kernel is bound to,
; in order.  A buffer is not a value: it is named only as the first
; operand of a load or a store.
;
;   (f32-ref B I)  (f32-set! B I V)   the single at element I of B
;   (i32-ref B I)  (i32-set! B I V)   the 32-bit word at element I of B
;
; A buffer holds singles or words, whichever its loads and stores say; a
; store answers the value stored.
;
; An integer is a signed 32-bit word, and the operators are word-form's:
; + - * / >> << & and the comparisons < and =.  A float is a single: f+ f-
; f* f/, f-sqrt f-exp f-tanh, the comparisons f< and f=, and i->f and f->i
; between the two.  A Float standing in the form is that constant, rounded
; to a single.  A comparison is the test of an if, or #t and #f an if
; answers.
;
; The forms are if (with or without its else), do, let, and the named
; let, which is the loop: its name is called in tail position, with the
; next values of its variables.
;
;   (let go ((j 0) (sum (i->f 0)))
;     (if (< j n) (go (+ j 1) (f+ sum (f32-ref a j))) sum))
;
; at-x and at-y are the grid point the run is for, across and down.
;
; A team is the threads that work one grid point together.  A form that
; names team, member or team-sum is run by a team at each point: team is
; how many they are, member is the thread's place among them from 0, and
; (team-sum V) is the sum of V over the team, the same in every member.
; Each member takes a share of the point's work, the elements member,
; member + team, member + 2 team and so on, and team-sum adds the shares
; up.  Every member of a team must reach a team-sum together: it stands
; where all of them go, the same number of times, not under a test that
; differs between members.
;
; The plan a form lowers to is (BUFFERS TYPES VARS STMTS TEAM?): how many
; buffers, each one's element type as (INDEX . f) or (INDEX . i), the
; variables as (N . TYPE), the statements, and whether a team runs it.
; A type is f, i or b.  An expression is
;
;   (i N) (f FLOAT) (b BOOL)   a constant
;   (v N TYPE)                 variable N
;   (at NAME)                  at-x, at-y, member or team
;   (ld B TYPE X)              element X of buffer B
;   (op NAME TYPE X ...)       an operator
;
; and a statement is
;
;   (set N X)                  variable N becomes X
;   (store B TYPE X V)         element X of buffer B becomes V
;   (if X STMTS STMTS)
;   (loop STMTS) (break) (continue)
;   (team-sum N X)             variable N becomes X summed over the team
;
; Every path through a loop's statements ends in a break or a continue.
;
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(module x/tool/grid-form)
(import x/type/list)
(import x/num/float float?)
(import x/core/doors int+ int- int< int= io-display-to-str)

; The operators: (NAME OPERAND-TYPES RESULT-TYPE).
(def %gf-ops
  (lit ((+ (i i) i) (- (i i) i) (* (i i) i) (/ (i i) i) (>> (i i) i) (<< (i i) i) (& (i i) i)
        (< (i i) b) (= (i i) b)
        (f+ (f f) f) (f- (f f) f) (f* (f f) f) (f/ (f f) f)
        (f< (f f) b) (f= (f f) b)
        (f-sqrt (f) f) (f-exp (f) f) (f-tanh (f) f)
        (i->f (i) f) (f->i (f) i))))

(def %gf-fail (fn (_ what form) (Err raise (lit value) (Str8 append "grid form: " what) form)))

; The lowering's state, each a cell: the last variable's number, the
; variables, the buffers by name as ((NAME . INDEX) ...), their element
; types, and whether a team was named.
(def %gf-ctx
  (fn (_ buffers) (list (pair 0 ()) (pair () ()) (pair buffers ()) (pair () ()) (pair #f ()))))

(def %gf-var
  (fn (_ ctx type)
    (let ((c (List ref 0 ctx)) (vs (List ref 1 ctx)))
      (let ((n (int+ (first c) 1)))
        (%set-first! c n)
        (%set-first! vs (pair (pair n type) (first vs)))
        n))))

(def %gf-team! (fn (_ ctx) (%set-first! (List ref 4 ctx) #t)))

(def %gf-type
  (fn (_ x)
    (let ((k (first x)))
      (match
        ((eq? k (lit i)) k) ((eq? k (lit f)) k) ((eq? k (lit b)) k)
        ((eq? k (lit at)) (lit i))
        (#t (List ref 2 x))))))

; Whether an expression reads no memory: it means the same wherever it is
; worked out.
(def %gf-simple?
  (fn (_ x)
    (let ((k (first x)))
      (if (eq? k (lit ld)) #f (not (eq? k (lit op)))))))

; The buffer a load or a store names, its element type noted.
(def %gf-buffer
  (fn (_ ctx name type form)
    (let ((e (Assoc entry name (first (List ref 2 ctx)))) (types (List ref 3 ctx)))
      (if (null? e) (%gf-fail "not a buffer" form) ())
      (let ((kept (Assoc entry (rest e) (first types))))
        (match
          ((null? kept) (%set-first! types (pair (pair (rest e) type) (first types))))
          ((eq? (rest kept) type) ())
          (#t (%gf-fail "a buffer holds singles or words, not both" form))))
      (rest e))))

; X as a variable's value: X itself when it is simple, else a fresh
; variable set to it.  Answers (STMTS . EXPR).
(def %gf-kept
  (fn (_ ctx x)
    (if (%gf-simple? x) (pair () x)
      (let ((n (%gf-var ctx (%gf-type x))))
        (pair (list (list (lit set) n x)) (list (lit v) n (%gf-type x)))))))

; The operands ES lowered in order: (STMTS . EXPRS).  An operand that
; reads memory is kept in a variable when a later one has statements, so
; it is read before they run.
(def %gf-operands
  (fn (_ ctx env es)
    (let ((parts (List map (fn (_ e) (%gf-lower ctx env e)) es)))
      (let walk ((ps (List reverse parts)) (later #f) (stmts ()) (exprs ()))
        (if (null? ps) (pair stmts exprs)
          (let ((p (first ps)))
            (if (null? (rest p)) (%gf-fail "an operand has no value" es) ())
            (let ((k (if later (%gf-kept ctx (rest p)) (pair () (rest p)))))
              (walk (rest ps)
                    (if later #t (not (null? (first p))))
                    (List append (first p) (first k) stmts)
                    (pair (rest k) exprs)))))))))

(def %gf-check
  (fn (_ want exprs form)
    (if (equal? want (List map %gf-type exprs)) ()
      (%gf-fail "an operand of the wrong type" form))))

; A sequence of forms: the statements of all, and the last one's value.
(def %gf-body
  (fn (_ ctx env forms)
    (let go ((fs forms) (stmts ()) (x ()))
      (if (null? fs) (pair stmts x)
        (let ((p (%gf-lower ctx env (first fs))))
          (go (rest fs) (List append stmts (first p)) (rest p)))))))

; A let's bindings, each worked out where the let stands:
; (STMTS . ENV), the environment with the names bound.
(def %gf-bind
  (fn (_ ctx env binds form)
    (let go ((bs binds) (stmts ()) (new env) (vars ()))
      (if (null? bs) (list stmts new (List reverse vars))
        (let ((p (%gf-lower ctx env (first (rest (first bs))))))
          (if (null? (rest p)) (%gf-fail "a binding has no value" form) ())
          (let ((type (%gf-type (rest p))))
            (let ((n (%gf-var ctx type)))
              (go (rest bs)
                  (List append stmts (first p) (list (list (lit set) n (rest p))))
                  (pair (pair (first (first bs)) (list (lit v) n type)) new)
                  (pair (pair n type) vars)))))))))

; A named let: its variables set, then a loop whose statements end each
; path in a break or a continue.  The loop is (NAME VARS RESULT), RESULT
; a cell holding the variable its value is left in, once one is known.
(def %gf-loop
  (fn (_ ctx env form)
    (let ((name (List ref 1 form)) (b (%gf-bind ctx env (List ref 2 form) form)))
      (let ((lp (list name (List ref 2 b) (pair () ()))))
        (let ((stmts (%gf-tail-body ctx (pair (pair name (pair (lit loop) lp)) (List ref 1 b)) lp
                                    (rest (rest (rest form))))))
          (pair (List append (first b) (list (list (lit loop) stmts)))
                (first (List ref 2 lp))))))))

(def %gf-tail-body
  (fn (_ ctx env lp forms)
    (if (null? forms) (list (list (lit break)))
      (let go ((fs forms) (stmts ()))
        (if (null? (rest fs)) (List append stmts (%gf-tail ctx env lp (first fs)))
          (go (rest fs) (List append stmts (first (%gf-lower ctx env (first fs))))))))))

; FORM where its loop LP's value is: the statements, ending in a break
; with the value kept, or in a continue with the variables set anew.
(def %gf-tail
  (fn (_ ctx env lp form)
    (let ((head (if (pair? form) (first form) ())))
      (match
        ((eq? head (lit if))
          (let ((c (%gf-lower ctx env (List ref 1 form))))
            (List append (first c)
              (list (list (lit if) (%gf-test c form)
                          (%gf-tail ctx env lp (List ref 2 form))
                          (if (null? (rest (rest (rest form)))) (list (list (lit break)))
                            (%gf-tail ctx env lp (List ref 3 form))))))))
        ((eq? head (lit do)) (%gf-tail-body ctx env lp (rest form)))
        ((if (eq? head (lit let)) (not (symbol? (List ref 1 form))) #f)
          (let ((b (%gf-bind ctx env (List ref 1 form) form)))
            (List append (first b) (%gf-tail-body ctx (List ref 1 b) lp (rest (rest form))))))
        ((if (symbol? head) (eq? head (first lp)) #f)
          (let ((vars (List ref 1 lp)) (p (%gf-operands ctx env (rest form))))
            (if (int= (List length vars) (List length (rest p))) ()
              (%gf-fail "a loop is called with a value for each variable" form))
            (%gf-check (List map rest vars) (rest p) form)
            ; every next value is worked out before any variable is set: one
            ; that names a variable is kept too, since the variable may be
            ; set before it is used
            (let ((kept (List map
                          (fn (_ x)
                            (if (eq? (first x) (lit v))
                              (let ((n (%gf-var ctx (%gf-type x))))
                                (pair (list (list (lit set) n x)) (list (lit v) n (%gf-type x))))
                              (%gf-kept ctx x)))
                          (rest p))))
              (List append (first p)
                (List flat-map first kept)
                (List map (fn (_ v k) (list (lit set) (first v) (rest k))) vars kept)
                (list (list (lit continue)))))))
        (#t
          (let ((p (%gf-lower ctx env form)) (cell (List ref 2 lp)))
            (if (null? (rest p)) (List append (first p) (list (list (lit break))))
              (let ((type (%gf-type (rest p))))
                (if (null? (first cell))
                  (%set-first! cell (list (lit v) (%gf-var ctx type) type))
                  ())
                (if (eq? (List ref 2 (first cell)) type) ()
                  (%gf-fail "a loop answers one type" form))
                (List append (first p)
                  (list (list (lit set) (List ref 1 (first cell)) (rest p)) (list (lit break))))))))))))

; An if's test: the lowered expression, which must be a comparison.
(def %gf-test
  (fn (_ c form)
    (if (if (null? (rest c)) #f (eq? (%gf-type (rest c)) (lit b))) (rest c)
      (%gf-fail "an if tests a comparison" form))))

; FORM lowered: (STMTS . EXPR), EXPR nil when it has no value.
(def %gf-lower
  (fn (_ ctx env form)
    (match
      ((null? form) (pair () ()))
      ((boolean? form) (pair () (list (lit b) form)))
      ((float? form) (pair () (list (lit f) form)))
      ((number? form) (pair () (list (lit i) form)))
      ((symbol? form)
        (match
          ((if (eq? form (lit at-x)) #t (eq? form (lit at-y))) (pair () (list (lit at) form)))
          ((if (eq? form (lit member)) #t (eq? form (lit team)))
            (do (%gf-team! ctx) (pair () (list (lit at) form))))
          (#t
            (let ((e (Assoc entry form env)))
              (if (if (null? e) #t (eq? (first (rest e)) (lit loop)))
                (%gf-fail "not a variable" form)
                (pair () (rest e)))))))
      ((pair? form) (%gf-lower-form ctx env form))
      (#t (%gf-fail "not a form" form)))))

(def %gf-lower-form
  (fn (_ ctx env form)
    (let ((head (first form)))
      (match
        ((eq? head (lit do)) (%gf-body ctx env (rest form)))
        ((eq? head (lit let))
          (if (symbol? (List ref 1 form)) (%gf-loop ctx env form)
            (let ((b (%gf-bind ctx env (List ref 1 form) form)))
              (let ((p (%gf-body ctx (List ref 1 b) (rest (rest form)))))
                (pair (List append (first b) (first p)) (rest p))))))
        ((eq? head (lit if))
          (let ((c (%gf-lower ctx env (List ref 1 form)))
                (a (%gf-lower ctx env (List ref 2 form)))
                (b (if (null? (rest (rest (rest form)))) (pair () ()) (%gf-lower ctx env (List ref 3 form)))))
            (let ((test (%gf-test c form)))
              (if (if (null? (rest a)) #t (null? (rest b)))
                (pair (List append (first c) (list (list (lit if) test (first a) (first b)))) ())
                (let ((type (%gf-type (rest a))))
                  (if (eq? type (%gf-type (rest b))) ()
                    (%gf-fail "an if answers one type" form))
                  (let ((n (%gf-var ctx type)))
                    (pair (List append (first c)
                            (list (list (lit if) test
                                        (List append (first a) (list (list (lit set) n (rest a))))
                                        (List append (first b) (list (list (lit set) n (rest b)))))))
                          (list (lit v) n type))))))))
        ((eq? head (lit team-sum))
          (let ((p (%gf-operands ctx env (rest form))))
            (%gf-check (lit (f)) (rest p) form)
            (%gf-team! ctx)
            (let ((n (%gf-var ctx (lit f))))
              (pair (List append (first p) (list (list (lit team-sum) n (first (rest p)))))
                    (list (lit v) n (lit f))))))
        ((if (eq? head (lit f32-ref)) #t (eq? head (lit i32-ref)))
          (let ((type (if (eq? head (lit f32-ref)) (lit f) (lit i))))
            (let ((b (%gf-buffer ctx (List ref 1 form) type form))
                  (p (%gf-operands ctx env (rest (rest form)))))
              (%gf-check (lit (i)) (rest p) form)
              (pair (first p) (list (lit ld) b type (first (rest p)))))))
        ((if (eq? head (lit f32-set!)) #t (eq? head (lit i32-set!)))
          (let ((type (if (eq? head (lit f32-set!)) (lit f) (lit i))))
            (let ((b (%gf-buffer ctx (List ref 1 form) type form))
                  (p (%gf-operands ctx env (rest (rest form)))))
              (%gf-check (list (lit i) type) (rest p) form)
              (let ((k (%gf-kept ctx (List ref 1 (rest p)))))
                (pair (List append (first p) (first k)
                        (list (list (lit store) b type (first (rest p)) (rest k))))
                      (rest k))))))
        (#t
          (let ((op (if (symbol? head) (Assoc entry head %gf-ops) ())))
            (if (null? op)
              (%gf-fail (if (if (symbol? head) (not (null? (Assoc entry head env))) #f)
                          "a loop is called where its value is" "not an operator")
                        form)
              ())
            (let ((p (%gf-operands ctx env (rest form))))
              (%gf-check (List ref 1 op) (rest p) form)
              (pair (first p) (pair (lit op) (pair head (pair (List ref 2 op) (rest p))))))))))))

(def grid-form-plan
  (fn (_ form)
    (if (if (pair? form) (if (eq? (first form) (lit fn)) (pair? (List ref 1 form)) #f) #f) ()
      (%gf-fail "a grid form is (fn (_ buffer ...) body ...)" form))
    (let ((names (rest (List ref 1 form))))
      (let ((ctx (%gf-ctx (let go ((ns names) (i 0))
                            (if (null? ns) () (pair (pair (first ns) i) (go (rest ns) (int+ i 1))))))))
        (let ((p (%gf-body ctx () (rest (rest form)))))
          (list (List length names) (first (List ref 3 ctx)) (List reverse (first (List ref 1 ctx)))
                (first p) (first (List ref 4 ctx))))))))

; --- the Metal Shading Language ---------------------------------------------------
; A team is a simdgroup: the 32 threads Metal runs together, whose sum
; simd_sum answers with no memory shared.  The grid is 32 threads across
; for each point, so a point is its thread's place across over 32.

(def %gf-metal-ops
  (lit ((+ . "+") (- . "-") (* . "*") (/ . "/") (>> . ">>") (<< . "<<") (& . "&") (< . "<") (= . "==")
        (f+ . "+") (f- . "-") (f* . "*") (f/ . "/") (f< . "<") (f= . "==")
        (f-sqrt . "sqrt") (f-exp . "exp") (f-tanh . "tanh") (i->f . "float") (f->i . "int"))))

(def %gf-metal-type
  (fn (_ type) (match ((eq? type (lit f)) "float") ((eq? type (lit i)) "int") (#t "bool"))))

(def %gf-metal-expr
  (fn (self x team)
    (let ((k (first x)))
      (match
        ((eq? k (lit i))
          (if (int< (List ref 1 x) 0) (Str8 append "(" (io-display-to-str (List ref 1 x)) ")")
            (io-display-to-str (List ref 1 x))))
        ((eq? k (lit f)) (Str8 append "(" (io-display-to-str (List ref 1 x)) "f)"))
        ((eq? k (lit b)) (if (List ref 1 x) "true" "false"))
        ((eq? k (lit v)) (Str8 append "v" (io-display-to-str (List ref 1 x))))
        ((eq? k (lit at))
          (let ((name (List ref 1 x)))
            (match
              ((eq? name (lit at-x)) (if team "int(at.x / 32)" "int(at.x)"))
              ((eq? name (lit at-y)) "int(at.y)")
              ((eq? name (lit member)) "int(lane)")
              (#t "32"))))
        ((eq? k (lit ld))
          (Str8 append "b" (io-display-to-str (List ref 1 x)) "[" (self (List ref 3 x) team) "]"))
        (#t
          (let ((text (rest (Assoc entry (List ref 1 x) %gf-metal-ops)))
                (args (List map (fn (_ a) (self a team)) (rest (rest (rest x))))))
            (if (null? (rest args)) (Str8 append text "(" (first args) ")")
              (Str8 append "(" (first args) " " text " " (List ref 1 args) ")"))))))))

; The statements as lines, each after the indent IN.
(def %gf-metal-stmts
  (fn (self stmts team in)
    (List flat-map
      (fn (_ s)
        (let ((k (first s)) (x (fn (_ e) (%gf-metal-expr e team))))
          (match
            ((eq? k (lit set))
              (list (Str8 append in "v" (io-display-to-str (List ref 1 s)) " = " (x (List ref 2 s)) ";")))
            ((eq? k (lit store))
              (list (Str8 append in "b" (io-display-to-str (List ref 1 s)) "[" (x (List ref 3 s)) "] = "
                                 (x (List ref 4 s)) ";")))
            ((eq? k (lit if))
              (List append
                (list (Str8 append in "if (" (x (List ref 1 s)) ") {"))
                (self (List ref 2 s) team (Str8 append in "  "))
                (if (null? (List ref 3 s)) ()
                  (pair (Str8 append in "} else {") (self (List ref 3 s) team (Str8 append in "  "))))
                (list (Str8 append in "}"))))
            ((eq? k (lit loop))
              (List append
                (list (Str8 append in "for (;;) {"))
                (self (List ref 1 s) team (Str8 append in "  "))
                (list (Str8 append in "}"))))
            ((eq? k (lit break)) (list (Str8 append in "break;")))
            ((eq? k (lit continue)) (list (Str8 append in "continue;")))
            (#t
              (list (Str8 append in "v" (io-display-to-str (List ref 1 s)) " = simd_sum("
                                 (x (List ref 2 s)) ");"))))))
      stmts)))

(def %grid-form-metal-plan
  (fn (_ plan name)
    (let ((team (List ref 4 plan)) (types (List ref 1 plan)))
      (Str8 join "\n"
        (List append
          (list "#include <metal_stdlib>" "using namespace metal;"
                (Str8 append "kernel void " name "("))
          (List map
            (fn (_ i)
              (Str8 append "    device "
                (%gf-metal-type (let ((e (Assoc entry i types))) (if (null? e) (lit f) (rest e))))
                "* b" (io-display-to-str i) " [[buffer(" (io-display-to-str i) ")]],"))
            (List range 0 (first plan)))
          (list (Str8 append "    uint2 at [[thread_position_in_grid]]"
                             (if team ",\n    uint lane [[thread_index_in_simdgroup]]) {" ") {")))
          (List map
            (fn (_ v) (Str8 append "  " (%gf-metal-type (rest v)) " v" (io-display-to-str (first v)) ";"))
            (List ref 2 plan))
          (%gf-metal-stmts (List ref 3 plan) team "  ")
          (list "}" ""))))))

(def grid-form-metal
  (fn (_ form name)
    (%grid-form-metal-plan (grid-form-plan form) name)))

(doc grid-form-metal "The kernel FORM means, in the Metal Shading Language: a kernel function NAME whose buffers are bound in the order of the form's parameters, the first at index 0. A form that names a team is run 32 threads across for each grid point, a simdgroup to a point."
  (param form LIST "A grid form: (fn (_ buffer ...) body ...) over 32-bit words and singles, with word-form's operators, the loads and stores f32-ref, f32-set!, i32-ref and i32-set!, the forms if, do, let and the named let, the grid point at-x and at-y, and team, member and team-sum")
  (param name STRING "The kernel function's name")
  (returns STRING "Metal Shading Language source")
  (note "Raises a label 'value for a form that is not a grid form: an unknown operator, an operand of the wrong type, a loop called where its value is.")
  (example "(do (import x/tool/grid-form grid-form-metal) (Str8 includes? \"v1 = (b0[int(at.x)] * b0[int(at.x)]);\" (grid-form-metal (lit (fn (_ a) (f32-set! a at-x (f* (f32-ref a at-x) (f32-ref a at-x))))) \"square\")))" "#t"))

(doc grid-form-plan "The plan FORM lowers to, which each backend's kernel is made from: (BUFFERS TYPES VARS STMTS TEAM?), how many buffers the form has, each one's element type as (INDEX . f) or (INDEX . i), the variables as (N . TYPE), the statements, and whether a team runs it."
  (param form LIST "A grid form")
  (returns LIST "The plan")
  (note "Raises a label 'value for a form that is not a grid form.")
  (example "(do (import x/tool/grid-form grid-form-plan) (grid-form-plan (lit (fn (_ a) (i32-set! a at-x 7)))))" "(1 ((0 . 'i)) () (('store 0 'i ('at 'at-x) ('i 7))) #f)"))

(doc (provide x/tool/grid-form grid-form-metal grid-form-plan)
  (example "(do (import x/tool/grid-form grid-form-metal) (str? (grid-form-metal (lit (fn (_ a) (i32-set! a at-x at-y))) \"place\")))" "#t")
  "A (fn ...) form over 32-bit words and singles run once for each point of a grid on a GPU, written once and turned into what each GPU backend takes: grid-form-metal answers the Metal Shading Language.")
