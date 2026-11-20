; byte-pair.x -- BytePair: text to a model's vocabulary ids and back.
;
; A language model reads text as a list of ids, each naming an item of
; its vocabulary, a run of bytes.  Byte-pair encoding makes the items:
; a word starts as its bytes, and the two neighbours that the model's
; merge list ranks first are joined, again and again, until no pair of
; neighbours is in the list.  What is left are items, and their ids are
; the word's.
;
;   (BytePair from-files vocabulary merges)  -> a BytePair, from a model's two files
;   (BytePair make ids merges)               -> one from a Dict of item to id and a
;                                               list of pairs of items
;   (b encode text)                          -> the text's ids
;   (b decode ids)                           -> the ids' text
;   (b item id)                              -> the bytes of the item with that id
;   (b id item)                              -> an item's id, or nil
;   (b size)                                 -> how many items there are
;
; The files are the two GPT-2 is published with.  The vocabulary is a
; JSON object of item to id, and the merges a text file whose first line
; is a comment and whose every other line is two items a space apart,
; the earliest ranked first.
;
; In those files an item is written in letters, one for a byte: a byte
; that is a printing character of Latin-1 stands for itself, and each of
; the 68 others, the controls, the space and the soft hyphen among them,
; is the code point 256 above its place in their order.  So a leading
; space is written as the letter U+0120.  item answers the bytes
; themselves, and encode and decode take and answer ordinary text.
;
; Before any merging the text is cut into words, each merged alone, as
; the model's own splitter cuts it: an apostrophe with s, t, re, ve, m,
; ll or d; a run of letters, a run of numbers, or a run of anything
; else that is not white space, each with the one space before it, if
; there is one; and a run of white space, less its last character when a
; word follows.  Letters, numbers and white space are Unicode 17's
; categories L and N and its White_Space property; the two tables below
; list the letters and numbers from U+0080, as (START END) in order.
;
; A word's ids are kept once worked out, so a word met again costs a
; lookup.  Nothing collects garbage during one call, so the loops over a
; vocabulary, a merge list and a text's words collect as they go, every
; %bp-window turns.
;
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(module x/codec/byte-pair)
(import x/type/class)
(import x/type/dict)
(import x/type/list)
(import x/type/vector)
(import x/codec/json)
(import x/codec/utf8 utf8-cp-at utf8-width utf8-encode)
(import x/sys/file)
(import x/sys/gc)
(import x/core/doors char->int int* int+ int- int/ int< int= str-byte-len str-byte-ref str-byte-sub type-of type?)

