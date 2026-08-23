;;; monorepo.el --- Monorepo project backend -*- lexical-binding: t; -*-
;; Package-Requires: ((emacs "30.1"))
;;; Commentary:
;;; Project detection backends for monorepos where project-try-vc scopes too
;;; broadly.
;;; Code:

(require 'cl-lib)
(require 'project)
(require 'subr-x)

(cl-defstruct monorepo
  root
  directories)

;;;###autoload
(defun project-try-monorepo (dir)
  "Return the `monorepo' project at DIR or nil if there is none."
  (when-let* ((root (locate-dominating-file dir ".monorepo")))
    (monorepo--from-config-file root
                                (expand-file-name ".monorepo" root))))

(defun monorepo--from-config-file (root config-path)
  "Get the `monorepo' struct from the .monorepo config.

ROOT - The root of the monorepo project.
CONFIG-PATH - The path to the .monorepo config."
  (let ((directories))
    (with-temp-buffer
      (insert-file-contents config-path)
      (goto-char (point-min))
      (while (not (eobp))
        (let* ((line (buffer-substring-no-properties (line-beginning-position)
                                                     (line-end-position)))
               (trimmed (string-trim line)))
          (unless (string-empty-p trimmed)
            (push trimmed directories)))
        (forward-line 1)))
    (make-monorepo
     :root root
     :directories directories)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; project methods
;; Methods not covered
;; project-name - The default is ok
;; project-buffers - The default is ok
;; project-external-roots - List of directories outside of the project. Maybe we
;;   should use this for the subdirectories.
;; project-ignores (project dir) - Glob patterns to ignore. Not sure how this is
;;   used. Our project-files function is good enough for now.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(cl-defmethod project-root ((project monorepo))
  "Get the project root for PROJECT."
  (monorepo-root project))

(cl-defmethod project-files ((project monorepo) &optional _dirs)
  "Get the files inside of PROJECT.

_DIRS - _DIRS is ignored.  TODO: We should only return files under
_DIRS."
  (let* ((default-directory (monorepo-root project))
         (dirs              (cl-remove-if-not #'file-directory-p
                                              (monorepo-directories project)))
         (find-args         (append dirs '("-type" "f")))
         (files             (cons ".monorepo"
                                  (apply #'process-lines "find" find-args))))
    (mapcar (lambda (f) (expand-file-name f default-directory))
            files)))

(provide 'monorepo)
;;; monorepo.el ends here
