;;; jj.el --- Jujutsu VCS integration -*- lexical-binding: t -*-
;;; Commentary:

;; Jujutsu VCS integration for Emacs.

;;; Code:

(require 'markdown-mode)

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
  "Call COMMAND synchronously in separate process.
The remaining arguments are optional.

The program’s input comes from file INFILE (nil means /dev/null).
If INFILE is a relative path, it will be looked for relative to the
directory where the process is run (see below).  If you want to make the
input come from an Emacs buffer, use ‘jj-call-process-region’ instead.

Third argument DESTINATION specifies how to handle program’s output.
\(\"Output\" here means both standard output and standard error
output.)
If DESTINATION is a buffer or the name of a buffer, or t (which stands for
the current buffer), it means insert output in that buffer before point.
If DESTINATION is nil, it means discard output; 0 means discard
 and don’t wait for the program to terminate.
If DESTINATION is ‘(:file FILE)’, where FILE is a file name string,
 it means that output should be written to that file (if the file
 already exists it is overwritten).
DESTINATION can also have the form (REAL-BUFFER STDERR-FILE); in that case,
 REAL-BUFFER says what to do with standard output, as above,
 while STDERR-FILE says what to do with standard error in the child.
 STDERR-FILE may be nil (discard standard error output),
 t (mix it with ordinary output), or a file name string.

Remaining arguments ARGS are strings passed as command arguments to the jj
COMMAND.

The jj executable is searched for in variable ‘exec-path’
\(which is a list of directories).

If executable jj can’t be found as an executable, ‘jj-call-process’
signals a Lisp error.  ‘jj-call-process’ reports errors in execution of
the program only through its return and output.

If DESTINATION is 0, ‘jj-call-process’ returns immediately with value nil.
Otherwise it waits for jj to terminate
and returns a numeric exit status or a signal description string.
If you quit, the process is killed with SIGINT, or SIGKILL if you quit again."
  (apply #'call-process "jj" infile destination nil
         command
         "--color" "never"
         "--no-pager"
         args))

(defun jj-call-process-region (start end command &optional delete buffer &rest args)
  "Send text from START to END to a synchronous process running jj.
COMMAND is the jj subcommand to invoke.
The remaining arguments are optional.

START and END are normally buffer positions specifying the part of the
buffer to send to the process.
If START is nil, that means to use the entire buffer contents; END is
ignored.
If START is a string, then send that string to the process
instead of any buffer contents; END is ignored.
The remaining arguments are optional.
Delete the text if fourth arg DELETE is non-nil.

Insert output in BUFFER before point; t means current buffer; nil for
 BUFFER means discard it; 0 means discard and don’t wait; and ‘(:file
 FILE)’, where FILE is a file name string, means that it should be
 written to that file (if the file already exists it is overwritten).
BUFFER can be a string which is the name of a buffer.
BUFFER can also have the form (REAL-BUFFER STDERR-FILE); in that case,
REAL-BUFFER says what to do with standard output, as above,
while STDERR-FILE says what to do with standard error in the child.
STDERR-FILE may be nil (discard standard error output),
t (mix it with ordinary output), or a file name string.

Remaining arguments ARGS are strings passed as command arguments to the jj
COMMAND.

The jj executable is searched for in variable ‘exec-path’
\(which is a list of directories).

If BUFFER is 0, ‘jj-call-process-region’ returns immediately with value nil.
Otherwise it waits for jj to terminate
and returns a numeric exit status or a signal description string.
If you quit, the process is killed with SIGINT, or SIGKILL if you quit again."
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
  "Execute jj log."
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
  (let ((window (display-buffer-in-side-window (jj-log) '((side . bottom)))))
    (unwind-protect
        (let ((revision (read-string "Revision (default @): " "")))
          (if (string-equal revision "") "@" revision))
      (when (window-live-p window)
        (delete-window window)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; diff
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun jj-diff--run (revision)
  "Execute jj diff on REVISION and output results to BUFFER."
  (let ((buffer (get-buffer-create "*jj-diff*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (jj-call-process "diff" nil buffer "--git" "-r" revision)
        (goto-char (point-min))
        (diff-mode)
        (read-only-mode t)))
    buffer))

;;;###autoload
(defun jj-diff (&optional rev)
  "Run jj diff with REV or @ when rev is not specified."
  (interactive "P")
  (with-jj-root
    (display-buffer
     (jj-diff--run (if rev (jj--read-revision) "@")))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; describe
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defvar jj-describe--change-id nil
  "The change_id for the current JJ-DESCRIBE-MODE buffer.")
(defvar jj-describe--revision nil
  "The revision for the current JJ-DESCRIBE-MODE buffer.")

(defun jj-describe-submit ()
  "Update the description for the current JJ-DESCRIBE buffer."
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
   comment-use-syntax nil
   header-line-format (substitute-command-keys
                       "JJ Describe | Submit (\\[jj-describe-submit]) | View Diff (\\[jj-describe-diff]) | Quit (\\[kill-buffer])"))
  (font-lock-add-keywords
   nil
   '(("^JJ:.*" . font-lock-comment-face))))

(define-key jj-describe-mode-map (kbd "C-c C-c") #'jj-describe-submit)
(define-key jj-describe-mode-map (kbd "C-c C-d") #'jj-describe-diff)
(define-key jj-describe-mode-map (kbd "C-c C-k") #'kill-buffer)

(defun jj-describe--run (buffer revision)
  "Dump the description of REVISION onto BUFFER.
Signals an error if REVISION cannot be resolved."
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

(defun jj-describe ()
  "Edit the description of the current revision."
  (interactive)
  (let ((buffer (get-buffer-create "*jj-describe*"))
        (revision "@"))
    (jj-describe--run buffer revision)
    (pop-to-buffer buffer)))

(provide 'jj)
;;; jj.el ends here