(def %bp-letters (list
  170 170 181 181 186 186 192 214 216 246 248 705 710 721 736 740 748 748 750
  750 880 884 886 887 890 893 895 895 902 902 904 906 908 908 910 929 931
  1013 1015 1153 1162 1327 1329 1366 1369 1369 1376 1416 1488 1514 1519 1522
  1568 1610 1646 1647 1649 1747 1749 1749 1765 1766 1774 1775 1786 1788 1791
  1791 1808 1808 1810 1839 1869 1957 1969 1969 1994 2026 2036 2037 2042 2042
  2048 2069 2074 2074 2084 2084 2088 2088 2112 2136 2144 2154 2160 2183 2185
  2191 2208 2249 2308 2361 2365 2365 2384 2384 2392 2401 2417 2432 2437 2444
  2447 2448 2451 2472 2474 2480 2482 2482 2486 2489 2493 2493 2510 2510 2524
  2525 2527 2529 2544 2545 2556 2556 2565 2570 2575 2576 2579 2600 2602 2608
  2610 2611 2613 2614 2616 2617 2649 2652 2654 2654 2674 2676 2693 2701 2703
  2705 2707 2728 2730 2736 2738 2739 2741 2745 2749 2749 2768 2768 2784 2785
  2809 2809 2821 2828 2831 2832 2835 2856 2858 2864 2866 2867 2869 2873 2877
  2877 2908 2909 2911 2913 2929 2929 2947 2947 2949 2954 2958 2960 2962 2965
  2969 2970 2972 2972 2974 2975 2979 2980 2984 2986 2990 3001 3024 3024 3077
  3084 3086 3088 3090 3112 3114 3129 3133 3133 3160 3162 3164 3165 3168 3169
  3200 3200 3205 3212 3214 3216 3218 3240 3242 3251 3253 3257 3261 3261 3292
  3294 3296 3297 3313 3314 3332 3340 3342 3344 3346 3386 3389 3389 3406 3406
  3412 3414 3423 3425 3450 3455 3461 3478 3482 3505 3507 3515 3517 3517 3520
  3526 3585 3632 3634 3635 3648 3654 3713 3714 3716 3716 3718 3722 3724 3747
  3749 3749 3751 3760 3762 3763 3773 3773 3776 3780 3782 3782 3804 3807 3840
  3840 3904 3911 3913 3948 3976 3980 4096 4138 4159 4159 4176 4181 4186 4189
  4193 4193 4197 4198 4206 4208 4213 4225 4238 4238 4256 4293 4295 4295 4301
  4301 4304 4346 4348 4680 4682 4685 4688 4694 4696 4696 4698 4701 4704 4744
  4746 4749 4752 4784 4786 4789 4792 4798 4800 4800 4802 4805 4808 4822 4824
  4880 4882 4885 4888 4954 4992 5007 5024 5109 5112 5117 5121 5740 5743 5759
  5761 5786 5792 5866 5873 5880 5888 5905 5919 5937 5952 5969 5984 5996 5998
  6000 6016 6067 6103 6103 6108 6108 6176 6264 6272 6276 6279 6312 6314 6314
  6320 6389 6400 6430 6480 6509 6512 6516 6528 6571 6576 6601 6656 6678 6688
  6740 6823 6823 6917 6963 6981 6988 7043 7072 7086 7087 7098 7141 7168 7203
  7245 7247 7258 7293 7296 7306 7312 7354 7357 7359 7401 7404 7406 7411 7413
  7414 7418 7418 7424 7615 7680 7957 7960 7965 7968 8005 8008 8013 8016 8023
  8025 8025 8027 8027 8029 8029 8031 8061 8064 8116 8118 8124 8126 8126 8130
  8132 8134 8140 8144 8147 8150 8155 8160 8172 8178 8180 8182 8188 8305 8305
  8319 8319 8336 8348 8450 8450 8455 8455 8458 8467 8469 8469 8473 8477 8484
  8484 8486 8486 8488 8488 8490 8493 8495 8505 8508 8511 8517 8521 8526 8526
  8579 8580 11264 11492 11499 11502 11506 11507 11520 11557 11559 11559 11565
  11565 11568 11623 11631 11631 11648 11670 11680 11686 11688 11694 11696
  11702 11704 11710 11712 11718 11720 11726 11728 11734 11736 11742 11823
  11823 12293 12294 12337 12341 12347 12348 12353 12438 12445 12447 12449
  12538 12540 12543 12549 12591 12593 12686 12704 12735 12784 12799 13312
  19903 19968 42124 42192 42237 42240 42508 42512 42527 42538 42539 42560
  42606 42623 42653 42656 42725 42775 42783 42786 42888 42891 42972 42993
  43009 43011 43013 43015 43018 43020 43042 43072 43123 43138 43187 43250
  43255 43259 43259 43261 43262 43274 43301 43312 43334 43360 43388 43396
  43442 43471 43471 43488 43492 43494 43503 43514 43518 43520 43560 43584
  43586 43588 43595 43616 43638 43642 43642 43646 43695 43697 43697 43701
  43702 43705 43709 43712 43712 43714 43714 43739 43741 43744 43754 43762
  43764 43777 43782 43785 43790 43793 43798 43808 43814 43816 43822 43824
  43866 43868 43881 43888 44002 44032 55203 55216 55238 55243 55291 63744
  64109 64112 64217 64256 64262 64275 64279 64285 64285 64287 64296 64298
  64310 64312 64316 64318 64318 64320 64321 64323 64324 64326 64433 64467
  64829 64848 64911 64914 64967 65008 65019 65136 65140 65142 65276 65313
  65338 65345 65370 65382 65470 65474 65479 65482 65487 65490 65495 65498
  65500 65536 65547 65549 65574 65576 65594 65596 65597 65599 65613 65616
  65629 65664 65786 66176 66204 66208 66256 66304 66335 66349 66368 66370
  66377 66384 66421 66432 66461 66464 66499 66504 66511 66560 66717 66736
  66771 66776 66811 66816 66855 66864 66915 66928 66938 66940 66954 66956
  66962 66964 66965 66967 66977 66979 66993 66995 67001 67003 67004 67008
  67059 67072 67382 67392 67413 67424 67431 67456 67461 67463 67504 67506
  67514 67584 67589 67592 67592 67594 67637 67639 67640 67644 67644 67647
  67669 67680 67702 67712 67742 67808 67826 67828 67829 67840 67861 67872
  67897 67904 67929 67968 68023 68030 68031 68096 68096 68112 68115 68117
  68119 68121 68149 68192 68220 68224 68252 68288 68295 68297 68324 68352
  68405 68416 68437 68448 68466 68480 68497 68608 68680 68736 68786 68800
  68850 68864 68899 68938 68965 68975 68997 69248 69289 69296 69297 69314
  69319 69376 69404 69415 69415 69424 69445 69488 69505 69552 69572 69600
  69622 69635 69687 69745 69746 69749 69749 69763 69807 69840 69864 69891
  69926 69956 69956 69959 69959 69968 70002 70006 70006 70019 70066 70081
  70084 70106 70106 70108 70108 70144 70161 70163 70187 70207 70208 70272
  70278 70280 70280 70282 70285 70287 70301 70303 70312 70320 70366 70405
  70412 70415 70416 70419 70440 70442 70448 70450 70451 70453 70457 70461
  70461 70480 70480 70493 70497 70528 70537 70539 70539 70542 70542 70544
  70581 70583 70583 70609 70609 70611 70611 70656 70708 70727 70730 70751
  70753 70784 70831 70852 70853 70855 70855 71040 71086 71128 71131 71168
  71215 71236 71236 71296 71338 71352 71352 71424 71450 71488 71494 71680
  71723 71840 71903 71935 71942 71945 71945 71948 71955 71957 71958 71960
  71983 71999 71999 72001 72001 72096 72103 72106 72144 72161 72161 72163
  72163 72192 72192 72203 72242 72250 72250 72272 72272 72284 72329 72349
  72349 72368 72440 72640 72672 72704 72712 72714 72750 72768 72768 72818
  72847 72960 72966 72968 72969 72971 73008 73030 73030 73056 73061 73063
  73064 73066 73097 73112 73112 73136 73179 73440 73458 73474 73474 73476
  73488 73490 73523 73648 73648 73728 74649 74880 75075 77712 77808 77824
  78895 78913 78918 78944 82938 82944 83526 90368 90397 92160 92728 92736
  92766 92784 92862 92880 92909 92928 92975 92992 92995 93027 93047 93053
  93071 93504 93548 93760 93823 93856 93880 93883 93907 93952 94026 94032
  94032 94099 94111 94176 94177 94179 94179 94194 94195 94208 101589 101631
  101662 101760 101874 110576 110579 110581 110587 110589 110590 110592
  110882 110898 110898 110928 110930 110933 110933 110948 110951 110960
  111355 113664 113770 113776 113788 113792 113800 113808 113817 119808
  119892 119894 119964 119966 119967 119970 119970 119973 119974 119977
  119980 119982 119993 119995 119995 119997 120003 120005 120069 120071
  120074 120077 120084 120086 120092 120094 120121 120123 120126 120128
  120132 120134 120134 120138 120144 120146 120485 120488 120512 120514
  120538 120540 120570 120572 120596 120598 120628 120630 120654 120656
  120686 120688 120712 120714 120744 120746 120770 120772 120779 122624
  122654 122661 122666 122928 122989 123136 123180 123191 123197 123214
  123214 123536 123565 123584 123627 124112 124139 124368 124397 124400
  124400 124608 124638 124640 124642 124644 124645 124647 124653 124656
  124660 124670 124671 124896 124902 124904 124907 124909 124910 124912
  124926 124928 125124 125184 125251 125259 125259 126464 126467 126469
  126495 126497 126498 126500 126500 126503 126503 126505 126514 126516
  126519 126521 126521 126523 126523 126530 126530 126535 126535 126537
  126537 126539 126539 126541 126543 126545 126546 126548 126548 126551
  126551 126553 126553 126555 126555 126557 126557 126559 126559 126561
  126562 126564 126564 126567 126570 126572 126578 126580 126583 126585
  126588 126590 126590 126592 126601 126603 126619 126625 126627 126629
  126633 126635 126651 131072 173791 173824 178205 178208 183981 183984
  191456 191472 192093 194560 195101 196608 201546 201552 210041))

