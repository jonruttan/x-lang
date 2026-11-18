; pdf-glyphs.x -- the characters of a PDF font's glyph names and encodings.
;
; A simple font shows a byte as the glyph its encoding names: one of the
; three named encodings, changed code by code through /Differences, each
; change a glyph name.  (pdf-glyph NAME) answers the Unicode code point of
; a glyph name, and (pdf-encoding NAME CODE) that of a code in a named
; encoding; both nil where there is none.
;
; The names are the Adobe Glyph List's for Latin text -- ASCII, Latin-1, the
; typographic quotes, dashes and ligatures, and the letters the named
; encodings add -- and its two spelled forms, uniXXXX and uXXXX to uXXXXXX.
; A single letter names itself.
(module x/codec/pdf-glyphs)

(import x/core/doors char->int int* int+ int- int< int= str-byte-len str-byte-ref str-byte-sub)

; The glyphs at 160 to 255, in order: Latin-1's.
(def %pg-latin
  (list "nbspace" "exclamdown" "cent" "sterling" "currency" "yen" "brokenbar" "section" "dieresis" "copyright"
        "ordfeminine" "guillemotleft" "logicalnot" "sfthyphen" "registered" "macron" "degree" "plusminus"
        "twosuperior" "threesuperior" "acute" "mu" "paragraph" "periodcentered" "cedilla" "onesuperior"
        "ordmasculine" "guillemotright" "onequarter" "onehalf" "threequarters" "questiondown"
        "Agrave" "Aacute" "Acircumflex" "Atilde" "Adieresis" "Aring" "AE" "Ccedilla" "Egrave" "Eacute"
        "Ecircumflex" "Edieresis" "Igrave" "Iacute" "Icircumflex" "Idieresis" "Eth" "Ntilde" "Ograve" "Oacute"
        "Ocircumflex" "Otilde" "Odieresis" "multiply" "Oslash" "Ugrave" "Uacute" "Ucircumflex" "Udieresis"
        "Yacute" "Thorn" "germandbls"
        "agrave" "aacute" "acircumflex" "atilde" "adieresis" "aring" "ae" "ccedilla" "egrave" "eacute"
        "ecircumflex" "edieresis" "igrave" "iacute" "icircumflex" "idieresis" "eth" "ntilde" "ograve" "oacute"
        "ocircumflex" "otilde" "odieresis" "divide" "oslash" "ugrave" "uacute" "ucircumflex" "udieresis"
        "yacute" "thorn" "ydieresis"))
; Every other name, each before its code point.
(def %pg-names
  (list "space" 32 "exclam" 33 "quotedbl" 34 "numbersign" 35 "dollar" 36 "percent" 37 "ampersand" 38
        "quotesingle" 39 "parenleft" 40 "parenright" 41 "asterisk" 42 "plus" 43 "comma" 44 "hyphen" 45
        "period" 46 "slash" 47 "zero" 48 "one" 49 "two" 50 "three" 51 "four" 52 "five" 53 "six" 54 "seven" 55
        "eight" 56 "nine" 57 "colon" 58 "semicolon" 59 "less" 60 "equal" 61 "greater" 62 "question" 63 "at" 64
        "bracketleft" 91 "backslash" 92 "bracketright" 93 "asciicircum" 94 "underscore" 95 "grave" 96
        "braceleft" 123 "bar" 124 "braceright" 125 "asciitilde" 126
        "quoteleft" 8216 "quoteright" 8217 "quotesinglbase" 8218 "quotedblleft" 8220 "quotedblright" 8221
        "quotedblbase" 8222 "dagger" 8224 "daggerdbl" 8225 "bullet" 8226 "ellipsis" 8230 "perthousand" 8240
        "guilsinglleft" 8249 "guilsinglright" 8250 "fraction" 8260 "endash" 8211 "emdash" 8212 "minus" 8722
        "Euro" 8364 "trademark" 8482 "florin" 402 "ff" 64256 "fi" 64257 "fl" 64258 "ffi" 64259 "ffl" 64260
        "OE" 338 "oe" 339 "Scaron" 352 "scaron" 353 "Ydieresis" 376 "Zcaron" 381 "zcaron" 382 "Lslash" 321
        "lslash" 322 "dotlessi" 305 "circumflex" 710 "caron" 711 "breve" 728 "dotaccent" 729 "ring" 730
        "ogonek" 731 "tilde" 732 "hungarumlaut" 733 "Delta" 8710 "Omega" 8486 "pi" 960 "partialdiff" 8706
        "summation" 8721 "product" 8719 "radical" 8730 "infinity" 8734 "integral" 8747 "approxequal" 8776
        "notequal" 8800 "lessequal" 8804 "greaterequal" 8805 "lozenge" 9674 "apple" 63743
        "softhyphen" 173 "middot" 183 "nonbreakingspace" 160))

; The code points of WinAnsiEncoding at 128 to 159, nil where it has none.
(def %pg-win
  (list 8364 () 8218 402 8222 8230 8224 8225 710 8240 352 8249 338 () 381 ()
        () 8216 8217 8220 8221 8226 8211 8212 732 8482 353 8250 339 () 382 376))
