;;; tau-agent-session.el --- Structured conversation persistence -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Versioned JSON sessions contain text and protocol records, never OAuth
;; credentials.  Loading a session neither sends requests nor runs tools.

;;; Code:

(require 'tau-agent-core)
(declare-function tau-agent--idle-only "tau-agent")
(declare-function tau-agent--system-text "tau-agent")
(declare-function tau-agent--text "tau-agent" (overlay))
(declare-function tau-agent--append "tau-agent" (role text &optional wire draft))
(declare-function tau-agent--refresh-tools "tau-agent" ())
(declare-function tau-agent-mode "tau-agent" (&optional arg))
(declare-function markdown-mode "markdown-mode" ())
(defvar tau-agent--messages)
(defvar tau-agent--root)
(defvar tau-agent--prompt)
(defvar tau-agent--session-file)
(defvar tau-agent--draft)
(defvar tau-agent--next-id)
(defvar tau-agent-model)
(defvar tau-agent-reasoning-effort)
(defvar tau-agent--usage)
(defvar tau-agent--usage-total)

(defun tau-agent-session--data ()
  "Return the current conversation as a JSON-compatible plist."
  (list :version 1 :directory tau-agent--root :model tau-agent-model
        :reasoning_effort tau-agent-reasoning-effort
        :system_prompt (tau-agent--system-text)
        :usage tau-agent--usage :usage_total tau-agent--usage-total
        :messages
        (vconcat
         (mapcar (lambda (ov)
                   (list :id (overlay-get ov 'tau-id)
                         :role (symbol-name (overlay-get ov 'tau-role))
                         :text (tau-agent--text ov)
                         :draft (if (overlay-get ov 'tau-draft) t :json-false)
                         :wire (overlay-get ov 'tau-wire)))
                 ;; Store the system text once, and regenerate the tools
                 ;; list from current definitions when loading a session.
                 (cl-remove-if (lambda (ov) (memq (overlay-get ov 'tau-role) '(system tools)))
                               tau-agent--messages)))))

(defun tau-agent-session--validate (data)
  "Validate session DATA before creating or modifying a buffer."
  (unless (eql (plist-get data :version) 1) (user-error "Unsupported tau-agent session version"))
  (dolist (key '(:directory :model :reasoning_effort :system_prompt))
    (unless (stringp (plist-get data key)) (user-error "Invalid session field %s" key)))
  (unless (and (file-name-absolute-p (plist-get data :directory))
               (member (plist-get data :reasoning_effort)
                       '("none" "minimal" "low" "medium" "high" "xhigh")))
    (user-error "Invalid session directory or reasoning effort"))
  (let ((usage (plist-get data :usage)) (total (plist-get data :usage_total)))
    (unless (and (listp usage)
                 (cl-every (lambda (value) (or (null value)
                                               (and (integerp value) (>= value 0))))
                           (cons total (mapcar (lambda (key) (plist-get usage key))
                                               '(:input :output :cached :reasoning)))))
      (user-error "Invalid session token usage")))
  (let ((messages (plist-get data :messages)) ids calls results (drafts 0))
    (unless (vectorp messages) (user-error "Session messages must be an array"))
    (seq-doseq (message messages)
      (let ((role (plist-get message :role)) (id (plist-get message :id))
            (wire (plist-get message :wire)))
        (unless (and (member role '("user" "assistant" "tool-call" "tool-result" "reasoning" "error"))
                     (stringp (plist-get message :text))
                     (integerp id) (> id 0) (not (memq id ids))
                     (memq (plist-get message :draft) '(t :json-false)))
          (user-error "Invalid session message"))
        (push id ids)
        (when (eq (plist-get message :draft) t)
          (cl-incf drafts)
          (unless (and (equal role "user") (eq message (aref messages (1- (length messages)))))
            (user-error "Draft must be the final user message")))
        (when wire
          (pcase role
            ("tool-call"
             (unless (and (equal (plist-get wire :type) "function_call")
                          (stringp (plist-get wire :call_id))
                          (stringp (plist-get wire :name))
                          (stringp (plist-get wire :arguments))
                          (not (member (plist-get wire :call_id) calls)))
               (user-error "Invalid tool call record"))
             (push (plist-get wire :call_id) calls))
            ("tool-result"
             (unless (and (equal (plist-get wire :type) "function_call_output")
                          (member (plist-get wire :call_id) calls)
                          (not (member (plist-get wire :call_id) results))
                          (stringp (plist-get wire :output)))
               (user-error "Invalid tool result record"))
             (push (plist-get wire :call_id) results))
            ("reasoning"
             (unless (equal (plist-get wire :type) "reasoning")
               (user-error "Invalid reasoning record")))))))
    (unless (= drafts 1) (user-error "Session must contain exactly one draft"))
    (unless (equal (sort calls #'string<) (sort results #'string<))
      (user-error "Session contains unanswered tool calls")))
  data)

;;;###autoload
(defun tau-agent-save-session (&optional file)
  "Save this idle conversation to FILE, prompting on first save."
  (interactive)
  (tau-agent--idle-only)
  (setq file (expand-file-name
              (or file tau-agent--session-file
                  (read-file-name "Save session: " nil nil nil "conversation.tau.json"))))
  (let ((data (tau-agent-session--data)) temporary)
    (tau-agent-session--validate data)
    (when (and (file-exists-p file) (not (equal file tau-agent--session-file))
               (called-interactively-p 'interactive)
               (not (yes-or-no-p "Overwrite existing session file? ")))
      (user-error "Save canceled"))
    (unwind-protect
        (progn
          (setq temporary (make-temp-file (expand-file-name ".tau-session-" (file-name-directory file))))
          (set-file-modes temporary #o600)
          (let ((coding-system-for-write 'utf-8-unix))
            (write-region (tau-agent--json data) nil temporary nil 'silent))
          (rename-file temporary file t)
          (setq tau-agent--session-file file)
          (set-buffer-modified-p nil)
          (message "Saved tau-agent session: %s" file))
      (when (and temporary (file-exists-p temporary)) (delete-file temporary)))))

;;;###autoload
(defun tau-agent-load-session (file)
  "Load FILE as a new conversation without executing any actions."
  (interactive "fLoad tau-agent session: ")
  (require 'tau-agent)
  (setq file (expand-file-name file))
  (let* ((data (tau-agent-session--validate
                (with-temp-buffer
                  (insert-file-contents file)
                  (tau-agent--json-read (buffer-string)))))
         (buffer (generate-new-buffer "*tau-agent*")))
    (with-current-buffer buffer
      (markdown-mode)
      (setq tau-agent--root (file-name-as-directory (plist-get data :directory))
            default-directory tau-agent--root
            tau-agent-model (plist-get data :model)
            tau-agent-reasoning-effort (plist-get data :reasoning_effort)
            tau-agent--prompt (plist-get data :system_prompt)
            tau-agent--usage (plist-get data :usage)
            tau-agent--usage-total (plist-get data :usage_total)
            tau-agent--session-file (expand-file-name file))
      (tau-agent-mode 1)
      ;; Allocate a fresh ID for the system overlay without colliding with
      ;; IDs from sessions saved before inline system messages existed.
      (setq tau-agent--next-id
            (seq-reduce (lambda (maximum message) (max maximum (plist-get message :id)))
                        (plist-get data :messages) 0))
      (tau-agent--append 'system tau-agent--prompt)
      (tau-agent--refresh-tools)
      (seq-doseq (message (plist-get data :messages))
        (let* ((draft (eq (plist-get message :draft) t))
               (ov (tau-agent--append (intern (plist-get message :role))
                                      (plist-get message :text)
                                      (plist-get message :wire) draft)))
          (overlay-put ov 'tau-id (plist-get message :id))
          (setq tau-agent--next-id (max tau-agent--next-id (plist-get message :id)))
          (when draft (setq tau-agent--draft ov))))
      (goto-char (overlay-end tau-agent--draft))
      (set-buffer-modified-p nil)
      (unless (file-directory-p tau-agent--root)
        (message "Session directory is missing: %s" tau-agent--root)))
    (pop-to-buffer buffer)
    buffer))

(provide 'tau-agent-session)
;;; tau-agent-session.el ends here
