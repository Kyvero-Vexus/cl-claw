;;;; net.lisp - Network utilities for cl-claw
;;;;
;;;; Provides safe network request utilities including SSRF protection,
;;;; URL validation, and proxy-aware fetch helpers.

(defpackage :cl-claw.infra.net
  (:use :cl)
  (:import-from :cl-ppcre :scan)
  (:export :ssrf-error
           :ssrf-error-url
           :ssrf-error-reason
           :validate-url-not-ssrf
           :safe-private-ip-p
           :fetch-url
           :make-fetch-options
           :fetch-options-url
           :fetch-options-method
           :fetch-options-headers
           :fetch-options-body
           :fetch-options-timeout-ms
           :fetch-options-proxy
           :fetch-response
           :make-fetch-response
           :fetch-response-status
           :fetch-response-body
           :fetch-response-headers
           :resolve-proxy-url))
(in-package :cl-claw.infra.net)

(declaim (optimize (safety 3) (debug 3)))

;;; Conditions

(define-condition ssrf-error (error)
  ((url :initarg :url :reader ssrf-error-url
        :documentation "The URL that triggered the SSRF block")
   (reason :initarg :reason :reader ssrf-error-reason
           :documentation "Reason why the URL was blocked"))
  (:report (lambda (c s)
             (format s "SSRF protection blocked request to ~s: ~a"
                     (ssrf-error-url c)
                     (ssrf-error-reason c))))
  (:documentation "Condition signaled when SSRF protection blocks a request."))

;;; Private IP ranges (RFC1918, loopback, link-local, etc.)

(defparameter *private-ip-patterns*
  (list
   ;; Loopback
   "^127\\."
   "^::1$"
   ;; RFC1918 private ranges
   "^10\\."
   "^172\\.(1[6-9]|2[0-9]|3[0-1])\\."
   "^192\\.168\\."
   ;; Link-local
   "^169\\.254\\."
   "^fe80:"
   ;; CGNAT (used by Tailscale but still private)
   "^100\\.(6[4-9]|[7-9][0-9]|1[0-1][0-9]|12[0-7])\\."
   ;; Multicast
   "^224\\."
   "^ff0"
   ;; Metadata services
   "^metadata\\."
   "^169\\.254\\.169\\.254$")
  "Patterns for private/SSRF-dangerous addresses.")

(declaim (ftype (function (string) boolean) safe-private-ip-p))
(defun safe-private-ip-p (host)
  "Return T if HOST matches a private/internal IP range or hostname.
These should be blocked in SSRF protection."
  (declare (type string host))
  (dolist (pattern *private-ip-patterns*)
    (when (cl-ppcre:scan pattern host)
      (return-from safe-private-ip-p t)))
  nil)

(defparameter *blocked-hostnames*
  '("localhost" "metadata" "metadata.google.internal" "169.254.169.254")
  "Hostnames that should always be blocked for SSRF protection.")

