;;; jj.el --- Jujutsu VCS integration -*- lexical-binding: t -*-
;;; Commentary:

;; Jujutsu VCS integration for Emacs.
;;
;; This library provides several interactive commands for working with
;; Jujutsu (jj) repositories from within Emacs:
;;
;;   - `jj-log'         Display the jj log output in a dedicated buffer.
;;   - `jj-diff'        Show a diff for a given revision.
;;   - `jj-diff-from'   Show a diff between two revisions.
;;   - `jj-describe'    Edit a revision's description in a dedicated buffer.
;;   - `jj-edit'        Set a revision as the working-copy revision.
;;   - `jj-new'         Create a new empty change on top of a revision.
;;
;; The non-interactive helpers `jj-root', `jj-call-process', and
;; `jj-call-process-region' can be used to build additional jj-based
;; commands.
;;
;; The library is currently under development and new commands may be
;; added.

;;; Code:

(require 'markdown-mode)

(defgroup jj nil
  "Jujutsu VCS integration."
  :group 'vc)

(defcustom jj-autorevert-repo-buffers nil
  "When non-nil, revert unmodified file-visiting buffers under the jj root.
This happens after commands that change the working copy, such as
`jj-edit' and `jj-new'."
  :type 'boolean
  :group 'jj)

(defun jj-root ()
  "Get the root of the jj repository.

Signals an error if not inside a jj repository."
  (with-temp-buffer
    (unless (eq 0 (call-process "jj" nil t nil "root"
                                "--color" "never"))
      (error "Not inside a jj repository"))
    (string-trim (buffer-string))))

(defmacro with-jj-root (&rest body)
  "Run BODY at the jj root."
  (declare (indent 0) (debug t))
  `(let ((default-directory (jj-root)))
     ,@body))

(defun jj-revision-to-change-id (revision)
  "Convert a REVISION to a change id.

A revision, such as (@) may point to a different change.  The change id should
be more stable."
  (with-temp-buffer
    (unless (eq 0 (call-process "jj" nil t nil "log"
                                "--color" "never"
                                "--no-graph"
                                "-r" revision
                                "-T" "change_id"))
      (error "Not inside a jj repository"))
    (string-trim (buffer-string))))

(defun jj-call-process (command &optional infile destination &rest args)
  "Invoke the jj COMMAND synchronously.
This is a wrapper around `call-process' that runs the jj executable with
`--color' never and `--no-pager'.  COMMAND is the jj subcommand to invoke.
INFILE, DESTINATION, and ARGS have the same meaning as in `call-process'.

Returns the numeric exit status of jj, or a signal description string if
jj is interrupted."
  (apply #'call-process "jj" infile destination nil
         command
         "--color" "never"
         "--no-pager"
         args))

(defun jj-call-process-region (start end command &optional delete buffer &rest args)
  "Send text from START to END to a synchronous jj process.
This is a wrapper around `call-process-region' that runs jj with COMMAND
and adds `--color' never and `--no-pager'.  START, END, DELETE, BUFFER,
and ARGS have the same meaning as in `call-process-region'.

Returns the numeric exit status of jj, or a signal description string if
jj is interrupted."
  (apply #'call-process-region start end "jj"
         delete buffer nil
         command
         "--color" "never"
         "--no-pager"
         args))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; log
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defvar jj-log-font-lock-keywords
  '(
    ;; Graph characters (handles various Unicode drawing characters used by jj)
    ("^\\([ @◆○×│~├─╮╯╰╭]+\\)" 1 'font-lock-keyword-face)
    ;; Change ID (the string of lowercase letters immediately following the graph)
    ("^[ @◆○×│~├─╮╯╰╭]+\\s-+\\([a-z]+\\)\\b" 1 'font-lock-constant-face)
    ;; Author Email
    ("\\b\\([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]\\{2,\\}\\)\\b" 1 'font-lock-string-face)
    ;; Date and Time (YYYY-MM-DD HH:MM:SS)
    ("\\b\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\} [0-9]\\{2\\}:[0-9]\\{2\\}:[0-9]\\{2\\}\\)\\b" 1 'font-lock-type-face)
    ;; Commit Hash (the hex string at the end of a log entry line)
    ("\\b\\([0-9a-f]\\{8,\\}\\)$" 1 'font-lock-comment-face)
    ;; Branches/Bookmarks (Matches text sitting between the timestamp and commit hash)
    ;; E.g., `... 19:22:47 main 39049392` -> matches and highlights `main`
    ("\\b[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\} [0-9]\\{2\\}:[0-9]\\{2\\}:[0-9]\\{2\\}\\s-+\\(.+?\\)\\s-+[0-9a-f]\\{8,\\}$" 1 'font-lock-builtin-face)
    ;; Empty description placeholder
    ("\\((no description set)\\)" 1 'font-lock-doc-face))
  "Highlighting expressions for `jj-log-mode`.")

(define-derived-mode jj-log-mode special-mode "jj-log"
  "Major mode for jj log buffers."
  (setq-local
   font-lock-defaults '(jj-log-font-lock-keywords))
  (read-only-mode t))

(defun jj-log (&optional interactive-p)
  "Display the output of `jj log' in a dedicated buffer.
When called interactively (INTERACTIVE-P non-nil), the buffer is displayed
to the user.  Returns the log buffer."
  (interactive "p")
  (with-current-buffer (get-buffer-create "*jj-log*")
    (let ((buffer (current-buffer))
          (inhibit-read-only t))
      (erase-buffer)
      (jj-call-process "log" nil buffer)
      (jj-log-mode)
      (when interactive-p
        (display-buffer buffer))
      buffer)))

