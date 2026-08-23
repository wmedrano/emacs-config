;;; jj.el --- JJ integration for emacs -*- lexical-binding: t -*-

;; Package-Requires: ((emacs "30") (markdown-mode "2.0"))
;; Version: 0.1.0
;; Keywords: vc, tools
;; Author: Will Medrano <will@wmedrano.dev>

;;; Commentary:
;;
;; This package provides integration for `jj'.

;;; Code:

(require 'subr-x)
(require 'cl-lib)

(defgroup jj nil
  "JJ integration for Emacs."
  :group 'tools)

(defcustom jj-executable "jj"
  "Path to the jj executable."
  :type 'string
  :group 'jj)

(defcustom jj-global-args
  '("--config" "ui.progress-indicator=false"
    "--color" "never" "--no-pager")
  "Args prepended to every `jj' command.

By default, the progress indicator, color, and pager are disabled.  This makes
`jj' output is suitable for parsing and display in Emacs."
  :type '(repeat string)
  :group 'jj)

(defface jj-bookmark-face
  '((t :inherit font-lock-type-face))
  "Face for bookmarks in the jj log."
  :group 'jj)

(defface jj-change-id-face
  '((t :inherit font-lock-constant-face))
  "Face for change ids in the jj log."
  :group 'jj)

(defface jj-selected-face
  '((t :inherit highlight))
  "Face for the currently selected revision in the jj log."
  :group 'jj)

(defface jj-graph-face
  '((t :inherit font-lock-keyword-face))
  "Face for graph line characters in the jj log."
  :group 'jj)

(defface jj-email-face
  '((t :inherit font-lock-string-face))
  "Face for email addresses in the jj log."
  :group 'jj)

(defface jj-timestamp-face
  '((t :inherit font-lock-type-face))
  "Face for timestamps in the jj log."
  :group 'jj)

(defface jj-commit-id-face
  '((t :inherit font-lock-comment-face))
  "Face for commit ids in the jj log."
  :group 'jj)

(defface jj-no-description-face
  '((t :inherit font-lock-comment-face))
  "Face for \"(no description set)\" in the jj log."
  :group 'jj)

(define-error 'jj-error "JJ error")

(defun jj--signal (message)
  "Signal a `jj-error' with the failure MESSAGE from a `jj' command.

When MESSAGE indicates that the current directory is not in a jj
repository, signal with a clearer message."
  (let ((trimmed (string-trim (string-remove-prefix "Error: " message))))
    (signal 'jj-error
            (list (cond
                   ((string-empty-p trimmed)
                    "jj failed.")
                   ((string-match-p "\\(no jj repo\\|failed to find repository\\)" trimmed)
                    "There is no jj repository here.  Run jj from a directory inside a jj repository.")
                   (t trimmed))))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; General
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun jj-root ()
  "Get the root directory.

Returns an error if the `default-directory' is not in a jj repository."
  (with-temp-buffer
    (let* ((status (apply #'call-process jj-executable nil t nil
                          (append jj-global-args '("root"))))
           (result (string-trim (buffer-substring (point-min)
                                                  (point-max)))))
      (if (= status 0)
          result
        (jj--signal result)))))

(defmacro jj--with-new-buffer (name &rest body)
  "Create a new buffer named NAME and execute BODY in it.

The buffer is created with `generate-new-buffer', so a unique name is used
if NAME is already taken.  Its `default-directory' is set to the root of the
current jj repository.  Returns the buffer."
  (declare (indent 1))
  `(let* ((default-directory (jj-root))
          (buffer            (generate-new-buffer ,name)))
     (with-current-buffer buffer
       ,@body
       buffer)))

