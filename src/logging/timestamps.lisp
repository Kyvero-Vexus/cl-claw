;;;; timestamps.lisp — ISO 8601 timestamp formatting with timezone offset
;;;;
;;;; Implements FORMAT-LOCAL-ISO-WITH-OFFSET and IS-VALID-TIME-ZONE.

(defpackage :cl-claw.logging.timestamps
  (:use :cl)
  (:export :format-local-iso-with-offset
           :is-valid-time-zone))

(in-package :cl-claw.logging.timestamps)

(declaim (optimize (safety 3) (debug 3)))

;;; ─── Timezone initialization ─────────────────────────────────────────────────

(defvar *tz-db-loaded* nil "Whether we've called reread-timezone-repository yet.")

(declaim (ftype (function () t) ensure-tz-db))
(defun ensure-tz-db ()
  "Ensure the timezone database is loaded."
  (unless *tz-db-loaded*
    (handler-case
        (progn
          (local-time:reread-timezone-repository)
          (setf *tz-db-loaded* t))
      (error () nil))))

;;; ─── Timezone validation ─────────────────────────────────────────────────────

(declaim (ftype (function (string) boolean) is-valid-time-zone))
(defun is-valid-time-zone (tz-name)
  "Return T if TZ-NAME is a valid IANA timezone string."
  (declare (type string tz-name))
  (when (string= tz-name "")
    (return-from is-valid-time-zone nil))
  (ensure-tz-db)
  (handler-case
      (let ((tz (local-time:find-timezone-by-location-name tz-name)))
        (declare (type t tz))
        (not (null tz)))
    (error () nil)))

;;; ─── ISO 8601 formatting ─────────────────────────────────────────────────────

(declaim (ftype (function (t string) string) format-local-iso-with-offset))
(defun format-local-iso-with-offset (universal-time tz-name)
  "Format UNIVERSAL-TIME as ISO 8601 with numeric offset for TZ-NAME.

Format: YYYY-MM-DDTHH:MM:SS.mmm+HH:MM (always numeric offset, never Z)"
  (declare (type t universal-time)
           (type string tz-name))
  (ensure-tz-db)
  (let* ((ts (typecase universal-time
               (local-time:timestamp universal-time)
               (integer (local-time:universal-to-timestamp universal-time))
               (t (local-time:now))))
         (tz (handler-case
                 (if (is-valid-time-zone tz-name)
                     (local-time:find-timezone-by-location-name tz-name)
                     local-time:+utc-zone+)
               (error () local-time:+utc-zone+))))
    (declare (type local-time:timestamp ts)
             (type t tz))
    ;; Use :gmt-offset (not :gmt-offset-or-z) so UTC shows +00:00 not Z
    (local-time:format-timestring
     nil ts
     :format '((:year 4) #\- (:month 2) #\- (:day 2)
               #\T (:hour 2) #\: (:min 2) #\: (:sec 2)
               #\. (:msec 3) :gmt-offset)
     :timezone tz)))
