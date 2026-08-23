;;; jj-describe.el --- Edit jj change descriptions -*- lexical-binding: t -*-

;; Package-Requires: ((emacs "30") (markdown-mode "2.0"))

;; Author: Will Medrano <wmedrano@wmedrano.dev>

;;; Commentary:
;;
;; This file provides `jj-describe', which edits jj change
;; descriptions in a `markdown-mode' buffer.

;;; Code:

(require 'jj)
(require 'jj-diff)
(require 'markdown-mode)

(defvar-local jj--describe-revision nil
  "Change id of the revision whose description is being edited.

Buffer-local in `jj-describe-mode' buffers.")
(put 'jj--describe-revision 'permanent-local t)

(define-derived-mode jj-describe-mode markdown-mode "jj-describe"
  "Major mode for editing a jj change description.

The revision being edited is recorded in the buffer-local variable
`jj--describe-revision'.  `jj-describe-accept' sets the new
description on the change and kills the buffer.  `jj-describe-reject'
discards the edit and kills the buffer."
  (font-lock-add-keywords nil '(("^JJ:.*" . font-lock-comment-face))))

(define-key jj-describe-mode-map (kbd "C-c C-c") #'jj-describe-accept)
(define-key jj-describe-mode-map (kbd "C-c C-k") #'jj-describe-reject)
(define-key jj-describe-mode-map (kbd "C-c C-d") #'jj-describe-diff)

;;;###autoload
(defun jj-describe (rev)
  "Edit the description of revision REV in a \"*jj-describe*\" buffer.

REV is the revision.  When called interactively, prompt with `completing-read',
defaulting to \"@\"."
  (interactive (list (jj-read-revision "jj describe" "@")))
  (let* (;; TODO: If a jj-describe buffer already exists for `rev', we should
         ;; use that.
         (buffer (jj--with-new-buffer "*jj-describe*"
                   (jj--describe-start rev))))
    (pop-to-buffer buffer)
    buffer))

(defun jj--describe-start (rev)
  "Dump the description of REV into the current buffer.

The description is followed by a comment block prefixed with
\"JJ: \", showing the change id.  `jj-describe-accept'
removes those comment lines before sending the buffer to
`jj describe --stdin'.

Enables `jj-describe-mode' and records the change id parsed
from the buffer in `jj--describe-revision'."
  (let* ((describe-template
          (string-join
           '("description"
             "\"\\n\\n\""
             "\"JJ: Change ID: \""
             "change_id"
             "\"\\n\""
             "\"JJ:\\n\""
             "\"JJ: Lines starting with \\\"JJ:\\\" (like this one) will be removed.\\n\"")
           " ++ "))
         (status
          (apply #'call-process jj-executable nil t nil
                 (append jj-global-args
                         `("log"
                           "-T" ,describe-template
                           "--no-graph" "-r" ,rev)))))
    (unless (zerop status)
      (jj--signal (buffer-string))))
  (goto-char (point-min))
  (if (re-search-forward "^JJ: Change ID: \\([a-z0-9]+\\)" nil t)
      (setq-local jj--describe-revision
                  (match-string-no-properties 1))
    (setq-local jj--describe-revision rev))
  (goto-char (point-min))
  (jj-describe-mode)
  (setq-local
   header-line-format (substitute-command-keys
                       (string-join
                        '("JJ Describe"
                          "Accept (\\[jj-describe-accept])"
                          "Reject (\\[jj-describe-reject])"
                          "Diff (\\[jj-describe-diff])")
                        " | "))))

(defun jj-describe-accept ()
  "Set the buffer's contents as the description of the revision.

- Kills the buffer on success.
- Lines starting with JJ: are trimmed.
- Trailing whitespace is also removed."
  (interactive)
  (unless (derived-mode-p 'jj-describe-mode)
    (user-error "Not in a `jj-describe-mode' buffer"))
  (unless jj--describe-revision
    (user-error "No revision is being described in this buffer"))
  (let ((buffer         (current-buffer))
        (revision       jj--describe-revision)
        (tmp-error-file (make-temp-file "jj-describe-")))
    (unwind-protect
        (unless (zerop (with-temp-buffer
                         (jj--insert-sanitized-describe buffer)
                         (apply #'call-process-region (point-min) (point-max)
                                jj-executable nil
                                (list nil tmp-error-file)
                                nil
                                (append jj-global-args
                                        `("describe" "-r" ,revision "--stdin")))))
          (jj--signal (with-temp-buffer
                                (insert-file-contents tmp-error-file)
                                (buffer-string))))
      (delete-file tmp-error-file))
    (with-current-buffer buffer
      (funcall jj--display-function "Description for %s updated" revision)
      (kill-buffer))))

(defun jj--insert-sanitized-describe (src-buffer)
  "Copy the contents of SRC-BUFFER over to the current buffer and sanitize.

This involves removing lines that start with JJ: and cleaning up some
whitespace."
  (insert-buffer-substring src-buffer)
  (flush-lines "^JJ:" (point-min) (point-max))
  (delete-trailing-whitespace)
  (let ((end (point-max)))
    (goto-char end)
    (skip-chars-backward "\n")
    (unless (= (point) end)
      (delete-region (point) end)))
  (goto-char (point-min))
  (let ((start (point)))
    (skip-chars-forward "\n")
    (unless (= (point) start)
      (delete-region start (point)))))

(defun jj-describe-reject ()
  "Kill the buffer without saving the description."
  (interactive)
  (unless (derived-mode-p 'jj-describe-mode)
    (user-error "Not in a `jj-describe-mode' buffer"))
  (unless jj--describe-revision
    (user-error "No revision is being described in this buffer"))
  (kill-buffer))

(defun jj-describe-diff ()
  "Show the diff of the change being described in the current buffer.

Displays the diff of `jj--describe-revision' using
`jj-diff-at', which pops to a new \"*jj-diff*\" buffer."
  (interactive)
  (unless (derived-mode-p 'jj-describe-mode)
    (user-error "Not in a `jj-describe-mode' buffer"))
  (unless jj--describe-revision
    (user-error "No revision is being described in this buffer"))
  (jj-diff-at jj--describe-revision))

(provide 'jj-describe)
;;; jj-describe.el ends here
