; # x-lang -- language-model
;
; ## apps/language-model/main.x -- continue a prompt with a language model
;
;   x -l xe -f apps/language-model/main.x -- DIR PROMPT [N [TEMPERATURE [GREATEST]]]
;
; DIR holds a model as GPT-2 is published: model.safetensors, vocab.json
; and merges.txt.  The prompt is printed, and N pieces after it, 32 by
; default, each as the model writes it.  With no TEMPERATURE each piece
; is the one scored highest; with one, each is drawn at random, among
; GREATEST of the highest-scored where that is given.
;
; Reading the vocabulary is most of a run.  A prelude that binds
; language-model-pieces to the model's BytePair is imaged with the boot
; (x --prelude FILE), and this program then uses that one and does not
; read the two files; README.md has the prelude.
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
(import x/num/language-model)
(import x/num/float float-of f-lt)
(import x/num/random)

(def %usage
  (fn (_ said)
    (display said) (newline)
    (display "usage: x -l xe -f apps/language-model/main.x -- DIR PROMPT [N [TEMPERATURE [GREATEST]]]") (newline)
    (Sys exit 2)))

; A whole number above 0 from an argument, or the usage.
(def %count
  (fn (_ text what)
    (let ((x (guard (_ ()) (float-of text))))
      (if (if (null? x) #f (f-lt (float-of 0) x)) (Float ->int x)
        (%usage (Str8 append what " is a whole number above 0: " text))))))

(let ((args (rest (Sys args (lit program)))))
  (if (if (null? args) #t (null? (rest args))) (%usage "a model's directory and a prompt are needed") ())
  (let ((dir (first args)) (prompt (first (rest args))) (more (rest (rest args))))
    (let ((n (if (null? more) 32 (%count (first more) "N")))
          (temperature (if (if (null? more) #t (null? (rest more))) () (float-of (first (rest more)))))
          (greatest (if (if (null? more) #t (if (null? (rest more)) #t (null? (rest (rest more))))) ()
                      (%count (first (rest (rest more))) "GREATEST")))
          (file (fn (_ name) (Str8 append dir "/" name)))
          (kept (guard (_ ()) language-model-pieces)))
      (let ((lm (LanguageModel make
                  (Transformer from-file (file "model.safetensors") 12)
                  (if (null? kept) (BytePair from-files (file "vocab.json") (file "merges.txt")) kept))))
        (display prompt)
        (if (null? temperature)
          (lm each prompt n display)
          (if (null? greatest)
            (lm each prompt n display (Random hw) temperature)
            (lm each prompt n display (Random hw) temperature greatest)))
        (newline)
        (lm release)))))