(def %bp-numbers (list
  178 179 185 185 188 190 1632 1641 1776 1785 1984 1993 2406 2415 2534 2543
  2548 2553 2662 2671 2790 2799 2918 2927 2930 2935 3046 3058 3174 3183 3192
  3198 3302 3311 3416 3422 3430 3448 3558 3567 3664 3673 3792 3801 3872 3891
  4160 4169 4240 4249 4969 4988 5870 5872 6112 6121 6128 6137 6160 6169 6470
  6479 6608 6618 6784 6793 6800 6809 6992 7001 7088 7097 7232 7241 7248 7257
  8304 8304 8308 8313 8320 8329 8528 8578 8581 8585 9312 9371 9450 9471 10102
  10131 11517 11517 12295 12295 12321 12329 12344 12346 12690 12693 12832
  12841 12872 12879 12881 12895 12928 12937 12977 12991 42528 42537 42726
  42735 43056 43061 43216 43225 43264 43273 43472 43481 43504 43513 43600
  43609 44016 44025 65296 65305 65799 65843 65856 65912 65930 65931 66273
  66299 66336 66339 66369 66369 66378 66378 66513 66517 66720 66729 67672
  67679 67705 67711 67751 67759 67835 67839 67862 67867 68028 68029 68032
  68047 68050 68095 68160 68168 68221 68222 68253 68255 68331 68335 68440
  68447 68472 68479 68521 68527 68858 68863 68912 68921 68928 68937 69216
  69246 69405 69414 69457 69460 69573 69579 69714 69743 69872 69881 69942
  69951 70096 70105 70113 70132 70384 70393 70736 70745 70864 70873 71248
  71257 71360 71369 71376 71395 71472 71483 71904 71922 72016 72025 72688
  72697 72784 72812 73040 73049 73120 73129 73184 73193 73552 73561 73664
  73684 74752 74862 90416 90425 92768 92777 92864 92873 93008 93017 93019
  93025 93552 93561 93824 93846 94196 94198 118000 118009 119488 119507
  119520 119539 119648 119672 120782 120831 123200 123209 123632 123641
  124144 124153 124401 124410 125127 125135 125264 125273 126065 126123
  126125 126127 126129 126132 126209 126253 126255 126269 127232 127244
  130032 130041))

