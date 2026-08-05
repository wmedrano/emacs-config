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
;;   - `jj-restore-file' Restore a file from its parent revision (with confirmation).
;;   - `jj-restore-all'  Restore all files from the parent revision (with confirmation).
;;
;; The non-interactive helpers `jj-run' and `jj-run-into-buffer' can be used to
;; build additional jj-based commands.  They signal `jj-error' when jj fails.
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

(defcustom jj-log-side-window-height 'fit-window-to-buffer
  "Height of the side window showing the jj log when prompting for a revision.
Either an integer number of lines, a float fraction of the frame height,
or the function `fit-window-to-buffer' to size the window to its contents."
  :type '(choice (integer :tag "Lines")
                 (float :tag "Fraction of frame height")
                 (const :tag "Fit to contents" fit-window-to-buffer))
  :group 'jj)

(defcustom jj-diff-from-default "@-"
  "The default revision to use for jj-diff-from.

Can be set to a bookmark like \"main\" for quicker diffing."
  :type 'string
  :group 'jj)

(defcustom jj-restore-file-confirm t
  "Whether `jj-restore-file' asks for confirmation before restoring.

When non-nil (the default), `jj-restore-file' asks the user to
confirm before running `jj restore'.  Set to nil to skip the
confirmation and restore immediately."
  :type 'boolean
  :group 'jj)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; process plumbing
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-error 'jj-error "jj command failed")

(defun jj--args (cmd &rest args)
  "Get the jj arguments to use for CMD with ARGS."
  `(,cmd
    "--color" "never"
    "--no-pager"
    ,@args))

(defun jj--run (destination args)
  "Run the jj executable synchronously with ARGS.

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
        (let ((status (apply #'call-process jj-executable nil
                             `(,destination ,err-file) nil
                             full-args)))
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
  (jj--run nil args))

(defun jj-run-into-buffer (buffer &rest args)
  "Run jj with ARGS, inserting standard output into BUFFER before point.
Signals `jj-error' on failure."
  (jj--run buffer args))

(defun jj-root ()
  "Get the root of the jj repository.

Signals `jj-error' with jj's error output if not inside a jj
repository."
  (with-temp-buffer
    (jj-run-into-buffer (current-buffer) "root")
    (string-trim (buffer-string))))

