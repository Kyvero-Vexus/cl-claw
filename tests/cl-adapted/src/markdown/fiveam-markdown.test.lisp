;;;; FiveAM tests for markdown IR and WhatsApp normalization

(defpackage :cl-claw.markdown.test
  (:use :cl :fiveam))

(in-package :cl-claw.markdown.test)

(declaim (optimize (safety 3) (debug 3)))

(def-suite markdown-suite
  :description "Tests for markdown parsing and WhatsApp formatting")

(in-suite markdown-suite)

(test parse-markdown-to-ir-detects-core-blocks
  (let* ((doc (format nil "# Title~%~%- one~%hello~%```~%(+ 1 2)~%```"))
         (ir (cl-claw.markdown:parse-markdown-to-ir doc)))
    (is (= 5 (length ir)))
    (is (eq :heading (getf (first ir) :type)))
    (is (eq :bullet (getf (third ir) :type)))
    (is (eq :paragraph (getf (fourth ir) :type)))
    (is (eq :code (getf (fifth ir) :type)))))

(test contains-markdown-table-p-detects-pipes
  (is-true (cl-claw.markdown:contains-markdown-table-p (format nil "| a | b |~%|---|---|~%|1|2|")))
  (is-false (cl-claw.markdown:contains-markdown-table-p (format nil "- a~%- b"))))

(test normalize-markdown-for-whatsapp-flattens-tables
  (let ((normalized (cl-claw.markdown:normalize-markdown-for-whatsapp
                     (format nil "| key | value |~%|---|---|~%| a | b |~%para"))))
    (is (search "-   key   value" normalized))
    (is (search "-   a   b" normalized))
    (is (search "para" normalized))))

(test render-for-whatsapp-bolds-headings
  (let ((rendered (cl-claw.markdown:render-for-whatsapp (format nil "# Hello~%- one~%para"))))
    (is (search "*Hello*" rendered))
    (is (search "- one" rendered))
    (is (search "para" rendered))))
