;;; jj-diff.el --- Show jj diffs -*- lexical-binding: t -*-

;; Package-Requires: ((emacs "30"))

;; Author: Will Medrano <wmedrano@wmedrano.dev>

;;; Commentary:
;;
;; This file provides commands for showing jj revision diffs in `jj-diff-mode'.

;;; Code:

(require 'cl-lib)
(require 'diff-mode)
(require 'jj)

(defgroup jj-diff nil
  "Show jj diffs."
  :group 'jj)

(defvar-local jj-diff-revision nil
  "Resolved change ID shown by `jj-diff-at', or nil for a range diff.")

(defcustom jj-diff-reuse-buffer t
  "Whether to reuse an existing `jj-diff-mode' buffer for the same repository.
When non-nil, `jj-diff' commands reuse an existing diff buffer belonging
to the current repository.  When nil, a new buffer is created each time."
  :type 'boolean
  :group 'jj-diff)

;;;###autoload
(define-derived-mode jj-diff-mode diff-mode "jj-diff"
  "Major mode for viewing jj diffs.")

(defun jj-diff--find-buffer (root)
  "Find an existing live `jj-diff-mode' buffer for ROOT.
ROOT is the repository root directory."
  (cl-find-if
   (lambda (buf)
     (and (buffer-live-p buf)
          (with-current-buffer buf
            (and (derived-mode-p 'jj-diff-mode)
                 (file-equal-p default-directory root)))))
   (buffer-list)))

(defun jj-diff--get-buffer (root)
  "Get or create a buffer for displaying a jj diff for ROOT.
If `jj-diff-reuse-buffer' is non-nil and an existing `jj-diff-mode' buffer
for ROOT exists, reuse it.  Otherwise create a new buffer named \"*jj-diff*\"."
  (let ((existing (and jj-diff-reuse-buffer
                       (jj-diff--find-buffer root))))
    (if existing
        (progn
          (when-let* ((proc (get-buffer-process existing)))
            (delete-process proc))
          (with-current-buffer existing
            (read-only-mode -1)
            (erase-buffer)
            (setq default-directory root)
            existing))
      (let ((buffer (generate-new-buffer "*jj-diff*")))
        (with-current-buffer buffer
          (setq default-directory root))
        buffer))))

(defmacro jj-diff--with-buffer (&rest body)
  "Execute BODY in a diff buffer for the current repository.
Reuses an existing `jj-diff-mode' buffer when `jj-diff-reuse-buffer' is
non-nil, or creates a new buffer.  Returns the buffer."
  (declare (indent 0))
  `(let* ((root   (jj-root))
          (buffer (jj-diff--get-buffer root)))
     (with-current-buffer buffer
       ,@body
       buffer)))

;;;###autoload
(defun jj-diff-at (rev)
  "Show the diff of revision REV in a \"*jj-diff*\" buffer.

REV is the revision.  When called interactively, prompt with `completing-read',
defaulting to \"@\".  The diff is generated asynchronously and displayed with
`jj-diff-mode'.

If `jj-diff-reuse-buffer' is non-nil, an existing `jj-diff-mode' buffer
from the same repository is reused; otherwise a new buffer is created."
  (interactive (list (jj-read-revision "jj diff at" "@")))
  (let* ((buffer (jj-diff--with-buffer
                   (jj--diff-run `("-r" ,rev) rev))))
    (pop-to-buffer buffer)
    buffer))

;;;###autoload
(defun jj-diff-from (from-rev &optional to-rev)
  "Show the diff from FROM-REV to TO-REV in a \"*jj-diff*\" buffer.

FROM-REV is the starting revision.  When called interactively, prompt for
FROM-REV with `completing-read', defaulting to \"@-\".  With a prefix argument,
also prompt for TO-REV, defaulting to \"@\", and show the diff between the two
revisions; otherwise show the diff from FROM-REV to the working copy.  The diff
is displayed with `jj-diff-mode'.

If `jj-diff-reuse-buffer' is non-nil, an existing `jj-diff-mode' buffer
from the same repository is reused; otherwise a new buffer is created."
  (interactive
   (list (jj-read-revision "jj diff from" "@-")
         (when current-prefix-arg
           (jj-read-revision "jj diff to" "@"))))
  (let* ((buffer (jj-diff--with-buffer
                   (jj--diff-run
                    (if to-rev
                        `("--from" ,from-rev "--to" ,to-rev)
                      `("--from" ,from-rev))))))
    (pop-to-buffer buffer)
    buffer))

(defun jj--diff-run (args &optional revision)
  "Run jj diff on the current buffer with ARGS.
REVISION identifies a single revision being displayed, when applicable."
  (setq jj-diff-revision nil)
  (jj--start-process
   (append '("diff" "--git")
           args)
   :on-done (lambda (exit-status)
              (jj--diff-finalize exit-status)
              (when (and (zerop exit-status) revision)
                (setq-local jj-diff-revision
                            (jj-diff--resolve-revision revision))))))

(defun jj-diff--resolve-revision (revision)
  "Return REVISION's change ID without snapshotting the working copy.
Return nil if REVISION does not identify exactly one change."
  (let ((change-ids
         (with-temp-buffer
           (let ((status
                  (apply #'process-file jj-executable nil t nil
                         (append jj-global-args
                                 (list "--ignore-working-copy"
                                       "log" "--no-graph" "-r" revision
                                       "-T" "change_id ++ \"\\n\"")))))
             (unless (zerop status)
               (jj--signal (buffer-string)))
             (split-string (buffer-string) "\n" t)))))
    (when (= (length change-ids) 1)
      (car change-ids))))

(defun jj-diff--highlight-revision (buffer revision)
  "Highlight resolved change ID REVISION in log BUFFER and move point to it."
  (with-current-buffer buffer
    (dolist (overlay (overlays-in (point-min) (point-max)))
      (when-let* ((entry (overlay-get overlay 'jj--revision)))
        (when (equal (jj--revision-change-id entry) revision)
          (overlay-put overlay 'face 'jj-selected-face)
          (goto-char (overlay-start overlay)))))))

;;;###autoload
(defun jj-diff-squash ()
  "Show the jj log and squash this diff's revision after confirmation.
Requires a single-revision diff created by `jj-diff-at'.  Run
`jj squash -r' synchronously and display its output if the user confirms."
  (interactive)
  (unless (derived-mode-p 'jj-diff-mode)
    (user-error "Not in a jj-diff buffer"))
  (unless jj-diff-revision
    (user-error "No single revision to squash; the current diff likely represents a range instead of a single revision"))
  (let ((revision jj-diff-revision)
        (log-buffer (jj--log))
        log-window)
    (unwind-protect
        (progn
          (jj-diff--highlight-revision log-buffer revision)
          (setq log-window
                (display-buffer-in-side-window
                 log-buffer
                 '((side . bottom)
                   (window-height . fit-window-to-buffer)
                   (window-parameters . ((mode-line-format . none))))))
          (when (yes-or-no-p (format "Do you want to squash revision %s?" revision))
            (jj-run-command `("squash" "-r" ,revision))))
      (when (window-live-p log-window)
        (delete-window log-window))
      (when (buffer-live-p log-buffer)
        (kill-buffer log-buffer)))))

(defun jj--diff-finalize (exit-status)
  "Finalize the diff buffer by enabling `jj-diff-mode' and `read-only-mode'.

When EXIT-STATUS is non-zero, the buffer contains a jj error.  Leave it in
`fundamental-mode' so the error is displayed without diff highlighting."
  (goto-char (point-min))
  (if (> exit-status 0)
      (fundamental-mode)
    (jj-diff-mode))
  (read-only-mode 1))

(provide 'jj-diff)
;;; jj-diff.el ends here
