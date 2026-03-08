;;;; diagnostic-events.test.lisp - Tests for diagnostic-events module

(defpackage :cl-claw.infra.diagnostic-events.test
  (:use :cl :fiveam))
(in-package :cl-claw.infra.diagnostic-events.test)

(def-suite diagnostic-events-suite
  :description "Tests for the diagnostic-events module")
(in-suite diagnostic-events-suite)

(test creates-event-bus
  "Creates a fresh event bus"
  (let ((bus (cl-claw.infra.diagnostic-events:make-event-bus)))
    (is (not (null bus)))
    (is (= 0 (cl-claw.infra.diagnostic-events:event-bus-event-count bus)))))

(test emit-creates-event
  "Emitting an event stores it in the bus"
  (let ((bus (cl-claw.infra.diagnostic-events:make-event-bus)))
    (cl-claw.infra.diagnostic-events:emit-event bus "test.event" '(:value 42))
    (is (= 1 (cl-claw.infra.diagnostic-events:event-bus-event-count bus)))))

(test emit-returns-event
  "Emit returns the created event"
  (let ((bus (cl-claw.infra.diagnostic-events:make-event-bus)))
    (let ((event (cl-claw.infra.diagnostic-events:emit-event bus "test.type" "data")))
      (is (not (null event)))
      (is (string= "test.type" (cl-claw.infra.diagnostic-events:diagnostic-event-type event)))
      (is (string= "data" (cl-claw.infra.diagnostic-events:diagnostic-event-data event))))))

(test get-events-returns-all
  "get-events returns all emitted events"
  (let ((bus (cl-claw.infra.diagnostic-events:make-event-bus)))
    (cl-claw.infra.diagnostic-events:emit-event bus "type.a" 1)
    (cl-claw.infra.diagnostic-events:emit-event bus "type.b" 2)
    (cl-claw.infra.diagnostic-events:emit-event bus "type.a" 3)
    (let ((events (cl-claw.infra.diagnostic-events:get-events bus)))
      (is (= 3 (length events))))))

(test get-events-filters-by-type
  "get-events filters by event-type"
  (let ((bus (cl-claw.infra.diagnostic-events:make-event-bus)))
    (cl-claw.infra.diagnostic-events:emit-event bus "type.a" 1)
    (cl-claw.infra.diagnostic-events:emit-event bus "type.b" 2)
    (cl-claw.infra.diagnostic-events:emit-event bus "type.a" 3)
    (let ((events (cl-claw.infra.diagnostic-events:get-events bus :event-type "type.a")))
      (is (= 2 (length events))))))

(test get-events-with-limit
  "get-events respects limit parameter"
  (let ((bus (cl-claw.infra.diagnostic-events:make-event-bus)))
    (dotimes (i 10)
      (cl-claw.infra.diagnostic-events:emit-event bus "evt" i))
    (let ((events (cl-claw.infra.diagnostic-events:get-events bus :limit 3)))
      (is (= 3 (length events))))))

(test subscribe-receives-events
  "Subscriber receives emitted events"
  (let ((bus (cl-claw.infra.diagnostic-events:make-event-bus))
        (received '()))
    (cl-claw.infra.diagnostic-events:subscribe
     bus "my.event"
     (lambda (event)
       (push (cl-claw.infra.diagnostic-events:diagnostic-event-data event) received)))
    (cl-claw.infra.diagnostic-events:emit-event bus "my.event" "payload")
    (is (equal '("payload") received))))

(test subscribe-all-receives-all-types
  "Subscriber with :all receives all event types"
  (let ((bus (cl-claw.infra.diagnostic-events:make-event-bus))
        (count 0))
    (cl-claw.infra.diagnostic-events:subscribe
     bus :all
     (lambda (event) (declare (ignore event)) (incf count)))
    (cl-claw.infra.diagnostic-events:emit-event bus "type.x" nil)
    (cl-claw.infra.diagnostic-events:emit-event bus "type.y" nil)
    (is (= 2 count))))

(test subscribe-filter-by-type
  "Subscriber only receives events of its registered type"
  (let ((bus (cl-claw.infra.diagnostic-events:make-event-bus))
        (received-a 0)
        (received-b 0))
    (cl-claw.infra.diagnostic-events:subscribe
     bus "type.a"
     (lambda (e) (declare (ignore e)) (incf received-a)))
    (cl-claw.infra.diagnostic-events:subscribe
     bus "type.b"
     (lambda (e) (declare (ignore e)) (incf received-b)))
    (cl-claw.infra.diagnostic-events:emit-event bus "type.a" nil)
    (cl-claw.infra.diagnostic-events:emit-event bus "type.a" nil)
    (cl-claw.infra.diagnostic-events:emit-event bus "type.b" nil)
    (is (= 2 received-a))
    (is (= 1 received-b))))

(test unsubscribe-stops-delivery
  "Unsubscribing removes the handler"
  (let ((bus (cl-claw.infra.diagnostic-events:make-event-bus))
        (count 0))
    (let ((token (cl-claw.infra.diagnostic-events:subscribe
                  bus "ev"
                  (lambda (e) (declare (ignore e)) (incf count)))))
      (cl-claw.infra.diagnostic-events:emit-event bus "ev" nil)
      (cl-claw.infra.diagnostic-events:unsubscribe bus token)
      (cl-claw.infra.diagnostic-events:emit-event bus "ev" nil)
      (is (= 1 count)))))

(test clear-events-empties-bus
  "Clearing events removes all stored events"
  (let ((bus (cl-claw.infra.diagnostic-events:make-event-bus)))
    (cl-claw.infra.diagnostic-events:emit-event bus "e" nil)
    (cl-claw.infra.diagnostic-events:emit-event bus "e" nil)
    (cl-claw.infra.diagnostic-events:clear-events bus)
    (is (= 0 (cl-claw.infra.diagnostic-events:event-bus-event-count bus)))))

(test respects-max-events-capacity
  "Bus evicts oldest events when max-events is exceeded"
  (let ((bus (cl-claw.infra.diagnostic-events:make-event-bus :max-events 3)))
    (dotimes (i 5)
      (cl-claw.infra.diagnostic-events:emit-event bus "e" i))
    ;; Should have at most 3 events
    (is (<= (cl-claw.infra.diagnostic-events:event-bus-event-count bus) 3))))