(defun jj--get-buffer (name)
  "Get or create buffer NAME with `default-directory' set to the jj root.

The root is computed in the calling buffer's context, before switching
buffers, so that a reused buffer always points at the repository the
command was invoked from.  This matters because `default-directory' is
buffer-local: a cached buffer would otherwise keep running jj in the
repository that was current when it was created."
  (let ((root (jj-root))
        (buffer (get-buffer-create name)))
    (with-current-buffer buffer
      (setq-local default-directory root))
    buffer))

(defun jj-revision-to-change-id (revision)
  "Convert a REVISION to a change id.

A revision, such as (@) may point to a different change.  The change id should
be more stable."
  (with-temp-buffer
    (jj-run-into-buffer (current-buffer)
                        "log"
                        "--no-graph"
                        "-r" revision
                        "-T" "change_id")
    (string-trim (buffer-string))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; log
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defconst jj-log--graph-node-chars "@◆○×"
  "Node glyphs that mark revisions in jj log graph output.")

(defconst jj-log--graph-edge-chars " │~├─╮╯╰╭┤┬┴┼"
  "Characters that draw graph edges in jj log output.")

(defconst jj-log--revision-header-regexp
  (concat
   "^[" jj-log--graph-edge-chars "]*"
   "\\([" jj-log--graph-node-chars "]\\)"
   "[" jj-log--graph-edge-chars "]*"
   "[ \t]+"
   "\\([a-z]+\\)"                       ; 2: change id
   "[ \t]+"
   "\\([^ \t]+\\)"                      ; 3: author
   "\\(?:[ \t]+\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}"
   " [0-9]\\{2\\}:[0-9]\\{2\\}:[0-9]\\{2\\}\\)\\)?" ; 4: timestamp (optional)
   "\\(?:[ \t]+\\(.+?\\)\\)?"            ; 5: bookmarks (optional)
   "[ \t]+"
   "\\([0-9a-f]\\{8,\\}\\)"               ; 6: commit id
   "\\(?:[ \t]+\\((conflict)\\)\\)?$")      ; 7: conflict marker (optional)
  "Regexp matching the header line of a revision in jj log output.
Group 1 is the node glyph, 2 the change id, 3 the author, 4 the
timestamp (nil for the root commit), 5 the bookmarks text (nil when
there are none), 6 the commit id, and 7 the \"(conflict)\" marker
\(nil when there is no conflict).")

(defconst jj-log--description-line-regexp
  (concat "^[" jj-log--graph-edge-chars "]+[ \t]*\\(.*\\)$")
  "Regexp matching a description continuation line in jj log output.
Group 1 is the description text with the graph prefix stripped; it is
empty for graph-only lines such as \"├─╯\" or \"~\".")

;; TODO(unslop): Vibecoded with kimi-k3
(defun jj-log--parse-revisions ()
  "Parse the jj log output from the current buffer into a list of revisions.

The current buffer and is expected to contain jj log output in the default
template format, e.g. a `jj-log-mode' buffer created by `jj-log'.

The return value is a list with one plist per revision, in buffer
order (newest first), with the following keys:

  :change-id      displayed change id (an abbreviated prefix)
  :commit-id      displayed commit id (an abbreviated prefix)
  :author         author, typically an email address
  :timestamp      author timestamp, or nil (e.g. for the root commit)
  :bookmarks      list of bookmark names, or nil
  :description    displayed description line, or nil
  :working-copy-p non-nil for the working copy (@) revision
  :conflicted-p   non-nil if the revision has conflicts
  :immutable-p    non-nil if the revision is immutable
  :position       buffer position of the revision's header line"
  (save-excursion
    (goto-char (point-min))
    (let ((revisions nil)
          (current nil)
          (in-description nil))
      (while (not (eobp))
        (cond
         ;; Header line: start a new revision.
         ((looking-at jj-log--revision-header-regexp)
          (when current
            (push current revisions))
          (let ((node (match-string-no-properties 1))
                (bookmarks (match-string-no-properties 5)))
            (setq current
                  (list :change-id (match-string-no-properties 2)
                        :commit-id (match-string-no-properties 6)
                        :author (match-string-no-properties 3)
                        :timestamp (match-string-no-properties 4)
                        :bookmarks (when bookmarks
                                     (split-string bookmarks nil t))
                        :description nil
                        :working-copy-p (string-equal node "@")
                        :conflicted-p (if (or (string-equal node "×")
                                              (match-string-no-properties 7))
                                          t
                                        nil)
                        :immutable-p (string-equal node "◆")
                        :position (match-beginning 0))
                  in-description t)))
         ;; Description continuation line: append to the current
         ;; revision.  Graph-only lines (empty group 1) end it.
         ((and in-description
               (looking-at jj-log--description-line-regexp)
               (not (string-empty-p (match-string-no-properties 1))))
          (let ((text (string-trim-right (match-string-no-properties 1)))
                (old (plist-get current :description)))
            (setq current
                  (plist-put current :description
                             (if old (concat old "\n" text) text)))))
         ;; Graph-only or unrecognized line: no more description
         ;; lines belong to the current revision.
         (t (setq in-description nil)))
        (forward-line 1))
      (when current
        (push current revisions))
      (nreverse revisions))))

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

