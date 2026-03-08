;;;; diagnostic-events.lisp - Diagnostic event bus for cl-claw
;;;;
;;;; Provides a lightweight diagnostic event bus for collecting and
;;;; emitting structured diagnostic/observability events.

(defpackage :cl-claw.infra.diagnostic-events
  (:use :cl)
  (:export :make-event-bus
           :emit-event
           :subscribe
           :unsubscribe
           :get-events
           :clear-events
           :event-bus-event-count
           :make-diagnostic-event
           :diagnostic-event-type
           :diagnostic-event-data
           :diagnostic-event-timestamp))
(in-package :cl-claw.infra.diagnostic-events)

(defstruct diagnostic-event
  "A single diagnostic event."
  (type nil :type (or null string))
  (data nil)
  (timestamp (get-universal-time) :type integer))

(defstruct (event-bus-state (:constructor %make-event-bus-state))
  "Internal state for a diagnostic event bus."
  (events nil :type list)
  (subscribers nil :type list)   ; list of (type . handler-fn) pairs
  (max-events 1000 :type (integer 1)))

;; Public type alias
(deftype event-bus () 'event-bus-state)

(defun make-event-bus (&key (max-events 1000))
  "Create a new diagnostic event bus with MAX-EVENTS capacity."
  (%make-event-bus-state :max-events max-events))

(defun emit-event (bus event-type &optional data)
  "Emit a diagnostic event of EVENT-TYPE with optional DATA to BUS.
Notifies all subscribers registered for EVENT-TYPE or :all.
Keeps only the most recent MAX-EVENTS events."
  (declare (type event-bus-state bus)
           (type string event-type))
  (let ((event (make-diagnostic-event :type event-type
                                      :data data
                                      :timestamp (get-universal-time))))
    ;; Append to events, evict oldest if over capacity
    (setf (event-bus-state-events bus)
          (append (event-bus-state-events bus) (list event)))
    (when (> (length (event-bus-state-events bus)) (event-bus-state-max-events bus))
      (setf (event-bus-state-events bus) (rest (event-bus-state-events bus))))
    ;; Notify subscribers
    (dolist (sub (event-bus-state-subscribers bus))
      (let ((sub-type (car sub))
            (handler (cdr sub)))
        (when (or (eq sub-type :all)
                  (and (stringp sub-type) (string= sub-type event-type)))
          (funcall handler event))))
    event))

(defun subscribe (bus event-type handler)
  "Subscribe HANDLER to events of EVENT-TYPE on BUS.
EVENT-TYPE can be a string or :all for all events.
Returns a subscription token (used for unsubscribe)."
  (declare (type event-bus-state bus)
           (type function handler))
  (let ((entry (cons event-type handler)))
    (push entry (event-bus-state-subscribers bus))
    entry))

(defun unsubscribe (bus subscription-token)
  "Remove a subscription from BUS using the token returned by SUBSCRIBE."
  (declare (type event-bus-state bus))
  (setf (event-bus-state-subscribers bus)
        (remove subscription-token (event-bus-state-subscribers bus) :test #'eq)))

(defun get-events (bus &key event-type limit)
  "Return events from BUS, optionally filtered by EVENT-TYPE and limited to LIMIT count."
  (declare (type event-bus-state bus))
  (let* ((all (event-bus-state-events bus))
         (filtered (if event-type
                       (remove-if-not (lambda (e)
                                        (string= (diagnostic-event-type e) event-type))
                                      all)
                       all)))
    (if (and limit (> (length filtered) limit))
        (last filtered limit)
        filtered)))

(defun clear-events (bus)
  "Clear all stored events from BUS."
  (declare (type event-bus-state bus))
  (setf (event-bus-state-events bus) nil))

(defun event-bus-event-count (bus)
  "Return the number of events stored in BUS."
  (declare (type event-bus-state bus))
  (length (event-bus-state-events bus)))
