; hosted.x -- a scoped fixture a plain include loads from an imported file.
(module scoped/hosted)
(def %hosted-secret 12)
(def hosted-twelve (fn (_) %hosted-secret))
(provide scoped/hosted hosted-twelve)
