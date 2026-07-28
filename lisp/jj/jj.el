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
;; The non-interactive helpers `jj-root', `jj-run', `jj-run-to-string',
;; `jj-run-into-buffer', and `jj-run-region' can be used to build
;; additional jj-based commands.  They signal `jj-error' when jj fails.
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

(defcustom jj-executable "jj"
  "Location of jj executable."
  :type 'string
  :group 'jj)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; process plumbing
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-error 'jj-error "jj command failed")

(defun jj--run (infile destination args)
  "Run the jj executable synchronously with ARGS.

INFILE is nil, a file name, or a cons (START . END) of positions in the
current buffer whose text is sent as standard input.

DESTINATION is nil (discard standard output) or a buffer to insert it into.

The global flags `--color' never and `--no-pager' are added automatically.

Returns the exit status on success.  Signals `jj-error' with jj's
standard error output when jj exits non-zero or is interrupted."
  (let* ((jj-cmd        (car args))
         (jj-extra-args (cdr args))
         (full-args `(,jj-cmd
                      "--color" "never" "--no-pager"
                      ,@jj-extra-args))
         ;; A temp file holds stderr: the stderr slot of
         ;; DESTINATION in `call-process'/`call-process-region' accepts only
         ;; nil, t, or a file name. A buffer is preferred, but only
         ;; `make-process' allows this.
         (err-file      (make-temp-file "jj-stderr")))
    (unwind-protect
        (let ((status (if (consp infile)
                          (apply #'call-process-region
                                 (car infile) (cdr infile) jj-executable
                                 nil `(,destination ,err-file) nil
                                 full-args)
                        (apply #'call-process jj-executable infile
                               `(,destination ,err-file) nil
                               full-args))))
          (unless (eq 0 status)
            (let ((details (with-temp-buffer
                             (insert-file-contents err-file)
                             (string-trim (buffer-string)))))
              (signal 'jj-error
                      (list (format "jj %s failed: %s"
                                    (car args) details)))))
          status)
      (delete-file err-file))))

(defun jj-run (&rest args)
  "Run jj with ARGS, discarding standard output.

ARGS is the jj subcommand followed by its arguments,
e.g. (jj-run \"edit\" \"@\").  Signals `jj-error' on failure."
  (jj--run nil nil args))

(defun jj-run-to-string (&rest args)
  "Run jj with ARGS and return standard output as a trimmed string.
Signals `jj-error' on failure."
  (with-temp-buffer
    (jj--run nil (current-buffer) args)
    (string-trim (buffer-string))))

(defun jj-run-into-buffer (buffer &rest args)
  "Run jj with ARGS, inserting standard output into BUFFER before point.
Signals `jj-error' on failure."
  (jj--run nil buffer args))

(defun jj-run-region (start end &rest args)
  "Send text from START to END in the current buffer to jj with ARGS.
The text is sent as standard input; standard output is discarded.
Signals `jj-error' on failure."
  (jj--run (cons start end) nil args))

(defun jj-root ()
  "Get the root of the jj repository.

Signals an error if not inside a jj repository."
  (condition-case nil
      (jj-run-to-string "root")
    (jj-error (error "Not inside a jj repository"))))

(defmacro with-jj-root (&rest body)
  "Run BODY at the jj root."
  (declare (indent 0) (debug t))
  `(let ((default-directory (jj-root)))
     ,@body))

(defun jj-revision-to-change-id (revision)
  "Convert a REVISION to a change id.

A revision, such as (@) may point to a different change.  The change id should
be more stable."
  (jj-run-to-string "log" "--no-graph" "-r" revision "-T" "change_id"))

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
      (jj-run-into-buffer buffer "log")
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
            (jj-run-into-buffer buffer "diff" "--git" "--from" from-rev)
          (jj-run-into-buffer buffer "diff" "--git" "-r" revision))
        (goto-char (point-min))
        (diff-mode)
        (read-only-mode t)))
    buffer))

(defun jj--display-buffer-other-window (buffer)
  "Display BUFFER in a window other than the selected one.
Reuses a window already showing BUFFER or pops up a new window, but
never takes over the selected window."
  (unless (eq buffer (window-buffer))
    (display-buffer buffer
                    '((display-buffer-reuse-window display-buffer-pop-up-window)
                      (inhibit-same-window . t)))))

;;;###autoload
(defun jj-diff (&optional rev)
  "Run jj diff with REV or @ when REV is not specified."
  (interactive "P")
  (with-jj-root
    (jj--display-buffer-other-window
     (jj-diff--run (jj--maybe-read-revision rev)))))

;;;###autoload
(defun jj-diff-from (&optional from-rev)
  "Run jj diff to compare the current revision against FROM-REV."
  (interactive "P")
  (with-jj-root
    (jj--display-buffer-other-window
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
    (jj-run-region (point-min) (point-max)
                   "describe" "--stdin" "-r" jj-describe--change-id)
    (if (equal jj-describe--revision jj-describe--change-id)
        (message "Set description for %s" jj-describe--revision)
      (message "Set description for %s(%s)" jj-describe--revision jj-describe--change-id))
    (kill-buffer buffer)))

(defun jj-describe-diff ()
  "View the diff for the jj describe buffer."
  (interactive)
  (unless jj-describe--change-id
    (user-error "Not a valid jj-describe buffer"))
  (jj--display-buffer-other-window (jj-diff--run jj-describe--change-id)))


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
    (jj-run-into-buffer buffer "log" "--no-graph" "-r" revision "-T" "description")
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
      (jj-run "edit" revision)
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
      (jj-run "new" revision)
      (message "Created new change on top of %s" revision)
      (jj--autorevert-repo-buffers))))

(provide 'jj)
;;; jj.el ends here
