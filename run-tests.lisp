(require :asdf)
;; Load Quicklisp if available (needed for cl-ppcre etc. under --script)
(let ((ql-setup (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname))))
  (when (probe-file ql-setup) (load ql-setup)))
;; Muffle style warnings
(handler-bind ((style-warning #'muffle-warning))
  (asdf:load-system :cl-claw-tests))
(asdf:test-system :cl-claw-tests)
(sb-ext:exit)
