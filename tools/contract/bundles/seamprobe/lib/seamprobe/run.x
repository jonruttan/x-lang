; run.x -- the fixture bundle's entry.  See bundle.xon.
;
; Does nothing on purpose.  Everything the gate reads is emitted by the wrapper
; before this module is imported (import-path! and %lang-lead, from
; bundle_form), so an entry whose main does nothing is the right amount: what
; is under test is the wrapper's arrangement, not anything a bundle could do
; to help it.  The probe -f file runs after main and does the looking.
(module seamprobe/run)
(def main (fn (_) ()))
(provide seamprobe/run main)
