; codec/entity.x -- HTML character references: &name; &#N; and &#xH;.
;
; (entity-at S I) reads the reference at I of S (& through ;) as (TEXT . END),
; or nil when there is none: the named ones are HTML 4's 252 and apos, and
; every numeric form, decimal to seven digits and hex to six.  A number that
; is 0, a surrogate or past U+10FFFF reads as U+FFFD, as browsers and
; CommonMark read it.  (entity-decode S) is S with every reference decoded;
; a & that starts none stays as it is.
;
; The Markdown and HTML codecs call these per byte, so they are module
; functions over primitives bound once, as the codecs themselves are.

(module x/codec/entity)
(import x/type/class)
(import x/codec/utf8 utf8-encode)

(import x/core/doors char->int int+ int< str-byte-len str-byte-ref str-byte-sub)

; The byte at I of S as an integer, -1 past either end.
(def %en-at
  (fn (_ s i)
    (match ((int< i 0) -1) ((int< i (str-byte-len s)) (char->int (str-byte-ref s i))) (#t -1))))
(def %en-sub (fn (_ s i j) (str-byte-sub s i (- j i))))
(def %en-digit? (fn (_ c) (match ((int< c #\0) #f) ((int< #\9 c) #f) (#t #t))))
(def %en-alnum?
  (fn (_ c)
    (match ((int< c #\0) #f) ((int< c #\:) #t) ((int< c #\A) #f) ((int< #\z c) #f)
           ((int< c #\[) #t) ((int< c #\a) #f) (#t #t))))
(def %en-assoc
  (fn (self k al) (match ((eq? al ()) ()) ((str=? k (first (first al))) (first al)) (#t (self k (rest al))))))

; HTML 4's named references, and apos: Latin-1, symbols and Greek, and the
; special characters.
(def %en-names
  (list (pair "amp" 38) (pair "lt" 60) (pair "gt" 62) (pair "quot" 34) (pair "apos" 39)
        (pair "nbsp" 160) (pair "iexcl" 161) (pair "cent" 162) (pair "pound" 163)
        (pair "curren" 164) (pair "yen" 165) (pair "brvbar" 166) (pair "sect" 167)
        (pair "uml" 168) (pair "copy" 169) (pair "ordf" 170) (pair "laquo" 171)
        (pair "not" 172) (pair "shy" 173) (pair "reg" 174) (pair "macr" 175)
        (pair "deg" 176) (pair "plusmn" 177) (pair "sup2" 178) (pair "sup3" 179)
        (pair "acute" 180) (pair "micro" 181) (pair "para" 182) (pair "middot" 183)
        (pair "cedil" 184) (pair "sup1" 185) (pair "ordm" 186) (pair "raquo" 187)
        (pair "frac14" 188) (pair "frac12" 189) (pair "frac34" 190) (pair "iquest" 191)
        (pair "Agrave" 192) (pair "Aacute" 193) (pair "Acirc" 194) (pair "Atilde" 195)
        (pair "Auml" 196) (pair "Aring" 197) (pair "AElig" 198) (pair "Ccedil" 199)
        (pair "Egrave" 200) (pair "Eacute" 201) (pair "Ecirc" 202) (pair "Euml" 203)
        (pair "Igrave" 204) (pair "Iacute" 205) (pair "Icirc" 206) (pair "Iuml" 207)
        (pair "ETH" 208) (pair "Ntilde" 209) (pair "Ograve" 210) (pair "Oacute" 211)
        (pair "Ocirc" 212) (pair "Otilde" 213) (pair "Ouml" 214) (pair "times" 215)
        (pair "Oslash" 216) (pair "Ugrave" 217) (pair "Uacute" 218) (pair "Ucirc" 219)
        (pair "Uuml" 220) (pair "Yacute" 221) (pair "THORN" 222) (pair "szlig" 223)
        (pair "agrave" 224) (pair "aacute" 225) (pair "acirc" 226) (pair "atilde" 227)
        (pair "auml" 228) (pair "aring" 229) (pair "aelig" 230) (pair "ccedil" 231)
        (pair "egrave" 232) (pair "eacute" 233) (pair "ecirc" 234) (pair "euml" 235)
        (pair "igrave" 236) (pair "iacute" 237) (pair "icirc" 238) (pair "iuml" 239)
        (pair "eth" 240) (pair "ntilde" 241) (pair "ograve" 242) (pair "oacute" 243)
        (pair "ocirc" 244) (pair "otilde" 245) (pair "ouml" 246) (pair "divide" 247)
        (pair "oslash" 248) (pair "ugrave" 249) (pair "uacute" 250) (pair "ucirc" 251)
        (pair "uuml" 252) (pair "yacute" 253) (pair "thorn" 254) (pair "yuml" 255)
        (pair "OElig" 338) (pair "oelig" 339) (pair "Scaron" 352) (pair "scaron" 353)
        (pair "Yuml" 376) (pair "fnof" 402) (pair "circ" 710) (pair "tilde" 732)
        (pair "Alpha" 913) (pair "Beta" 914) (pair "Gamma" 915) (pair "Delta" 916)
        (pair "Epsilon" 917) (pair "Zeta" 918) (pair "Eta" 919) (pair "Theta" 920)
        (pair "Iota" 921) (pair "Kappa" 922) (pair "Lambda" 923) (pair "Mu" 924)
        (pair "Nu" 925) (pair "Xi" 926) (pair "Omicron" 927) (pair "Pi" 928)
        (pair "Rho" 929) (pair "Sigma" 931) (pair "Tau" 932) (pair "Upsilon" 933)
        (pair "Phi" 934) (pair "Chi" 935) (pair "Psi" 936) (pair "Omega" 937)
        (pair "alpha" 945) (pair "beta" 946) (pair "gamma" 947) (pair "delta" 948)
        (pair "epsilon" 949) (pair "zeta" 950) (pair "eta" 951) (pair "theta" 952)
        (pair "iota" 953) (pair "kappa" 954) (pair "lambda" 955) (pair "mu" 956)
        (pair "nu" 957) (pair "xi" 958) (pair "omicron" 959) (pair "pi" 960)
        (pair "rho" 961) (pair "sigmaf" 962) (pair "sigma" 963) (pair "tau" 964)
        (pair "upsilon" 965) (pair "phi" 966) (pair "chi" 967) (pair "psi" 968)
        (pair "omega" 969) (pair "thetasym" 977) (pair "upsih" 978) (pair "piv" 982)
        (pair "ensp" 8194) (pair "emsp" 8195) (pair "thinsp" 8201) (pair "zwnj" 8204)
        (pair "zwj" 8205) (pair "lrm" 8206) (pair "rlm" 8207) (pair "ndash" 8211)
        (pair "mdash" 8212) (pair "lsquo" 8216) (pair "rsquo" 8217) (pair "sbquo" 8218)
        (pair "ldquo" 8220) (pair "rdquo" 8221) (pair "bdquo" 8222) (pair "dagger" 8224)
        (pair "Dagger" 8225) (pair "bull" 8226) (pair "hellip" 8230) (pair "permil" 8240)
        (pair "prime" 8242) (pair "Prime" 8243) (pair "lsaquo" 8249) (pair "rsaquo" 8250)
        (pair "oline" 8254) (pair "frasl" 8260) (pair "euro" 8364) (pair "image" 8465)
        (pair "weierp" 8472) (pair "real" 8476) (pair "trade" 8482) (pair "alefsym" 8501)
        (pair "larr" 8592) (pair "uarr" 8593) (pair "rarr" 8594) (pair "darr" 8595)
        (pair "harr" 8596) (pair "crarr" 8629) (pair "lArr" 8656) (pair "uArr" 8657)
        (pair "rArr" 8658) (pair "dArr" 8659) (pair "hArr" 8660) (pair "forall" 8704)
        (pair "part" 8706) (pair "exist" 8707) (pair "empty" 8709) (pair "nabla" 8711)
        (pair "isin" 8712) (pair "notin" 8713) (pair "ni" 8715) (pair "prod" 8719)
        (pair "sum" 8721) (pair "minus" 8722) (pair "lowast" 8727) (pair "radic" 8730)
        (pair "prop" 8733) (pair "infin" 8734) (pair "ang" 8736) (pair "and" 8743)
        (pair "or" 8744) (pair "cap" 8745) (pair "cup" 8746) (pair "int" 8747)
        (pair "there4" 8756) (pair "sim" 8764) (pair "cong" 8773) (pair "asymp" 8776)
        (pair "ne" 8800) (pair "equiv" 8801) (pair "le" 8804) (pair "ge" 8805)
        (pair "sub" 8834) (pair "sup" 8835) (pair "nsub" 8836) (pair "sube" 8838)
        (pair "supe" 8839) (pair "oplus" 8853) (pair "otimes" 8855) (pair "perp" 8869)
        (pair "sdot" 8901) (pair "lceil" 8968) (pair "rceil" 8969) (pair "lfloor" 8970)
        (pair "rfloor" 8971) (pair "lang" 10216) (pair "rang" 10217) (pair "loz" 9674)
        (pair "spades" 9824) (pair "clubs" 9827) (pair "hearts" 9829) (pair "diams" 9830)))

(def %en-char
  (fn (_ cp)
    (bytes->str (utf8-encode (if (if (= cp 0) #t (if (< 55295 cp) (< cp 57344) #f)) 65533 cp)))))
; The digits of a numeric reference from J of S, at most MORE in RADIX, then ;:
; (TEXT . END), or nil.
(def %en-numeric
  (fn (self s j k v radix more)
    (def c (%en-at s k))
    (def d (match ((%en-digit? c) (- c #\0))
                  ((= radix 10) -1)
                  ((if (int< c #\a) #f (int< c #\g)) (+ 10 (- c #\a)))
                  ((if (int< c #\A) #f (int< c #\G)) (+ 10 (- c #\A)))
                  (#t -1)))
    (match
      ((< -1 d) (if (< (- k j) more) (self s j (+ k 1) (+ (* v radix) d) radix more) ()))
      ((if (= c #\;) (< j k) #f) (pair (%en-char (if (< 1114111 v) 65533 v)) (+ k 1)))
      (#t ()))))
(def entity-at
  (fn (_ s i)
    (match
      ((not (= (%en-at s i) #\&)) ())
      ((= (%en-at s (+ i 1)) #\#)
        ((fn (_ c) (if (if (= c #\x) #t (= c #\X))
                     (%en-numeric s (+ i 3) (+ i 3) 0 16 6)
                     (%en-numeric s (+ i 2) (+ i 2) 0 10 7)))
         (%en-at s (+ i 2))))
      (#t
        ((fn (go j)
           (match
             ((%en-alnum? (%en-at s j)) (go (int+ j 1)))
             ((if (= (%en-at s j) #\;) (< (+ i 1) j) #f)
               ((fn (_ hit) (if (null? hit) () (pair (%en-char (rest hit)) (+ j 1))))
                (%en-assoc (%en-sub s (+ i 1) j) %en-names)))
             (#t ())))
         (+ i 1))))))
(def %en-decode-from
  (fn (self s i from out)
    (def c (%en-at s i))
    (match
      ((= c -1) (match ((= from 0) s) (#t (%str-concat (%reverse (pair (%en-sub s from i) out))))))
      ((= c #\&)
        ((fn (_ e)
           (match ((eq? e ()) (self s (int+ i 1) from out))
                  (#t (self s (rest e) (rest e) (pair (first e) (pair (%en-sub s from i) out))))))
         (entity-at s i)))
      (#t (self s (int+ i 1) from out)))))
(def entity-decode (fn (_ s) (%en-decode-from s 0 0 ())))

(def-class Entity ()
  (doc "HTML character references: (Entity at s i) reads the one at I of S as (TEXT . END), or nil; (Entity decode s) decodes every one in S."
    (example "(Entity decode \"a &amp; b &#x41; &copy; &nope;\")" "\"a & b A © &nope;\"")
    (see at) (see decode))
  (static
    (method at (self (param s STRING "Text") (param i INTEGER "Where a & is"))
      (doc "The character reference at I of S, & through ;, as (TEXT . END): HTML 4's named ones and apos, &#N; to seven digits, &#xH; to six.  Nil when there is none at I."
        (returns ANY "(TEXT . END), or nil")
        (example "(Entity at \"x&lt;y\" 1)" "(\"<\" . 5)")
        (example "(Entity at \"&#0; &#1114112; &amp\" 0)" "(\"�\" . 4)"))
      (entity-at s i))
    (method decode (self (param s STRING "Text with character references"))
      (doc "S with every character reference decoded; a & that starts none stays."
        (returns STRING "The decoded text")
        (example "(Entity decode \"&quot;&eacute;&quot; &#8212; a&b\")" "\"\\\"é\\\" — a&b\""))
      (entity-decode s))))

(provide x/codec/entity Entity entity-at entity-decode)
