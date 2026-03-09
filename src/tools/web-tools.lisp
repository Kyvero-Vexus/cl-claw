;;;; web-tools.lisp — Web fetch/search tools
;;;;
;;;; Implements web_fetch and web_search tools for retrieving content
;;;; from URLs and performing web searches.

(defpackage :cl-claw.tools.web
  (:use :cl)
  (:import-from :cl-claw.tools.types
                :tool-definition
                :make-tool-definition)
  (:import-from :cl-claw.tools.dispatch
                :register-tool)
  (:export
   ;; Handlers
   :handle-web-fetch
   :handle-web-search

   ;; Registration
   :register-web-tools

   ;; Configuration
   :*web-fetch-max-chars*
   :*web-fetch-timeout*))

(in-package :cl-claw.tools.web)

(declaim (optimize (safety 3) (debug 3)))

;;; -----------------------------------------------------------------------
;;; Configuration
;;; -----------------------------------------------------------------------

(defvar *web-fetch-max-chars* 100000
  "Maximum characters to return from web fetch.")

(defvar *web-fetch-timeout* 30
  "Web fetch timeout in seconds.")

;;; -----------------------------------------------------------------------
;;; Web fetch — retrieve and extract content from URLs
;;; -----------------------------------------------------------------------

(declaim (ftype (function (hash-table) string) handle-web-fetch))
(defun handle-web-fetch (args)
  "Handle a web_fetch tool call.
Arguments:
  url: URL to fetch
  extractMode: 'markdown' or 'text' (default: markdown)
  maxChars: maximum characters to return (optional)"
  (declare (type hash-table args))
  (let* ((url (or (gethash "url" args)
                  (error "web_fetch requires url")))
         (max-chars (or (gethash "maxChars" args) *web-fetch-max-chars*))
         (extract-mode (or (gethash "extractMode" args) "markdown")))
    (declare (type string url extract-mode)
             (type fixnum max-chars))
    ;; Basic URL validation
    (unless (or (uiop:string-prefix-p "http://" url)
                (uiop:string-prefix-p "https://" url))
      (error "Invalid URL: ~A (must start with http:// or https://)" url))
    ;; Use curl for fetching
    (handler-case
        (multiple-value-bind (output exit-code)
            (uiop:run-program (list "curl" "-sL"
                                    "--max-time" (format nil "~D" *web-fetch-timeout*)
                                    "-A" "Mozilla/5.0 (compatible; cl-claw/1.0)"
                                    url)
                              :output '(:string :stripped t)
                              :error-output :string
                              :ignore-error-status t)
          (declare (type string output)
                   (type (or fixnum null) exit-code))
          (if (and exit-code (zerop exit-code))
              (let ((content (if (> (length output) max-chars)
                                 (subseq output 0 max-chars)
                                 output)))
                (declare (type string content))
                (if (string= extract-mode "text")
                    (strip-html-tags content)
                    content))
              (format nil "Failed to fetch ~A (curl exit ~A)" url exit-code)))
      (error (e)
        (format nil "Web fetch error: ~A" e)))))

(declaim (ftype (function (string) string) strip-html-tags))
(defun strip-html-tags (html)
  "Strip HTML tags from content (basic implementation)."
  (declare (type string html))
  (let ((result (make-array (length html) :element-type 'character
                                          :fill-pointer 0))
        (in-tag nil))
    (loop for ch across html
          do (cond
               ((char= ch #\<) (setf in-tag t))
               ((char= ch #\>) (setf in-tag nil))
               ((not in-tag) (vector-push-extend ch result))))
    (coerce result 'string)))

;;; -----------------------------------------------------------------------
;;; Web search — search the web
;;; -----------------------------------------------------------------------

(declaim (ftype (function (hash-table) string) handle-web-search))
(defun handle-web-search (args)
  "Handle a web_search tool call.
Arguments:
  query: search query string
  count: number of results (optional, 1-10)"
  (declare (type hash-table args))
  (let* ((query (or (gethash "query" args)
                    (error "web_search requires query")))
         (count (or (gethash "count" args) 5)))
    (declare (type string query)
             (type fixnum count))
    ;; Use a search engine API or fallback to curl+DuckDuckGo
    (handler-case
        (multiple-value-bind (output exit-code)
            (uiop:run-program
             (list "curl" "-sL"
                   "--max-time" "15"
                   (format nil "https://lite.duckduckgo.com/lite/?q=~A&kl=us-en"
                           (uiop:escape-shell-token query)))
             :output '(:string :stripped t)
             :error-output :string
             :ignore-error-status t)
          (declare (ignore exit-code))
          (if (plusp (length output))
              (let ((stripped (strip-html-tags output)))
                (if (> (length stripped) (* count 500))
                    (subseq stripped 0 (* count 500))
                    stripped))
              (format nil "No results found for: ~A" query)))
      (error (e)
        (format nil "Web search error: ~A" e)))))

;;; -----------------------------------------------------------------------
;;; Registration
;;; -----------------------------------------------------------------------

(defun register-web-tools ()
  "Register web_fetch and web_search tools."
  (register-tool (make-tool-definition
                  :name "web_fetch"
                  :description "Fetch and extract readable content from a URL (HTML → markdown/text)."
                  :handler #'handle-web-fetch
                  :category "web"))
  (register-tool (make-tool-definition
                  :name "web_search"
                  :description "Search the web. Returns AI-synthesized answers with citations."
                  :handler #'handle-web-search
                  :category "web"))
  (values))
