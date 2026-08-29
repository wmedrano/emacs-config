;;; eglot-extra.el --- Extra eglot stuff -*- lexical-binding: t -*-

;; Package-Requires: ((emacs "30"))
;; Version: 0.1.0
;; Keywords: rust

;;; Commentary:
;;
;; This package provides extra eglot stuff.

;;; Code:

(require 'eglot)
(require 'flymake)

;;;###autoload
(define-minor-mode eglot-format-on-save-mode
  "Format eglot buffers on save."
  :lighter nil
  (if eglot-format-on-save-mode
      (add-hook 'before-save-hook
                #'eglot-extra--maybe-format-on-save
                nil
                t)
    (remove-hook 'before-save-hook
                 #'eglot-extra--maybe-format-on-save
                 t)))

(defun eglot-extra--maybe-format-on-save ()
  "Format the current buffer if eglot is enabled."
  (when (and (eglot-managed-p) eglot-format-on-save-mode)
    (eglot-format-buffer)))

;;;###autoload
(defun eglot-autofix-all ()
  "Fix the next error or warning."
  (interactive)
  (dotimes (_ 100)
    (flymake-goto-next-error)
    (call-interactively #'eglot-code-actions)
    (save-buffer)
    (sit-for 0.1)))

;;;###autoload
(defun eglot-extra-disable-inlay-hints ()
  "Disable `eglot-inlay-hints-mode' in the current buffer."
  (interactive)
  (eglot-inlay-hints-mode -1))

(provide 'eglot-extra)
;;; eglot-extra.el ends here
