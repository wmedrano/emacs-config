;;; gptel-agent-tools.el --- Run Bash commands as gptel tools -*- lexical-binding: t; -*-

;;; Commentary:

;;; Code:

(require 'gptel)
(require 'gptel-request)

(defvar-local gptel-agent-tools-default-system-prompt--cache nil)
(defun gptel-agent-tools-default-system-prompt ()
  "Get the default system prompt."
  (unless gptel-agent-tools-default-system-prompt--cache
    (setq gptel-agent-tools-default-system-prompt--cache
          (format "You are an expert assistant operating inside a coding agent harness. You help users by reading files, executing commands, editing code, and writing new files.

- Use tools like rg to search.
- Use jj for version control. Avoid looking at other branches as they are often broken prototypes.

working directory: %s
scratch directory: %s"
                  default-directory
                  (make-temp-file "/tmp/agent-scratch-" t))))
  gptel-agent-tools-default-system-prompt--cache)

(defun gptel-agent-tools-bash--format-output (status-message output-buffer)
  "Create a bash tool output based on OUTPUT-BUFFER.

STATUS-MESSAGE is a description of the result or nil to exclude it."
  (let ((output (with-current-buffer output-buffer
                  (buffer-substring-no-properties (point-min)
                                                  (point-max)))))
    (if status-message
        (format "%s\n%s" status-message output)
      output)))

(defun gptel-agent-tools-bash--respond
    (result-callback bash-process process-event)
  "Sentinel for use in `gptel-agent-tools-bash--impl'.

RESULT-CALLBACK is the gptel callback.

BASH-PROCESS is the bash command process.

PROCESS-EVENT is the sentinel event."
  (cond
   ((string= process-event "finished\n")
    (funcall
     result-callback
     (gptel-agent-tools-bash--format-output
      nil
      (process-buffer bash-process))))
   ((or (string-match-p "timeout" process-event)
        (string-match-p "exited-abnormally" process-event)
        (string-match-p "name-of-signal" process-event))
    (funcall
     result-callback
     (gptel-agent-tools-bash--format-output
      process-event
      (process-buffer bash-process))))
   (t
    (funcall
     result-callback
     (format
      "bash tool call failure, abort task and report broken tool. Unknown process event %s"
      process-event)))))

(defun gptel-agent-tools-bash--impl
    (result-callback shell-command &optional timeout-seconds)
  "Call bash tool with SHELL-COMMAND and TIMEOUT-SECONDS.

Call RESULT-CALLBACK with the result when done."
  (let* ((bash-path (executable-find "bash"))
         (output-buffer (generate-new-buffer "gptel-bash"))
         (timeout-timer nil)
         (responded     nil)
         (process-sentinel
          (lambda (bash-process process-event)
            (when timeout-timer
              (cancel-timer timeout-timer))
            (when (not responded)
              (gptel-agent-tools-bash--respond result-callback bash-process process-event)
              (setq responded t))))
         (bash-process
          (make-process
           :name "gptel-bash"
           :buffer output-buffer
           :command (list bash-path "-c" shell-command)
           :sentinel process-sentinel))
         (on-timeout (lambda ()
                       (funcall process-sentinel bash-process "timeout\n")
                       (kill-process bash-process))))
    (when (and timeout-seconds (> timeout-seconds 0))
      (setq timeout-timer
            (run-at-time timeout-seconds nil on-timeout)))
    nil))

(defconst gptel-agent-tools-bash
  (gptel-make-tool
   :name "bash"
   :function #'gptel-agent-tools-bash--impl
   :description "Call bash commands like rg and jj"
   :args (list
          '(:name "command"
                  :description "command to run"
                  :type string)
          '(:name "timeout"
                  :description "the number of seconds to wait before canceling"
                  :type integer
                  :optional true))
   :async t
   :confirm t))

(provide 'gptel-agent-tools)
;;; gptel-agent-tools.el ends here