(declaim (ftype (function (string) (or null string)) extract-host-from-url))
(defun extract-host-from-url (url-string)
  "Extract hostname from URL string. Returns hostname or NIL."
  (declare (type string url-string))
  ;; Simple extraction: find // and then take until : or /
  (let ((proto-pos (search "//" url-string)))
    (when proto-pos
      (let* ((host-start (+ proto-pos 2))
             (rest (subseq url-string host-start))
             ;; Find end of host: /, :, or end of string
             (host-end (or (position #\/ rest)
                           (position #\: rest)
                           (length rest))))
        (subseq rest 0 host-end)))))

(declaim (ftype (function (string) string) validate-url-not-ssrf))
(defun validate-url-not-ssrf (url-string)
  "Validate that URL-STRING is not an SSRF-dangerous URL.
Signals SSRF-ERROR if the URL targets a private/internal host.
Returns the URL string if it passes validation."
  (declare (type string url-string))
  ;; Block non-http(s) protocols
  (unless (or (uiop:string-prefix-p "http://" url-string)
              (uiop:string-prefix-p "https://" url-string))
    (error 'ssrf-error
           :url url-string
           :reason "Only http:// and https:// protocols are allowed"))
  ;; Extract and validate host
  (let ((host (extract-host-from-url url-string)))
    (unless host
      (error 'ssrf-error :url url-string :reason "Could not parse URL host"))
    ;; Check blocked hostnames
    (when (member (string-downcase host) *blocked-hostnames* :test #'string=)
      (error 'ssrf-error
             :url url-string
             :reason (format nil "Host ~s is blocked (SSRF protection)" host)))
    ;; Check private IP patterns
    (when (safe-private-ip-p host)
      (error 'ssrf-error
             :url url-string
             :reason (format nil "Host ~s matches private IP range (SSRF protection)" host))))
  url-string)

;;; Fetch options and response

(defstruct fetch-options
  "Options for a network fetch request."
  (url nil :type (or null string))
  (method "GET" :type string)
  (headers nil :type list)          ; alist of (name . value)
  (body nil :type (or null string))
  (timeout-ms 30000 :type (integer 0))
  (proxy nil :type (or null string)))

(defstruct fetch-response
  "Response from a network fetch request."
  (status 200 :type integer)
  (body "" :type string)
  (headers nil :type list))

(declaim (ftype (function (&key (:env t)) (or null string)) resolve-proxy-url))
(defun resolve-proxy-url (&key env)
  "Resolve the proxy URL from environment variables.
Checks HTTPS_PROXY, HTTP_PROXY, and https_proxy in that order."
  (let ((proxy-env (cond
                     ((functionp env) (funcall env))
                     ((listp env) env)
                     (t nil))))
    (flet ((get-var (name)
             (if proxy-env
                 (or (cdr (assoc name proxy-env :test #'string=))
                     (getf proxy-env name))
                 (uiop:getenv name))))
      (or (get-var "HTTPS_PROXY")
          (get-var "HTTP_PROXY")
          (get-var "https_proxy")
          (get-var "http_proxy")))))

(declaim (ftype (function ((or string fetch-options) &key (:validate-ssrf t) (:proxy (or null string))) fetch-response) fetch-url))
(defun fetch-url (url-or-options &key (validate-ssrf t) (proxy nil))
  "Fetch a URL with optional SSRF validation and proxy support.

URL-OR-OPTIONS can be a string URL or FETCH-OPTIONS struct.
When VALIDATE-SSRF is T (default), validates against SSRF attacks.
Returns a FETCH-RESPONSE struct.

Note: This implementation uses UIOP to shell out to curl for actual fetching.
For production use, a proper HTTP library (dexador, drakma) should be used."
  (declare (type (or string fetch-options) url-or-options))
  (let* ((opts (if (stringp url-or-options)
                   (make-fetch-options :url url-or-options)
                   url-or-options))
         (url (fetch-options-url opts))
         (method (fetch-options-method opts))
         (timeout-ms (fetch-options-timeout-ms opts))
         (effective-proxy (or proxy (fetch-options-proxy opts))))
    ;; SSRF validation
    (when validate-ssrf
      (validate-url-not-ssrf url))
    ;; Build curl command
    (let* ((curl-args
             (append
              (list "curl" "-s" "-S" "-L"
                    "-X" method
                    "--max-time" (format nil "~a" (/ timeout-ms 1000.0)))
              (when effective-proxy (list "--proxy" effective-proxy))
              ;; Add headers
              (loop for (name . value) in (fetch-options-headers opts)
                    append (list "-H" (format nil "~a: ~a" name value)))
              ;; Add body
              (when (fetch-options-body opts)
                (list "-d" (fetch-options-body opts)))
              ;; Output with status code
              (list "-w" "\\n---STATUS:%{http_code}"
                    url)))
           (output
             (handler-case
                 (uiop:run-program curl-args :output :string :ignore-error-status t)
               (error (e)
                 (error "Fetch failed: ~a" e)))))
      ;; Parse the output to extract body and status
      (let* ((sep "---STATUS:")
             (sep-pos (search sep output :from-end t))
             (body (if sep-pos
                       (string-right-trim '(#\Newline #\Return)
                                          (subseq output 0 sep-pos))
                       output))
             (status (if sep-pos
                         (parse-integer (subseq output (+ sep-pos (length sep))) :junk-allowed t)
                         200)))
        (make-fetch-response
         :status (or status 0)
         :body body
         :headers nil)))))
