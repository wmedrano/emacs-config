;;; jj.el --- Jujutsu VCS integration -*- lexical-binding: t -*-

;; Author: wmedrano
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: vc
;; URL: https://github.com/wmedrano/jj.el

;;; Commentary:

;; Jujutsu VCS integration for Emacs.

;;; Code:

(require 'diff-mode)
(require 'markdown-mode)
(require 'subr-x)

(defgroup jj nil
  "jj VCS integration."
  :group 'vc)

(defcustom jj-edit-show-log t
  "When non-nil, show jj log in a side window during `jj-edit'."
  :type 'boolean
  :group 'jj)

(defvar-local jj--diff-args nil
  "Stored arguments for the current jj-diff buffer.")


(defun jj--root ()
  "Return the root directory of the current jj repository."
  (file-name-as-directory (jj--call-to-string "root")))

(defun jj--call-to-string (&rest args)
  "Run jj with ARGS and return its trimmed output."
  (with-temp-buffer
    (let ((exit-code (apply #'call-process "jj" nil t nil args)))
      (unless (zerop exit-code)
        (user-error "jj %s failed (exit %d): %s"
                    (string-join args " ")
                    exit-code
                    (string-trim (buffer-string))))
      (string-trim (buffer-string)))))

(defun jj--call-buffer (buffer &rest args)
  "Run jj with ARGS, writing output to BUFFER.
Signal a `user-error' if jj exits unsuccessfully."
  (let ((exit-code (apply #'call-process "jj" nil buffer nil args)))
    (unless (zerop exit-code)
      (with-current-buffer buffer
        (user-error "jj %s failed (exit %d): %s"
                    (string-join args " ")
                    exit-code
                    (string-trim (buffer-string)))))))

(defun jj--call-region (start end buffer &rest args)
  "Run jj with ARGS using region START to END as stdin.
Write output to BUFFER and signal a `user-error' on failure."
  (let ((exit-code (apply #'call-process-region start end "jj" nil buffer nil args)))
    (unless (zerop exit-code)
      (with-current-buffer buffer
        (user-error "jj %s failed (exit %d): %s"
                    (string-join args " ")
                    exit-code
                    (string-trim (buffer-string)))))))

(defmacro jj--with-root (&rest body)
  "Evaluate BODY with `default-directory' set to the jj repository root."
  `(let ((default-directory (jj--root)))
     ,@body))

(defun jj--show-diff (&rest args)
  "Show jj diff output in a buffer, passing ARGS to the jj diff command."
  (jj--with-root
   (let ((working-dir default-directory)
         (buf         (get-buffer-create "*jj-diff*")))
     (with-current-buffer buf
       (setq-local default-directory working-dir)
       (let ((inhibit-read-only t))
         (erase-buffer)
         (setq-local jj--diff-args args)
         (apply #'jj--call-buffer buf "diff" "--git" args)
         (jj-diff-mode)
         (goto-char (point-min))
         (read-only-mode t)))
     (pop-to-buffer buf))))

(defun jj--revert-diff-buffer (&optional _ignore-auto _noconfirm)
  "Revert the jj-diff buffer by re-running jj diff with stored args."
  (let ((args jj--diff-args))
    (let ((inhibit-read-only t))
      (erase-buffer)
      (apply #'jj--call-buffer (current-buffer) "diff" "--git" args)
      (goto-char (point-min))))
  (message "jj diff: reloaded"))

(define-derived-mode jj-diff-mode diff-mode "jj-diff"
  "Major mode for viewing jj diff output.
\\{jj-diff-mode-map}"
  (setq-local revert-buffer-function #'jj--revert-diff-buffer))

(define-key jj-diff-mode-map (kbd "g") #'revert-buffer)

;;;###autoload
(defun jj-diff (&rest args)
  "Show jj diff output. ARGS are passed to `jj diff --git'."
  (interactive)
  (apply #'jj--show-diff args))

(defconst jj-status--font-lock-keywords
  `(;; Modified/Added/Deleted file status indicators
    ("^[MAD] " . 'font-lock-warning-face)
    ;; Change IDs and commit IDs (8+ lowercase hex chars)
    ("[0-9a-f]\\{8,\\}" . 'font-lock-constant-face)
    ;; Working copy / Parent commit labels
    ("^\\(Working copy\\|Parent commit\\)" . 'font-lock-keyword-face)
    ;; Revset expressions like (@) and (@-)
    ("(@[^)]*)" . 'font-lock-type-face)))

(define-derived-mode jj-status-mode special-mode "jj-status"
  "Major mode for viewing jj status output."
  (setq font-lock-defaults '(jj-status--font-lock-keywords t))
  (font-lock-mode 1))

(define-key jj-status-mode-map (kbd "g") #'jj-status)

;;;###autoload
(defun jj-status ()
  "Show the current jj status in a buffer."
  (interactive)
  (jj--with-root
   (let ((buf (get-buffer-create "*jj-status*")))
     (with-current-buffer buf
       (let ((inhibit-read-only t))
         (erase-buffer)
         (jj--call-buffer buf "st")
         (goto-char (point-min))))
     (with-current-buffer buf
       (jj-status-mode))
     (pop-to-buffer buf))))

(defun jj--show-log-side-window ()
  "Display the jj log buffer in a bottom side window."
  (jj--log-buffer)
  (let ((win (display-buffer "*jj-log*"
                             '(display-buffer-in-side-window
                               (side . bottom)
                               (window-height . 0.3)))))
    (let* ((max-height (floor (* 0.3 (frame-height))))
           (buf-lines (with-current-buffer (window-buffer win)
                        (count-lines (point-min) (point-max)))))
      (set-window-text-height win (min (1+ buf-lines) max-height)))))

(defun jj--hide-log-side-window ()
  "Delete the jj log side window if it exists."
  (when-let ((win (get-buffer-window "*jj-log*")))
    (delete-window win)))

(defun jj--revsets ()
  "Return a list of change IDs from the jj log."
  (jj--with-root
   (let ((output (jj--call-to-string
                  "log" "--no-graph" "-T"
                  "change_id.short() ++ \" \" ++ description.first_line() ++ \"\\n\"")))
     (split-string output "\n" t))))

(defun jj--current-revset ()
  "Return the short change ID of the current working copy revision."
  (jj--call-to-string "log" "--no-graph" "-T" "change_id.short()" "-r" "@"))

(defun jj--read-revset ()
  "Prompt for a revset, optionally showing the log side window."
  (when jj-edit-show-log (jj--show-log-side-window))
  (unwind-protect
      (let* ((candidates (jj--revsets))
             (choice (completing-read "Revset (empty for @): " (cons "" candidates) nil nil nil)))
        (if (string-empty-p choice)
            (jj--current-revset)
          (car (split-string choice " " t))))
    (when jj-edit-show-log (jj--hide-log-side-window))))

;;;###autoload
(defun jj-edit (revset)
  "Set REVSET as the working-copy revision using `jj edit'."
  (interactive (list (jj--read-revset)))
  (jj--with-root
   (let ((buf (get-buffer-create "*jj*")))
     (with-current-buffer buf
       (let ((inhibit-read-only t))
         (erase-buffer)
         (jj--call-buffer buf "edit" revset)
         (goto-char (point-min))))
     (display-buffer buf))))

;;;###autoload
(defun jj-new (revset)
  "Create a new change with REVSET as parent using `jj new'.
Defaults to \"@\" (current revision).  With a prefix argument, prompt for REVSET."
  (interactive (list (jj--read-revset)))
  (jj--with-root
   (let ((buf (get-buffer-create "*jj*")))
     (with-current-buffer buf
       (let ((inhibit-read-only t))
         (erase-buffer)
         (jj--call-buffer buf "new" revset)
         (goto-char (point-min))))
     (display-buffer buf))))

(defcustom jj-describe-diff-on-exit 'bury
  "What to do with the diff buffer when accepting or rejecting a describe edit.
- `nil'  do nothing
- `bury' hide the window and bury the buffer
- `kill' delete the window and kill the buffer"
  :type '(choice (const :tag "Do nothing" nil)
                 (const :tag "Bury" bury)
                 (const :tag "Kill" kill))
  :group 'jj)

(defvar-local jj--describe-revset nil
  "The revset being described in this jj-describe buffer.")

(defvar-local jj--describe-diff-spawned nil
  "Non-nil if a diff buffer was spawned from this jj-describe buffer.")

(define-derived-mode jj-describe-mode markdown-mode "jj-describe"
  "Major mode for editing jj change descriptions."
  (setq-local header-line-format
              (substitute-command-keys
               "Confirm: \\[jj--describe-accept]  Diff: \\[jj--describe-diff]  Abort: \\[jj--describe-reject]")))

(define-key jj-describe-mode-map (kbd "C-c C-c") #'jj--describe-accept)
(define-key jj-describe-mode-map (kbd "C-c C-d") #'jj--describe-diff)
(define-key jj-describe-mode-map (kbd "C-c C-k") #'jj--describe-reject)

;;;###autoload
(defun jj-describe (revset)
  "Edit the description of REVSET using `jj describe'."
  (interactive (list (jj--read-revset)))
  (let ((buf (get-buffer-create "*jj-describe*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (jj--with-root
         (jj--call-buffer buf "log" "--no-graph" "-T" "description" "-r" revset)
         (insert "\n\nJJ: Lines prefixed with JJ: are ignored\n")
         (let ((diff-start (point)))
           (jj--call-buffer buf "diff" "--stat" "-r" revset)
           (save-excursion
             (goto-char diff-start)
             (while (not (eobp))
               (insert "JJ: ")
               (forward-line 1)))))
        (jj-describe-mode)
        (setq-local jj--describe-revset revset)
        (goto-char (point-min))))
    (pop-to-buffer buf)))

(defun jj--display-transient (buf &optional seconds)
  "Display BUF in a bottom side window, then kill it after SECONDS (default 3)."
  (display-buffer buf '(display-buffer-in-side-window
                        (side . bottom)
                        (window-height . 0.2)))
  (run-with-timer (or seconds 3) nil
                  (lambda ()
                    (when (buffer-live-p buf)
                      (when-let ((win (get-buffer-window buf)))
                        (delete-window win))
                      (kill-buffer buf)))))

(defun jj--describe-cleanup ()
  "Clean up describe and optionally the diff buffer per `jj-describe-diff-on-exit'."
  (when-let (((and jj-describe-diff-on-exit jj--describe-diff-spawned))
             (diff-buf (get-buffer "*jj-diff*")))
    (when-let ((win (get-buffer-window diff-buf)))
      (delete-window win))
    (pcase jj-describe-diff-on-exit
      ('bury (bury-buffer diff-buf))
      ('kill (kill-buffer diff-buf))))
  (kill-buffer))

(defun jj--describe-accept ()
  "Apply the buffer contents as the description for `jj--describe-revset'."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (flush-lines "^JJ:")
    (delete-trailing-whitespace))
  (let ((revset jj--describe-revset)
        (msg (buffer-string))
        (root (jj--root)))
    (let ((buf (get-buffer-create "*jj*")))
      (with-current-buffer buf
        (let ((inhibit-read-only t))
          (erase-buffer)
          (let ((default-directory root))
            (with-temp-buffer
              (insert msg)
              (jj--call-region (point-min) (point-max) buf
                               "describe" "--stdin" revset)))
          (goto-char (point-min))))
      (jj--display-transient buf))
    (jj--describe-cleanup)))

(defun jj--describe-reject ()
  "Abort the jj describe edit by killing the buffer."
  (interactive)
  (jj--describe-cleanup))

(defun jj--describe-diff ()
  "Show the diff for the revision being described."
  (interactive)
  (setq-local jj--describe-diff-spawned t)
  (jj--show-diff "-r" jj--describe-revset))

(defconst jj-log--font-lock-keywords
  `(;; Current commit marker
    ("^@" . 'font-lock-warning-face)
    ;; Change IDs and commit IDs (8+ lowercase hex chars)
    ("[0-9a-f]\\{8,\\}" . 'font-lock-constant-face)
    ;; Email addresses
    ("[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]+" . 'font-lock-type-face)
    ;; Timestamps
    ("[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\} [0-9]\\{2\\}:[0-9]\\{2\\}:[0-9]\\{2\\}" . 'font-lock-comment-face)))

(define-derived-mode jj-log-mode special-mode "jj-log"
  "Major mode for viewing jj log output."
  (setq font-lock-defaults '(jj-log--font-lock-keywords t))
  (font-lock-mode 1))

(define-key jj-log-mode-map (kbd "g") #'jj-log)

(defun jj--log-buffer ()
  "Populate and return the *jj-log* buffer without displaying it."
  (jj--with-root
   (let ((buf (get-buffer-create "*jj-log*")))
     (with-current-buffer buf
       (let ((inhibit-read-only t))
         (erase-buffer)
         (jj--call-buffer buf "log")
         (goto-char (point-min)))
       (jj-log-mode))
     buf)))

;;;###autoload
(defun jj-log ()
  "Show the jj log in a buffer using `jj-log-mode'."
  (interactive)
  (pop-to-buffer (jj--log-buffer)))

;;;###autoload
(defun jj-git-push ()
  "Run `jj git push'"
  (interactive)
  (message "Running jj git push")
  (async-shell-command "jj git push"))

(provide 'jj)

;;; jj.el ends here
