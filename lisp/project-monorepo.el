;;; project-monorepo.el --- Monorepo-aware project detection -*- lexical-binding: t; -*-

;; Author: wmedrano
;; Version: 0.3.0
;; Package-Requires: ((emacs "28.1"))

;;; Commentary:
;; In a monorepo, `project-try-vc' resolves the entire git repo as one
;; project.  This makes `project-files', `consult-project-buffer',
;; `project-find-regexp', etc. scan every sub-project — painfully slow
;; and noisy.
;;
;; This package defines an explicit monorepo project type registered in
;; `project-find-functions'.  Instead of heuristic marker-file detection,
;; the user configures monorepo roots and their sub-project directories
;; directly via `project-monorepo-configs'.
;;
;; Usage:
;;
;;   (setq project-monorepo-configs
;;         (list (project-monorepo-create
;;                :root "~/repo/my-workspace"
;;                :subdirs '("~/repo/my-workspace/crates/foo"
;;                           "~/repo/my-workspace/crates/bar"))
;;               (project-monorepo-create
;;                :root "~/repo/other-monorepo"
;;                :subdirs '("~/repo/other-monorepo/services/api"))))

;;; Code:

;;;; Data Structures

(cl-defstruct (project-monorepo
               (:constructor project-monorepo-create)
               (:copier nil))
  "A monorepo project with sub-project scoping."
  root       ; absolute directory — the sub-project boundary
  subdirs)   ; list of absolute directories — all sub-project roots

;;;; Configuration

(defcustom project-monorepo-configs nil
  "List of project-monorepo structs describing known monorepos.
Each entry has a `root' (monorepo root) and `subdirs' (list of
sub-project directories).  Relative paths are expanded automatically."
  :type '(repeat (list :tag "Monorepo"
                       (directory :tag "Monorepo root")
                       (repeat :tag "Subdirectories" (directory :tag "Subdirectory"))))
  :group 'project)

;;;; Finder Function

(defun project-monorepo-try-find (dir)
  "Find a sub-project inside a monorepo for DIR.
Return a `project-monorepo' struct, or nil."
  (let* ((dir-expanded (expand-file-name dir))
         (dir-as-dir (file-name-as-directory dir-expanded))
         best-config
         best-project)
    ;; Find the most specific (longest root) matching config
    (dolist (cfg project-monorepo-configs)
      (let* ((root (expand-file-name (project-monorepo-root cfg)))
             (root-as-dir (file-name-as-directory root)))
        (when (string-prefix-p root-as-dir dir-as-dir)
          ;; Only consider this config if it is more specific than the current best
          (when (or (null best-config)
                    (> (length root) (length (expand-file-name (project-monorepo-root best-config)))))
            ;; Find the longest matching subdirectory within this config
            (let (match-project)
              (dolist (proj (project-monorepo-subdirs cfg))
                (let ((proj-expanded (expand-file-name proj)))
                  (when (and (string-prefix-p (file-name-as-directory proj-expanded) dir-as-dir)
                             (or (null match-project)
                                 (> (length proj-expanded) (length match-project))))
                    (setq match-project proj-expanded))))
              (when match-project
                (setq best-config cfg
                      best-project match-project)))))))
    (when best-config
      (project-monorepo-create
       :root best-project
       :subdirs (mapcar #'expand-file-name (project-monorepo-subdirs best-config))))))

;;;###autoload
(add-hook 'project-find-functions #'project-monorepo-try-find)

;;;; project- Protocol Methods

(cl-defmethod project-root ((proj project-monorepo))
  "Return the root directory of PROJ's matched sub-project."
  (project-monorepo-root proj))

(cl-defmethod project-files ((proj project-monorepo) &optional dirs)
  "Return a list of files in PROJ, scoped to the sub-project root.
DIRS is an optional list of directories to limit the search."
  (let ((default-directory (project-root proj)))
    (project--files-in-directory default-directory
                                  (project-ignores proj default-directory))))

(provide 'project-monorepo)

;;; project-monorepo.el ends here