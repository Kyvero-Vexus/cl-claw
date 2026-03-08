;;;; core.lisp — media mime inference and local storage helpers

(defpackage :cl-claw.media
  (:use :cl)
  (:export
   :infer-mime-type
   :infer-media-kind
   :allowed-media-url-p
   :media-storage-filename
   :store-media-bytes))

(in-package :cl-claw.media)

(declaim (optimize (safety 3) (debug 3)))

(defparameter *mime-by-extension*
  '(("png" . "image/png")
    ("jpg" . "image/jpeg")
    ("jpeg" . "image/jpeg")
    ("gif" . "image/gif")
    ("webp" . "image/webp")
    ("mp3" . "audio/mpeg")
    ("wav" . "audio/wav")
    ("ogg" . "audio/ogg")
    ("m4a" . "audio/mp4")
    ("mp4" . "video/mp4")
    ("pdf" . "application/pdf")
    ("json" . "application/json")
    ("txt" . "text/plain"))
  "Association list mapping extension strings to mime strings.")

(declaim (ftype (function (string) (or string null)) extension-of))
(defun extension-of (path)
  (declare (type string path))
  (let ((dot (position #\. path :from-end t)))
    (declare (type (or fixnum null) dot))
    (when (and dot (< dot (1- (length path))))
      (string-downcase (subseq path (1+ dot))))))

(declaim (ftype (function (string &optional (or string null)) string) infer-mime-type))
(defun infer-mime-type (path &optional declared-mime)
  (declare (type string path)
           (type (or string null) declared-mime))
  (cond
    ((and declared-mime (not (string= declared-mime ""))) declared-mime)
    (t
     (let* ((ext (or (extension-of path) ""))
            (pair (assoc ext *mime-by-extension* :test #'string=))
            (mapped (and pair (cdr pair))))
       (declare (type string ext)
                (type t pair mapped))
       (if (stringp mapped) mapped "application/octet-stream")))))

(declaim (ftype (function (string) keyword) infer-media-kind))
(defun infer-media-kind (mime)
  (declare (type string mime))
  (cond
    ((uiop:string-prefix-p "image/" mime) :image)
    ((uiop:string-prefix-p "audio/" mime) :audio)
    ((uiop:string-prefix-p "video/" mime) :video)
    ((string= mime "application/pdf") :document)
    (t :file)))

(declaim (ftype (function (string) boolean) allowed-media-url-p))
(defun allowed-media-url-p (url)
  (declare (type string url))
  (or (uiop:string-prefix-p "https://" url)
      (uiop:string-prefix-p "http://" url)))

(declaim (ftype (function (string string) string) media-storage-filename))
(defun media-storage-filename (original-name mime)
  (declare (type string original-name mime))
  (let* ((seed (format nil "~a|~a" original-name mime))
         (bytes (sb-ext:string-to-octets seed :external-format :utf-8))
         (digest (ironclad:byte-array-to-hex-string (ironclad:digest-sequence :sha1 bytes)))
         (ext (or (extension-of original-name)
                  (extension-of mime)
                  "bin")))
    (declare (type (simple-array (unsigned-byte 8) (*)) bytes)
             (type string digest ext))
    (format nil "~a.~a" digest ext)))

(declaim (ftype (function (string (simple-array (unsigned-byte 8) (*)) string) string)
                store-media-bytes))
(defun store-media-bytes (media-dir bytes filename)
  (declare (type string media-dir filename)
           (type (simple-array (unsigned-byte 8) (*)) bytes))
  (let* ((dir (uiop:ensure-directory-pathname media-dir))
         (path (merge-pathnames filename dir)))
    (uiop:ensure-all-directories-exist (list path))
    (with-open-file (out path :direction :output :if-exists :supersede
                              :if-does-not-exist :create
                              :element-type '(unsigned-byte 8))
      (write-sequence bytes out))
    (namestring path)))
