; guard-include-fixture.x -- raises partway through loading, leaving
; trailing forms unread.  The #242 specs (core/include-paths.spec.md)
; assert that a guard catching the raise unwinds the include state:
; the fd closes and %guard-include-leaked below must NEVER be defined.
; Pre-#242 the un-popped filein head made top-level reads continue
; from THIS file after the catch, evaluating the trailing def.
(def %guard-include-marker 'loaded)
(error "guard-include-fixture: deliberate raise")
(def %guard-include-leaked 'leaked)
