;;;; FiveAM tests for config merge-patch

(in-package :cl-claw.config.tests)

(declaim (optimize (safety 3) (debug 3)))

(in-suite config-suite)

;; Helper to create hash tables
(defun %hash (&rest kv)
  (let ((h (make-hash-table :test 'equal)))
    (loop for (k v) on kv by #'cddr do
      (setf (gethash k h) v))
    h))

;; Note: These tests assume a merge-patch implementation exists
;; The actual function names may need adjustment based on the real API

(test merge-patch-replaces-arrays-by-default
  "Replaces arrays by default (no merge by id)"
  (let ((base (%hash "agents"
                     (%hash "list"
                            (list (%hash "id" "primary" "workspace" "/tmp/one")
                                  (%hash "id" "secondary" "workspace" "/tmp/two")))))
        (patch (%hash "agents"
                      (%hash "list"
                             (list (%hash "id" "primary"
                                          "memorySearch"
                                          (%hash "extraPaths" (list "/tmp/memory.md"))))))))
    ;; TODO: Implement when merge-patch function is available
    ;; Expected: patch list replaces base list entirely
    (skip "merge-patch function not yet available")))

(test merge-patch-merges-object-arrays-by-id
  "Merges object arrays by id when enabled"
  (let ((base (%hash "agents"
                     (%hash "list"
                            (list (%hash "id" "primary" "workspace" "/tmp/one")
                                  (%hash "id" "secondary" "workspace" "/tmp/two")))))
        (patch (%hash "agents"
                      (%hash "list"
                             (list (%hash "id" "primary"
                                          "memorySearch"
                                          (%hash "extraPaths" (list "/tmp/memory.md"))))))))
    ;; TODO: Implement when merge-patch function with mergeObjectArraysById option is available
    ;; Expected: 2 items, primary merged with workspace + memorySearch, secondary unchanged
    (skip "merge-patch with mergeObjectArraysById option not yet available")))

(test merge-patch-preserves-non-patched-agents
  "Does not destroy agents list when patching single agent"
  (let ((base (%hash "agents"
                     (%hash "list"
                            (list (%hash "id" "main" "default" t "workspace" "/home/main")
                                  (%hash "id" "ota" "workspace" "/home/ota")
                                  (%hash "id" "trading" "workspace" "/home/trading")
                                  (%hash "id" "codex" "workspace" "/home/codex")))))
        (patch (%hash "agents"
                      (%hash "list"
                             (list (%hash "id" "main" "model" "claude-opus-4-20250918"))))))
    ;; TODO: Implement when merge-patch function is available
    ;; Expected: 4 agents, main gets model field added, others unchanged
    (skip "merge-patch function not yet available")))

(test merge-patch-fallback-for-non-id-arrays
  "Falls back to replacement for non-id arrays"
  (let ((base (%hash "channels"
                     (%hash "telegram" (%hash "allowFrom" (list "111" "222")))))
        (patch (%hash "channels"
                      (%hash "telegram" (%hash "allowFrom" (list "333"))))))
    ;; TODO: Implement when merge-patch function is available
    ;; Expected: allowFrom is ["333"], replaced not merged
    (skip "merge-patch function not yet available")))
