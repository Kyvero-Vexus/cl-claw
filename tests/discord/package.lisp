;;;; package.lisp — Test suite for Discord modules

(defpackage :cl-claw.discord.tests
  (:use :cl :fiveam)
  (:export :run-discord-tests))

(in-package :cl-claw.discord.tests)

(def-suite :cl-claw.discord.tests
  :description "Discord module test suite")

(def-suite :discord-accounts :in :cl-claw.discord.tests)
(def-suite :discord-api :in :cl-claw.discord.tests)
(def-suite :discord-audit :in :cl-claw.discord.tests)
(def-suite :discord-chunk :in :cl-claw.discord.tests)
(def-suite :discord-components :in :cl-claw.discord.tests)
(def-suite :discord-gateway :in :cl-claw.discord.tests)
(def-suite :discord-mentions :in :cl-claw.discord.tests)
(def-suite :discord-monitor :in :cl-claw.discord.tests)
(def-suite :discord-pluralkit :in :cl-claw.discord.tests)
(def-suite :discord-probe :in :cl-claw.discord.tests)
(def-suite :discord-resolve :in :cl-claw.discord.tests)
(def-suite :discord-send :in :cl-claw.discord.tests)
(def-suite :discord-voice :in :cl-claw.discord.tests)

(defun run-discord-tests ()
  (run! :cl-claw.discord.tests))
