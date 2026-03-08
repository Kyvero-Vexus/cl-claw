;;;; fiveam-voicewake.test.lisp - FiveAM tests for voicewake module

(defpackage :cl-claw.infra.voicewake.test
  (:use :cl :fiveam))
(in-package :cl-claw.infra.voicewake.test)

(def-suite voicewake-suite
  :description "Tests for the voicewake module")
(in-suite voicewake-suite)

(test creates-detector
  "Creates a voicewake detector"
  (let ((detector (cl-claw.infra.voicewake:make-voicewake-detector)))
    (is (not (null detector)))))

(test detects-default-wake-word
  "Detects a default wake word"
  (let* ((detector (cl-claw.infra.voicewake:make-voicewake-detector))
         (event (cl-claw.infra.voicewake:detect-wake-word detector "hey openclaw")))
    (is (not (null event)))
    (is (not (null (cl-claw.infra.voicewake:voicewake-event-word event))))))

(test detects-wake-word-case-insensitive
  "Wake word detection is case-insensitive"
  (let* ((detector (cl-claw.infra.voicewake:make-voicewake-detector))
         (event (cl-claw.infra.voicewake:detect-wake-word detector "HEY OPENCLAW")))
    (is (not (null event)))))

(test detects-wake-word-in-text
  "Detects wake word embedded in larger text"
  (let* ((detector (cl-claw.infra.voicewake:make-voicewake-detector))
         (event (cl-claw.infra.voicewake:detect-wake-word
                 detector "hello there hey openclaw how are you?")))
    (is (not (null event)))))

(test returns-nil-for-non-wake-text
  "Returns NIL when no wake word is present"
  (let* ((detector (cl-claw.infra.voicewake:make-voicewake-detector))
         (event (cl-claw.infra.voicewake:detect-wake-word detector "just a regular phrase")))
    (is (null event))))

(test detector-in-cooldown-after-wake
  "Detector ignores wake words during cooldown period"
  (let* ((detector (cl-claw.infra.voicewake:make-voicewake-detector
                    :cooldown-ms 5000))
         ;; First detection
         (first-event (cl-claw.infra.voicewake:detect-wake-word detector "hey openclaw")))
    (is (not (null first-event)))
    ;; Immediately after, should be in cooldown
    (is (cl-claw.infra.voicewake:voicewake-active-p detector))
    ;; Should not detect again
    (let ((second-event (cl-claw.infra.voicewake:detect-wake-word detector "hey openclaw")))
      (is (null second-event)))))

(test reset-exits-cooldown
  "reset-voicewake clears the cooldown state"
  (let* ((detector (cl-claw.infra.voicewake:make-voicewake-detector
                    :cooldown-ms 5000))
         (_first (cl-claw.infra.voicewake:detect-wake-word detector "hey openclaw")))
    (declare (ignore _first))
    (is-true (cl-claw.infra.voicewake:voicewake-active-p detector))
    ;; Reset
    (cl-claw.infra.voicewake:reset-voicewake detector)
    (is-false (cl-claw.infra.voicewake:voicewake-active-p detector))
    ;; Should detect again after reset
    (let ((event (cl-claw.infra.voicewake:detect-wake-word detector "hey openclaw")))
      (is (not (null event))))))

(test disabled-detector-ignores-wake-words
  "Disabled detector never returns events"
  (let* ((detector (cl-claw.infra.voicewake:make-voicewake-detector
                    :enabled nil))
         (event (cl-claw.infra.voicewake:detect-wake-word detector "hey openclaw")))
    (is (null event))))

(test custom-wake-words
  "Detector uses custom wake words when configured"
  (let* ((detector (cl-claw.infra.voicewake:make-voicewake-detector
                    :wake-words '("activate system" "wake up")))
         (event1 (cl-claw.infra.voicewake:detect-wake-word detector "activate system"))
         ;; Default wake words should not match
         (_first (progn
                   (cl-claw.infra.voicewake:reset-voicewake detector)
                   nil))
         (event2 (cl-claw.infra.voicewake:detect-wake-word detector "hey openclaw")))
    (declare (ignore _first))
    (is (not (null event1)))
    (is (null event2))))

(test voicewake-event-has-expected-fields
  "Wake event includes word, confidence, and timestamp"
  (let* ((detector (cl-claw.infra.voicewake:make-voicewake-detector))
         (event (cl-claw.infra.voicewake:detect-wake-word
                 detector "hey openclaw" :confidence 0.9)))
    (is (not (null event)))
    (is (stringp (cl-claw.infra.voicewake:voicewake-event-word event)))
    (is (realp (cl-claw.infra.voicewake:voicewake-event-confidence event)))
    (is (integerp (cl-claw.infra.voicewake:voicewake-event-timestamp event)))))
