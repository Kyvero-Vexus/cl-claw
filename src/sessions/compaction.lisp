;;;; compaction.lisp — Transcript compaction utilities

(defpackage :cl-claw.sessions.compaction
  (:use :cl)
  (:import-from :cl-claw.sessions.store
                :session-store
                :now-ms)
  (:import-from :cl-claw.sessions.transcript
                :make-transcript-message
                :read-session-transcript
                :rewrite-session-transcript)
  (:export
   :compaction-result
   :compaction-result-changed-p
   :compaction-result-before-count
   :compaction-result-after-count
   :compaction-result-dropped-count
   :compact-session-transcript
   :build-compaction-marker))

(in-package :cl-claw.sessions.compaction)

(declaim (optimize (safety 3) (debug 3)))

(defstruct compaction-result
  (changed-p nil :type boolean)
  (before-count 0 :type fixnum)
  (after-count 0 :type fixnum)
  (dropped-count 0 :type fixnum))

(declaim (ftype (function (fixnum) hash-table) build-compaction-marker))
(defun build-compaction-marker (dropped-count)
  (declare (type fixnum dropped-count))
  (make-transcript-message
   "system"
   (format nil "[compaction] ~d older message~:p omitted" dropped-count)
   :timestamp-ms (now-ms)
   :metadata (let ((m (make-hash-table :test 'equal)))
               (declare (type hash-table m))
               (setf (gethash "kind" m) "compaction"
                     (gethash "droppedCount" m) dropped-count)
               m)))

(declaim (ftype (function (session-store string &key (:max-messages fixnum)) compaction-result)
                compact-session-transcript))
(defun compact-session-transcript (store session-key &key (max-messages 200))
  "Keep only the most recent MAX-MESSAGES transcript entries, inserting a compaction marker.
No-op when under threshold."
  (declare (type session-store store)
           (type string session-key)
           (type fixnum max-messages))
  (let* ((messages (read-session-transcript store session-key))
         (before (length messages)))
    (declare (type list messages)
             (type fixnum before))
    (if (or (<= max-messages 0)
            (<= before max-messages))
        (make-compaction-result :changed-p nil
                                :before-count before
                                :after-count before
                                :dropped-count 0)
        (let* ((kept (subseq messages (- before max-messages)))
               (dropped (- before max-messages))
               (marker (build-compaction-marker dropped))
               (rewritten (cons marker kept)))
          (declare (type list kept rewritten)
                   (type fixnum dropped)
                   (type hash-table marker))
          (rewrite-session-transcript store session-key rewritten
                                      :last-compaction-at-ms (now-ms))
          (make-compaction-result :changed-p t
                                  :before-count before
                                  :after-count (length rewritten)
                                  :dropped-count dropped)))))