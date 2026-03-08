;;;; FiveAM tests for media helpers

(defpackage :cl-claw.media.test
  (:use :cl :fiveam))

(in-package :cl-claw.media.test)

(declaim (optimize (safety 3) (debug 3)))

(def-suite media-suite
  :description "Tests for mime inference, URL policy, and media storage")

(in-suite media-suite)

(test infer-mime-type-by-extension
  (is (string= "image/png" (cl-claw.media:infer-mime-type "x.png")))
  (is (string= "audio/mpeg" (cl-claw.media:infer-mime-type "x.mp3")))
  (is (string= "application/octet-stream" (cl-claw.media:infer-mime-type "x.unknown"))))

(test infer-media-kind-by-mime
  (is (eq :image (cl-claw.media:infer-media-kind "image/png")))
  (is (eq :audio (cl-claw.media:infer-media-kind "audio/mpeg")))
  (is (eq :video (cl-claw.media:infer-media-kind "video/mp4")))
  (is (eq :document (cl-claw.media:infer-media-kind "application/pdf")))
  (is (eq :file (cl-claw.media:infer-media-kind "application/octet-stream"))))

(test allowed-media-url-policy
  (is-true (cl-claw.media:allowed-media-url-p "https://example.com/a.png"))
  (is-true (cl-claw.media:allowed-media-url-p "http://example.com/a.png"))
  (is-false (cl-claw.media:allowed-media-url-p "file:///etc/passwd"))
  (is-false (cl-claw.media:allowed-media-url-p "data:text/plain,hi")))

(test media-storage-filename-is-stable
  (let ((a (cl-claw.media:media-storage-filename "voice.mp3" "audio/mpeg"))
        (b (cl-claw.media:media-storage-filename "voice.mp3" "audio/mpeg"))
        (c (cl-claw.media:media-storage-filename "voice.mp3" "audio/wav")))
    (is (string= a b))
    (is-false (string= a c))
    (is (search ".mp3" a))))

(test store-media-bytes-writes-binary-data
  (let* ((tmp-root (merge-pathnames (format nil "cl-claw-media-~a/" (gensym "T"))
                                    (uiop:ensure-directory-pathname "/tmp")))
         (bytes (make-array 4 :element-type '(unsigned-byte 8)
                              :initial-contents '(1 2 3 4))))
    (uiop:ensure-all-directories-exist (list tmp-root))
    (unwind-protect
         (let* ((path (cl-claw.media:store-media-bytes (namestring tmp-root) bytes "x.bin"))
                (read-back (make-array 4 :element-type '(unsigned-byte 8))))
           (with-open-file (in path :direction :input :element-type '(unsigned-byte 8))
             (read-sequence read-back in))
           (is (equalp bytes read-back)))
      (uiop:delete-directory-tree tmp-root :validate t :if-does-not-exist :ignore))))