; --- character classes -----------------------------------------------------------
; A table as a Vector, made the first time a class is asked for.
(def %bp-tables (pair () ()))
(def %bp-table
  (fn (_ numbers?)
    (if (null? (first %bp-tables))
      (do (%set-first! %bp-tables (Vector from-list %bp-letters))
          (%set-rest! %bp-tables (Vector from-list %bp-numbers)))
      ())
    (if numbers? (rest %bp-tables) (first %bp-tables))))

; Whether code point cp lies in a range of the table, searched by halves.
(def %bp-in?
  (fn (_ table cp)
    ((fn (go lo hi)
       (if (int< lo hi)
         (let ((mid (int/ (int+ lo hi) 2)))
           (match
             ((int< cp (Vector ref (int* 2 mid) table)) (go lo mid))
             ((int< (Vector ref (int+ (int* 2 mid) 1) table) cp) (go (int+ mid 1) hi))
             (#t #t)))
         #f))
      0 (int/ (Vector length table) 2))))

(def %bp-between? (fn (_ cp lo hi) (if (int< cp lo) #f (not (int< hi cp)))))

; A code point's class: space, letter, number or other.
(def %bp-class
  (fn (_ cp)
    (if (int< cp 128)
      (match
        ((int= cp 32) (lit space))
        ((%bp-between? cp 9 13) (lit space))
        ((%bp-between? cp 48 57) (lit number))
        ((%bp-between? cp 65 90) (lit letter))
        ((%bp-between? cp 97 122) (lit letter))
        (#t (lit other)))
      (match
        ((if (int= cp 133) #t (if (int= cp 160) #t (if (int= cp 5760) #t (if (%bp-between? cp 8192 8202) #t
           (if (%bp-between? cp 8232 8233) #t (if (int= cp 8239) #t (if (int= cp 8287) #t (int= cp 12288))))))))
          (lit space))
        ((%bp-in? (%bp-table #f) cp) (lit letter))
        ((%bp-in? (%bp-table #t) cp) (lit number))
        (#t (lit other))))))

; --- cutting text into words -------------------------------------------------------
(def %bp-byte (fn (_ s i) (char->int (str-byte-ref s i))))

; The byte width of the character at i, never past the end: a lead byte
; whose sequence is cut short is one byte.
(def %bp-width
  (fn (_ s i n) (let ((w (utf8-width s i))) (if (int< n (int+ i w)) 1 w))))

; The class of the character at i.  A byte that begins no whole sequence
; is other.
(def %bp-class-at
  (fn (_ s i n)
    (if (int= (%bp-width s i n) (utf8-width s i))
      (if (%bp-between? (%bp-byte s i) 128 191) (lit other) (%bp-class (utf8-cp-at s i)))
      (lit other))))

; The index after the run of characters of class c that starts at i.
(def %bp-run
  (fn (go s i n c)
    (if (int< i n)
      (if (eq? (%bp-class-at s i n) c) (go s (int+ i (%bp-width s i n)) n c) i)
      i)))

; The contractions, in the order the splitter tries them.
(def %bp-contractions (list "'s" "'t" "'re" "'ve" "'m" "'ll" "'d"))

(def %bp-starts?
  (fn (_ s i n lit-text)
    (let ((k (str-byte-len lit-text)))
      (if (int< n (int+ i k)) #f
        ((fn (go j) (if (int< j k) (if (int= (%bp-byte s (int+ i j)) (%bp-byte lit-text j)) (go (int+ j 1)) #f) #t)) 0)))))

; The index after the word that starts at i, i below n.
(def %bp-word-end
  (fn (_ s i n)
    (let ((hit ((fn (go l) (match ((null? l) ()) ((%bp-starts? s i n (first l)) (first l)) (#t (go (rest l)))))
                 %bp-contractions)))
      (if (null? hit)
        ; one space, when a word follows it, is the word's
        (let ((j (if (if (int= (%bp-byte s i) 32) (int< (int+ i 1) n) #f) (int+ i 1) i)))
          (let ((c (%bp-class-at s j n)))
            (if (eq? c (lit space))
              ; white space: the run, less its last character when a word follows
              (let ((end (%bp-run s i n (lit space))))
                (if (int= end n) end
                  ((fn (go k last) (if (int< k end) (go (int+ k (%bp-width s k n)) k) (if (int= last i) end last)))
                    i i)))
              (%bp-run s j n c))))
        (int+ i (str-byte-len hit))))))

; --- memory -------------------------------------------------------------------------
; The turns of a loop between collections.
(def %bp-window 2048)
(def %bp-debt (pair 0 ()))
(def %bp-owe!
  (fn (_ k)
    (let ((d (int+ (first %bp-debt) k)))
      (if (int< d %bp-window) (%set-first! %bp-debt d)
        (do (%set-first! %bp-debt 0) (Heap collect))))))

; --- merging -------------------------------------------------------------------------
(def %bp-key (fn (_ a b) (Str8 append a " " b)))

; The pair of neighbours ranked first, as (RANK A B), or nil.
(def %bp-best
  (fn (go ranks parts best)
    (if (if (null? parts) #t (null? (rest parts))) best
      (let ((r (ranks get (%bp-key (first parts) (first (rest parts))))))
        (go ranks (rest parts)
          (if (null? r) best
            (if (if (null? best) #t (int< r (first best)))
              (list r (first parts) (first (rest parts)))
              best)))))))

; parts with every neighbouring a and b joined.
(def %bp-join
  (fn (go parts a b)
    (match
      ((null? parts) ())
      ((null? (rest parts)) parts)
      ((if (equal? (first parts) a) (equal? (first (rest parts)) b) #f)
        (pair (Str8 append a b) (go (rest (rest parts)) a b)))
      (#t (pair (first parts) (go (rest parts) a b))))))

(def %bp-merge
  (fn (go ranks parts)
    (let ((best (%bp-best ranks parts ())))
      (if (null? best) parts
        (go ranks (%bp-join parts (first (rest best)) (first (rest (rest best)))))))))

; A merge file's pairs, (A B) a line: the text before a line's first space
; and the text after it.  The first line is the comment, and a line with
; no space names no pair.
(def %bp-pairs
  (fn (_ text)
    (let ((n (str-byte-len text)))
      (def line
        (fn (_ start space end comment? acc)
          (if (if comment? #t (null? space)) acc
            (pair (list (str-byte-sub text start (int- space start))
                        (str-byte-sub text (int+ space 1) (int- end (int+ space 1))))
                  acc))))
      ((fn (go i start space comment? acc)
         (if (int< i n)
           (let ((b (%bp-byte text i)))
             (match
               ((int= b 10)
                 (do (%bp-owe! 1)
                     (go (int+ i 1) (int+ i 1) () #f (line start space i comment? acc))))
               ((if (int= b 32) (null? space) #f) (go (int+ i 1) start i comment? acc))
               (#t (go (int+ i 1) start space comment? acc))))
           (List reverse (line start space n comment? acc))))
        0 0 () #t ()))))

; --- the letters the files write bytes in -----------------------------------------
; Byte b's code point: itself for a printing character of Latin-1, else
; 256 above its place among the others.
(def %bp-letter-of
  (fn (_)
    ((fn (go b extra acc)
       (if (int< b 256)
         (if (if (%bp-between? b 33 126) #t (if (%bp-between? b 161 172) #t (%bp-between? b 174 255)))
           (go (int+ b 1) extra (pair b acc))
           (go (int+ b 1) (int+ extra 1) (pair (int+ 256 extra) acc)))
         (Vector from-list (List reverse acc))))
      0 0 ())))

; An item as the files write it, from its bytes, and back.
(def %bp-written
  (fn (_ letters bytes)
    (let ((n (str-byte-len bytes)))
      (bytes->str
        ((fn (go i)
           (if (int< i n) (List append (utf8-encode (Vector ref (%bp-byte bytes i) letters)) (go (int+ i 1))) ()))
          0)))))

(def %bp-bytes
  (fn (_ back written)
    (let ((n (str-byte-len written)))
      (bytes->str
        ((fn (go i)
           (if (int< i n)
             (let ((b (back get (utf8-cp-at written i))))
               (if (null? b) (Err raise (lit value) "BytePair: an item holds a letter that stands for no byte" written) ())
               (pair b (go (int+ i (utf8-width written i)))))
             ()))
          0)))))

(def-class BytePair ()
  (doc "Byte-pair encoding: text to the ids of a language model's vocabulary and back, from the model's vocabulary and merge list."
    (note "A unit of the vocabulary is an item, a run of bytes with an id. The reader's token is another thing.")
    (note "The text is cut into words as GPT-2's splitter cuts it, and each word's bytes are merged by the merge list's ranks.")
    (example "((BytePair make (Dict from-plist (list \"a\" 0 \"b\" 1 \"ab\" 2)) (list (list \"a\" \"b\"))) encode \"abb\")" "(2 1)")
    (known-as "BPE" "tokenizer")
    (see from-files) (see make) (see encode) (see decode) (see item))

  ids       ; item, as the files write it -> id
  items     ; id -> item, as the files write it; a Vector
  ranks     ; "A B" -> the pair's place in the merge list
  letters   ; byte -> the code point that writes it; a Vector
  back      ; code point -> byte
  words     ; word -> its ids, as they are worked out

  (static
    (method make (self (param ids Dict "Each item, written in the files' letters, and its id")
                       (param merges LIST "Pairs of items, (A B), the earliest ranked first"))
      (doc "A BytePair from a vocabulary and a merge list held in memory."
        (returns BytePair "The encoder")
        (example "((BytePair make (Dict from-plist (list \"a\" 0 \"b\" 1 \"ab\" 2)) (list (list \"a\" \"b\"))) size)" "3"))
      (let ((letters (%bp-letter-of)) (back (Dict make)) (ranks (Dict make))
            (count (List fold (fn (_ acc id) (if (int< acc (int+ id 1)) (int+ id 1) acc)) 0 (ids vals))))
        ((fn (go b) (if (int< b 256) (do (back set! (Vector ref b letters) b) (go (int+ b 1))) ())) 0)
        ((fn (go l k)
           (if (null? l) ()
             (do (ranks set! (%bp-key (first (first l)) (first (rest (first l)))) k) (%bp-owe! 1) (go (rest l) (int+ k 1)))))
          merges 0)
        (let ((items (Vector make count ())))
          (ids for-each (fn (_ kv) (Vector set! (rest kv) (first kv) items) (%bp-owe! 1)))
          (new-from self
            (list (lit ids) ids (lit items) items (lit ranks) ranks (lit letters) letters
                  (lit back) back (lit words) (Dict make))))))

    (method from-files (self (param vocabulary STRING "The vocabulary file: a JSON object of item to id")
                             (param merges STRING "The merge file: a comment line, then two items a line"))
      (doc "A BytePair from a model's two files, as GPT-2 is published with them."
        (returns BytePair "The encoder")
        (sample "(BytePair from-files \"vocab.json\" \"merges.txt\")" "the encoder"))
      (let ((ids (Json parse (File read-all vocabulary))))
        (if (Dict dict? ids) () (Err raise (lit value) "BytePair: the vocabulary is not a JSON object" vocabulary))
        (BytePair make ids (%bp-pairs (File read-all merges))))))

  (method size (self)
    (doc "How many items the vocabulary has."
      (returns INTEGER "One more than the greatest id")
      (example "((BytePair make (Dict from-plist (list \"a\" 0 \"b\" 1 \"ab\" 2)) ()) size)" "3"))
    (Vector length (field (lit items))))

  (method item (self (param id INTEGER "An id"))
    (doc "The bytes of the item with an id."
      (returns STRING "The item's bytes, or nil for an id the vocabulary lacks")
      (example "((BytePair make (Dict from-plist (list \"a\" 0 \"b\" 1 \"ab\" 2)) ()) item 2)" "\"ab\""))
    (let ((items (field (lit items))))
      (if (if (type? id (type-of 0)) (if (int< id 0) #f (int< id (Vector length items))) #f)
        (let ((w (Vector ref id items))) (if (null? w) () (%bp-bytes (field (lit back)) w)))
        ())))

  (method id (self (param item STRING "An item's bytes"))
    (doc "The id of the item with these bytes."
      (returns INTEGER "The id, or nil when no item is these bytes")
      (example "((BytePair make (Dict from-plist (list \"a\" 0 \"b\" 1 \"ab\" 2)) ()) id \"ab\")" "2"))
    ((field (lit ids)) get (%bp-written (field (lit letters)) item)))

  (method encode (self (param text STRING "Text, in UTF-8"))
    (doc "The text's ids: it is cut into words, and each word's bytes are merged by the merge list until no neighbouring pair is in it. A piece left that the vocabulary lacks raises a label 'value."
      (returns LIST "The ids, in the text's order")
      (example "((BytePair make (Dict from-plist (list \"a\" 0 \"b\" 1 \"ab\" 2)) (list (list \"a\" \"b\"))) encode \"abb\")" "(2 1)"))
    (let ((n (str-byte-len text)) (ids (field (lit ids))) (ranks (field (lit ranks)))
          (letters (field (lit letters))) (words (field (lit words))))
      (def word
        (fn (_ w)
          (let ((known (words get w)))
            (if (null? known)
              (let ((made
                      (List map
                        (fn (_ part)
                          (let ((id (ids get part)))
                            (if (null? id) (Err raise (lit value) "BytePair: the vocabulary lacks an item the text needs" part) id)))
                        (%bp-merge ranks
                          ((fn (go i k)
                             (if (int< i k) (pair (%bp-written letters (str-byte-sub w i 1)) (go (int+ i 1) k)) ()))
                            0 (str-byte-len w))))))
                (words set! w made)
                made)
              known))))
      ((fn (go i acc)
         (if (int< i n)
           (let ((end (%bp-word-end text i n)))
             ; a word's merging leaves far more behind than a turn of the other loops
             (%bp-owe! 16)
             (go end (pair (word (str-byte-sub text i (int- end i))) acc)))
           (List flat-map (fn (_ l) l) (List reverse acc))))
        0 ())))

  (method decode (self (param ids LIST "Ids"))
    (doc "The ids' text: their items' bytes end to end. An id the vocabulary lacks raises a label 'value."
      (returns STRING "The text")
      (example "((BytePair make (Dict from-plist (list \"a\" 0 \"b\" 1 \"ab\" 2)) ()) decode (list 2 1 0))" "\"abba\""))
    (let ((items (field (lit items))) (back (field (lit back))))
      (Str8 join ""
        (List map
          (fn (_ id)
            (let ((w (if (if (type? id (type-of 0)) (if (int< id 0) #f (int< id (Vector length items))) #f)
                       (Vector ref id items) ())))
              (if (null? w) (Err raise (lit value) "BytePair: no item has this id" id) (%bp-bytes back w))))
          ids)))))

(doc (provide x/codec/byte-pair BytePair)
  (example "((BytePair make (Dict from-plist (list \"a\" 0 \"b\" 1 \"ab\" 2)) (list (list \"a\" \"b\"))) encode \"abb\")" "(2 1)")
  "BytePair: byte-pair encoding, text to the ids of a language model's vocabulary and back, from the vocabulary and merge list the model is published with.")
