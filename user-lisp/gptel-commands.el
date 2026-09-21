;;; gptel-commands.el --- Extra commands for gptel -*- lexical-binding: t; -*-

;;; Commentary:

;;; Code:

(require 'gptel)

;;;###autoload
(defun gptel-shell-insert (command)
  "Insert COMMAND as a bash source block in the current buffer."
  (interactive "sShell command: ")
  (insert (format "#+begin_src bash\n%s\n#+end_src\n" command)))

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
