;;;; core.lisp — browser profile/target routing helpers

(defpackage :cl-claw.browser
  (:use :cl)
  (:export
   :normalize-browser-profile
   :profile-requires-extension-attach-p
   :ensure-relay-tab-attached
   :sanitize-cdp-endpoint
   :choose-browser-target
   :build-browser-open-request))

(in-package :cl-claw.browser)

(declaim (optimize (safety 3) (debug 3)))

(declaim (ftype (function ((or string null)) string) normalize-browser-profile))
(defun normalize-browser-profile (profile)
  (declare (type (or string null) profile))
  (let ((normalized (if (and profile (not (string= profile "")))
                        (string-downcase (string-trim '(#\Space #\Tab #\Newline #\Return) profile))
                        "openclaw")))
    (declare (type string normalized))
    (if (member normalized '("chrome" "openclaw") :test #'string=)
        normalized
        "openclaw")))

(declaim (ftype (function (string) boolean) profile-requires-extension-attach-p))
(defun profile-requires-extension-attach-p (profile)
  (declare (type string profile))
  (string= "chrome" (normalize-browser-profile profile)))

(declaim (ftype (function (string fixnum) null) ensure-relay-tab-attached))
(defun ensure-relay-tab-attached (profile connected-tab-count)
  (declare (type string profile)
           (type fixnum connected-tab-count))
  (when (and (profile-requires-extension-attach-p profile)
             (<= connected-tab-count 0))
    (error "Chrome extension relay requires an attached tab."))
  nil)

(declaim (ftype (function (string) string) sanitize-cdp-endpoint))
(defun sanitize-cdp-endpoint (endpoint)
  (declare (type string endpoint))
  (let ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) endpoint)))
    (declare (type string trimmed))
    (unless (or (uiop:string-prefix-p "ws://" trimmed)
                (uiop:string-prefix-p "wss://" trimmed))
      (error "Invalid CDP endpoint (must be ws:// or wss://): ~a" endpoint))
    trimmed))

(declaim (ftype (function (string boolean) keyword) choose-browser-target))
(defun choose-browser-target (requested-target node-available-p)
  (declare (type string requested-target)
           (type boolean node-available-p))
  (let ((target (string-downcase requested-target)))
    (declare (type string target))
    (cond
      ((string= target "node") (if node-available-p :node :host))
      ((string= target "sandbox") :sandbox)
      (t :host))))

(declaim (ftype (function (string string keyword) hash-table) build-browser-open-request))
(defun build-browser-open-request (url profile target)
  (declare (type string url profile)
           (type keyword target))
  (let ((request (make-hash-table :test 'equal))
        (normalized-profile (normalize-browser-profile profile)))
    (declare (type hash-table request)
             (type string normalized-profile))
    (setf (gethash "action" request) "open"
          (gethash "url" request) url
          (gethash "profile" request) normalized-profile
          (gethash "target" request) (string-downcase (symbol-name target)))
    request))