(defun jj--read-revision ()
  "Prompt for a revision using the jj log buffer as a reference.
Displays the jj log buffer in a side window below the current frame.
Returns \"@\" if the user enters an empty string."
  (let ((window (display-buffer-in-side-window (jj-log) '((side . bottom)))))
    (unwind-protect
        (let ((revision (read-string "Revision (default @): " "")))
          (if (string-equal revision "") "@" revision))
      (when (window-live-p window)
        (delete-window window)))))

(defun jj--maybe-read-revision (arg)
  "Resolve ARG to a revision string.
If ARG is nil, return \"@\".  If ARG is a string, return it.
Otherwise, prompt for a revision via `jj--read-revision'."
  (cond
   ((null arg) "@")
   ((stringp arg) arg)
   (t (jj--read-revision))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; diff
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun jj-diff--run (revision &optional from-rev)
  "Execute jj diff for REVISION and return the diff buffer.
If FROM-REV is non-nil, diff FROM-REV against REVISION.
Otherwise, diff REVISION against the working copy.
The output is displayed in `*jj-diff*' using `diff-mode'."
  (let ((buffer (get-buffer-create "*jj-diff*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (if from-rev
            (jj-call-process "diff" nil buffer "--git" "--from" from-rev)
          (jj-call-process "diff" nil buffer "--git" "-r" revision))
        (goto-char (point-min))
        (diff-mode)
        (read-only-mode t)))
    buffer))

;;;###autoload
(defun jj-diff (&optional rev)
  "Run jj diff with REV or @ when REV is not specified."
  (interactive "P")
  (with-jj-root
    (display-buffer
     (jj-diff--run (jj--maybe-read-revision rev)))))

;;;###autoload
(defun jj-diff-from (&optional from-rev)
  "Run jj diff to compare the current revision against FROM-REV."
  (interactive "P")
  (with-jj-root
    (display-buffer
     (jj-diff--run "@" (or from-rev (jj--read-revision))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; describe
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defvar jj-describe--change-id nil
  "The change id for the current `jj-describe-mode' buffer.")
(defvar jj-describe--revision nil
  "The revision for the current `jj-describe-mode' buffer.")

(defun jj-describe-submit ()
  "Update the description for the current `jj-describe-mode' buffer."
  (interactive)
  (let ((buffer (current-buffer)))
    (unless jj-describe--change-id
      (user-error "Not a valid jj-describe buffer"))
    (goto-char (point-min))
    (flush-lines "^JJ:")
    (delete-trailing-whitespace)
    (let ((status (jj-call-process-region (point-min) (point-max)
                                          "describe" nil nil "--stdin"
                                          "-r" jj-describe--change-id)))
      (unless (eq 0 status)
        (error "Command jj describe failed (status %S)" status))
      (if (equal jj-describe--revision jj-describe--change-id)
          (message "Set description for %s" jj-describe--revision)
        (message "Set description for %s(%s)" jj-describe--revision jj-describe--change-id))
      (kill-buffer buffer))))

(defun jj-describe-diff ()
  "View the diff for the jj describe buffer."
  (interactive)
  (unless jj-describe--change-id
    (user-error "Not a valid jj-describe buffer"))
  (display-buffer (jj-diff--run jj-describe--change-id)))


(define-derived-mode jj-describe-mode markdown-mode "jj-describe"
  "Major mode for editing jj descriptions."
  (setq-local
   comment-start "JJ: "
   comment-start-skip "^JJ:[ \t]*"
   comment-use-syntax nil)
  (setq-local
   header-line-format
   (substitute-command-keys
    "JJ Describe | Submit (\\[jj-describe-submit]) | View Diff (\\[jj-describe-diff]) | Quit (\\[kill-buffer])"))
  (font-lock-add-keywords
   nil
   '(("^JJ:.*" . font-lock-comment-face))))

(define-key jj-describe-mode-map (kbd "C-c C-c") #'jj-describe-submit)
(define-key jj-describe-mode-map (kbd "C-c C-d") #'jj-describe-diff)
(define-key jj-describe-mode-map (kbd "C-c C-k") #'kill-buffer)

(defun jj-describe--run (buffer revision)
  "Populate BUFFER with the description of REVISION.

Switches to `jj-describe-mode' and stores the revision and its
corresponding change id in buffer-local variables.  Signals an error if
REVISION cannot be resolved."
  (with-current-buffer buffer
    (erase-buffer)
    (let ((status (jj-call-process "log" nil buffer
                                   "--no-graph"
                                   "-r" revision
                                   "-T" "description")))
      (unless (eq 0 status)
        (error "Command jj log failed (status %S)" status)))
    (jj-describe-mode)
    (setq-local
     jj-describe--revision  revision
     jj-describe--change-id (jj-revision-to-change-id revision))
    (goto-char (point-min))))

(defun jj-describe (&optional rev)
  "Edit the description of REV or @ when REV is not specified.

Opens a `jj-describe-mode' buffer where the description can be edited and
submitted with `jj-describe-submit'."
  (interactive "P")
  (let ((revision (jj--maybe-read-revision rev))
        (buffer (get-buffer-create "*jj-describe*")))
    (jj-describe--run buffer revision)
    (pop-to-buffer buffer)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; edit & new
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun jj--autorevert-repo-buffers ()
  "Revert unmodified file-visiting buffers under the jj root.

Does nothing unless `jj-autorevert-repo-buffers' is non-nil."
  (when jj-autorevert-repo-buffers
    (let ((root (jj-root)))
      (dolist (buffer (buffer-list))
        (with-current-buffer buffer
          (when (and buffer-file-name
                     (not (buffer-modified-p))
                     (file-in-directory-p buffer-file-name root))
            (revert-buffer nil t)))))))

(defun jj-edit (&optional rev)
  "Run jj edit with REV.

Prompts for a revision (showing the jj log in a side window) when REV is nil,
since editing \"@\" is a no-op.  When `jj-autorevert-repo-buffers' is non-nil,
also reverts unmodified file-visiting buffers under the jj root."
  (interactive "P")
  (with-jj-root
    (let ((revision (if (stringp rev) rev (jj--read-revision))))
      (with-temp-buffer
        (let ((status (jj-call-process "edit" nil (list (current-buffer) t) revision)))
          (unless (eq 0 status)
            (error "jj edit failed: %s" (string-trim (buffer-string))))))
      (message "Now editing %s" revision)
      (jj--autorevert-repo-buffers))))

(defun jj-new (&optional rev)
  "Run jj new with REV or @ when REV is not specified.

Creates a new empty change on top of REV and makes it the working-copy revision.
With a prefix argument, prompts for a revision.  When
`jj-autorevert-repo-buffers' is non-nil, also reverts unmodified file-visiting
buffers under the jj root."
  (interactive "P")
  (with-jj-root
    (let ((revision (jj--maybe-read-revision rev)))
      (with-temp-buffer
        (let ((status (jj-call-process "new" nil (list (current-buffer) t) revision)))
          (unless (eq 0 status)
            (error "jj new failed: %s" (string-trim (buffer-string))))))
      (message "Created new change on top of %s" revision)
      (jj--autorevert-repo-buffers))))

(provide 'jj)
;;; jj.el ends here
