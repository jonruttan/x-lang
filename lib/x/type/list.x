; list.x -- List: the list/sequence operations as static methods.
;
; Transitional: the global functions in core/list.x still exist; call sites
; migrate to (List ...) and the globals are removed once nothing references them.
; This class loads AFTER object.x (it needs def-class); core/list.x loads before
; it (and the object system) as the low-level layer -- the %-helpers (%map1,
; %any-null?, %for-each1, %append2) stay there, shared by both.
;
; Recursion uses `recur` (a method's own self-reference); cross-calls to other
; list operations go through (List ...).

(import x/type/object)

(def-class List ()
  (static
    (method as-list (self x)
      (if (or (null? x) (pair? x)) x (Iter ->list (Iter new x))))
    (method fold (self f init lst)
      (let ((lst (List as-list lst)))
        (if (null? lst) init (recur self f (f init (first lst)) (rest lst)))))
    (method reduce (self f lst)
      (let ((lst (List as-list lst))) (List fold f (first lst) (rest lst))))
    (method map (self f . lsts)
      (let ((lsts (%map1 (fn (_ x) (List as-list x)) lsts)))
        (if (null? (rest lsts))
          (%map1 f (first lsts))
          (if (%any-null? lsts) ()
            (pair (apply f (%map1 first lsts)) (apply recur self f (%map1 rest lsts)))))))
    (method filter (self pred lst)
      (let ((lst (List as-list lst)))
        (match
          ((null? lst) ())
          ((pred (first lst)) (pair (first lst) (recur self pred (rest lst))))
          (#t (recur self pred (rest lst))))))
    (method for-each (self f . lsts)
      (let ((lsts (%map1 (fn (_ x) (List as-list x)) lsts)))
        (if (null? (rest lsts))
          (%for-each1 f (first lsts))
          (if (not (%any-null? lsts))
            (do (apply f (%map1 first lsts)) (apply recur self f (%map1 rest lsts)))))))))
