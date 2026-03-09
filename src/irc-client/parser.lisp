;;;; parser.lisp — IRC message parsing and handling
;;;;
;;;; Parses raw IRC protocol lines into structured messages.

(defpackage :cl-claw.irc-client.parser
  (:use :cl)
  (:export
   :irc-message
   :make-irc-message
   :irc-message-prefix
   :irc-message-nick
   :irc-message-user
   :irc-message-host
   :irc-message-command
   :irc-message-params
   :irc-message-trailing

   :parse-irc-line
   :extract-nick-from-prefix))

(in-package :cl-claw.irc-client.parser)

(declaim (optimize (safety 3) (debug 3)))

;;; -----------------------------------------------------------------------
;;; IRC message structure
;;; -----------------------------------------------------------------------

(defstruct irc-message
  "Parsed IRC protocol message."
  (prefix nil :type (or string null))
  (nick nil :type (or string null))
  (user nil :type (or string null))
  (host nil :type (or string null))
  (command "" :type string)
  (params '() :type list)
  (trailing nil :type (or string null)))

;;; -----------------------------------------------------------------------
;;; Nick extraction
;;; -----------------------------------------------------------------------

(declaim (ftype (function (string) string) extract-nick-from-prefix))
(defun extract-nick-from-prefix (prefix)
  "Extract the nick from an IRC prefix (nick!user@host)."
  (declare (type string prefix))
  (let ((bang-pos (position #\! prefix)))
    (if bang-pos
        (subseq prefix 0 bang-pos)
        prefix)))

;;; -----------------------------------------------------------------------
;;; IRC line parsing
;;; -----------------------------------------------------------------------

(declaim (ftype (function (string) irc-message) parse-irc-line))
(defun parse-irc-line (line)
  "Parse a raw IRC protocol line into an irc-message struct."
  (declare (type string line))
  ;; Strip trailing CR/LF
  (let ((clean (string-right-trim '(#\Return #\Newline) line))
        (prefix nil)
        (nick nil)
        (user nil)
        (host nil)
        (command "")
        (params '())
        (trailing nil)
        (pos 0))
    (declare (type string clean command)
             (type (or string null) prefix nick user host trailing)
             (type list params)
             (type fixnum pos))

    ;; Parse prefix
    (when (and (plusp (length clean)) (char= (char clean 0) #\:))
      (let ((space (position #\Space clean :start 1)))
        (when space
          (setf prefix (subseq clean 1 space))
          (setf pos (1+ space))
          ;; Parse nick!user@host
          (let ((bang (position #\! prefix))
                (at (position #\@ prefix)))
            (cond
              ((and bang at (< bang at))
               (setf nick (subseq prefix 0 bang))
               (setf user (subseq prefix (1+ bang) at))
               (setf host (subseq prefix (1+ at))))
              (bang
               (setf nick (subseq prefix 0 bang)))
              (t
               (setf nick prefix)))))))

    ;; Parse command
    (let ((space (position #\Space clean :start pos)))
      (if space
          (progn
            (setf command (subseq clean pos space))
            (setf pos (1+ space)))
          (progn
            (setf command (subseq clean pos))
            (setf pos (length clean)))))

    ;; Parse params and trailing
    (loop while (< pos (length clean))
          do (if (char= (char clean pos) #\:)
                 ;; Trailing parameter (rest of line)
                 (progn
                   (setf trailing (subseq clean (1+ pos)))
                   (return))
                 ;; Middle parameter
                 (let ((space (position #\Space clean :start pos)))
                   (if space
                       (progn
                         (push (subseq clean pos space) params)
                         (setf pos (1+ space)))
                       (progn
                         (push (subseq clean pos) params)
                         (return))))))

    (make-irc-message :prefix prefix
                      :nick nick
                      :user user
                      :host host
                      :command (string-upcase command)
                      :params (nreverse params)
                      :trailing trailing)))
