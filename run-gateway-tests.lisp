(load "~/quicklisp/setup.lisp")
(push (truename ".") asdf:*central-registry*)
(ql:quickload :cl-claw-tests :silent t)

(format t "~%=== Gateway Server Tests ===~%")
(funcall (find-symbol "RUN!" :fiveam)
         (find-symbol "GATEWAY-SERVER-SUITE" :cl-claw.gateway.server.test))

(format t "~%=== Gateway Auth Tests ===~%")
(funcall (find-symbol "RUN!" :fiveam)
         (find-symbol "GATEWAY-AUTH-SUITE" :cl-claw.gateway.auth.test))

(format t "~%=== Gateway Boot Tests ===~%")
(funcall (find-symbol "RUN!" :fiveam)
         (find-symbol "GATEWAY-BOOT-SUITE" :cl-claw.gateway.boot.test))
