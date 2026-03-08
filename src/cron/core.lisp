;;;; core.lisp — cron scheduler, jobs, and delivery helpers

(defpackage :cl-claw.cron
  (:use :cl)
  (:export
   :cron-delivery
   :make-cron-delivery
   :cron-delivery-mode
   :cron-delivery-to
   :cron-delivery-account-id
   :cron-delivery-thread-id
   :cron-job
   :make-cron-job
   :cron-job-id
   :cron-job-schedule
   :cron-job-payload
   :cron-job-timezone
   :cron-job-enabled-p
   :cron-job-next-run-at
   :cron-job-run-count
   :cron-job-last-status
   :cron-job-last-run-at
   :cron-store
   :make-cron-store
   :cron-store-jobs
   :normalize-cron-payload
   :compute-next-run-at
   :job-due-p
   :add-cron-job
   :get-cron-job
   :list-cron-jobs
   :set-job-enabled
   :advance-job-schedule
   :build-delivery-payload
   :run-due-jobs))

(in-package :cl-claw.cron)

(declaim (optimize (safety 3) (debug 3)))

(defstruct cron-delivery
  (mode "none" :type string)
  (to nil :type (or string null))
  (account-id nil :type (or string null))
  (thread-id nil :type (or string null)))

(defstruct cron-job
  (id "" :type string)
  (schedule (make-hash-table :test 'equal) :type hash-table)
  (payload (make-hash-table :test 'equal) :type hash-table)
  (timezone "UTC" :type string)
  (enabled-p t :type boolean)
  (next-run-at 0 :type integer)
  (run-count 0 :type integer)
  (last-status nil :type (or string null))
  (last-run-at nil :type (or integer null))
  (delivery (make-cron-delivery) :type cron-delivery))

(defstruct cron-store
  (jobs (make-hash-table :test 'equal) :type hash-table))

(declaim (ftype (function ((or hash-table null)) hash-table) normalize-cron-payload))
(defun normalize-cron-payload (payload)
  (declare (type (or hash-table null) payload))
  (or payload (make-hash-table :test 'equal)))

(declaim (ftype (function (string) list) split-cron-expr))
(defun split-cron-expr (expr)
  (declare (type string expr))
  (remove-if #'(lambda (item)
                 (declare (type string item))
                 (string= item ""))
             (uiop:split-string (string-trim '(#\Space #\Tab #\Newline #\Return) expr)
                                :separator '(#\Space #\Tab))))

(declaim (ftype (function (string integer integer) boolean) cron-field-matches-p))
(defun cron-field-matches-p (field value min-value)
  (declare (type string field)
           (type integer value min-value))
  (let ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) field)))
    (declare (type string trimmed))
    (cond
      ((string= trimmed "*") t)
      ((and (> (length trimmed) 2)
            (string= (subseq trimmed 0 2) "*/"))
       (let ((step (parse-integer (subseq trimmed 2) :junk-allowed t)))
         (declare (type (or integer null) step))
         (and step
              (> step 0)
              (= (mod (- value min-value) step) 0))))
      (t
       (let ((target (parse-integer trimmed :junk-allowed t)))
         (declare (type (or integer null) target))
         (and target (= value target)))))))

(declaim (ftype (function (hash-table integer) integer) compute-every-next-run-at))
(defun compute-every-next-run-at (schedule from-time)
  (declare (type hash-table schedule)
           (type integer from-time))
  (let* ((seconds (or (gethash "seconds" schedule)
                      (gethash "intervalSec" schedule)
                      60))
         (interval (if (and (integerp seconds) (> (the integer seconds) 0))
                       (the integer seconds)
                       60)))
    (declare (type integer interval))
    (+ from-time interval)))

(declaim (ftype (function (hash-table integer) integer) compute-cron-next-run-at))
(defun compute-cron-next-run-at (schedule from-time)
  (declare (type hash-table schedule)
           (type integer from-time))
  (let* ((expr-raw (or (gethash "expr" schedule)
                       (gethash "cron" schedule)
                       "* * * * *"))
         (expr (if (stringp expr-raw) expr-raw "* * * * *"))
         (parts (split-cron-expr expr)))
    (declare (type string expr)
             (type list parts))
    (unless (= (length parts) 5)
      (error "Unsupported cron expression: ~a" expr))
    (let ((minute (first parts))
          (hour (second parts))
          (cursor (+ from-time 60))
          (limit (+ from-time (* 366 24 60 60))))
      (declare (type string minute hour)
               (type integer cursor limit))
      (let ((found nil))
        (declare (type (or integer null) found))
        (loop while (<= cursor limit) do
          (multiple-value-bind (sec min hr day month year dow dst-p tz)
              (decode-universal-time cursor 0)
            (declare (ignore day month year dow dst-p tz)
                     (type integer sec min hr))
            (when (and (= sec 0)
                       (cron-field-matches-p minute min 0)
                       (cron-field-matches-p hour hr 0))
              (setf found cursor)
              (loop-finish)))
          (incf cursor 60))
        (or found
            (error "Unable to compute next run for cron expression: ~a" expr))))))

(declaim (ftype (function (hash-table &key (:from-time integer)) integer) compute-next-run-at))
(defun compute-next-run-at (schedule &key (from-time (get-universal-time)))
  (declare (type hash-table schedule)
           (type integer from-time))
  (let* ((kind-raw (or (gethash "kind" schedule) "every"))
         (kind (if (stringp kind-raw)
                   (string-downcase kind-raw)
                   "every")))
    (declare (type string kind))
    (cond
      ((string= kind "every")
       (compute-every-next-run-at schedule from-time))
      ((string= kind "cron")
       (compute-cron-next-run-at schedule from-time))
      (t
       (error "Unknown schedule kind: ~a" kind)))))

(declaim (ftype (function (cron-job &key (:now integer)) boolean) job-due-p))
(defun job-due-p (job &key (now (get-universal-time)))
  (declare (type cron-job job)
           (type integer now))
  (and (cron-job-enabled-p job)
       (<= (cron-job-next-run-at job) now)))

(declaim (ftype (function (cron-store cron-job) cron-job) add-cron-job))
(defun add-cron-job (store job)
  (declare (type cron-store store)
           (type cron-job job))
  (let ((id (cron-job-id job)))
    (declare (type string id))
    (setf (gethash id (cron-store-jobs store)) job)
    job))

(declaim (ftype (function (cron-store string) (or cron-job null)) get-cron-job))
(defun get-cron-job (store id)
  (declare (type cron-store store)
           (type string id))
  (gethash id (cron-store-jobs store)))

(declaim (ftype (function (cron-store) list) list-cron-jobs))
(defun list-cron-jobs (store)
  (declare (type cron-store store))
  (let ((items nil))
    (declare (type list items))
    (maphash (lambda (k v)
               (declare (ignore k)
                        (type cron-job v))
               (push v items))
             (cron-store-jobs store))
    (sort items #'string< :key #'cron-job-id)))

(declaim (ftype (function (cron-store string boolean) (or cron-job null)) set-job-enabled))
(defun set-job-enabled (store id enabled-p)
  (declare (type cron-store store)
           (type string id)
           (type boolean enabled-p))
  (let ((job (get-cron-job store id)))
    (declare (type (or cron-job null) job))
    (when job
      (setf (cron-job-enabled-p job) enabled-p)
      job)))

(declaim (ftype (function (cron-job &key (:from-time integer)) cron-job) advance-job-schedule))
(defun advance-job-schedule (job &key (from-time (get-universal-time)))
  (declare (type cron-job job)
           (type integer from-time))
  (setf (cron-job-next-run-at job)
        (compute-next-run-at (cron-job-schedule job) :from-time from-time))
  job)

(declaim (ftype (function (cron-job string string) hash-table) build-delivery-payload))
(defun build-delivery-payload (job status summary)
  (declare (type cron-job job)
           (type string status summary))
  (let* ((delivery (cron-job-delivery job))
         (obj (make-hash-table :test 'equal)))
    (declare (type cron-delivery delivery)
             (type hash-table obj))
    (setf (gethash "jobId" obj) (cron-job-id job)
          (gethash "status" obj) status
          (gethash "summary" obj) summary
          (gethash "mode" obj) (cron-delivery-mode delivery))
    (when (cron-delivery-to delivery)
      (setf (gethash "to" obj) (cron-delivery-to delivery)))
    (when (cron-delivery-account-id delivery)
      (setf (gethash "accountId" obj) (cron-delivery-account-id delivery)))
    (when (cron-delivery-thread-id delivery)
      (setf (gethash "threadId" obj) (cron-delivery-thread-id delivery)))
    obj))

(declaim (ftype (function (cron-store function &key (:now integer)) list) run-due-jobs))
(defun run-due-jobs (store runner &key (now (get-universal-time)))
  (declare (type cron-store store)
           (type function runner)
           (type integer now))
  (let ((results nil))
    (declare (type list results))
    (dolist (job (list-cron-jobs store))
      (declare (type cron-job job))
      (when (job-due-p job :now now)
        (let* ((outcome (funcall runner job))
               (status (if (and (stringp outcome)
                                (string/= (the string outcome) ""))
                           (the string outcome)
                           "ok")))
          (declare (type string status))
          (incf (cron-job-run-count job))
          (setf (cron-job-last-status job) status
                (cron-job-last-run-at job) now)
          (advance-job-schedule job :from-time now)
          (push (build-delivery-payload job status status) results))))
    (nreverse results)))