(cl-defun jj--start-process (args &key on-done)
  "Start a `jj' process with ARGS.

The process is started with the global args in `jj-global-args',
which disable the progress indicator, color, and pager.
ON-DONE is called in the process buffer when the process exits."
  (let* ((command    (car args))
         (final-args (append jj-global-args args)))
    (make-process
     :name (format "jj-%s" command)
     :buffer (current-buffer)
     :command (cons jj-executable final-args)
     :sentinel (if on-done (lambda (proc _event)
                             (when (and (eq (process-status proc) 'exit)
                                        (buffer-live-p (process-buffer proc)))
                               (with-current-buffer (process-buffer proc)
                                 (funcall on-done (process-exit-status proc)))))))))



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Revisions / Log
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defvar vertico-sort-function)

(declare-function vertico--candidate "vertico")

(defun jj-read-revision (prompt-prefix default-revision)
  "Read a revision from the user.

PROMPT-PREFIX is prepended to the prompt.
DEFAULT-REVISION is returned if the user selects the empty string."
  (let* ((jj-log-buffer     (jj--log))
         (jj-log-window     (display-buffer-in-side-window
                             jj-log-buffer
                             '((side              . bottom)
                               (window-height     . fit-window-to-buffer)
                               (window-parameters . ((mode-line-format . none))))))
         (candidates        (jj--log-candidates jj-log-buffer))
         (update-highlights (lambda ()
                              (jj--read-revision-update-highlights
                               candidates default-revision)))
         ;; The candidates are already sorted by `jj log' output.
         (vertico-sort-function nil)
         (prompt            (if default-revision
                                (format "%s revision (default %s): "
                                        prompt-prefix default-revision)
                              (format "%s revision: " prompt-prefix))))
    (unwind-protect
        (let ((rev
               (minibuffer-with-setup-hook
                   (lambda ()
                     (add-hook 'post-command-hook update-highlights nil t))
                 (completing-read prompt candidates))))
          (cond
           ;; Empty -> Default, or nil if there is none
           ((string-empty-p rev) default-revision)
           ;; Revision -> Change ID
           ((assoc rev candidates)
            (jj--revision-change-id
             (overlay-get (cdr (assoc rev candidates)) 'jj--revision)))
           ;; Custom text
           (t rev)))
      (when (window-live-p jj-log-window)
        (delete-window jj-log-window))
      (when (buffer-live-p jj-log-buffer)
        (kill-buffer jj-log-buffer)))))

(defun jj--read-revision-update-highlights (candidates default-revision)
  "Update the the selected items from CANDIDATES.

If the candidate selection is empty, then DEFAULT-REVISION is used."
  (when-let* ((selected (when (fboundp 'vertico--candidate)
                          (or (vertico--candidate) ""))))
         (cl-loop
          for (candidate . overlay) in candidates
          for revision = (overlay-get overlay 'jj--revision)
          when revision
          do (overlay-put
              overlay
              'face
              (when (or (string= candidate selected)
                        (and default-revision
                             (string= "@" default-revision)
                             (or (string= "@" selected) (string= "" selected))
                             (jj--revision-current-working-copy-p revision)))
                'jj-selected-face)))))

(defconst jj--revision-fields
  '((:change-id              . "json(change_id)")
    (:description            . "json(description.first_line())")
    (:bookmarks              . "json(bookmarks.map(|b| b.name()))")
    (:current-working-copy-p . "json(stringify(current_working_copy))"))
  "Alist mapping revision field keywords to jj template expressions.")

(cl-defstruct (jj--revision (:constructor jj--make-revision))
  change-id
  description
  bookmarks
  current-working-copy-p)

(define-derived-mode jj--log-mode special-mode "jj-log"
  "Major mode for displaying `jj log' output."
  (setq-local font-lock-defaults
              '((("^\\([ @◆○×│~├─╮╯╰╭┤┬┴┼]+\\)" 1 'jj-graph-face)
                 ("^[ @◆○×│~├─╮╯╰╭┤┬┴┼]+\\s-+\\([a-z]+\\)\\b" 1 'jj-change-id-face)
                 ("\\b\\([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]\\{2,\\}\\)\\b" 1 'jj-email-face)
                 ("\\b\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\} [0-9]\\{2\\}:[0-9]\\{2\\}:[0-9]\\{2\\}\\)\\b" 1 'jj-timestamp-face)
                 ("\\b\\([0-9a-f]\\{8,\\}\\)$" 1 'jj-commit-id-face)
                 ("\\b[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\} [0-9]\\{2\\}:[0-9]\\{2\\}:[0-9]\\{2\\}\\s-+\\(.+?\\)\\s-+[0-9a-f]\\{8,\\}$" 1 'jj-bookmark-face)
                 ("(no description set)" 0 'jj-no-description-face)))))

(defun jj--log ()
  "Show the `jj log' output in a \"*jj-log*\" buffer.

The log is generated synchronously.  Returns the log buffer."
  (interactive)
  (jj--with-new-buffer "*jj-log*"
    (let* ((template (string-join (append (mapcar #'cdr jj--revision-fields)
                                          '("builtin_log_compact"))
                                  "++"))
           (status (apply #'call-process jj-executable nil t nil
                          (append jj-global-args
                                  '("log" "-T")
                                  (list template)))))
      (unless (zerop status)
        (jj--signal (buffer-string)))
      (jj--log-finalize))))

(defun jj--log-finalize ()
  "Prepare the jj log buffer for display."
  (goto-char (point-min))
  (save-excursion
    (while (search-forward "\"" nil t)
      (backward-char)
      (let* ((start         (line-beginning-position))
             (json-start    (point))
             (revision-args (cl-loop for (field . _template) in jj--revision-fields
                                     append (list field (json-parse-buffer))))
             (revision      (apply #'jj--make-revision revision-args)))
        (setf (jj--revision-current-working-copy-p revision)
              (string= "true" (jj--revision-current-working-copy-p revision)))
        (delete-region json-start (point))
        (forward-line 2)
        (overlay-put (make-overlay start (point))
                     'jj--revision
                     revision))))
  (jj--log-mode))

(defun jj--log-candidates (buffer)
  "Return an alist of candidate text to overlay for BUFFER.

Each element is a cons cell `(TEXT . OVERLAY)'.  TEXT is the revision's
change id (trimmed to 8 characters), description, and bookmarks."
  (with-current-buffer buffer
    (sort
     (cl-loop for overlay in (overlays-in (point-min) (point-max))
              for revision = (overlay-get overlay 'jj--revision)
              when revision
              collect (let* ((change-id       (let ((id (jj--revision-change-id revision)))
                                                (propertize (substring id 0 (min 8 (length id)))
                                                            'face 'jj-change-id-face)))
                             (raw-description (jj--revision-description revision))
                             (description     (if (string-empty-p raw-description)
                                                  (propertize "(no description set)" 'face 'jj-no-description-face)
                                                raw-description))
                             (bookmarks       (propertize (string-join (jj--revision-bookmarks revision) " ")
                                                          'face 'jj-bookmark-face))
                             (text            (string-trim
                                               (string-join
                                                (list change-id description bookmarks)
                                                " "))))
                        (cons text overlay)))
     :in-place t
     ;; overlays-in is not guaranteed to return overlays in order
     :lessp (lambda (a b)
              (< (overlay-start (cdr a))
                 (overlay-start (cdr b)))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; New/Edit
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defvar jj--display-function #'display-message-or-buffer)

(defun jj-run-command (args)
  "Run `jj' with ARGS and display its output.

Runs synchronously and signals a `jj-error' on failure."
  (with-temp-buffer
    (let* ((default-directory (jj-root))
           (status (apply
                    #'process-file jj-executable nil t nil
                    (append jj-global-args args))))
      (unless (zerop status)
        (jj--signal (buffer-string)))
      (funcall jj--display-function (string-trim (buffer-string))))))

(defvar jj--run-command-warned nil
  "Whether the deprecation warning for `jj--run-command' has been shown.")

(defun jj--run-command (args)
  "Run `jj' with ARGS and display its output.

Deprecated wrapper for `jj-run-command'.  This function is
obsolete and will be removed on 2026-12-01."
  (declare (obsolete jj-run-command "2026-12-01"))
  (unless jj--run-command-warned
    (setq jj--run-command-warned t)
    (lwarn 'jj :warning
           "`jj--run-command' is deprecated; use `jj-run-command' instead.  It will be removed on 2026-12-01."))
  (jj-run-command args))

;;;###autoload
(defun jj-new (rev)
  "Create a new change on top of revision REV.

REV is the revision.  When called interactively, prompt with `completing-read',
defaulting to \"@\".  Runs `jj new' synchronously and displays its output."
  (interactive (list (jj-read-revision "jj new" "@")))
  (jj-run-command `("new" ,rev)))


;;;###autoload
(defun jj-edit (rev)
  "Move the working copy to revision REV.

 When called interactively, prompt with `completing-read', defaulting to \"@\".
Runs `jj edit' synchronously and displays its output."
  (interactive (list (jj-read-revision "jj edit" "@")))
  (jj-run-command `("edit" ,rev)))


;;;###autoload
(defun jj-git-push (rev)
  "Push revision REV to the remote.

When called interactively, prompt with `completing-read', defaulting to \"@\"."
  (interactive (list (jj-read-revision "jj git push" "@")))
  (jj-run-command `("git" "push" "-r" ,rev)))

;;;###autoload
(defun jj-git-fetch ()
  "Run jj git fetch."
  (interactive)
  (jj-run-command `("git" "fetch")))

;;;###autoload
(defun jj-abandon (rev)
  "Abandon revision REV.

REV is the revision.  When called interactively, prompt with `completing-read'.
Runs `jj abandon' synchronously and displays its output."
  (interactive (list (or (jj-read-revision "jj abandon" nil)
                         (user-error "No revision selected"))))
  (jj-run-command `("abandon" ,rev)))

;;;###autoload
(defun jj-duplicate (rev)
  "Duplicate revision REV.

When called interactively, prompt with `completing-read', defaulting to \"@\".
Runs `jj duplicate' synchronously and displays its output."
  (interactive (list (jj-read-revision "jj duplicate" "@")))
  (jj-run-command `("duplicate" ,rev)))

;;;###autoload
(defun jj-rebase-onto (rev dest)
  "Rebase revision REV, without its descendants, onto revision DEST.

REV is the revision to rebase and DEST is the destination revision.
When called interactively, REV defaults to \"@\" unless called with a
prefix argument, in which case prompt for REV with `completing-read'.
Runs `jj rebase -r' synchronously and displays its output."
  (interactive
   (list (if current-prefix-arg
             (jj-read-revision "jj rebase" "@")
           "@")
         (or (jj-read-revision "jj rebase onto" nil)
             (user-error "No destination selected"))))
  (jj-run-command `("rebase" "-r" ,rev "-o" ,dest)))

;;;###autoload
(defun jj-rebase (src dest)
  "Rebase revision SRC and its descendants onto revision DEST.

SRC is the source revision and DEST is the destination revision.  When
called interactively, prompt for both with `completing-read',
defaulting SRC to \"@\".  Runs `jj rebase -s' synchronously and
displays its output."
  (interactive
   (let ((src (jj-read-revision "jj rebase" "@")))
     (list src
           (or (jj-read-revision "jj rebase onto" nil)
               (user-error "No destination selected")))))
  (jj-run-command `("rebase" "-s" ,src "-o" ,dest)))

(provide 'jj)
;;; jj.el ends here
