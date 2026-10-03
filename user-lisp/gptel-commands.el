;;; gptel-commands.el --- Extra commands for gptel -*- lexical-binding: t; -*-

;;; Commentary:

;;; Code:

(require 'gptel)
(require 'ob-core)

(defvar gptel-commands-backends nil
  "Alist of gptel backends available for selection.
Each entry has the form (NAME . BACKEND), where NAME is the name
offered during completion and BACKEND is a gptel backend object.
Configure this alist in the `use-package gptel-commands'
declaration.")

;;;###autoload
(defun gptel-commands-set-backend ()
  "Select the current backend from `gptel-commands-backends'.
Keep the current model if supported, otherwise use the first model
advertised by the selected backend."
  (interactive)
  (unless gptel-commands-backends
    (user-error "No gptel backends are configured"))
  (let* ((choices (mapcar (lambda (entry)
                            (cons (format "%s" (car entry)) (cdr entry)))
                          gptel-commands-backends))
         (name (completing-read "gptel backend: " choices nil t nil nil
                                (and gptel-backend
                                     (car (rassq gptel-backend choices)))))
         (backend (cdr (assoc name choices)))
         (models (gptel-backend-models backend)))
    (unless models
      (user-error "Backend %s has no available models" name))
    (setq gptel-backend backend)
    (unless (memq gptel-model models)
      (setq gptel-model (car models)))))

;;;###autoload
(defun gptel-shell-insert (command)
  "Insert COMMAND as a bash source block in the current buffer."
  (interactive "sShell command: ")
  (insert "#+begin_src bash :results output verbatim\n")
  (insert command)
  (insert "\n#+end_src\n")
  (forward-line -2)
  (let ((org-confirm-babel-evaluate nil))
    (org-babel-execute-src-block))
  (goto-char (point-max)))

;;;###autoload
(defun gptel-submit ()
  "Go to the end of the buffer and send the gptel prompt."
  (interactive)
  (goto-char (point-max))
  (gptel-send))

;;;###autoload
(defun gptel-model ()
  "Select a model from the current gptel backend."
  (interactive)
  (let* ((models (gptel-backend-models gptel-backend))
         (choices (mapcar #'symbol-name models)))
    (unless choices
      (user-error "The current gptel backend has no available models"))
    (setq gptel-model
          (intern (completing-read "gptel model: " choices nil t nil
                                   'gptel-model-history
                                   (and gptel-model
                                        (symbol-name gptel-model)))))))

(provide 'gptel-commands)
;;; gptel-commands.el ends here
