;;;; channel-activity.lisp - Channel activity tracking for cl-claw
;;;;
;;;; Tracks the last activity timestamp per channel, used to determine
;;;; idle channels and manage heartbeat scheduling.

(defpackage :cl-claw.infra.channel-activity
  (:use :cl)
  (:export :make-channel-activity-tracker
           :record-activity
           :get-last-activity
           :get-idle-duration-ms
           :channel-active-p
           :clear-activity))
(in-package :cl-claw.infra.channel-activity)

(defstruct channel-activity-tracker
  "Tracks per-channel activity timestamps."
  (table (make-hash-table :test #'equal) :type hash-table))

(declaim (ftype (function () integer) current-time-ms))
(defun current-time-ms ()
  "Return current time in milliseconds since Unix epoch."
  ;; get-universal-time returns seconds since 1900-01-01
  ;; Unix epoch (1970-01-01) is 2208988800 seconds after 1900-01-01
  (let ((now (get-universal-time)))
    (* (- now 2208988800) 1000)))

(declaim (ftype (function (channel-activity-tracker string &optional (or null integer)) integer) record-activity))
(defun record-activity (tracker channel-id &optional (timestamp-ms nil))
  "Record activity for CHANNEL-ID at TIMESTAMP-MS (defaults to now).
Returns the recorded timestamp."
  (declare (type channel-activity-tracker tracker)
           (type string channel-id))
  (let ((ts (or timestamp-ms (current-time-ms))))
    (setf (gethash channel-id (channel-activity-tracker-table tracker)) ts)
    ts))

(declaim (ftype (function (channel-activity-tracker string) (or null integer)) get-last-activity))
(defun get-last-activity (tracker channel-id)
  "Return last activity timestamp in ms for CHANNEL-ID, or NIL if none."
  (declare (type channel-activity-tracker tracker)
           (type string channel-id))
  (gethash channel-id (channel-activity-tracker-table tracker)))

(declaim (ftype (function (channel-activity-tracker string &optional (or null integer)) (or null integer)) get-idle-duration-ms))
(defun get-idle-duration-ms (tracker channel-id &optional (now-ms nil))
  "Return number of ms since last activity for CHANNEL-ID, or NIL if no activity."
  (declare (type channel-activity-tracker tracker)
           (type string channel-id))
  (let ((last (get-last-activity tracker channel-id)))
    (when last
      (- (or now-ms (current-time-ms)) last))))

(declaim (ftype (function (channel-activity-tracker string (integer 0) &optional (or null integer)) boolean) channel-active-p))
(defun channel-active-p (tracker channel-id threshold-ms &optional (now-ms nil))
  "Return T if CHANNEL-ID has had activity within THRESHOLD-MS milliseconds."
  (declare (type channel-activity-tracker tracker)
           (type string channel-id)
           (type (integer 0) threshold-ms))
  (let ((idle (get-idle-duration-ms tracker channel-id now-ms)))
    (and idle (<= idle threshold-ms))))

(declaim (ftype (function (channel-activity-tracker string) t) clear-activity))
(defun clear-activity (tracker channel-id)
  "Remove activity record for CHANNEL-ID."
  (declare (type channel-activity-tracker tracker)
           (type string channel-id))
  (remhash channel-id (channel-activity-tracker-table tracker)))
