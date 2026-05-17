;;; project-chromium.el --- Chromium monorepo project backend -*- lexical-binding: t; -*-
;;; Commentary:
;;; Project detection backends for monorepos where project-try-vc
;;; scopes too broadly.  Each backend is a finder added to
;;; `project-find-functions' and a struct implementing the
;;; `project-' protocol.
;;; Code:

(require 'project)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Chromium
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(cl-defstruct (chromium-project
               (:copier nil))
  "A Chromium source-tree sub-project.
Slots: `root' (absolute path to source root), `dirs' (sub-dirs relative to root)."
  root
  dirs)

(cl-defmethod project-name ((_ chromium-project))
  "chromium")

(cl-defmethod project-root ((proj chromium-project))
  "Return the Chromium source root."
  (chromium-project-root proj))

(defun chromium-project--files-in-subdir (subdir)
  "Return all regular files under SUBDIR."
  (process-lines "find" subdir "-type" "f"))

(cl-defmethod project-files ((proj chromium-project) &optional _dirs)
  "Return all files across PROJ's configured sub-directories."
  (let ((default-directory (chromium-project-root proj)))
    (apply #'append
           (mapcar #'chromium-project--files-in-subdir
                   (chromium-project-dirs proj)))))

(defun project-try-chromium (dir)
  "Find a Chromium sub-project for DIR.

Detects the Chromium source tree by looking for
\"LICENSE.chromium_os\" as a marker file.  Returns a
`chromium-project' struct scoped to known sub-directories, or nil."
  (when-let* ((marker (locate-dominating-file dir "LICENSE.chromium_os")))
    (make-chromium-project
     :root (file-name-directory (expand-file-name marker))
     :dirs '("third_party/blink/renderer" "net/shared_dictionary"))))

(add-to-list 'project-find-functions #'project-try-chromium)

(provide 'project-chromium)
;;; project-chromium.el ends here