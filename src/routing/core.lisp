;;;; core.lisp — Session-key based routing helpers

(defpackage :cl-claw.routing
  (:use :cl)
  (:export
   :route-entry
   :make-route-entry
   :route-entry-provider
   :route-entry-account
   :route-entry-target
   :route-entry-thread
   :route-entry-topic
   :route-entry-agent-id
   :route-table
   :create-route-table
   :normalize-provider-id
   :normalize-account-id
   :make-session-key
   :parse-session-key
   :parsed-session-key
   :parsed-session-key-provider
   :parsed-session-key-account
   :parsed-session-key-target
   :parsed-session-key-thread
   :parsed-session-key-topic
   :parsed-session-key-agent-id
   :remember-route
   :resolve-route
   :resolve-route-for-inbound))

(in-package :cl-claw.routing)

(declaim (optimize (safety 3) (debug 3)))

;;; ROUTE-ENTRY - canonical routing record (stored in the route table)
(defstruct route-entry
  (provider "" :type string)
  (account "default" :type string)
  (target "" :type string)
  (thread nil :type (or string null))
  (topic nil :type (or string null))
  (agent-id "main" :type string))

;;; PARSED-SESSION-KEY - idiomatic CL struct returned by PARSE-SESSION-KEY.
;;; Previously this was returned as a hash-table with JS-style string keys;
;;; using a struct allows compile-time slot access and type checking.
(defstruct parsed-session-key
  "Components parsed out of a session-key string."
  (provider "unknown" :type string)
  (account  "default" :type string)
  (target   "unknown" :type string)
  (thread   nil       :type (or string null))
  (topic    nil       :type (or string null))
  (agent-id "main"   :type string))

