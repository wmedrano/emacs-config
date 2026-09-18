;;; gptel-extra-tools.el --- Extra gptel stuff -*- lexical-binding: t -*-

;; Package-Requires: ((emacs "30") (gptel "0.9.9"))
;; Version: 0.1.0
;; Keywords: convenience, ai

;;; Commentary:
;;
;; This package provides extra gptel stuff.

;;; Code:

(require 'project)
(require 'image)
(require 'seq)
(require 'subr-x)
(require 'gptel-request)

(defun gptel-extra--root ()
  "Get the root directory that should be used."
  (or (when-let* ((project (project-current)))
        (project-root project))
      default-directory))

(defun gptel-extra--resolve-path (path)
  "Resolve PATH against the project root.
`expand-file-name' handles absolute and home-relative paths for us."
  (expand-file-name path (gptel-extra--root)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; shell
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defcustom gptel-extra-shell-output-limit 20000
  "Maximum number of characters returned by the shell tool.
A non-positive value means do not limit the output.  Keep the end of the
output, saving the full output to a temporary file when truncated."
  :type 'integer
  :group 'gptel)

(defun gptel-extra--truncate-output (output)
  "Return the tail of OUTPUT, saving full output when truncation is needed."
  (if (or (<= gptel-extra-shell-output-limit 0)
          (<= (length output) gptel-extra-shell-output-limit))
      output
    (let ((coding-system-for-write 'utf-8-unix)
          (file (make-temp-file "gptel-shell-" nil ".log")))
      (with-temp-buffer
        (insert output)
        (write-region (point-min) (point-max) file nil 'silent))
      (concat (substring output (- gptel-extra-shell-output-limit))
              (format "\n[Showing last %d characters. Full output: %s]"
                      gptel-extra-shell-output-limit file)))))

(defun gptel-extra--shell-tool-impl (callback command &optional timeout)
  "Run COMMAND asynchronously and call CALLBACK with its status and output.
TIMEOUT, when supplied, is a positive finite number of seconds."
  (unless (or (null timeout)
              (and (numberp timeout) (> timeout 0) (<= timeout 2147483.647)))
    (user-error "Timeout must be positive and at most 2147483.647 seconds"))
  (let* ((output-buffer (generate-new-buffer "*gptel-shell-output*"))
         (completed nil)
         (timed-out nil)
         (timer nil)
         (process
          (condition-case err
              (let ((default-directory (gptel-extra--root)))
                (make-process
                 :name "gptel-shell"
                 :buffer output-buffer
                 :command (list shell-file-name shell-command-switch command)
                 :connection-type 'pipe
                 :noquery t
                 :sentinel
                 (lambda (proc _event)
                   (when (and (not completed)
                              (memq (process-status proc) '(exit signal)))
                     (setq completed t)
                     (when timer (cancel-timer timer))
                     (unwind-protect
                         (funcall callback
                                  (format "exit code: %d\n%s%s"
                                          (+ (process-exit-status proc)
                                             (if (eq (process-status proc) 'signal) 128 0))
                                          (gptel-extra--truncate-output
                                           (with-current-buffer output-buffer
                                             (buffer-string)))
                                          (if timed-out
                                              (format "\nCommand timed out after %s seconds" timeout)
                                            "")))
                       (when (buffer-live-p output-buffer)
                         (kill-buffer output-buffer)))))))
            (error (format "process could not be started: %s"
                           (error-message-string err))))))
    (if (processp process)
        (progn
          ;; Match `call-process' with nil INFILE: commands receive EOF.
          (when (process-live-p process)
            (process-send-eof process)
            (when timeout
              (setq timer
                    (run-at-time
                     timeout nil
                     (lambda ()
                       (when (and (not completed) (process-live-p process))
                         (setq timed-out t)
                         (kill-process process)))))))
          process)
      (setq completed t)
      (unwind-protect
          (funcall callback process)
        (when (buffer-live-p output-buffer)
          (kill-buffer output-buffer))))))

(defvar gptel-extra-shell-tool
  (gptel-make-tool
   :name "shell"
   :function #'gptel-extra--shell-tool-impl
   :async t
   :description
   "Run a shell command in the current project's root directory and return
its exit code and output. Use this to inspect files, run tests, and invoke
formatters. Returns the end of large output and saves the full output to a
temporary file whose path is returned. Optionally specify a timeout in seconds;
there is no default timeout. Signal termination uses exit code 128 + signal."
   :args
   (list
    '(:name "command"
            :type string
            :description "The shell command to execute")
    '(:name "timeout" :type number :optional t
            :exclusiveMinimum 0 :maximum 2147483.647
            :description "Timeout in seconds (optional, no default timeout)"))
   :category "coding"))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; read
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defconst gptel-extra--read-max-lines 2000)
(defconst gptel-extra--read-max-bytes (* 50 1024))

