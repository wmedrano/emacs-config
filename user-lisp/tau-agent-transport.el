;;; tau-agent-transport.el --- Streaming ChatGPT requests -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Incremental SSE framing and asynchronous curl transport.  Credentials go
;; into a private temporary config, never the process command line.

;;; Code:

(require 'tau-agent-auth)

(cl-defstruct tau-agent-stream
  "State for one request and its CALLBACK."
  process file stderr (pending "") callback response error finished)

(defun tau-agent-transport--feed (stream chunk)
  "Deliver complete events from STREAM after appending CHUNK."
  (setf (tau-agent-stream-pending stream)
        (concat (tau-agent-stream-pending stream) chunk))
  (let ((text (tau-agent-stream-pending stream)))
    (while (string-match "\r?\n\r?\n" text)
      (let* ((end (match-end 0)) (frame (substring text 0 (match-beginning 0)))
             data)
        (setq text (substring text end))
        (dolist (line (split-string frame "\r?\n"))
          (when (string-prefix-p "data:" line)
            (push (string-remove-prefix " " (substring line 5)) data)))
        (when data
          (let ((payload (string-join (nreverse data) "\n")))
            (unless (equal payload "[DONE]")
              (let* ((event (tau-agent--json-read payload))
                     (type (plist-get event :type)))
                (pcase type
                  ("response.completed"
                   (setf (tau-agent-stream-response stream) (plist-get event :response)))
                  ((or "error" "response.failed" "response.incomplete")
                   (setf (tau-agent-stream-error stream)
                         (format "Response failed: %s"
                                 (or (plist-get event :message)
                                     (plist-get event :error)
                                     (plist-get (plist-get event :response) :error)
                                     type)))))
                (funcall (tau-agent-stream-callback stream) 'event event)))))))
    (setf (tau-agent-stream-pending stream) text)))

(defun tau-agent-transport--cleanup (stream)
  "Remove temporary resources belonging to STREAM."
  (when-let* ((file (tau-agent-stream-file stream)))
    (when (file-exists-p file) (delete-file file))
    (setf (tau-agent-stream-file stream) nil))
  (when (buffer-live-p (tau-agent-stream-stderr stream))
    (kill-buffer (tau-agent-stream-stderr stream))))

(defun tau-agent-transport-cancel (stream)
  "Stop STREAM and release its resources without delivering callbacks."
  (setf (tau-agent-stream-finished stream) t)
  (when-let* ((process (tau-agent-stream-process stream)))
    (when (process-live-p process) (delete-process process)))
  (tau-agent-transport--cleanup stream))

(defun tau-agent-transport--quote (text)
  "Quote TEXT for a curl configuration value."
  (when (string-match-p "[\r\n]" text) (error "Invalid HTTP header"))
  (concat "\"" (string-replace "\"" "\\\"" (string-replace "\\" "\\\\" text)) "\""))

(defun tau-agent-transport--http-error (stream stderr)
  "Describe a failed STREAM using its JSON body and curl STDERR."
  (let* ((body (ignore-errors (tau-agent--json-read (tau-agent-stream-pending stream))))
         (error-value (plist-get body :error))
         (detail (or (and (listp error-value) (plist-get error-value :message))
                     (and (stringp error-value) error-value)
                     (plist-get body :message))))
    (format "HTTP request failed: %s%s" stderr
            (if (stringp detail) (concat "\n" (truncate-string-to-width detail 2000)) ""))))

(defun tau-agent-transport-start (payload callback)
  "Send PAYLOAD and invoke CALLBACK with event or done and associated data.
The done payload is a plist containing :response or :error."
  (unless (executable-find "curl") (user-error "Tau-agent requires curl"))
  (let* ((headers (tau-agent-auth-headers))
         (stream (make-tau-agent-stream :callback callback))
         (file (make-temp-file "tau-agent-http-")))
    (setf (tau-agent-stream-file stream) file)
    (condition-case err
        (progn
          (set-file-modes file #o600)
          (with-temp-buffer
            (dolist (header (append '(("Content-Type" . "application/json")) headers))
              (insert "header = " (tau-agent-transport--quote
                                   (concat (car header) ": " (cdr header))) "\n"))
            (write-region (point-min) (point-max) file nil 'silent))
          (setf (tau-agent-stream-stderr stream) (generate-new-buffer " *tau-http-errors*"))
          (let ((process
                 (make-process
                  :name "tau-agent-http" :buffer nil :connection-type 'pipe
                  :coding 'utf-8-unix :noquery t
                  :stderr (tau-agent-stream-stderr stream)
                  :command (list "curl" "--disable" "--silent" "--show-error"
                                 "--fail-with-body" "--no-buffer" "--connect-timeout" "30"
                                 "--config" file "--data-binary" "@-"
                                 "https://chatgpt.com/backend-api/codex/responses")
                  :filter
                  (lambda (_proc chunk)
                    (unless (tau-agent-stream-finished stream)
                      (condition-case failure
                          (tau-agent-transport--feed stream chunk)
                        (error
                         (setf (tau-agent-stream-error stream) (error-message-string failure))
                         (when (process-live-p (tau-agent-stream-process stream))
                           (delete-process (tau-agent-stream-process stream)))))))
                  :sentinel
                  (lambda (proc _event)
                    (when (and (memq (process-status proc) '(exit signal))
                               (not (tau-agent-stream-finished stream)))
                      (setf (tau-agent-stream-finished stream) t)
                      (let* ((stderr (when (buffer-live-p (tau-agent-stream-stderr stream))
                                       (with-current-buffer (tau-agent-stream-stderr stream)
                                         (string-trim (buffer-string)))))
                             (failure
                              (or (tau-agent-stream-error stream)
                                  (unless (zerop (process-exit-status proc))
                                    (tau-agent-transport--http-error stream stderr))
                                  (unless (tau-agent-stream-response stream)
                                    "Stream ended without a completed response"))))
                        (tau-agent-transport--cleanup stream)
                        (funcall callback 'done
                                 (if failure (list :error failure)
                                   (list :response (tau-agent-stream-response stream))))))))))
            (setf (tau-agent-stream-process stream) process)
            (process-send-string process (tau-agent--json payload))
            (process-send-eof process))
          stream)
      (error
       (tau-agent-transport-cancel stream)
       (signal (car err) (cdr err))))))

(provide 'tau-agent-transport)
;;; tau-agent-transport.el ends here
