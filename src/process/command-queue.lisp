;;;; command-queue.lisp — Sequential command execution with named lanes
;;;;
;;;; Provides a simple serialized task queue (one active task per lane at a time).
;;;; Supports per-lane concurrency configuration, gateway draining, and lane clearing.

(defpackage :cl-claw.process.command-queue
  (:use :cl)
  (:export
   ;; Lane management
   :reset-all-lanes
   :set-command-lane-concurrency
   :clear-command-lane
   :mark-gateway-draining

   ;; Enqueueing
   :enqueue-command
   :enqueue-command-in-lane

   ;; Status
   :get-active-task-count
   :get-queue-size
   :wait-for-active-tasks

   ;; Error conditions
   :command-lane-cleared-error
   :gateway-draining-error))

(in-package :cl-claw.process.command-queue)

(declaim (optimize (safety 3) (debug 3)))

;;; ─── Conditions ──────────────────────────────────────────────────────────────

(define-condition command-lane-cleared-error (error)
  ()
  (:report (lambda (c s)
             (declare (ignore c))
             (format s "Command lane was cleared while task was queued"))))

(define-condition gateway-draining-error (error)
  ()
  (:report (lambda (c s)
             (declare (ignore c))
             (format s "Gateway is draining; no new commands accepted"))))

;;; ─── Lane data structure ─────────────────────────────────────────────────────