; The code points of MacRomanEncoding at 128 to 255.
(def %pg-mac
  (list 196 197 199 201 209 214 220 225 224 226 228 227 229 231 233 232
        234 235 237 236 238 239 241 243 242 244 246 245 250 249 251 252
        8224 176 162 163 167 8226 182 223 174 169 8482 180 168 8800 198 216
        8734 177 8804 8805 165 181 8706 8721 8719 960 8747 170 186 8486 230 248
        191 161 172 8730 402 8776 8710 171 187 8230 160 192 195 213 338 339
        8211 8212 8220 8221 8216 8217 247 9674 255 376 8260 8364 8249 8250 64257 64258
        8225 183 8218 8222 8240 194 202 193 203 200 205 206 207 204 211 212
        63743 210 218 219 217 305 710 732 175 728 729 730 184 733 731 711))
; StandardEncoding's codes past ASCII, each before its code point.
(def %pg-standard
  (list 161 161 162 162 163 163 164 8260 165 165 166 402 167 167 168 164 169 39 170 8220 171 171 172 8249
        173 8250 174 64257 175 64258 177 8211 178 8224 179 8225 180 183 182 182 183 8226 184 8218 185 8222
        186 8221 187 187 188 8230 189 8240 191 191 193 96 194 180 195 710 196 732 197 175 198 728 199 729
        200 168 202 730 203 184 205 733 206 731 207 711 208 8212 225 198 227 170 232 321 233 216 234 338
        235 186 241 230 245 305 248 322 249 248 250 339 251 223))

; The item K of the list L, or nil past its end.
(def %pg-nth (fn (self l k) (match ((null? l) ()) ((int= k 0) (first l)) (#t (self (rest l) (int- k 1))))))
; The value after KEY in the flat list L of keys and values, or nil; SAME?
; compares keys.
(def %pg-after
  (fn (self same? l key)
    (match ((null? l) ()) ((same? (first l) key) (first (rest l))) (#t (self same? (rest (rest l)) key)))))
; Where NAME is in the list L from index K, or nil.
(def %pg-index
  (fn (self l name k)
    (match ((null? l) ()) ((str=? (first l) name) k) (#t (self (rest l) name (int+ k 1))))))
; The hexadecimal number NAME spells from byte I to its end, of FEWEST to
; MOST digits, or nil.
(def %pg-hex
  (fn (_ name i fewest most)
    (def n (str-byte-len name))
    ((fn (self k v)
       (match ((int= k n)
                (match ((int< (int- n i) fewest) ()) ((int< most (int- n i)) ()) (#t v)))
              (#t ((fn (_ c)
                     ((fn (_ d) (match ((int< d 0) ()) (#t (self (int+ k 1) (int+ (int* v 16) d)))))
                      (match ((int< c 48) -1) ((int< c 58) (int- c 48)) ((int< c 65) -1) ((int< c 71) (int- c 55))
                             ((int< c 97) -1) ((int< c 103) (int- c 87)) (#t -1))))
                   (char->int (str-byte-ref name k))))))
     i 0)))

(def pdf-glyph
  (fn (_ name)
    (def n (str-byte-len name))
    (def c (match ((int= n 0) 0) (#t (char->int (str-byte-ref name 0)))))
    (match
      ((int= n 0) ())
      ((int= n 1) c)
      (#t ((fn (_ at)
             (match ((null? at)
                      ((fn (_ code)
                         (match ((null? code)
                                  (match ((match ((int< 6 n) (str=? (str-byte-sub name 0 3) "uni")) (#t #f)) (%pg-hex name 3 4 4))
                                         ((int= c 117) (%pg-hex name 1 4 6))
                                         (#t ())))
                                (#t code)))
                       (%pg-after str=? %pg-names name)))
                    (#t (int+ 160 at))))
           (%pg-index %pg-latin name 0))))))

(def pdf-encoding
  (fn (_ name code)
    (def ascii? (match ((int< code 32) #f) ((int< code 127) #t) (#t #f)))
    (match
      ((str=? name "WinAnsiEncoding")
        (match (ascii? code) ((int< code 128) ()) ((int< code 160) (%pg-nth %pg-win (int- code 128))) ((int< code 256) code) (#t ())))
      ((str=? name "MacRomanEncoding")
        (match (ascii? code) ((int< code 128) ()) (#t (%pg-nth %pg-mac (int- code 128)))))
      ((str=? name "StandardEncoding")
        (match ((int= code 39) 8217) ((int= code 96) 8216) (ascii? code) (#t (%pg-after int= %pg-standard code))))
      (#t ()))))

(doc (provide x/codec/pdf-glyphs pdf-glyph pdf-encoding)
  (example "(do (import x/codec/pdf-glyphs pdf-glyph pdf-encoding) (list (pdf-glyph \"A\") (pdf-glyph \"eacute\") (pdf-glyph \"fi\") (pdf-glyph \"uni20AC\") (pdf-glyph \"nosuch\") (pdf-encoding \"WinAnsiEncoding\" 150) (pdf-encoding \"MacRomanEncoding\" 128) (pdf-encoding \"StandardEncoding\" 174)))" "(65 233 64257 8364 () 8211 196 64257)")
  (note "A name with a suffix, as a.sc or f_i, is not read; nor are the Symbol and ZapfDingbats fonts' own encodings.")
  (see Pdf)
  "The Unicode code points of a PDF simple font's glyph names and of the codes of WinAnsiEncoding, MacRomanEncoding and StandardEncoding.")
