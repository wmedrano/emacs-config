;;; project-monorepo.el --- Monorepo project backend -*- lexical-binding: t; -*-
;; Package-Requires: ((emacs "30.1"))
;;; Commentary:
;;; Project detection backends for monorepos where project-try-vc
;;; scopes too broadly.
;;; Code:

(require 'cl-lib)
(require 'project)
(require 'subr-x)

(defcustom monorepo-project-use-cached-files t
  "When non-nil, `project-files' returns the cached file list.
When nil, files are re-scanned on every call and the cache slot
is cleared."
  :type 'boolean
  :group 'monorepo-project)

(defcustom monorepo-project-enter-hook nil
  "Hook run when entering a monorepo project for the first time.
Functions receive no arguments — call `project-current' if you
need the project struct.  This fires only on project creation,
not on subsequent cache hits."
  :type 'hook
  :group 'monorepo-project)


(defvar monorepo-project-root nil
  "The root of the monorepo. Should usually be set with a .dir-locals.el file.")

(defvar monorepo-project-subdirs nil
  "List of subdirectory paths (relative to the monorepo root) to track files under.")

(defvar monorepo-project-cache (make-hash-table :test 'equal)
  "Cache mapping expanded root directories to `monorepo-project' structs.")

(cl-defstruct monorepo-project
  root
  (cached-files nil))

(defun monorepo-project--do-find-files (root subdirectories)
  "Find all files under SUBDIRECTORIES in ROOT.

Returns a list of absolute file paths."
  (let ((default-directory root))
    (mapcar (lambda (f) (file-name-concat root f))
            (apply #'process-lines "find"
                   (append subdirectories '("-type" "f"))))))

(cl-defmethod project-root ((project monorepo-project))
  "Return the root directory of the monorepo project."
  (monorepo-project-root project))

(defun monorepo-project-populate-cached-files (&optional project)
  "Populate and return the cached file list for PROJECT.

Files are collected from all `monorepo-project-subdirs'."
  (let ((project (or project (project-current))))
    (unless (monorepo-project-p project)
      (error "Not a monorepo project: %S" project))
    (unless monorepo-project-subdirs
      (error "monorepo-project-subdirs not set"))
    (let ((files (monorepo-project--do-find-files
                   (monorepo-project-root project)
                   monorepo-project-subdirs)))
      (setf (monorepo-project-cached-files project) files)
      files)))

(cl-defmethod project-files ((project monorepo-project) &optional dirs)
  "Return the list of files in PROJECT.

Uses the cache if populated and `monorepo-project-use-cached-files'
is non-nil, otherwise rescans and clears the cache slot."
  (if monorepo-project-use-cached-files
      (or (monorepo-project-cached-files project)
          (monorepo-project-populate-cached-files project))
    (prog1 (monorepo-project-populate-cached-files project)
      (setf (monorepo-project-cached-files project) nil))))

(defun project-try-monorepo (_dir)
  "Detect a monorepo project using `monorepo-project-root'.

If `monorepo-project-root' is non-nil (typically set via .dir-locals.el), return
a project instance with that root."
  (when monorepo-project-root
    ;; `expand-file-name' resolves a relative root against _DIR
    ;; (the directory project was invoked from), matching how
    ;; .dir-locals.el paths work.
    (let ((root (expand-file-name monorepo-project-root)))
      (when (file-directory-p root)
        (or (gethash root monorepo-project-cache)
            (let ((proj (make-monorepo-project :root root)))
              (puthash root proj monorepo-project-cache)
              (run-hooks 'monorepo-project-enter-hook)
              proj))))))

(add-to-list 'project-find-functions #'project-try-monorepo)

;;;###autoload
(defun monorepo-project-clear-cache ()
  "Clear the monorepo project cache.

After calling this, subsequent `project-files' calls will re-scan the
filesystem."
  (interactive)
  (clrhash monorepo-project-cache))

(provide 'project-monorepo)
;;; project-monorepo.el ends here