(defvar jj-log-revisions nil "List of jj log revisions.

A revision is a plist with the following elements:
  :change-id      displayed change id (an abbreviated prefix)
  :commit-id      displayed commit id (an abbreviated prefix)
  :author         author, typically an email address
  :timestamp      author timestamp, or nil (e.g. for the root commit)
  :bookmarks      list of bookmark names, or nil
  :description    displayed description line, or nil
  :working-copy-p non-nil for the working copy (@) revision
  :conflicted-p   non-nil if the revision has conflicts
  :immutable-p    non-nil if the revision is immutable
  :position       buffer position of the revision's header line")

(defun jj-log (&optional interactive-p)
  "Display the output of `jj log' in a dedicated buffer.
When called interactively (INTERACTIVE-P non-nil), the buffer is displayed
to the user.  Returns the log buffer."
  (interactive "p")
  (with-current-buffer (jj--get-buffer "*jj-log*")
    (let ((buffer (current-buffer))
          (inhibit-read-only t))
      (erase-buffer)
      (jj-run-into-buffer buffer "log")
      (goto-char (point-min))
      (jj-log-mode)
      (setq-local jj-log-revisions (jj-log--parse-revisions))
      (when interactive-p
        (display-buffer buffer))
      buffer)))

(defun jj--read-revision (prompt-prefix &optional default-revision)
  "Prompt for a revision using the jj log buffer as a reference.
Displays the jj log buffer in a side window below the current frame.
Returns \"@\" if the user enters an empty string."
  (let* ((jj-log-buffer (jj-log))
         (revision-window (display-buffer-in-side-window
                           jj-log-buffer
                           `((side . bottom)
                             (window-height . ,jj-log-side-window-height)
                             (window-parameters . ((mode-line-format . none))))))
         (revisions (mapcar (lambda (x) (cons
                                         (format "%s %s %s"
                                                 (or (plist-get x :change-id) "")
                                                 (or (plist-get x :description) "")
                                                 (or (plist-get x :bookmarks) ""))
                                         (plist-get x :change-id)))
                            (buffer-local-value 'jj-log-revisions jj-log-buffer))))
    (unwind-protect
        (let* ((revision (completing-read (format "%sRevision (default %s): "
                                                  (or prompt-prefix "")
                                                  (or default-revision "@"))
                                          revisions
                                          nil
                                          nil
                                          ""
                                          nil
                                          "")))
          (if (string-equal revision "")
              (or default-revision "@")
            (alist-get revision revisions revision nil #'string-equal)))
      (when (window-live-p revision-window)
        (delete-window revision-window)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; diff
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun jj-diff--run (revision &optional from-rev-p)
  "Execute jj diff for REVISION and return the diff buffer.

If FROM-REV-P is non-nil, diff the working copy from REVISION.
The output is displayed in `*jj-diff*' using `diff-mode'."
  (let ((buffer (jj--get-buffer "*jj-diff*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t)
            (args              (if from-rev-p
                                   (jj--args "diff" "--git" "--from" revision)
                                 (jj--args "diff" "--git" "-r" revision)))
            (err-file          (make-temp-file "*jj-diff-stderr*")))
        (erase-buffer)
        (let ((status (apply #'call-process jj-executable nil (cons t err-file) nil args)))
          (unless (= status 0)
            (insert-file-contents err-file)
            (error "jj diff failed with status: %d, see %s" status (buffer-name buffer))))
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
(defun jj-diff-at (&optional rev)
  "Run jj diff with REV.

Prompts for the revision if REV is nil."
  (interactive)
  (jj--display-buffer-other-window
   (jj-diff--run (or rev (jj--read-revision "jj-diff-at ")))))

;;;###autoload
(defun jj-diff-from (&optional from-rev)
  "Run jj diff to compare the current revision against FROM-REV.

Prompts for revision if FROM-REV is nil."
  (interactive)
  (jj--display-buffer-other-window
   (jj-diff--run (or from-rev (jj--read-revision "jj-diff-from " jj-diff-from-default))
                 t)))

(defun jj-diff ()
  "Prompt for a revision and display its diff.

With a prefix argument, compare the current revision against the selected
revision instead."
  (interactive)
  (let ((revision (jj--read-revision
                   (if current-prefix-arg "jj-diff-from " "jj-diff-at ")
                   (if current-prefix-arg jj-diff-from-default "@"))))
    (if current-prefix-arg
        (jj-diff-from revision)
      (jj-diff-at revision))))

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
  (unless jj-describe--change-id
    (user-error "Not a valid jj-describe buffer"))
  (goto-char (point-min))
  (flush-lines "^JJ:")
  (delete-trailing-whitespace)
  (let* ((args (jj--args "describe"
                         "-r" jj-describe--change-id
                         "--stdin"))
         (err-file      (make-temp-file "jj-stderr")))
    (unwind-protect
        (let ((status (apply #'call-process-region
                             (point-min) (point-max) jj-executable
                             nil (cons nil err-file) nil
                             args)))
          (unless (eq 0 status)
            (let ((details (with-temp-buffer
                             (insert-file-contents err-file)
                             (string-trim (buffer-string)))))
              (signal 'jj-error
                      (list (format "jj describe failed: %s"
                                    details))))))
      (delete-file err-file)))
  (if (equal jj-describe--revision jj-describe--change-id)
      (message "Set description for %s" jj-describe--revision)
    (message "Set description for %s(%s)" jj-describe--revision jj-describe--change-id))
  (kill-buffer (current-buffer)))

(defun jj-describe-quit ()
  "Quit editing the description for the current `jj-describe-mode' buffer."
  (interactive)
  (when (derived-mode-p '(jj-describe-mode))
    (kill-this-buffer)))

(defun jj-describe-diff ()
  "View the diff for the jj describe buffer."
  (interactive)
  (unless jj-describe--change-id
    (user-error "Not a valid jj-describe buffer"))
  (pop-to-buffer (jj-diff--run jj-describe--change-id)))


(define-derived-mode jj-describe-mode markdown-mode "jj-describe"
  "Major mode for editing jj descriptions."
  (setq-local
   comment-start "JJ: "
   comment-start-skip "^JJ:[ \t]*"
   comment-use-syntax nil)
  (setq-local
   header-line-format
   (substitute-command-keys
    "JJ Describe | Submit (\\[jj-describe-submit]) | View Diff (\\[jj-describe-diff]) | Quit (\\[jj-describe-quit])"))
  (font-lock-add-keywords
   nil
   '(("^JJ:.*" . font-lock-comment-face))))

(define-key jj-describe-mode-map (kbd "C-c C-c") #'jj-describe-submit)
(define-key jj-describe-mode-map (kbd "C-c C-d") #'jj-describe-diff)
(define-key jj-describe-mode-map (kbd "C-c C-k") #'jj-describe-quit)

(defun jj-describe--activate (revision change-id)
  "Enable `jj-describe-mode' and set up its buffer-local variables.

Delays mode hooks so that `jj-describe-mode-hook' runs after
`jj-describe--revision' and `jj-describe--change-id' are set (see
`delay-mode-hooks').  Call `run-mode-hooks' afterwards to run the
delayed hooks."
  (delay-mode-hooks
    (jj-describe-mode))
  (setq-local
   jj-describe--revision  revision
   jj-describe--change-id change-id)
  (run-mode-hooks))

(defun jj-describe (&optional rev)
  "Edit the description of REV.

Prompts for a revision if REV is nil.

Opens a `jj-describe-mode' buffer where the description can be edited and
submitted with `jj-describe-submit'."
  (interactive)
  (let ((buffer   (jj--get-buffer "*jj-describe*"))
        (revision (or rev (jj--read-revision "jj-describe "))))
    (with-current-buffer buffer
      (erase-buffer)
      (jj-run-into-buffer buffer "log" "--no-graph" "-r" revision "-T" "description")
      (jj-describe--activate revision (jj-revision-to-change-id revision))
      (goto-char (point-min)))
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

Prompts for a revision (showing the jj log in a side window) when REV is nil.

When `jj-autorevert-repo-buffers' is non-nil, also reverts unmodified
file-visiting buffers under the jj root."
  (interactive)
  (let ((rev (or rev (jj--read-revision "jj-edit "))))
    (jj-run "edit" rev)
    (message "Now editing %s" rev)
    (jj--autorevert-repo-buffers)))

(defun jj-new (&optional rev)
  "Run jj new with REV.

Prompts for a revision if REV is nil.

Creates a new empty change on top of REV and makes it the working-copy revision.

When `jj-autorevert-repo-buffers' is non-nil, also reverts unmodified
file-visiting buffers under the jj root."
  (interactive)
  (let ((rev (or rev (jj--read-revision "jj-new "))))
    (jj-run "new" rev)
    (message "Created new change on top of %s" rev)
    (jj--autorevert-repo-buffers)))

;;;###autoload
(defun jj-restore-file (&optional file)
  "Restore FILE from its parent revision, discarding working copy changes.

Interactively, prompts for the file to restore, defaulting to the file
visited by the current buffer.  Unless `jj-restore-file-confirm' is
nil, asks for confirmation before running `jj restore FILE'."
  (interactive
   (let ((file (and buffer-file-name
                    (file-relative-name buffer-file-name))))
     (list (read-file-name "jj restore file: "
                           nil
                           file
                           nil
                           file))))
  (unless file
    (user-error "jj-restore-file requires a file argument"))
  (when (or (not jj-restore-file-confirm)
            (y-or-n-p
             (format "Restore %s from its parent revision? " file)))
    (jj-run "restore" file)
    (message "Restored %s" file)
    (jj--autorevert-repo-buffers)))

;;;###autoload
(defun jj-restore-all ()
  "Restore all files from the parent revision, discarding all working copy changes.

Runs `jj restore' without any path arguments, which restores the
entire working copy to match the parent revision.  Unless
`jj-restore-file-confirm' is nil, asks for confirmation before
running `jj restore'."
  (interactive)
  (when (or (not jj-restore-file-confirm)
            (y-or-n-p "Restore all files from the parent revision? "))
    (jj-run "restore")
    (message "Restored all files")
    (jj--autorevert-repo-buffers)))

(provide 'jj)
;;; jj.el ends here
