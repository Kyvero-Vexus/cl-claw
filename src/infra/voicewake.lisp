;;;; voicewake.lisp - Voice wake detection utilities for cl-claw
;;;;
;;;; Provides utilities for detecting and handling voice wake word events,
;;;; including wake word classification and cooldown management.

(defpackage :cl-claw.infra.voicewake
  (:use :cl)
  (:export :make-voicewake-detector
           :detect-wake-word
           :voicewake-active-p
           :reset-voicewake
           :voicewake-event
           :make-voicewake-event
           :voicewake-event-word
           :voicewake-event-confidence
           :voicewake-event-timestamp
           :*default-wake-words*
           :*default-cooldown-ms*))
(in-package :cl-claw.infra.voicewake)

(declaim (optimize (safety 3) (debug 3)))

(defparameter *default-wake-words*
  '("hey openclaw" "ok openclaw" "openclaw" "hey claude" "ok claude")
  "Default wake word phrases to detect.")

(defparameter *default-cooldown-ms* 3000
  "Default cooldown period in ms after a wake event before re-detecting.")

(defstruct voicewake-event
  "A detected voice wake event."
  (word nil :type (or null string))
  (confidence 1.0 :type real)
  (timestamp (get-universal-time) :type integer))

(defstruct voicewake-detector
  "State for voice wake word detection."
  (wake-words *default-wake-words* :type list)
  (cooldown-ms *default-cooldown-ms* :type (integer 0))
  (last-event nil :type (or null voicewake-event))
  (enabled t :type boolean))

(declaim (ftype (function () integer) current-time-ms))
(defun current-time-ms ()
  "Return current time in milliseconds."
  (let ((now (get-universal-time)))
    (* (- now 2208988800) 1000)))

(declaim (ftype (function (voicewake-detector) boolean) voicewake-active-p))
(defun voicewake-active-p (detector)
  "Return T if the detector is within the cooldown period after a wake event."
  (declare (type voicewake-detector detector))
  (let ((last (voicewake-detector-last-event detector)))
    (when last
      (let ((elapsed-ms (* (- (get-universal-time)
                               (voicewake-event-timestamp last))
                            1000)))
        (< elapsed-ms (voicewake-detector-cooldown-ms detector))))))

(declaim (ftype (function (string) string) normalize-text))
(defun normalize-text (text)
  "Normalize TEXT for wake word matching: lowercase and trim."
  (string-downcase (string-trim '(#\Space #\Tab #\Newline) text)))

(declaim (ftype (function (voicewake-detector string &key (:confidence real)) (or null voicewake-event)) detect-wake-word))
(defun detect-wake-word (detector text &key (confidence 1.0))
  "Check if TEXT contains a wake word. Returns a VOICEWAKE-EVENT or NIL.

Returns NIL if:
- Detector is disabled
- Detector is in cooldown
- TEXT doesn't contain a recognized wake word."
  (declare (type voicewake-detector detector)
           (type string text)
           (type real confidence))
  (unless (voicewake-detector-enabled detector)
    (return-from detect-wake-word nil))
  (when (voicewake-active-p detector)
    (return-from detect-wake-word nil))
  (let ((normalized (normalize-text text)))
    (dolist (wake-word (voicewake-detector-wake-words detector))
      (let ((normalized-word (normalize-text wake-word)))
        (when (or (string= normalized normalized-word)
                  (search normalized-word normalized))
          (let ((event (make-voicewake-event
                        :word wake-word
                        :confidence confidence
                        :timestamp (get-universal-time))))
            (setf (voicewake-detector-last-event detector) event)
            (return-from detect-wake-word event)))))
    nil))

(declaim (ftype (function (voicewake-detector) t) reset-voicewake))
(defun reset-voicewake (detector)
  "Reset the detector's wake state (clear last event, exit cooldown)."
  (declare (type voicewake-detector detector))
  (setf (voicewake-detector-last-event detector) nil))