(defstruct (route-table (:constructor %make-route-table))
  (lock (bt:make-lock "route-table-lock") :type t)
  (by-session-key (make-hash-table :test 'equal) :type hash-table)
  (by-provider-target (make-hash-table :test 'equal) :type hash-table))

(declaim (ftype (function () route-table) create-route-table))
(defun create-route-table ()
  (%make-route-table))

(declaim (ftype (function (string) string) sanitize-route-fragment))
(defun sanitize-route-fragment (value)
  (declare (type string value))
  (let ((down (string-downcase (string-trim '(#\Space #\Tab #\Newline #\Return) value))))
    (declare (type string down))
    (with-output-to-string (out)
      (loop for ch across down do
        (if (or (alphanumericp ch) (char= ch #\-) (char= ch #\_) (char= ch #\.))
            (write-char ch out)
            (write-char #\_ out))))))

(declaim (ftype (function (string) string) normalize-provider-id))
(defun normalize-provider-id (provider)
  (declare (type string provider))
  (let ((s (sanitize-route-fragment provider)))
    (if (string= s "") "unknown" s)))

(declaim (ftype (function (string) string) normalize-account-id))
(defun normalize-account-id (account)
  (declare (type string account))
  (let ((s (sanitize-route-fragment account)))
    (if (string= s "") "default" s)))

(declaim (ftype (function (string string string &key (:thread (or string null))
                                                   (:topic (or string null))
                                                   (:agent-id (or string null)))
                          string)
                make-session-key))
(defun make-session-key (provider account target &key thread topic (agent-id "main"))
  (declare (type string provider account target)
           (type (or string null) thread topic agent-id))
  (let ((p (normalize-provider-id provider))
        (a (normalize-account-id account))
        (tgt (sanitize-route-fragment target))
        (ag (sanitize-route-fragment (or agent-id "main")))
        (thread-part (and thread (sanitize-route-fragment thread)))
        (topic-part (and topic (sanitize-route-fragment topic))))
    (declare (type string p a tgt ag)
             (type (or string null) thread-part topic-part))
    (with-output-to-string (out)
      (format out "~a:~a:~a" p a (if (string= tgt "") "unknown" tgt))
      (when thread-part
        (format out ":thread:~a" thread-part))
      (when topic-part
        (format out ":topic:~a" topic-part))
      (format out "@~a" (if (string= ag "") "main" ag)))))

(declaim (ftype (function (string) parsed-session-key) parse-session-key))
(defun parse-session-key (session-key)
  "Parse a SESSION-KEY string into a PARSED-SESSION-KEY struct.

Session keys have the form:
  provider:account:target[:thread:V][:topic:V]@agent-id"
  (declare (type string session-key))
  (let* ((parts    (uiop:split-string session-key :separator '(#\@)))
         (lhs      (if parts (first parts) session-key))
         (agent-id (if (and parts (second parts)) (second parts) "main"))
         (frags    (uiop:split-string lhs :separator '(#\:)))
         (provider (or (nth 0 frags) "unknown"))
         (account  (or (nth 1 frags) "default"))
         (target   (or (nth 2 frags) "unknown"))
         (thread   nil)
         (topic    nil))
    (declare (type list parts frags)
             (type string lhs agent-id provider account target)
             (type (or string null) thread topic))
    (loop :for i :from 3 :below (length frags) :by 2
          :for k := (nth i frags)
          :for v := (nth (1+ i) frags)
          :when (and k v)
            :do (cond
                  ((string= k "thread") (setf thread v))
                  ((string= k "topic")  (setf topic  v))))
    (make-parsed-session-key :provider provider
                             :account  account
                             :target   target
                             :thread   thread
                             :topic    topic
                             :agent-id agent-id)))

(declaim (ftype (function (route-table route-entry) string) remember-route))
(defun remember-route (table entry)
  (declare (type route-table table)
           (type route-entry entry))
  (let* ((canonical (make-route-entry
                     :provider (normalize-provider-id (route-entry-provider entry))
                     :account (normalize-account-id (route-entry-account entry))
                     :target (sanitize-route-fragment (route-entry-target entry))
                     :thread (and (route-entry-thread entry)
                                  (sanitize-route-fragment (route-entry-thread entry)))
                     :topic (and (route-entry-topic entry)
                                 (sanitize-route-fragment (route-entry-topic entry)))
                     :agent-id (sanitize-route-fragment (route-entry-agent-id entry))))
         (session-key (make-session-key (route-entry-provider canonical)
                                        (route-entry-account canonical)
                                        (route-entry-target canonical)
                                        :thread (route-entry-thread canonical)
                                        :topic (route-entry-topic canonical)
                                        :agent-id (route-entry-agent-id canonical)))
         (secondary-key (format nil "~a|~a|~a"
                                (route-entry-provider canonical)
                                (route-entry-account canonical)
                                (route-entry-target canonical))))
    (declare (type route-entry canonical)
             (type string session-key secondary-key))
    (bt:with-lock-held ((route-table-lock table))
      (setf (gethash session-key (route-table-by-session-key table)) canonical
            (gethash secondary-key (route-table-by-provider-target table)) session-key))
    session-key))

(declaim (ftype (function (route-table string) (or route-entry null)) resolve-route))
(defun resolve-route (table session-key)
  (declare (type route-table table)
           (type string session-key))
  (bt:with-lock-held ((route-table-lock table))
    (gethash session-key (route-table-by-session-key table))))

(declaim (ftype (function (route-table string string string &key (:thread (or string null))
                                                         (:topic (or string null))
                                                         (:agent-id (or string null)))
                          route-entry)
                resolve-route-for-inbound))
(defun resolve-route-for-inbound (table provider account target &key thread topic (agent-id "main"))
  (declare (type route-table table)
           (type string provider account target)
           (type (or string null) thread topic agent-id))
  (let* ((normalized-provider (normalize-provider-id provider))
         (normalized-account (normalize-account-id account))
         (normalized-target (sanitize-route-fragment target))
         (secondary-key (format nil "~a|~a|~a" normalized-provider normalized-account normalized-target)))
    (declare (type string normalized-provider normalized-account normalized-target secondary-key))
    (or
     (bt:with-lock-held ((route-table-lock table))
       (let ((existing-session-key (gethash secondary-key (route-table-by-provider-target table))))
         (declare (type (or string null) existing-session-key))
         (when existing-session-key
           (gethash existing-session-key (route-table-by-session-key table)))))
     (let ((entry (make-route-entry :provider normalized-provider
                                    :account normalized-account
                                    :target normalized-target
                                    :thread (and thread (sanitize-route-fragment thread))
                                    :topic (and topic (sanitize-route-fragment topic))
                                    :agent-id (sanitize-route-fragment (or agent-id "main")))))
       (declare (type route-entry entry))
       (remember-route table entry)
       entry))))