(defstruct (lane (:constructor make-lane ()))
  "A named execution lane that serializes task execution."
  (lock    (bt:make-lock "lane-lock") :type t)
  (cvar    (bt:make-condition-variable) :type t)
  ;; Queue of (thunk . mailbox) pairs
  (queue   '() :type list)
  ;; Number of currently active tasks
  (active  0   :type fixnum)
  ;; Configured max concurrency (default 1)
  (concurrency 1 :type fixnum)
  ;; Generation counter — bumped on reset/clear
  (generation 0 :type fixnum))

;;; ─── Global state ────────────────────────────────────────────────────────────

(defvar *lanes-lock* (bt:make-lock "lanes-lock")
  "Protects the *lanes* hash table.")

(defvar *lanes* (make-hash-table :test 'equal)
  "Maps lane-name (string) → lane struct.")

(defvar *gateway-draining* nil
  "When T, no new commands are accepted.")

(defvar *default-lane-name* "default"
  "The default lane name used by ENQUEUE-COMMAND.")

;;; ─── Helpers ─────────────────────────────────────────────────────────────────

(declaim (ftype (function (string) lane) get-or-create-lane))
(defun get-or-create-lane (name)
  "Return the lane for NAME, creating it if necessary."
  (declare (type string name))
  (bt:with-lock-held (*lanes-lock*)
    (or (gethash name *lanes*)
        (setf (gethash name *lanes*) (make-lane)))))

(declaim (ftype (function () fixnum) get-active-task-count))
(defun get-active-task-count ()
  "Return total number of actively executing tasks across all lanes."
  (let ((total 0))
    (declare (type fixnum total))
    (bt:with-lock-held (*lanes-lock*)
      (maphash (lambda (name lane)
                 (declare (ignore name))
                 (bt:with-lock-held ((lane-lock lane))
                   (incf total (lane-active lane))))
               *lanes*))
    total))

(declaim (ftype (function (&optional (or string null)) fixnum) get-queue-size))
(defun get-queue-size (&optional lane-name)
  "Return number of queued (not active) tasks for LANE-NAME (default lane if nil)."
  (declare (type (or string null) lane-name))
  (let* ((name (or lane-name *default-lane-name*))
         (lane (bt:with-lock-held (*lanes-lock*)
                 (gethash name *lanes*))))
    (if lane
        (bt:with-lock-held ((lane-lock lane))
          ;; Queue includes both active and waiting entries; subtract active
          (max 0 (- (length (lane-queue lane)) (lane-active lane))))
        0)))

;;; ─── Lane worker thread ──────────────────────────────────────────────────────

(defun run-lane-worker (lane generation)
  "Run tasks from LANE until queue is empty (for generation GENERATION)."
  (declare (type lane lane)
           (type fixnum generation))
  (loop
    (let ((entry nil))
      (bt:with-lock-held ((lane-lock lane))
        ;; Check for generation mismatch (lane was reset/cleared)
        (when (/= (lane-generation lane) generation)
          (return))
        ;; Check concurrency limit
        (when (>= (lane-active lane) (lane-concurrency lane))
          (return))
        ;; Pop next task from queue
        (when (lane-queue lane)
          (setf entry (pop (lane-queue lane)))
          (incf (lane-active lane))))
      (unless entry (return))
      ;; entry is (thunk . mailbox)
      (let ((thunk (car entry))
            (mailbox (cdr entry)))
        (declare (type function thunk)
                 (type t mailbox))
        (handler-case
            (let ((result (funcall thunk)))
              (setf (car mailbox) :ok)
              (setf (cdr mailbox) result))
          (error (c)
            (setf (car mailbox) :error)
            (setf (cdr mailbox) c)))
        ;; Signal completion
        (bt:with-lock-held ((lane-lock lane))
          (decf (lane-active lane))
          (bt:condition-notify (lane-cvar lane)))))))

(defun enqueue-to-lane (lane thunk)
  "Add THUNK to LANE's queue. Returns a mailbox (cons status value) for the result.
Signals GATEWAY-DRAINING-ERROR if draining. Signals COMMAND-LANE-CLEARED-ERROR if lane
was cleared while waiting."
  (declare (type lane lane)
           (type function thunk))
  (when *gateway-draining*
    (error 'gateway-draining-error))
  (let ((mailbox (cons :pending nil))
        (generation nil))
    (bt:with-lock-held ((lane-lock lane))
      (setf generation (lane-generation lane))
      (setf (lane-queue lane) (append (lane-queue lane) (list (cons thunk mailbox)))))
    ;; Spawn a worker thread to drain the lane
    (bt:make-thread
     (lambda ()
       (run-lane-worker lane generation))
     :name "cl-claw-lane-worker")
    mailbox))

(defun wait-for-mailbox (mailbox)
  "Block until MAILBOX has a result, then return it or signal the stored error."
  (declare (type cons mailbox))
  (loop
    (case (car mailbox)
      (:ok    (return (cdr mailbox)))
      (:error (error (cdr mailbox)))
      (t      (sleep 0.005)))))

;;; ─── Public API ──────────────────────────────────────────────────────────────

(declaim (ftype (function () t) reset-all-lanes))
(defun reset-all-lanes ()
  "Reset all lanes: bump their generation (invalidating in-flight workers),
clear queued tasks, reject them with COMMAND-LANE-CLEARED-ERROR, and
re-allow enqueuing. Also clears the gateway-draining flag."
  (setf *gateway-draining* nil)
  (bt:with-lock-held (*lanes-lock*)
    (maphash
     (lambda (name lane)
       (declare (ignore name))
       (let ((cleared '()))
         (bt:with-lock-held ((lane-lock lane))
           (incf (lane-generation lane))
           ;; Drain queue, collect mailboxes
           (setf cleared (lane-queue lane))
           (setf (lane-queue lane) '()))
         ;; Reject cleared entries
         (dolist (entry cleared)
           (let ((mailbox (cdr entry)))
             (setf (car mailbox) :error)
             (setf (cdr mailbox) (make-condition 'command-lane-cleared-error))))))
     *lanes*)))

(declaim (ftype (function (string fixnum) t) set-command-lane-concurrency))
(defun set-command-lane-concurrency (lane-name concurrency)
  "Set the maximum concurrency for LANE-NAME to CONCURRENCY."
  (declare (type string lane-name)
           (type fixnum concurrency))
  (let ((lane (get-or-create-lane lane-name)))
    (bt:with-lock-held ((lane-lock lane))
      (setf (lane-concurrency lane) concurrency))))

(declaim (ftype (function (&optional (or string null)) fixnum) clear-command-lane))
(defun clear-command-lane (&optional lane-name)
  "Clear all queued (not active) tasks from LANE-NAME. Returns the count removed."
  (declare (type (or string null) lane-name))
  (let* ((name (or lane-name *default-lane-name*))
         (lane (bt:with-lock-held (*lanes-lock*)
                 (gethash name *lanes*))))
    (if lane
        (let ((removed 0)
              (cleared '()))
          (declare (type fixnum removed))
          (bt:with-lock-held ((lane-lock lane))
            ;; Only remove queued (not active) entries
            (let ((active-count (lane-active lane))
                  (all-queue (lane-queue lane)))
              (declare (type fixnum active-count))
              ;; Keep only the first active-count entries (active tasks)
              (let ((active-entries (subseq all-queue 0 (min active-count (length all-queue))))
                    (queued-entries (if (> (length all-queue) active-count)
                                        (subseq all-queue active-count)
                                        '())))
                (setf (lane-queue lane) active-entries)
                (setf removed (length queued-entries))
                (setf cleared queued-entries))))
          ;; Reject removed entries
          (dolist (entry cleared)
            (let ((mailbox (cdr entry)))
              (setf (car mailbox) :error)
              (setf (cdr mailbox) (make-condition 'command-lane-cleared-error))))
          removed)
        0)))

(declaim (ftype (function () t) mark-gateway-draining))
(defun mark-gateway-draining ()
  "Mark the gateway as draining. No new commands will be accepted."
  (setf *gateway-draining* t))

(declaim (ftype (function (function &key (:lane (or string null))
                                         (:warn-after-ms (or fixnum null))
                                         (:on-wait (or function null)))
                          t)
                enqueue-command))
(defun enqueue-command (thunk &key lane warn-after-ms on-wait)
  "Enqueue THUNK on the default lane (or LANE if specified).
Returns the result of THUNK when it completes.
WARN-AFTER-MS: if non-nil, call ON-WAIT after this many ms if still waiting.
ON-WAIT: (lambda (ms-waited queued-ahead) ...)"
  (declare (type function thunk)
           (type (or string null) lane)
           (type (or fixnum null) warn-after-ms)
           (type (or function null) on-wait))
  (let* ((name (or lane *default-lane-name*))
         (l (get-or-create-lane name))
         (start-time (when warn-after-ms (get-internal-real-time)))
         (mailbox (enqueue-to-lane l thunk)))
    (declare (ignore start-time))
    ;; TODO: implement warn-after-ms callback properly with a background thread
    (when (and warn-after-ms on-wait)
      (let ((start (get-internal-real-time)))
        (declare (type fixnum start))
        (bt:make-thread
         (lambda ()
           (sleep (/ warn-after-ms 1000.0))
           ;; Check if still pending
           (when (eq (car mailbox) :pending)
             (let* ((elapsed (round (* 1000 (/ (- (get-internal-real-time) start)
                                               internal-time-units-per-second))))
                    (ahead (max 0 (1- (get-queue-size name)))))
               (declare (type fixnum elapsed ahead))
               (ignore-errors (funcall on-wait elapsed ahead)))))
         :name "cl-claw-wait-watcher")))
    (wait-for-mailbox mailbox)))

(declaim (ftype (function (string function &key (:warn-after-ms (or fixnum null))
                                              (:on-wait (or function null)))
                          t)
                enqueue-command-in-lane))
(defun enqueue-command-in-lane (lane-name thunk &key warn-after-ms on-wait)
  "Enqueue THUNK on the named lane LANE-NAME."
  (declare (type string lane-name)
           (type function thunk)
           (type (or fixnum null) warn-after-ms)
           (type (or function null) on-wait))
  (enqueue-command thunk :lane lane-name :warn-after-ms warn-after-ms :on-wait on-wait))

(declaim (ftype (function (fixnum) (values boolean &optional)) wait-for-active-tasks))
(defun wait-for-active-tasks (timeout-ms)
  "Wait up to TIMEOUT-MS milliseconds for all currently active tasks to finish.
Returns (values drained) where DRAINED is T if all tasks completed in time."
  (declare (type fixnum timeout-ms))
  (let ((active (get-active-task-count)))
    (declare (type fixnum active))
    (when (= active 0)
      (return-from wait-for-active-tasks (values t)))
    (when (= timeout-ms 0)
      (return-from wait-for-active-tasks (values nil)))
    (let ((deadline (+ (get-internal-real-time)
                       (round (* timeout-ms (/ internal-time-units-per-second 1000))))))
      (declare (type fixnum deadline))
      (loop
        (let ((remaining (- deadline (get-internal-real-time))))
          (declare (type fixnum remaining))
          (when (<= remaining 0)
            (return (values nil)))
          (when (= (get-active-task-count) 0)
            (return (values t)))
          (sleep 0.01))))))
