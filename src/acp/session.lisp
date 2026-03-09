;;;; session.lisp — ACP session manager with concurrent turn tracking, eviction
;;;;
;;;; Implements the in-memory session store: creation, refresh, active run
;;;; tracking, idle TTL reaping, max-cap enforcement with soft eviction,
;;;; and stale marking.

(defpackage :cl-claw.acp.session
  (:use :cl :cl-claw.acp.types)
  (:export
   :create-session-store
   :session-store-create-session
   :session-store-get-session
   :session-store-has-session-p
   :session-store-set-active-run
   :session-store-cancel-active-run
   :session-store-get-session-by-run-id
   :session-store-list-sessions
   :session-store-remove-session
   :session-store-clear-all
   :session-store-reap-idle
   :session-store
   :session-store-max-sessions
   :session-store-idle-ttl-ms))

(in-package :cl-claw.acp.session)

(declaim (optimize (safety 3) (debug 3)))

;;; ─── Session Store ──────────────────────────────────────────────────────────

(defstruct (session-store (:conc-name session-store-)
                          (:constructor %make-session-store))
  "In-memory store for ACP sessions with eviction policy."
  (sessions (make-hash-table :test 'equal) :type hash-table)
  (run-index (make-hash-table :test 'equal) :type hash-table)
  (max-sessions 0 :type fixnum)       ; 0 = unlimited
  (idle-ttl-ms 0 :type fixnum)        ; 0 = no idle reaping
  (now-fn (lambda () (get-internal-real-time)) :type function)
  (lock (bt:make-lock "acp-session-store") :type t))

(defun create-session-store (&key (max-sessions 0) (idle-ttl-ms 0) (now nil))
  "Create a new session store."
  (declare (type fixnum max-sessions idle-ttl-ms)
           (type (or function null) now))
  (let ((now-fn (or now (lambda ()
                          (floor (* (get-internal-real-time) 1000)
                                 internal-time-units-per-second)))))
    (let ((store (%make-session-store)))
      (setf (session-store-max-sessions store) max-sessions
            (session-store-idle-ttl-ms store) idle-ttl-ms
            (session-store-now-fn store) now-fn)
      store)))

;;; Helper to get current time from the store
(declaim (ftype (function (session-store) fixnum) %now))
(defun %now (store)
  (declare (type session-store store))
  (the fixnum (funcall (session-store-now-fn store))))

;;; ─── Reaping ────────────────────────────────────────────────────────────────

(declaim (ftype (function (session-store) list) session-store-reap-idle))
(defun session-store-reap-idle (store)
  "Remove sessions that have been idle longer than idle-ttl-ms.
   Returns list of reaped session IDs."
  (declare (type session-store store))
  (let ((ttl (session-store-idle-ttl-ms store))
        (now (%now store))
        (reaped nil))
    (declare (type fixnum ttl now) (type list reaped))
    (when (> ttl 0)
      (let ((sessions (session-store-sessions store)))
        (maphash (lambda (sid entry)
                   (declare (type string sid))
                   (when (and (null (acp-session-entry-active-run-id entry))
                              (>= (- now (acp-session-entry-last-touched-at entry)) ttl))
                     (push sid reaped)))
                 sessions)
        (dolist (sid reaped)
          (let ((entry (gethash sid sessions)))
            (when entry
              (let ((run-id (acp-session-entry-active-run-id entry)))
                (when run-id
                  (remhash run-id (session-store-run-index store))))))
          (remhash sid sessions))))
    reaped))

;;; ─── Eviction ───────────────────────────────────────────────────────────────

(declaim (ftype (function (session-store) (or string null)) %find-oldest-idle-session))
(defun %find-oldest-idle-session (store)
  "Find the session ID of the oldest idle (no active run) session."
  (declare (type session-store store))
  (let ((oldest-id nil)
        (oldest-time most-positive-fixnum))
    (declare (type (or string null) oldest-id)
             (type fixnum oldest-time))
    (maphash (lambda (sid entry)
               (declare (type string sid))
               (when (and (null (acp-session-entry-active-run-id entry))
                          (< (acp-session-entry-last-touched-at entry) oldest-time))
                 (setf oldest-id sid
                       oldest-time (acp-session-entry-last-touched-at entry))))
             (session-store-sessions store))
    oldest-id))

(declaim (ftype (function (session-store) boolean) %enforce-cap))
(defun %enforce-cap (store)
  "Enforce max-sessions cap. Returns T if space is available after enforcement."
  (declare (type session-store store))
  (let ((max (session-store-max-sessions store)))
    (declare (type fixnum max))
    (when (or (= max 0) (< (hash-table-count (session-store-sessions store)) max))
      (return-from %enforce-cap t))
    ;; Try reaping idle first
    (session-store-reap-idle store)
    (when (< (hash-table-count (session-store-sessions store)) max)
      (return-from %enforce-cap t))
    ;; Try soft eviction of oldest idle session
    (let ((victim (%find-oldest-idle-session store)))
      (when victim
        (session-store-remove-session store victim)
        (return-from %enforce-cap t)))
    nil))

;;; ─── Core Operations ───────────────────────────────────────────────────────

(declaim (ftype (function (session-store &key (:session-id string)
                                              (:session-key string)
                                              (:cwd string))
                          acp-session-entry)
                session-store-create-session))
(defun session-store-create-session (store &key session-id session-key cwd)
  "Create or refresh a session. Signals ACP-SESSION-FULL-ERROR when at capacity."
  (declare (type session-store store)
           (type string session-key cwd)
           (type (or string null) session-id))
  (let* ((now (%now store))
         (sid (or session-id (format nil "acp-~A" (random 1000000000))))
         (existing (gethash sid (session-store-sessions store))))
    (declare (type fixnum now) (type string sid))
    (if existing
        ;; Refresh existing session
        (progn
          (setf (acp-session-entry-session-key existing) session-key
                (acp-session-entry-cwd existing) cwd
                (acp-session-entry-last-touched-at existing) now)
          existing)
        ;; Create new session
        (progn
          (unless (%enforce-cap store)
            (error 'acp-session-full-error
                   :text (format nil "Maximum sessions (~D) reached; no evictable session found"
                                 (session-store-max-sessions store))))
          (let ((entry (cl-claw.acp.types::make-acp-session-entry
                        :session-id sid
                        :session-key session-key
                        :cwd cwd
                        :created-at now
                        :last-touched-at now)))
            (setf (gethash sid (session-store-sessions store)) entry)
            entry)))))

(declaim (ftype (function (session-store string) (or acp-session-entry null))
                session-store-get-session))
(defun session-store-get-session (store session-id)
  "Look up a session by its ID."
  (declare (type session-store store) (type string session-id))
  (gethash session-id (session-store-sessions store)))

(declaim (ftype (function (session-store string) boolean) session-store-has-session-p))
(defun session-store-has-session-p (store session-id)
  "Returns T if the session exists."
  (declare (type session-store store) (type string session-id))
  (not (null (gethash session-id (session-store-sessions store)))))

(declaim (ftype (function (session-store string string t) null)
                session-store-set-active-run))
(defun session-store-set-active-run (store session-id run-id controller)
  "Register an active run for a session."
  (declare (type session-store store)
           (type string session-id run-id))
  (let ((entry (gethash session-id (session-store-sessions store))))
    (when entry
      (setf (acp-session-entry-active-run-id entry) run-id
            (acp-session-entry-abort-controller entry) controller)
      (setf (gethash run-id (session-store-run-index store)) session-id)))
  nil)

(declaim (ftype (function (session-store string) boolean) session-store-cancel-active-run))
(defun session-store-cancel-active-run (store session-id)
  "Cancel the active run for a session. Returns T if there was one to cancel."
  (declare (type session-store store) (type string session-id))
  (let ((entry (gethash session-id (session-store-sessions store))))
    (when (and entry (acp-session-entry-active-run-id entry))
      (remhash (acp-session-entry-active-run-id entry) (session-store-run-index store))
      (setf (acp-session-entry-active-run-id entry) nil
            (acp-session-entry-abort-controller entry) nil)
      t)))

(declaim (ftype (function (session-store string) (or acp-session-entry null))
                session-store-get-session-by-run-id))
(defun session-store-get-session-by-run-id (store run-id)
  "Look up which session owns a given run ID."
  (declare (type session-store store) (type string run-id))
  (let ((session-id (gethash run-id (session-store-run-index store))))
    (when session-id
      (gethash session-id (session-store-sessions store)))))

(declaim (ftype (function (session-store) list) session-store-list-sessions))
(defun session-store-list-sessions (store)
  "Return a list of all session entries."
  (declare (type session-store store))
  (let ((result nil))
    (maphash (lambda (k v) (declare (ignore k)) (push v result))
             (session-store-sessions store))
    result))

(declaim (ftype (function (session-store string) boolean) session-store-remove-session))
(defun session-store-remove-session (store session-id)
  "Remove a session and its run index entry. Returns T if it existed."
  (declare (type session-store store) (type string session-id))
  (let ((entry (gethash session-id (session-store-sessions store))))
    (when entry
      (let ((run-id (acp-session-entry-active-run-id entry)))
        (when run-id
          (remhash run-id (session-store-run-index store))))
      (remhash session-id (session-store-sessions store))
      t)))

(declaim (ftype (function (session-store) null) session-store-clear-all))
(defun session-store-clear-all (store)
  "Remove all sessions (for testing)."
  (declare (type session-store store))
  (clrhash (session-store-sessions store))
  (clrhash (session-store-run-index store))
  nil)
