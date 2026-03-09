;;;; runtime-cache.lisp — ACP runtime cache with idle tracking, touch-aware lookups
;;;;
;;;; Maps actor keys to cached runtime state. Provides idle candidate collection,
;;;; touch-on-access semantics, and point-in-time snapshots.

(defpackage :cl-claw.acp.runtime-cache
  (:use :cl :cl-claw.acp.types)
  (:export
   :runtime-cache
   :make-runtime-cache
   :runtime-cache-set
   :runtime-cache-get
   :runtime-cache-remove
   :runtime-cache-has-p
   :runtime-cache-size
   :runtime-cache-clear
   :runtime-cache-collect-idle-candidates
   :runtime-cache-snapshot))

(in-package :cl-claw.acp.runtime-cache)

(declaim (optimize (safety 3) (debug 3)))

;;; ─── Cache Structure ────────────────────────────────────────────────────────

(defstruct (runtime-cache (:conc-name runtime-cache-))
  "Cache of ACP runtime state, indexed by actor key."
  (entries (make-hash-table :test 'equal) :type hash-table))

;;; ─── Operations ─────────────────────────────────────────────────────────────

(declaim (ftype (function (runtime-cache string cached-runtime-state &key (:now fixnum)) null)
                runtime-cache-set))
(defun runtime-cache-set (cache actor-key state &key (now 0))
  "Insert or replace a cached runtime state for the given actor key."
  (declare (type runtime-cache cache)
           (type string actor-key)
           (type cached-runtime-state state)
           (type fixnum now))
  (setf (cached-runtime-state-last-touched-at state) now)
  (setf (gethash actor-key (runtime-cache-entries cache)) state)
  nil)

(declaim (ftype (function (runtime-cache string &key (:now fixnum))
                          (or cached-runtime-state null))
                runtime-cache-get))
(defun runtime-cache-get (cache actor-key &key (now 0))
  "Retrieve and touch the cached state for an actor key.
   Touch updates the last-touched-at timestamp."
  (declare (type runtime-cache cache)
           (type string actor-key)
           (type fixnum now))
  (let ((entry (gethash actor-key (runtime-cache-entries cache))))
    (when entry
      (when (> now 0)
        (setf (cached-runtime-state-last-touched-at entry) now))
      entry)))

(declaim (ftype (function (runtime-cache string) boolean) runtime-cache-remove))
(defun runtime-cache-remove (cache actor-key)
  "Remove an entry from the cache. Returns T if it existed."
  (declare (type runtime-cache cache) (type string actor-key))
  (not (null (remhash actor-key (runtime-cache-entries cache)))))

(declaim (ftype (function (runtime-cache string) boolean) runtime-cache-has-p))
(defun runtime-cache-has-p (cache actor-key)
  "Returns T if the actor key is in the cache."
  (declare (type runtime-cache cache) (type string actor-key))
  (not (null (gethash actor-key (runtime-cache-entries cache)))))

(declaim (ftype (function (runtime-cache) fixnum) runtime-cache-size))
(defun runtime-cache-size (cache)
  "Number of entries in the cache."
  (declare (type runtime-cache cache))
  (hash-table-count (runtime-cache-entries cache)))

(declaim (ftype (function (runtime-cache) null) runtime-cache-clear))
(defun runtime-cache-clear (cache)
  "Remove all entries."
  (declare (type runtime-cache cache))
  (clrhash (runtime-cache-entries cache))
  nil)

;;; ─── Idle Detection ─────────────────────────────────────────────────────────

(declaim (ftype (function (runtime-cache &key (:max-idle-ms fixnum) (:now fixnum)) list)
                runtime-cache-collect-idle-candidates))
(defun runtime-cache-collect-idle-candidates (cache &key (max-idle-ms 0) (now 0))
  "Collect entries that have been idle for at least MAX-IDLE-MS milliseconds.
   Returns a list of ACP-IDLE-CANDIDATE structs."
  (declare (type runtime-cache cache)
           (type fixnum max-idle-ms now))
  (let ((candidates nil))
    (declare (type list candidates))
    (maphash (lambda (key entry)
               (declare (type string key)
                        (type cached-runtime-state entry))
               (let ((idle (- now (cached-runtime-state-last-touched-at entry))))
                 (declare (type fixnum idle))
                 (when (>= idle max-idle-ms)
                   (push (cl-claw.acp.types::make-acp-idle-candidate
                          :actor-key key
                          :idle-ms idle)
                         candidates))))
             (runtime-cache-entries cache))
    candidates))

(declaim (ftype (function (runtime-cache &key (:now fixnum)) list)
                runtime-cache-snapshot))
(defun runtime-cache-snapshot (cache &key (now 0))
  "Return a list of ACP-SNAPSHOT-ENTRY structs for all cached runtimes."
  (declare (type runtime-cache cache)
           (type fixnum now))
  (let ((entries nil))
    (declare (type list entries))
    (maphash (lambda (key state)
               (declare (type string key)
                        (type cached-runtime-state state))
               (push (cl-claw.acp.types::make-acp-snapshot-entry
                      :actor-key key
                      :backend (cached-runtime-state-backend state)
                      :agent (cached-runtime-state-agent state)
                      :mode (cached-runtime-state-mode state)
                      :idle-ms (- now (cached-runtime-state-last-touched-at state)))
                     entries))
             (runtime-cache-entries cache))
    entries))