(defun gptel-extra--read-text (text path offset limit)
  "Return a bounded portion of TEXT beginning at OFFSET.
OFFSET is one-based and LIMIT, when non-nil, is the requested number of
lines.  The result never exceeds the line or byte limits, and always ends on
a line boundary.  PATH is used in the oversized-line diagnostic."
  (let* ((lines (unless (string-empty-p text)
                  (split-string text "\n" nil)))
         ;; A final newline terminates the last line; it does not introduce
         ;; another logical line.
         (lines (if (and lines (string-empty-p (car (last lines))))
                    (butlast lines)
                  lines))
         (total (length lines))
         (start (1- offset)))
    (when (and lines (>= start total))
      (user-error "Offset %d is beyond end of file (%d lines total)"
                  offset total))
    (if (null lines)
        ""
      (let ((remaining (nthcdr start lines))
            (requested (or limit most-positive-fixnum))
            (output nil)
            (used-bytes 0)
            (count 0)
            (byte-limited nil)
            oversized-line)
        (while (and remaining
                    (< count requested)
                    (< count gptel-extra--read-max-lines)
                    (not byte-limited))
          (let* ((line (car remaining))
                 (line-bytes (string-bytes
                              (encode-coding-string line 'utf-8-unix)))
                 (bytes (+ used-bytes (if output 1 0) line-bytes)))
            (if (> bytes gptel-extra--read-max-bytes)
                (setq byte-limited t
                      oversized-line (and (zerop count) line-bytes))
              (push line output)
              (setq remaining (cdr remaining)
                    used-bytes bytes
                    count (1+ count)))))
        (if oversized-line
            (format "[Line %d is %.1fKB, which exceeds the 50.0KB output limit.\nUse the shell tool for byte-level inspection of %s.]"
                    offset (/ oversized-line 1024.0) path)
          (let ((content (mapconcat #'identity (nreverse output) "\n")))
            (if (or (null remaining) (zerop count))
                content
              (format "%s\n\n[Showing lines %d-%d of %d. Use offset=%d to continue.]"
                      content offset (+ offset count -1) total
                      (+ offset count)))))))))

(defun gptel-extra--read-file-tool-impl (path &optional offset limit)
  "Read PATH, with optional OFFSET and LIMIT.
Relative paths use the project root; absolute and home-based paths are
resolved as supplied.  OFFSET is a one-based line number; LIMIT is a positive
line count."
  (setq offset (or offset 1))
  (unless (and (integerp offset) (> offset 0))
    (user-error "Offset must be a positive integer"))
  (unless (or (null limit) (and (integerp limit) (> limit 0)))
    (user-error "Limit must be a positive integer"))
  (let ((file (gptel-extra--resolve-path path)))
    (unless (file-regular-p file)
      (user-error "Not a regular file: %s" file))
    (with-temp-buffer
      (set-buffer-multibyte nil)
      (insert-file-contents-literally file)
      (let ((bytes (buffer-string)))
        (if (image-type-from-data bytes)
            "[Image not returned: this gptel version does not support image tool results.]"
          (gptel-extra--read-text
           (decode-coding-string bytes 'utf-8-unix)
           file offset limit))))))

(defvar gptel-extra-read-file-tool
  (gptel-make-tool
   :name "read"
   :function #'gptel-extra--read-file-tool-impl
   :description
   "Read the contents of a text file. Relative paths are resolved from the
current project's root directory; absolute and ~/ paths are respected. Output
is truncated to 2000 lines or 50KB
(whichever is hit first). Use offset/limit for large files. When you need the
full file, continue with offset until complete. Use read to examine files
instead of cat or sed. Image attachments are not supported."
   :args
   (list
    '(:name "path"
            :type string
            :description "Path to the file to read (relative or absolute)")
    '(:name "offset"
            :type integer
            :optional t
            :minimum 1
            :description "Line number to start reading from (1-indexed)")
    '(:name "limit"
            :type integer
            :optional t
            :minimum 1
            :description "Maximum number of lines to read"))
   :category "coding"))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; write (Pi-compatible API with Emacs buffer protections)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun gptel-extra--write-file-tool-impl (path content)
  "Write CONTENT as UTF-8 to PATH, creating parent directories as needed.
Leave the file open in an Emacs buffer.  Refuse to overwrite unsaved edits
or a read-only buffer.  Write the supplied content without save hooks."
  (let ((file (gptel-extra--resolve-path path)))
    (when (file-directory-p file)
      (user-error "Cannot write to a directory: %s" file))
    (make-directory (file-name-directory file) t)
    (let ((buffer (find-file-noselect file)))
      (with-current-buffer buffer
        (when buffer-read-only
          (user-error "File is read-only: %s" file))
        (when (buffer-modified-p)
          (user-error "Buffer has unsaved changes: %s" file))
        (save-restriction
          (widen)
          (erase-buffer)
          (insert content)
          (set-buffer-file-coding-system 'utf-8-unix t)
          (let ((coding-system-for-write 'utf-8-unix))
            (write-region (point-min) (point-max) file nil t))))
      (format "Successfully wrote to %s" path))))

(defvar gptel-extra-write-file-tool
  (gptel-make-tool
   :name "write"
   :function #'gptel-extra--write-file-tool-impl
   :description
   "Write content to a file. Creates the file if it doesn't exist, overwrites
if it does. Automatically creates parent directories. Use write only for new
files or complete rewrites. Relative paths are resolved from the current
project's root directory; absolute and ~/ paths are respected. Content is
written as UTF-8 without save hooks.
The file is left open in an Emacs buffer. Refuses to overwrite a read-only
buffer or a buffer with unsaved changes."
   :args
   (list
    '(:name "path"
            :type string
            :description "Path to the file to write (relative or absolute)")
    '(:name "content"
            :type string
            :description "Content to write to the file"))
   :category "coding"))
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; edit
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun gptel-extra--normalize-newlines (text)
  "Normalize CRLF and CR line endings in TEXT to LF."
  (replace-regexp-in-string "\r\n\\|\r" "\n" text t t))

(defun gptel-extra--apply-edits (text edits)
  "Apply EDITS to TEXT, matching all replacements against the original.
EDITS is a list or vector of plists with :oldText and :newText strings.
Reject empty, missing, ambiguous, overlapping, and collectively no-op edits."
  (unless (and (or (listp edits) (vectorp edits)) (> (length edits) 0))
    (user-error "edits must contain at least one replacement"))
  (let ((case-fold-search nil)
        matches)
    (seq-doseq (edit edits)
      (unless (and (listp edit) (stringp (plist-get edit :oldText))
                   (stringp (plist-get edit :newText)))
        (user-error "Each edit must contain oldText and newText strings"))
      (let* ((old (gptel-extra--normalize-newlines (plist-get edit :oldText)))
             (new (gptel-extra--normalize-newlines (plist-get edit :newText)))
             (pattern (regexp-quote old))
             (start (string-match pattern text)))
        (when (string-empty-p old)
          (user-error "oldText must not be empty"))
        (unless start
          (user-error "Could not find oldText; match exactly including whitespace and newlines"))
        (when (string-match pattern text (1+ start))
          (user-error "oldText is not unique; provide more context"))
        (push (list start (+ start (length old)) new) matches)))
    (setq matches (sort matches (lambda (a b) (< (car a) (car b)))))
    (let ((end 0))
      (dolist (match matches)
        (when (< (car match) end)
          (user-error "Edits overlap; merge them into one edit or target disjoint regions"))
        (setq end (cadr match))))
    (let ((result text))
      (dolist (match (reverse matches))
        (setq result (concat (substring result 0 (car match))
                             (nth 2 match) (substring result (cadr match)))))
      (when (equal result text)
        (user-error "No changes made; replacements produced identical content"))
      result)))

(defun gptel-extra--edit-file-tool-impl (path edits)
  "Apply targeted EDITS to existing PATH relative to the project root.
Preserve UTF-8 BOM and line ending style.  Refuse unsaved or read-only
buffers, and validate every replacement before changing the file."
  (let ((file (gptel-extra--resolve-path path)))
    (unless (and (file-regular-p file) (file-readable-p file)
                 (file-writable-p file))
      (user-error "Cannot edit file: %s" file))
    (when-let* ((buffer (find-buffer-visiting file)))
      (with-current-buffer buffer
        (when (or buffer-read-only (buffer-modified-p))
          (user-error "Buffer is read-only or has unsaved changes: %s" file))
        (unless (verify-visited-file-modtime buffer)
          (user-error "File changed on disk; revert its buffer before editing: %s" file))))
    (let* ((raw (with-temp-buffer
                  (set-buffer-multibyte nil)
                  (insert-file-contents-literally file)
                  (decode-coding-string (buffer-string) 'utf-8-unix)))
           (bom (string-prefix-p "\ufeff" raw))
           (text (if bom (substring raw 1) raw))
           (first-lf (string-match "\n" text))
           (crlf (and first-lf (> first-lf 0)
                      (= (aref text (1- first-lf)) ?\r)))
           (result (gptel-extra--apply-edits
                    (gptel-extra--normalize-newlines text) edits)))
      (when crlf
        (setq result (replace-regexp-in-string "\n" "\r\n" result t t)))
      (gptel-extra--write-file-tool-impl file (concat (if bom "\ufeff" "") result))
      (format "Successfully replaced %d block(s) in %s." (length edits) path))))

(defvar gptel-extra-edit-file-tool
  (gptel-make-tool
   :name "edit"
   :function #'gptel-extra--edit-file-tool-impl
   :description
   "Edit an existing file using exact text replacement. Every edits[].oldText
must match a unique, non-overlapping region of the original file. Use one call
with multiple edits for separate locations. Merge overlapping or nested edits.
Keep oldText as small as possible while still unique. Matching is case-sensitive
and whitespace-sensitive, with line endings normalized. Relative paths resolve
from the project root; absolute and ~/ paths are respected. Refuses read-only
buffers and unsaved changes."
   :args
   (list
    '(:name "path" :type string
            :description "Path to the file to edit (relative or absolute)")
    '(:name "edits" :type array :minItems 1
            :description "Targeted replacements, all matched against the original file"
            :items (:type object
                    :properties
                    (:oldText (:type string :minLength 1
                               :description "Exact unique text to replace")
                     :newText (:type string :description "Replacement text"))
                    :required ["oldText" "newText"])))
   :category "coding"))

(provide 'gptel-extra-tools)
;;; gptel-extra-tools.el ends here
