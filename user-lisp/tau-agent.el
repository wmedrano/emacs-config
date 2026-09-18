;;; tau-agent.el --- A small overlay-based coding agent -*- lexical-binding: t; -*-

;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1") (markdown-mode "2.6"))
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; M-x tau-agent opens a Markdown conversation.  C-c C-c sends its draft,
;; C-c C-k cancels, and C-x C-s saves a resumable JSON session.  The
;; system, user, and assistant messages are editable; tool records and
;; boundaries are not.

;;; Code:

(require 'tau-agent-core)
(require 'tau-agent-transport)
(require 'tau-agent-tools)
(require 'project)
(require 'markdown-mode)

(defcustom tau-agent-model "gpt-5.6-luna"
  "Model used for new conversations."
  :type 'string :group 'tau-agent)
(make-variable-buffer-local 'tau-agent-model)
(defcustom tau-agent-reasoning-effort "medium"
  "Reasoning effort sent on every request.
Supported values depend on the selected model.  The server reports any
unsupported model/effort combination; tau-agent does not silently downgrade."
  :type '(choice (const "none") (const "minimal") (const "low")
                 (const "medium") (const "high") (const "xhigh"))
  :group 'tau-agent)
(make-variable-buffer-local 'tau-agent-reasoning-effort)
(defcustom tau-agent-system-prompt
  "You are an expert coding assistant operating inside Emacs. You help users by reading files, executing commands, editing code, and writing new files.\n\n<rules>\n- Use bash for file operations like ls, rg, find\n- Be concise in your responses\n- Show file paths clearly when working with files\n</rules>"
  "Base system prompt for new conversations."
  :type 'string :group 'tau-agent)
(defcustom tau-agent-tools
  (list tau-agent-tools-shell-tool tau-agent-tools-read-file-tool
        tau-agent-tools-edit-file-tool tau-agent-tools-write-file-tool)
  "Tools available to the agent, made with `tau-agent-make-tool'."
  :type '(repeat sexp) :group 'tau-agent)
(make-variable-buffer-local 'tau-agent-tools)
(defcustom tau-agent-collapse-tools t
  "Whether new tool requests and results start collapsed."
  :type 'boolean :group 'tau-agent)

(defface tau-agent-system-face '((t (:foreground "LightCoral")))
  "Fringe face for the system instructions." :group 'tau-agent)
(defface tau-agent-tools-face '((t (:foreground "LightSlateGray")))
  "Fringe face for the available tools list." :group 'tau-agent)
(defface tau-agent-user-face '((t (:foreground "DeepSkyBlue")))
  "Fringe face for user messages." :group 'tau-agent)
(defface tau-agent-assistant-face '((t (:foreground "MediumSeaGreen")))
  "Fringe face for assistant messages." :group 'tau-agent)
(defface tau-agent-tool-call-face '((t (:foreground "MediumPurple")))
  "Fringe face for tool calls." :group 'tau-agent)
(defface tau-agent-tool-result-face '((t (:foreground "Goldenrod")))
  "Fringe face for tool results." :group 'tau-agent)
(defface tau-agent-error-face '((t (:inherit error)))
  "Fringe face for request errors." :group 'tau-agent)
;; Repeat the row to fill the display line, including larger/scaled fonts.
(define-fringe-bitmap 'tau-agent-bar [#b00111100] 1 8 '(center t))

(defvar-local tau-agent--messages nil)
(defvar-local tau-agent--next-id 0)
(defvar-local tau-agent--root nil)
(defvar-local tau-agent--prompt nil)
(defvar-local tau-agent--session-file nil)
(defvar-local tau-agent--activity "Idle")
(defvar-local tau-agent--generation 0)
(defvar-local tau-agent--active nil)
(defvar-local tau-agent--stream nil)
(defvar-local tau-agent--tool-process nil)
(defvar-local tau-agent--queue nil)
(defvar-local tau-agent--tool-current nil)
(defvar-local tau-agent--draft nil)
(defvar tau-agent--internal nil)
(defvar tau-agent-mode)
(defvar-local tau-agent--guard nil)
(defvar-local tau-agent--usage nil)
(defvar-local tau-agent--usage-total nil)

(defun tau-agent--status ()
  "Return the current activity with a status icon."
  (concat (cond ((equal tau-agent--activity "Error") "❌")
                ((equal tau-agent--activity "Canceled") "⏹️")
                ((string-prefix-p "Tool:" tau-agent--activity) "🛠️")
                ((equal tau-agent--activity "Responding") "✍️")
                (tau-agent--active "🤔")
                (t "✅"))
          " " tau-agent--activity))

(defun tau-agent--usage-text ()
  "Describe last-response usage and cumulative reported session tokens."
  (format "Tokens in:%s out:%s cache:%s reason:%s | Σ:%s"
          (or (plist-get tau-agent--usage :input) "?")
          (or (plist-get tau-agent--usage :output) "?")
          (or (plist-get tau-agent--usage :cached) "?")
          (or (plist-get tau-agent--usage :reasoning) "?")
          (or tau-agent--usage-total "?")))

(defun tau-agent--record-usage (response)
  "Record token usage from a terminal RESPONSE exactly once per request."
  (let* ((usage (plist-get response :usage))
         (input (plist-get usage :input_tokens))
         (output (plist-get usage :output_tokens))
         (total (or (plist-get usage :total_tokens)
                    (and (numberp input) (numberp output) (+ input output)))))
    (setq tau-agent--usage
          (list :input input :output output
                :cached (plist-get (plist-get usage :input_tokens_details) :cached_tokens)
                :reasoning (plist-get (plist-get usage :output_tokens_details) :reasoning_tokens)))
    (when (and (numberp total) (>= total 0))
      (setq tau-agent--usage-total (+ (or tau-agent--usage-total 0) total))))
  (force-mode-line-update))

(defun tau-agent--header ()
  "Render the compact first row of this conversation's header."
  (list " " (list :eval '(propertize tau-agent-model 'face 'mode-line-emphasis))
        "  |  Reasoning: " (list :eval 'tau-agent-reasoning-effort)
        "  |  " (list :eval '(file-name-nondirectory
                              (directory-file-name (or tau-agent--root default-directory))))))

(defun tau-agent--tab-line ()
  "Render the status and token statistics on the second header row."
  (concat " " (tau-agent--status) "  |  " (tau-agent--usage-text)))

(defun tau-agent--idle-only ()
  "Require an idle tau-agent conversation."
  (unless tau-agent-mode (user-error "Not a tau-agent conversation"))
  (when tau-agent--active (user-error "Cancel the active turn first")))

(defun tau-agent-set-reasoning-effort (effort)
  "Set this conversation's reasoning EFFORT for subsequent requests."
  (interactive
   (list (completing-read "Reasoning effort: "
                          '("none" "minimal" "low" "medium" "high" "xhigh")
                          nil t nil nil tau-agent-reasoning-effort)))
  (tau-agent--idle-only)
  (unless (member effort '("none" "minimal" "low" "medium" "high" "xhigh"))
    (user-error "Unknown reasoning effort: %s" effort))
  (setq tau-agent-reasoning-effort effort)
  (set-buffer-modified-p t)
  (force-mode-line-update))

(defun tau-agent-set-model (model)
  "Set this conversation's MODEL for subsequent requests."
  (interactive (list (read-string "Model: " tau-agent-model)))
  (tau-agent--idle-only)
  (when (string-empty-p model) (user-error "Model cannot be empty"))
  (setq tau-agent-model model)
  (set-buffer-modified-p t)
  (force-mode-line-update))

(defun tau-agent--text (overlay)
  "Return the body of message OVERLAY without text properties."
  (buffer-substring-no-properties (overlay-start overlay) (overlay-end overlay)))

(defun tau-agent--append (role text &optional wire draft)
  "Append a ROLE message with TEXT, optional WIRE data and DRAFT flag."
  (let ((tau-agent--internal t) (inhibit-read-only t) (buffer-undo-list t))
    (save-excursion
      (goto-char (point-max))
      (let ((heading (copy-marker (point))))
	(unless (eq role 'reasoning)
          (insert (format "\n\n### %s\n\n"
                          (if (eq role 'user) "You" (capitalize (symbol-name role))))))
	(let* ((begin (point))
               (_ (insert text))
               (overlay (make-overlay begin (point) nil nil t))
               (face (intern (format "tau-agent-%s-face" role))))
          (overlay-put overlay 'tau-agent t)
          (overlay-put overlay 'tau-id (cl-incf tau-agent--next-id))
          (overlay-put overlay 'tau-role role)
          (overlay-put overlay 'tau-wire wire)
          (overlay-put overlay 'tau-draft draft)
          (overlay-put overlay 'tau-heading heading)
          (when (facep face)
            (let ((prefix (propertize " " 'display `(left-fringe tau-agent-bar ,face))))
              (overlay-put overlay 'line-prefix prefix)
              (overlay-put overlay 'wrap-prefix prefix)))
          (when (eq role 'reasoning) (overlay-put overlay 'invisible t))
          ;; A non-message newline keeps neighboring zero-width bodies distinct.
          (insert "\n")
          (move-overlay overlay begin (1- (point)))
          (setq tau-agent--messages (append tau-agent--messages (list overlay)))
          (when (memq role '(tool-call tool-result))
            (overlay-put overlay 'tau-collapsed tau-agent-collapse-tools)
            (tau-agent--refresh-fold overlay))
          overlay)))))

(defun tau-agent--refresh-fold (overlay)
  "Update OVERLAY's display without changing its underlying text."
  (when (memq (overlay-get overlay 'tau-role) '(tool-call tool-result))
    (overlay-put
     overlay 'display
     (when (overlay-get overlay 'tau-collapsed)
       (let* ((text (tau-agent--text overlay))
              (preview (truncate-string-to-width
                        (replace-regexp-in-string "[\n\r\t]+" " " text) 80 nil nil "…")))
         (format "▸ %s  [%d chars; TAB to expand]" preview (length text)))))))

(defun tau-agent-toggle-tool ()
  "Toggle the tool request or result at point; otherwise use Markdown TAB."
  (interactive)
  (if-let* ((overlay
             (cl-find-if
              (lambda (ov)
                (and (memq (overlay-get ov 'tau-role) '(tool-call tool-result))
                     (<= (or (overlay-get ov 'tau-heading) (overlay-start ov))
                         (point) (overlay-end ov))))
              tau-agent--messages)))
      (progn
        (overlay-put overlay 'tau-collapsed (not (overlay-get overlay 'tau-collapsed)))
        (tau-agent--refresh-fold overlay)
        (when (> (point) (overlay-start overlay))
          (goto-char (overlay-start overlay))))
    (call-interactively #'markdown-cycle)))

(defun tau-agent--replace-text (overlay text)
  "Replace OVERLAY body with TEXT during internal rendering."
  (let ((tau-agent--internal t) (inhibit-read-only t) (buffer-undo-list t))
    (save-excursion
      (goto-char (overlay-start overlay))
      (delete-region (overlay-start overlay) (overlay-end overlay))
      (insert text))
    (tau-agent--refresh-fold overlay)))

(defun tau-agent--before-change (begin end)
  "Protect message boundaries and tool records between BEGIN and END."
  (unless tau-agent--internal
    (when tau-agent--active (user-error "Cancel the active turn before editing"))
    (unless (cl-find-if
             (lambda (ov)
               (and (memq (overlay-get ov 'tau-role) '(system user assistant))
                    (<= (overlay-start ov) begin end (overlay-end ov))))
             tau-agent--messages)
      (user-error "Edit inside a system, user or assistant message; generated sections and boundaries are protected"))))

(defun tau-agent--guard-change (_overlay after begin end &optional _length)
  "Before changes, protect the region from BEGIN to END unless AFTER is set."
  (unless after (tau-agent--before-change begin end)))

(defun tau-agent--new-draft ()
  "Create the next editable user draft."
  (unless tau-agent--draft
    (setq tau-agent--draft (tau-agent--append 'user "" nil t)))
  (goto-char (overlay-end tau-agent--draft)))

(defun tau-agent--tools-text ()
  "Describe the tools currently configured for this conversation."
  (if (null tau-agent-tools)
      "No tools enabled."
    (mapconcat
     (lambda (tool)
       (format "#### %s(%s)\n\n%s"
               (tau-agent-tool-name tool)
               (mapconcat (lambda (arg)
                            (format "%s%s: %s" (plist-get arg :name)
                                    (if (plist-get arg :optional) "?" "")
                                    (plist-get arg :type)))
                          (tau-agent-tool-args tool) ", ")
               (or (tau-agent-tool-description tool) "")))
     tau-agent-tools "\n\n")))

(defun tau-agent--refresh-tools ()
  "Update the generated tools overlay from the current tool definitions."
  (let ((text (tau-agent--tools-text))
        (overlay (cl-find 'tools tau-agent--messages
                          :key (lambda (ov) (overlay-get ov 'tau-role)))))
    (if overlay
        (unless (equal text (tau-agent--text overlay))
          (tau-agent--replace-text overlay text))
      (tau-agent--append 'tools text))))

(defun tau-agent-refresh-tools ()
  "Refresh the read-only tools list after changing `tau-agent-tools'.
The list also refreshes automatically before each request."
  (interactive)
  (tau-agent--idle-only)
  (tau-agent--refresh-tools))

(defun tau-agent--system-text ()
  "Return the current editable system prompt."
  (if-let* ((overlay (cl-find 'system tau-agent--messages
                              :key (lambda (ov) (overlay-get ov 'tau-role)))))
      (tau-agent--text overlay)
    ;; Keep already-open conversations usable after reloading the library.
    tau-agent--prompt))

(defun tau-agent-edit-system-prompt ()
  "Move to the editable system message in this conversation."
  (interactive)
  (tau-agent--idle-only)
  (if-let* ((overlay (cl-find 'system tau-agent--messages
                              :key (lambda (ov) (overlay-get ov 'tau-role)))))
      (goto-char (overlay-start overlay))
    (user-error "Save and reload this conversation to show its system message")))

(defun tau-agent-insert-reference ()
  "Insert a relative file path, or literal @ when completion is canceled.
Use project files relative to its root, or files in `default-directory'."
  (interactive)
  (let ((start (point)))
    (insert "@")
    (condition-case nil
        (let* ((project (project-current))
               (root (if project (project-root project) default-directory))
               (default-directory root)
               (files (if project (project-files project)
                        (seq-filter #'file-regular-p
                                    (directory-files root t directory-files-no-dot-files-regexp))))
               (relative (mapcar (lambda (file) (file-relative-name file root)) files)))
          (when relative
            (let ((file (completing-read "File: " relative nil t)))
              (unless (string-empty-p file)
                (delete-region start (point))
                (insert file)))))
      (quit nil))))

(defun tau-agent--input ()
  "Build Responses input from current overlay text and protocol records."
  (vconcat
   (delq nil
         (mapcar
          (lambda (ov)
            (unless (overlay-get ov 'tau-draft)
              (pcase (overlay-get ov 'tau-role)
                ((or 'user 'assistant)
                 (let ((text (tau-agent--text ov)))
                   (unless (string-empty-p text)
                     (list :role (symbol-name (overlay-get ov 'tau-role))
                           :content text))))
                ((or 'reasoning 'tool-call 'tool-result) (overlay-get ov 'tau-wire)))))
          tau-agent--messages))))

(defun tau-agent--wire-overlay (item)
  "Find or create the overlay for response ITEM."
  (let* ((id (plist-get item :id))
         (existing (and id (cl-find id tau-agent--messages :test #'equal
                                    :key (lambda (ov) (overlay-get ov 'tau-item-id)))))
         (role (pcase (plist-get item :type)
                 ("message" 'assistant) ("function_call" 'tool-call)
                 ("reasoning" 'reasoning))))
    (when role
      (let ((ov (or existing (tau-agent--append role ""))))
        (overlay-put ov 'tau-item-id id)
        ov))))

(defun tau-agent--accept-item (item)
  "Record a completed response ITEM, including its protocol fields."
  (when-let* ((ov (tau-agent--wire-overlay item)))
    (overlay-put ov 'tau-wire item)
    (pcase (plist-get item :type)
      ("message"
       (tau-agent--replace-text
        ov (mapconcat (lambda (part) (or (plist-get part :text)
                                         (plist-get part :refusal) ""))
                      (plist-get item :content) "")))
      ("function_call"
       (tau-agent--replace-text ov (format "%s\n%s" (plist-get item :name)
                                           (plist-get item :arguments)))))))

(defun tau-agent--event (event)
  "Apply a streaming EVENT to this buffer."
  (pcase (plist-get event :type)
    ("response.output_item.added" (tau-agent--wire-overlay (plist-get event :item)))
    ("response.output_item.done" (tau-agent--accept-item (plist-get event :item)))
    ("response.output_text.delta"
     (let ((ov (tau-agent--wire-overlay
                (list :type "message" :id (plist-get event :item_id)))))
       (let ((tau-agent--internal t) (inhibit-read-only t) (buffer-undo-list t))
         (save-excursion
           (goto-char (overlay-end ov))
           (insert (plist-get event :delta))))))))

(defun tau-agent--finish (&optional error-text)
  "Finish the active turn, displaying ERROR-TEXT when supplied."
  (setq tau-agent--active nil tau-agent--stream nil tau-agent--tool-process nil
        tau-agent--queue nil tau-agent--tool-current nil buffer-read-only nil
        tau-agent--activity (if error-text "Error" "Idle"))
  (when error-text (tau-agent--append 'error error-text))
  (tau-agent--new-draft)
  (force-mode-line-update))

(defun tau-agent--request ()
  "Start a request using this conversation's current history."
  (tau-agent--refresh-tools)
  (setq tau-agent--activity "Thinking")
  (force-mode-line-update)
  (let ((buffer (current-buffer)) (generation tau-agent--generation)
        (message-count (length tau-agent--messages)))
    (condition-case err
        (setq tau-agent--stream
              (tau-agent-transport-start
               (list :model tau-agent-model :instructions (tau-agent--system-text)
                     :input (tau-agent--input) :store :json-false :stream t
                     :include ["reasoning.encrypted_content"]
                     :reasoning (list :effort tau-agent-reasoning-effort)
                     :tools (vconcat (mapcar #'tau-agent-tool-schema tau-agent-tools)))
               (lambda (kind data)
                 (when (buffer-live-p buffer)
                   (with-current-buffer buffer
                     (when (and tau-agent--active (= generation tau-agent--generation))
                       (condition-case failure
                           (pcase kind
                             ('event
                              (when (equal (plist-get data :type) "response.output_text.delta")
                                (setq tau-agent--activity "Responding")
                                (force-mode-line-update))
                              (tau-agent--event data))
                             ('done
                              (setq tau-agent--stream nil)
                              (tau-agent--record-usage (plist-get data :response))
                              (if-let* ((error-text (plist-get data :error)))
                                  (tau-agent--fail error-text)
                                (let ((output (plist-get (plist-get data :response) :output)))
                                  (mapc #'tau-agent--accept-item output)
                                  ;; Item events can contain calls omitted from
                                  ;; the terminal output array.  Reconcile both
                                  ;; sources above, then use this request's
                                  ;; overlays to preserve order without replay.
                                  (setq tau-agent--queue
                                        (cl-loop for ov in (nthcdr message-count tau-agent--messages)
                                                 when (eq (overlay-get ov 'tau-role) 'tool-call)
                                                 collect (or (overlay-get ov 'tau-wire)
                                                             (error "Response ended with an incomplete tool call"))))
                                  (tau-agent--run-next-tool)))))
                         (error (tau-agent--fail (error-message-string failure))))))))))
      (error (tau-agent--fail (error-message-string err))))))

(defun tau-agent--tool-result (call text)
  "Record TEXT as the result of CALL."
  (tau-agent--append 'tool-result text
                     (list :type "function_call_output" :call_id (plist-get call :call_id)
                           :output text)))

(defun tau-agent--run-next-tool ()
  "Execute the next queued tool, continuing the model after the last one."
  (if (null tau-agent--queue)
      (if tau-agent--tool-current
          (progn (setq tau-agent--tool-current nil) (tau-agent--request))
        (tau-agent--finish))
    (let* ((call (pop tau-agent--queue))
           (tool (cl-find (plist-get call :name) tau-agent-tools
                          :key #'tau-agent-tool-name :test #'equal))
           (buffer (current-buffer)) (generation tau-agent--generation)
           (delivered nil))
      (setq tau-agent--tool-current call
            tau-agent--activity (format "Tool: %s" (plist-get call :name)))
      (force-mode-line-update)
      (cl-labels
          ((complete (result)
             (unless delivered
               (setq delivered t)
               (when (buffer-live-p buffer)
                 (with-current-buffer buffer
                   (when (and tau-agent--active (= generation tau-agent--generation))
                     (setq tau-agent--tool-process nil)
                     (tau-agent--tool-result call (format "%s" result))
                     (tau-agent--run-next-tool)))))))
        (condition-case err
            (progn
              (unless tool (error "Unknown tool: %s" (plist-get call :name)))
              (let* ((args (tau-agent--json-read (plist-get call :arguments)))
                     (values
                      (mapcar
                       (lambda (spec)
                         (let ((key (intern (concat ":" (plist-get spec :name)))))
                           (unless (or (plist-member args key) (plist-get spec :optional))
                             (error "Missing argument %s" key))
                           (plist-get args key)))
                       (tau-agent-tool-args tool)))
                     (default-directory tau-agent--root))
                (if (tau-agent-tool-async tool)
                    (let ((process (apply (tau-agent-tool-function tool) #'complete values)))
                      (unless delivered (setq tau-agent--tool-process process)))
                  (complete (apply (tau-agent-tool-function tool) values)))))
          (error (complete (concat "Tool error: " (error-message-string err)))))))))

(defun tau-agent--interrupt-records ()
  "Pair any completed but unanswered tool calls with interruption results."
  (let ((answered (mapcar (lambda (ov)
                            (when (eq (overlay-get ov 'tau-role) 'tool-result)
                              (plist-get (overlay-get ov 'tau-wire) :call_id)))
                          tau-agent--messages)))
    (dolist (ov (copy-sequence tau-agent--messages))
      (let ((wire (overlay-get ov 'tau-wire)))
        (when (and (eq (overlay-get ov 'tau-role) 'tool-call) wire
                   (not (member (plist-get wire :call_id) answered)))
          (tau-agent--tool-result
           wire "Interrupted. Execution may have partially completed; inspect state before retrying."))))))

(defun tau-agent--stop ()
  "Invalidate callbacks and stop owned request and tool processes."
  (cl-incf tau-agent--generation)
  (when tau-agent--stream (tau-agent-transport-cancel tau-agent--stream))
  (when (and (processp tau-agent--tool-process) (process-live-p tau-agent--tool-process))
    (kill-process tau-agent--tool-process))
  (setq tau-agent--stream nil tau-agent--tool-process nil))

(defun tau-agent--fail (text)
  "Stop the current turn and display failure TEXT."
  (tau-agent--stop)
  (tau-agent--interrupt-records)
  (tau-agent--finish text))

(defun tau-agent-cancel ()
  "Cancel the current turn without undoing tool side effects."
  (interactive)
  (when tau-agent--active
    (tau-agent--fail "Turn canceled; any completed tool effects remain.")
    (setq tau-agent--activity "Canceled")
    (force-mode-line-update)))

(defun tau-agent-send ()
  "Submit the draft and run the agent until it finishes or is canceled."
  (interactive)
  (tau-agent--idle-only)
  (unless (file-directory-p tau-agent--root) (user-error "Working directory no longer exists"))
  (unless (and tau-agent--draft (not (string-blank-p (tau-agent--text tau-agent--draft))))
    (user-error "Write a message in the draft first"))
  (overlay-put tau-agent--draft 'tau-draft nil)
  (setq tau-agent--draft nil tau-agent--active t buffer-read-only t)
  (cl-incf tau-agent--generation)
  (tau-agent--request))

(defun tau-agent--kill ()
  "Release resources owned by the conversation being killed."
  (tau-agent--stop))

(defvar tau-agent-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'tau-agent-send)
    (define-key map (kbd "C-c C-k") #'tau-agent-cancel)
    (define-key map (kbd "C-c C-r") #'tau-agent-set-reasoning-effort)
    (define-key map (kbd "C-c C-m") #'tau-agent-set-model)
    (define-key map (kbd "C-x C-s") #'tau-agent-save-session)
    (define-key map "@" #'tau-agent-insert-reference)
    (define-key map (kbd "TAB") #'tau-agent-toggle-tool)
    (define-key map (kbd "<tab>") #'tau-agent-toggle-tool)
    map)
  "Keymap for tau-agent conversations.")

(define-minor-mode tau-agent-mode
  "Manage an overlay-based Markdown conversation."
  :lighter " Tau" :keymap tau-agent-mode-map
  (if tau-agent-mode
      (progn
        (setq-local header-line-format (tau-agent--header))
        ;; Use the tab line as a second, deliberately simple status row.
        ;; It is buffer-local so ordinary buffers and tab bars are unaffected.
        (tab-line-mode 1)
        (setq-local tab-line-format '((:eval (tau-agent--tab-line))))
        (setq tau-agent--guard (make-overlay (point-min) (point-max) nil nil t))
        (overlay-put tau-agent--guard 'modification-hooks '(tau-agent--guard-change))
        (overlay-put tau-agent--guard 'insert-in-front-hooks '(tau-agent--guard-change))
        (overlay-put tau-agent--guard 'insert-behind-hooks '(tau-agent--guard-change))
        (add-hook 'kill-buffer-hook #'tau-agent--kill nil t)
        (visual-line-mode 1)
        (display-line-numbers-mode -1))
    (tau-agent--kill)
    (when tau-agent--guard (delete-overlay tau-agent--guard))
    (setq header-line-format nil tab-line-format nil buffer-read-only nil)
    (tab-line-mode -1)))

;;;###autoload
(defun tau-agent (&optional directory)
  "Create a conversation rooted in DIRECTORY or the current project."
  (interactive)
  (let* ((root (file-name-as-directory
                (expand-file-name
                 (or directory (when-let* ((project (project-current))) (project-root project))
                     default-directory))))
         (agents (expand-file-name "AGENTS.md" root))
         (prompt (concat tau-agent-system-prompt
                         (format "\n\n<cwd>\n%s\n</cwd>" (directory-file-name root))
                         (when (file-readable-p agents)
                           (format "\n\n<project_instructions path=%S>\n%s\n</project_instructions>"
                                   agents (with-temp-buffer (insert-file-contents agents) (buffer-string))))))
         (buffer (generate-new-buffer "*tau-agent*")))
    (with-current-buffer buffer
      (markdown-mode)
      (setq default-directory root tau-agent--root root tau-agent--prompt prompt)
      (tau-agent-mode 1)
      (tau-agent--append 'system prompt)
      (tau-agent--refresh-tools)
      (tau-agent--new-draft)
      (set-buffer-modified-p nil))
    (pop-to-buffer buffer)
    buffer))

(require 'tau-agent-session)

(provide 'tau-agent)
;;; tau-agent.el ends here
