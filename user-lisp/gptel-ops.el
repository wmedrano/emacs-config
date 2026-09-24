;;; gptel-ops.el --- General operations for gptel -*- lexical-binding: t; -*-

;;; Commentary:

;;; Code:

(require 'cl-lib)
(require 'imenu)
(require 'subr-x)

(defun gptel-ops-line-start (line-number)
  "Return the buffer position at the start of LINE-NUMBER."
  (save-excursion
    (goto-char (point-min))
    (forward-line (1- line-number))
    (line-beginning-position)))

(defun gptel-ops-line-end (line-number)
  "Return the buffer position at the end of LINE-NUMBER."
  (save-excursion
    (goto-char (point-min))
    (forward-line (1- line-number))
    (line-end-position)))

(defun gptel-ops-read (path &optional start-line end-line)
  "Read file at PATH, optionally including START-LINE and END-LINE."
  (let* ((path (expand-file-name path))
         (buffer (and (file-exists-p path)
                      (find-file-noselect path t))))
    (if (not buffer)
        (format "%s not found" path)
      (with-current-buffer buffer
        (let ((start (if start-line
                         (gptel-ops-line-start start-line)
                       (point-min)))
              (end (if end-line
                       (gptel-ops-line-end end-line)
                     (point-max))))
          (save-buffer)
          (format "%s\n%s" path
                  (buffer-substring-no-properties start end)))))))

(defun gptel-ops-replace (path buffer old-text new-text)
  "Replace OLD-TEXT with NEW-TEXT in BUFFER.

PATH is used to make error messages."
  (let ((case-fold-search nil))
    (with-current-buffer buffer
      (save-excursion
        (goto-char (point-min))
        (unless (search-forward old-text nil t)
          (error "Could not find old_text in %s" path))
        (let ((start (match-beginning 0))
              (end (match-end 0)))
          (when (search-forward old-text nil t)
            (error "Found multiple occurrences of old_text in %s" path))
          (delete-region start end)
          (goto-char start)
          (insert new-text)))
      (basic-save-buffer))))

(defun gptel-ops-imenu (buffer)
  "Return a CLI-style listing of BUFFER's Imenu entries.

Signal an error if Imenu is unavailable or has no valid entries in BUFFER."
  (unless (buffer-live-p buffer)
    (error "Not a live buffer: %s" buffer))
  (with-current-buffer buffer
    (unless (and (boundp 'imenu-generic-expression)
                 (or imenu-generic-expression
                     (bound-and-true-p imenu--index-alist)))
      (error "Imenu is not available in %s" (buffer-name)))
    (require 'imenu)
    (let ((index (imenu--make-index-alist t))
          groups)
      (dolist (entry index)
        (when (and (consp (cdr entry))
                   (not (markerp (cdr entry))))
          (let ((items
                 (cl-loop for item in (cdr entry)
                          when (markerp (cdr item))
                          collect (cons (line-number-at-pos (cdr item))
                                        (car item)))))
            (when items
              (push (cons (car entry) items) groups)))))
      (unless groups
        (error "Imenu has no valid entries in %s" (buffer-name)))
      (mapconcat
       (lambda (group)
         (concat (upcase (car group)) "\n"
                 (mapconcat
                  (lambda (item)
                    (format "%4d  %s" (car item) (cdr item)))
                  (nreverse (cdr group)) "\n")))
       (nreverse groups) "\n\n"))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Bash process operations
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun gptel-agent-tools-bash--format-output (status-message output-buffer)
  "Create a bash tool output based on OUTPUT-BUFFER.

STATUS-MESSAGE is a description of the result or nil to exclude it."
  (let ((output (with-current-buffer output-buffer
                  (buffer-substring-no-properties (point-min)
                                                  (point-max)))))
    (if status-message
        (format "%s\nOutput:\n%s" status-message
                (if (equal output "") "(no output)" output))
      output)))

(defun gptel-agent-tools-bash--format-error (error-data)
  "Format ERROR-DATA as a bash tool result."
  (format "bash tool call failure: %s"
          (error-message-string error-data)))

(defun gptel-agent-tools-bash--call-with-error-handling
    (result-callback function)
  "Call FUNCTION and pass its result to RESULT-CALLBACK.

If FUNCTION signals an error, pass a description of the error to
RESULT-CALLBACK instead."
  (funcall
   result-callback
   (condition-case error-data
       (funcall function)
     (error
      (gptel-agent-tools-bash--format-error error-data)))))

(defun gptel-agent-tools-bash--respond (bash-process process-event)
  "Return a result for BASH-PROCESS and PROCESS-EVENT.

PROCESS-EVENT is the sentinel event."
  (gptel-agent-tools-bash--format-output
   (cond
    ((process-get bash-process 'gptel-bash-timeout)
     (format "Command timed out after %s seconds."
             (process-get bash-process 'gptel-bash-timeout)))
    ((eq (process-status bash-process) 'exit)
     (unless (zerop (process-exit-status bash-process))
       (format "Command exited with code %d."
               (process-exit-status bash-process))))
    ((eq (process-status bash-process) 'signal)
     (format "Command terminated by signal %d (%s)."
             (process-exit-status bash-process)
             (string-trim process-event)))
    (t
     (error "Unexpected process status %s: %s"
            (process-status bash-process) (string-trim process-event))))
   (process-buffer bash-process)))

(defun gptel-agent-tools-bash--impl
    (result-callback shell-command &optional timeout-seconds)
  "Call bash tool with SHELL-COMMAND and TIMEOUT-SECONDS.

Call RESULT-CALLBACK with the result when done."
  (let ((output-buffer nil)
        (timeout-timer nil)
        (responded     nil)
        (bash-process  nil))
    (condition-case error-data
        (let ((process-sentinel
               (lambda (bash-process process-event)
                 (when (and (not responded)
                            (memq (process-status bash-process) '(exit signal)))
                   (unwind-protect
                       (progn
                         (setq responded t)
                         (gptel-agent-tools-bash--call-with-error-handling
                          result-callback
                          (lambda ()
                            (when timeout-timer
                              (cancel-timer timeout-timer))
                            (gptel-agent-tools-bash--respond
                             bash-process process-event))))
                     (when (buffer-live-p output-buffer)
                       (kill-buffer output-buffer)))))))
          (setq output-buffer (generate-new-buffer "gptel-bash")
                bash-process
                (make-process
                 :name "gptel-bash"
                 :buffer output-buffer
                 :command (list (executable-find "bash") "-c" shell-command)
                 :sentinel process-sentinel))
          (when (and (not responded) timeout-seconds (> timeout-seconds 0))
            (setq timeout-timer
                  (run-at-time timeout-seconds
                               nil
                               (lambda ()
                                 (when (and (not responded)
                                            (process-live-p bash-process))
                                   (process-put bash-process 'gptel-bash-timeout
                                                timeout-seconds)
                                   (kill-process bash-process))))))
          nil)
      (error
       (setq responded t)
       (when timeout-timer
         (cancel-timer timeout-timer))
       (when (process-live-p bash-process)
         (delete-process bash-process))
       (when (buffer-live-p output-buffer)
         (kill-buffer output-buffer))
       (funcall result-callback
                (gptel-agent-tools-bash--format-error error-data))))))

(provide 'gptel-ops)
;;; gptel-ops.el ends here
