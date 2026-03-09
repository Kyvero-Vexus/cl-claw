;;;; queue.lisp — Channel rate limiting & queue management
;;;;
;;;; Provides message queuing with rate-limit awareness for outbound
;;;; messages across all channels.

(defpackage :cl-claw.channel-protocol.queue
  (:use :cl)
  (:import-from :cl-claw.channel-protocol.types
                :rate-limiter
                :make-rate-limiter
                :rate-limit-check
                :rate-limit-record
                :outbound-message
                :outbound-message-target)
  (:export
   ;; Message queue
   :message-queue
   :make-message-queue
   :queue-enqueue
   :queue-dequeue
   :queue-length
   :queue-empty-p
   :queue-clear
   :queue-peek

   ;; Rate-limited sender
   :rate-limited-sender
   :make-rate-limited-sender
   :sender-enqueue
   :sender-process-next
   :sender-process-all
   :sender-queue-length))

(in-package :cl-claw.channel-protocol.queue)

(declaim (optimize (safety 3) (debug 3)))

;;; -----------------------------------------------------------------------
;;; Thread-safe message queue
;;; -----------------------------------------------------------------------

(defstruct message-queue
  "Thread-safe FIFO message queue."
  (items '() :type list)
  (tail nil :type (or cons null))
  (length 0 :type fixnum)
  (lock (bt:make-lock "message-queue") :type t))

(defun queue-enqueue (queue item)
  "Add an item to the end of the queue."
  (declare (type message-queue queue))
  (bt:with-lock-held ((message-queue-lock queue))
    (let ((new-cons (list item)))
      (if (message-queue-tail queue)
          (progn
            (setf (cdr (message-queue-tail queue)) new-cons)
            (setf (message-queue-tail queue) new-cons))
          (progn
            (setf (message-queue-items queue) new-cons)
            (setf (message-queue-tail queue) new-cons))))
    (incf (message-queue-length queue)))
  (values))

(defun queue-dequeue (queue)
  "Remove and return the first item from the queue.
Returns (values item t) on success, (values nil nil) if empty."
  (declare (type message-queue queue))
  (bt:with-lock-held ((message-queue-lock queue))
    (if (null (message-queue-items queue))
        (values nil nil)
        (let ((item (car (message-queue-items queue))))
          (setf (message-queue-items queue) (cdr (message-queue-items queue)))
          (when (null (message-queue-items queue))
            (setf (message-queue-tail queue) nil))
          (decf (message-queue-length queue))
          (values item t)))))

(defun queue-peek (queue)
  "Return the first item without removing it.
Returns (values item t) or (values nil nil)."
  (declare (type message-queue queue))
  (bt:with-lock-held ((message-queue-lock queue))
    (if (null (message-queue-items queue))
        (values nil nil)
        (values (car (message-queue-items queue)) t))))

(defun queue-length (queue)
  "Return the current queue length."
  (declare (type message-queue queue))
  (message-queue-length queue))

(defun queue-empty-p (queue)
  "Check if the queue is empty."
  (declare (type message-queue queue))
  (zerop (message-queue-length queue)))

(defun queue-clear (queue)
  "Clear all items from the queue."
  (declare (type message-queue queue))
  (bt:with-lock-held ((message-queue-lock queue))
    (setf (message-queue-items queue) '())
    (setf (message-queue-tail queue) nil)
    (setf (message-queue-length queue) 0))
  (values))

;;; -----------------------------------------------------------------------
;;; Rate-limited sender
;;; -----------------------------------------------------------------------

(defstruct (rate-limited-sender (:constructor %make-rate-limited-sender))
  "Combines a message queue with rate limiting for outbound messages."
  (queue (make-message-queue) :type message-queue)
  (limiter (make-rate-limiter) :type rate-limiter)
  (send-fn nil :type (or function null))
  (processing-p nil :type boolean)
  (lock (bt:make-lock "rate-limited-sender") :type t))

(defun make-rate-limited-sender (&key send-fn
                                       (max-per-second 1.0)
                                       (max-per-minute 30.0))
  "Create a rate-limited sender with the given send function."
  (declare (type (or function null) send-fn)
           (type single-float max-per-second max-per-minute))
  (%make-rate-limited-sender
   :send-fn send-fn
   :limiter (make-rate-limiter :max-per-second max-per-second
                               :max-per-minute max-per-minute)))

(defun sender-enqueue (sender message)
  "Enqueue a message for rate-limited sending."
  (declare (type rate-limited-sender sender))
  (queue-enqueue (rate-limited-sender-queue sender) message)
  (values))

(defun sender-process-next (sender)
  "Try to process the next message in the queue.
Returns T if a message was sent, NIL if queue empty or rate-limited."
  (declare (type rate-limited-sender sender))
  (when (queue-empty-p (rate-limited-sender-queue sender))
    (return-from sender-process-next nil))
  (unless (rate-limit-check (rate-limited-sender-limiter sender))
    (return-from sender-process-next nil))
  (multiple-value-bind (msg found) (queue-dequeue (rate-limited-sender-queue sender))
    (when found
      (let ((send-fn (rate-limited-sender-send-fn sender)))
        (when send-fn
          (handler-case
              (progn
                (funcall send-fn msg)
                (rate-limit-record (rate-limited-sender-limiter sender))
                t)
            (error ()
              ;; Re-enqueue on failure? For now just drop
              nil)))))))

(defun sender-process-all (sender)
  "Process all queued messages, respecting rate limits.
Blocks until queue is empty or rate limit is hit."
  (declare (type rate-limited-sender sender))
  (loop while (sender-process-next sender)))

(defun sender-queue-length (sender)
  "Return the number of messages in the send queue."
  (declare (type rate-limited-sender sender))
  (queue-length (rate-limited-sender-queue sender)))
