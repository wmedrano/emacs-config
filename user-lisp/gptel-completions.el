;;; gptel-completions.el --- Completions for gptel -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "30") (gptel "0.9.9"))
;; Version: 0.1.0
;; Keywords: convenience, ai

;;; Commentary:
;;
;; Completions used while composing prompts in gptel buffers.
;;
;; Enable `gptel-completions-mode' from `init.el', for example:
;;
;;   (require 'gptel-completions)
;;   (add-hook 'gptel-mode-hook #'gptel-completions-mode)
;;
;; Typing @ prompts for a file in the current project and inserts its path
;; relative to the project.  Cancel with C-g to insert just @.

;;; Code:

(require 'project)

(defun gptel-completions-insert-reference ()
  "Prompt for a project file and insert its project-relative path.
If the prompt is canceled with C-g, leave just @.  When there is no
current project or it has no files, insert @ without prompting."
  (interactive)
  (barf-if-buffer-read-only)
  (let ((start (point)))
    (insert "@")
    (condition-case nil
        (when-let* ((project (project-current))
                    (files (project-files project)))
          (let ((file (completing-read "Project file: " files nil t)))
            (delete-region start (point))
            (insert (file-relative-name file (project-root project)))))
      (quit nil))))

(defvar gptel-completions-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "@") #'gptel-completions-insert-reference)
    map)
  "Keymap for `gptel-completions-mode'.")

;;;###autoload
(define-minor-mode gptel-completions-mode
  "Enable completions for references in a gptel buffer.

Typing @ prompts for a file in the current project and inserts its path
relative to the project.  Cancel with C-g to insert a literal @.  This is a
buffer-local minor mode intended to be enabled from `gptel-mode-hook'."
  :lighter nil
  :keymap gptel-completions-mode-map)

(provide 'gptel-completions)
;;; gptel-completions.el ends here
