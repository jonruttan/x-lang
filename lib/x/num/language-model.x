; language-model.x -- LanguageModel: text in and text out, over a Transformer and its BytePair.
;
; A Transformer reads ids and answers ids, and a BytePair turns text into
; a vocabulary's ids and back.  A LanguageModel is the two together: it
; takes a text, and answers it with the pieces the model writes after it.
;
;   (LanguageModel from-files model vocabulary merges heads)  -> one, from a model's three files
;   (LanguageModel make transformer byte-pair)                -> one, from the two parts
;   (lm generate text n)                                      -> the text and n more pieces
;   (lm generate text n random temperature greatest)          -> the same, each piece drawn at random
;   (lm each text n f)                                        -> the same, f called with each piece as it is made
;   (lm release)                                              -> the model's GPU buffers given back
;
; A piece is one item of the vocabulary: a word, part of one, or a few
; bytes.  With no source of randomness each piece is the one the model
; scores highest, and the same text always answers the same; with one,
; each is drawn as Transformer's variate draws it.
;
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(module x/num/language-model)
(import x/type/class)
(import x/type/list)
(import x/codec/byte-pair)
(import x/num/transformer)

(def-class LanguageModel ()
  (doc "A language model that reads and writes text: a Transformer and the BytePair of its vocabulary. It takes a text and answers it with the pieces the model writes after it."
    (note "A piece is one item of the vocabulary: a word, part of one, or a few bytes. A character of several bytes may be split between two pieces.")
    (note "With no Random each piece is the one scored highest; with one, each is drawn as Transformer's variate draws it, with its temperature and greatest.")
    (sample "((LanguageModel from-files \"model.safetensors\" \"vocab.json\" \"merges.txt\" 12) generate \"Hello, I'm a language model,\" 8)" "the text and the eight pieces GPT-2 writes after it")
    (known-as "LLM" "text generation" "text completion")
    (see from-files) (see make) (see generate) (see each) (see release))

  transformer   ; the Transformer
  pieces        ; the BytePair of its vocabulary

  (static
    (method make (self (param transformer Transformer "The model")
                       (param pieces BytePair "The encoder of the model's vocabulary"))
      (doc "A LanguageModel from a Transformer and the BytePair of its vocabulary."
        (returns LanguageModel "The two together")
        (sample "(LanguageModel make m b)" "a language model"))
      (if (if (object? transformer) (instance-of? transformer Transformer) #f) ()
        (Err raise (lit type) "LanguageModel: not a Transformer" transformer))
      (if (if (object? pieces) (instance-of? pieces BytePair) #f) ()
        (Err raise (lit type) "LanguageModel: not a BytePair" pieces))
      (new-from self (list (lit transformer) transformer (lit pieces) pieces)))

    (method from-files (self (param model STRING "A safetensors file with GPT-2's tensor names")
                             (param vocabulary STRING "The vocabulary file: a JSON object of item to id")
                             (param merges STRING "The merge list's file")
                             (param heads INTEGER "How many heads each block's attention has: 12 for GPT-2"))
      (doc "A LanguageModel from a model's three files, as GPT-2 is published with them."
        (returns LanguageModel "The model and its encoder")
        (sample "(LanguageModel from-files \"model.safetensors\" \"vocab.json\" \"merges.txt\" 12)" "GPT-2")
        (see make))
      (LanguageModel make (Transformer from-file model heads) (BytePair from-files vocabulary merges))))

  ; The text and n more pieces; f is called with each piece's text as it
  ; is made.  OPTIONS is () or (RANDOM TEMPERATURE GREATEST), the last two
  ; optional.
  (method %run (self text n f options)
    (let ((tf (field (lit transformer))) (bp (field (lit pieces))))
      (let ((ids (bp encode text)))
        (if (null? ids) (Err raise (lit value) "LanguageModel: the text has no pieces" text) ())
        (let ((pick (tf %picking (if (null? options) () (first options)) (if (null? options) () (rest options)))))
          (bp decode (tf %generate ids n pick (fn (_ id) (f (bp decode (list id))))))))))

  (method generate (self (param text STRING "The text to begin from, in UTF-8, of at least one piece")
                         (param n INTEGER "How many pieces to add")
                         . (param options ANY "Optional (RANDOM TEMPERATURE GREATEST): a Random, and Transformer variate's temperature and greatest"))
    (doc "The text and n more pieces after it. With no Random each piece is the one the model scores highest after all those before it; with one, each is drawn at random. The text's pieces and the n less one fed back must be no more than the model has positions, or a label 'value is raised; so is a text of no pieces."
      (returns STRING "The text, n pieces longer")
      (sample "(lm generate \"Hello, I'm a language model,\" 8)" "\"Hello, I'm a language model, not a programming language. I'm a\" from GPT-2")
      (sample "(lm generate \"Once\" 20 (Random hw) 0.8 40)" "a different text each time")
      (known-as "complete" "continue")
      (see each))
    (self %run text n (fn (_ piece) ()) options))

  (method each (self (param text STRING "The text to begin from, in UTF-8, of at least one piece")
                     (param n INTEGER "How many pieces to add")
                     (param f CALLABLE "Called with each new piece's text as it is made")
                     . (param options ANY "Optional (RANDOM TEMPERATURE GREATEST), as generate takes them"))
    (doc "generate, with f called on each new piece as soon as the model has written it: a caller shows the text as it grows. A piece is the bytes of one vocabulary item, so a character of several bytes may arrive in two pieces."
      (returns STRING "The text, n pieces longer")
      (sample "(lm each \"Hello,\" 8 display)" "the eight pieces displayed one at a time, then the whole text answered")
      (known-as "stream")
      (see generate))
    (self %run text n f options))

  (method release (self)
    (doc "Give back the GPU buffers that hold the model's weights, as Transformer's release does. The model is finished."
      (returns ANY "nil")
      (sample "(lm release)" "the weights' buffers given back"))
    ((field (lit transformer)) release)))

(doc (provide x/num/language-model LanguageModel)
  (sample "((LanguageModel from-files \"model.safetensors\" \"vocab.json\" \"merges.txt\" 12) generate \"Hello,\" 8)" "the text and the eight pieces GPT-2 writes after it")
  "LanguageModel: a Transformer and its BytePair together, text in and text out: generate adds pieces to a text, greedily or drawn at random, and each hands them over as they are made.")
