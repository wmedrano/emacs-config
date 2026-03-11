;;; consult-agent-shell.el --- Consult integration for agent-shell -*- lexical-binding: t -*-

;; Author: wmedrano
;; Version: 0.1.0
;; Package-Requires: ((emacs "28.1") (consult "1.0") (agent-shell "0.1"))

;;; Commentary:
;; Provides consult-based commands for agent-shell buffer selection.

;;; Code:

(require 'consult)
(require 'agent-shell)
(require 'shell-maker)

(defun consult-agent-shell--annotate (buf-name)
  "Return a status annotation string for BUF-NAME."
  (when-let* ((buf (get-buffer buf-name)))
    (with-current-buffer buf
      (when (and (derived-mode-p 'agent-shell-mode) agent-shell--state)
        (let* ((state agent-shell--state)
               (heartbeat-status (map-nested-elt state '(:heartbeat :status)))
               (active-requests (map-elt state :active-requests)))
          (cond
           ((eq heartbeat-status 'busy) "  [busy]")
           (active-requests             "  [active]")
           (t                           "  [idle]")))))))

(defun consult-agent-shell--select-or-create (&optional other-window)
  "Prompt for an agent-shell buffer name and return the buffer.
If the selected name matches an existing buffer, return it.
Otherwise, create a new shell, rename it, and return it.
When OTHER-WINDOW is non-nil, preview buffers in another window."
  (let* ((consult--buffer-display (if other-window
                                      #'switch-to-buffer-other-window
                                    #'switch-to-buffer))
         (buffers (agent-shell-buffers))
         (selected (consult--read
                    (mapcar #'buffer-name buffers)
                    :prompt "Agent shell: "
                    :require-match nil
                    :sort nil
                    :annotate #'consult-agent-shell--annotate
                    :state (consult--buffer-preview)))
         (existing (get-buffer selected)))
    (if existing
        existing
      (let* ((new-buf (agent-shell-new-shell))
             (project (agent-shell--project-name))
             (new-name (format "%s Agent @ %s" selected project)))
        (shell-maker-set-buffer-name new-buf new-name)
        new-buf))))

;;;###autoload
(defun consult-agent-shell-switch-buffer (&optional other-window)
  "Switch to an agent-shell buffer, or create a new one.
When the entered name matches an existing buffer, switch to it.
Otherwise, create a new shell and rename it to
\"<name> Agent @ <project>\".
With a prefix argument (OTHER-WINDOW), display in another window."
  (interactive "P")
  (if other-window
      (switch-to-buffer-other-window (consult-agent-shell--select-or-create other-window))
    (switch-to-buffer (consult-agent-shell--select-or-create other-window))))

;;;###autoload
(defun consult-agent-shell-send-region ()
  "Send the active region to a selected agent-shell buffer.
Prompts for the target shell with Consult preview and busy/idle annotations."
  (interactive)
  (let* ((shell-buf (consult-agent-shell--select-or-create))
         (text (agent-shell--get-region-context
                :deactivate t
                :agent-cwd (with-current-buffer shell-buf (agent-shell-cwd)))))
    (agent-shell-insert :text text :shell-buffer shell-buf)))

;;;###autoload
(defun consult-agent-shell-queue-request (shell-buf prompt)
  "Queue PROMPT to SHELL-BUF.
Interactively, pick the shell with Consult and read the prompt string.
If the shell is busy the request is queued; otherwise submitted immediately."
  (interactive
   (let* ((buf (consult-agent-shell--select-or-create))
          (prompt-str (read-string
                       (or (map-nested-elt
                            (with-current-buffer buf (agent-shell--state))
                            '(:agent-config :shell-prompt))
                           "Request: "))))
     (list buf prompt-str)))
  (with-current-buffer shell-buf
    (agent-shell-queue-request prompt)))

;;;###autoload
(defun consult-agent-shell-rename (shell-buf new-name)
  "Rename a selected agent-shell buffer to NEW-NAME.
Interactively, pick the shell with Consult and read the new name."
  (interactive
   (let* ((buf (consult-agent-shell--select-or-create))
          (name (string-trim
                 (read-string "Rename buffer: " (buffer-name buf)))))
     (list buf name)))
  (shell-maker-set-buffer-name shell-buf new-name))

(defun consult-agent-shell--collect-items (buf)
  "Return a list of navigatable fragment candidates in BUF.
Each element is a cons of (DISPLAY-STRING . POSITION)."
  (with-current-buffer buf
    (require 'text-property-search)
    (save-excursion
      (goto-char (point-min))
      (let (items seen)
        (while-let ((match (text-property-search-forward
                            'agent-shell-ui-state nil
                            (lambda (_ state)
                              (and state (map-elt state :navigatable))))))
          (let* ((pos (prop-match-beginning match))
                 (state (get-text-property pos 'agent-shell-ui-state))
                 (qid (map-elt state :qualified-id)))
            (unless (member qid seen)
              (push qid seen)
              (let* ((fragment (agent-shell-ui--read-fragment-at pos qid))
                     (label-right (map-elt fragment :label-right))
                     (label-left  (map-elt fragment :label-left))
                     (display (string-trim
                               (concat
                                (when label-left
                                  (concat (substring-no-properties label-left) " "))
                                (when label-right
                                  (substring-no-properties label-right))))))
                (unless (string-empty-p display)
                  (push (cons display pos) items))))))
        (nreverse items)))))

;;;###autoload
(defun consult-agent-shell-jump-to-item ()
  "Jump to a navigatable item in the current agent-shell buffer.
Presents tool calls, thoughts, plans, and other fragments via Consult."
  (interactive)
  (unless (derived-mode-p 'agent-shell-mode)
    (user-error "Not in an agent-shell buffer"))
  (let* ((buf (current-buffer))
         (items (consult-agent-shell--collect-items buf))
         (candidates (mapcar #'car items))
         (state-fn (lambda (action candidate)
                     (when (eq action 'preview)
                       (when-let* ((pos (cdr (assoc candidate items))))
                         (with-current-buffer buf
                           (goto-char pos)
                           (recenter))))))
         (selected (consult--read
                    candidates
                    :prompt "Jump to: "
                    :require-match t
                    :sort nil
                    :state state-fn)))
    (when-let ((pos (cdr (assoc selected items))))
      (goto-char pos)
      (recenter))))

(provide 'consult-agent-shell)

;;; consult-agent-shell.el ends here
