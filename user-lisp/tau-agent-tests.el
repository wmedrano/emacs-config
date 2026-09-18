;;; tau-agent-tests.el --- Agent regression tests -*- lexical-binding: t; -*-

;;; Commentary:
;; Offline tests: no credentials or network requests are needed.

;;; Code:

(require 'ert)
(require 'tab-line)
(require 'tau-agent)

(defmacro tau-agent-test--buffer (&rest body)
  "Execute BODY inside an initialized temporary conversation."
  (declare (indent 0) (debug t))
  `(with-temp-buffer
     (markdown-mode)
     (setq tau-agent--root temporary-file-directory
           tau-agent--prompt "Test instructions")
     (tau-agent-mode 1)
     (tau-agent--append 'system tau-agent--prompt)
     (tau-agent--refresh-tools)
     (tau-agent--new-draft)
     ,@body))

(ert-deftest tau-agent-overlay-editing ()
  (tau-agent-test--buffer
    (buffer-enable-undo)
    (let ((draft tau-agent--draft))
      (insert "first\nsecond")
      (should (equal (tau-agent--text draft) "first\nsecond"))
      (should-not (text-property-not-all (overlay-start draft) (overlay-end draft) 'tau-role nil))
      (should (overlay-get draft 'line-prefix))
      (should (overlay-get draft 'wrap-prefix))
      (overlay-put draft 'tau-draft nil)
      (setq tau-agent--draft nil)
      (let ((answer (tau-agent--append 'assistant "answer")))
        (tau-agent--append 'tool-result "record" '(:type "function_call_output" :call_id "c" :output "record"))
        (tau-agent--new-draft)
        (goto-char (overlay-start draft))
        (undo-boundary)
        (insert "edited ")
        (undo-boundary)
        (should (equal (tau-agent--text draft) "edited first\nsecond"))
        (let ((inhibit-message t)) (undo 1))
        (should (equal (tau-agent--text draft) "first\nsecond"))
        (should (equal (tau-agent--text answer) "answer"))
        (should-error (delete-region (overlay-start draft) (overlay-end answer)) :type 'user-error)
        (goto-char (point-min))
        (should-error (insert "x") :type 'user-error)
        (let ((tool (cl-find 'tool-result tau-agent--messages
                             :key (lambda (ov) (overlay-get ov 'tau-role)))))
          (goto-char (overlay-start tool))
          (should-error (insert "x") :type 'user-error))))))

(ert-deftest tau-agent-empty-boundaries ()
  (tau-agent-test--buffer
    (insert "x")
    (delete-region (overlay-start tau-agent--draft) (overlay-end tau-agent--draft))
    (insert "new")
    (should (equal (tau-agent--text tau-agent--draft) "new"))
    (goto-char (overlay-end tau-agent--draft))
    (insert " end")
    (should (equal (tau-agent--text tau-agent--draft) "new end"))))

(ert-deftest tau-agent-sse-chunking ()
  (let* (events
         (stream (make-tau-agent-stream :callback (lambda (_kind data) (push data events))))
         (text (concat ": heartbeat\r\n\r\n"
                       "event: response.output_text.delta\r\ndata: {\"type\":\"response.output_text.delta\",\"delta\":\"hé🌱\"}\r\n\r\n"
                       "data: {\"type\":\"response.completed\",\"response\":{\"output\":[]}}\n\n")))
    (mapc (lambda (character) (tau-agent-transport--feed stream (string character))) text)
    (should (= (length events) 2))
    (should (equal (plist-get (cadr events) :delta) "hé🌱"))
    (should (tau-agent-stream-response stream))
    (should (equal (tau-agent-stream-pending stream) ""))))

(ert-deftest tau-agent-stream-errors ()
  (let ((stream (make-tau-agent-stream :callback #'ignore)))
    (tau-agent-transport--feed stream "data: {\"type\":\"response.failed\"}\n\n")
    (should (tau-agent-stream-error stream))
    (should-error (tau-agent-transport--feed stream "data: malformed\n\n"))))

(ert-deftest tau-agent-session-roundtrip ()
  (let ((file (make-temp-file "tau-test-")) restored)
    (unwind-protect
        (tau-agent-test--buffer
          (insert "draft text")
          (tau-agent--record-usage
           '(:usage (:input_tokens 100 :output_tokens 20 :total_tokens 120
                     :input_tokens_details (:cached_tokens 50)
                     :output_tokens_details (:reasoning_tokens 10))))
          (tau-agent-set-reasoning-effort "high")
          (tau-agent-edit-system-prompt)
          (insert "Edited: ")
          (let ((original (tau-agent-session--data)))
            (should (equal (plist-get original :system_prompt) "Edited: Test instructions"))
            (should-not (seq-find (lambda (message) (equal (plist-get message :role) "system"))
                                 (plist-get original :messages)))
            (tau-agent-save-session file)
            (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
              (setq restored (tau-agent-load-session file)))
            (with-current-buffer restored
              (should (equal original (tau-agent-session--data)))
              (should (eq (overlay-get (car tau-agent--messages) 'tau-role) 'system))
              (should (eq (overlay-get (cadr tau-agent--messages) 'tau-role) 'tools))
              (should (equal (tau-agent--system-text) "Edited: Test instructions"))
              (let ((ids (mapcar (lambda (ov) (overlay-get ov 'tau-id)) tau-agent--messages)))
                (should (= (length ids) (length (delete-dups (copy-sequence ids))))))
              (should (equal tau-agent-reasoning-effort "high"))
              (should header-line-format)
              (should tab-line-mode)
              (should tab-line-format)
              (should (equal (tau-agent--text tau-agent--draft) "draft text")))))
      (when (buffer-live-p restored) (kill-buffer restored))
      (delete-file file))))

(ert-deftest tau-agent-session-validation ()
  (tau-agent-test--buffer
    (let ((data (tau-agent-session--data)))
      (should (tau-agent-session--validate data))
      (should-error (tau-agent-session--validate (plist-put (copy-tree data) :version 42)))
      (should-error (tau-agent-session--validate (plist-put (copy-tree data) :reasoning_effort "invalid")))
      (should-error (tau-agent-session--validate (plist-put (copy-tree data) :messages []))))))

(ert-deftest tau-agent-inline-system-prompt ()
  (tau-agent-test--buffer
    (let ((system (car tau-agent--messages)) (buffer (current-buffer)) payload)
      (should (eq (overlay-get system 'tau-role) 'system))
      (should (equal (get-text-property 0 'display (overlay-get system 'line-prefix))
                     '(left-fringe tau-agent-bar tau-agent-system-face)))
      (tau-agent-edit-system-prompt)
      (should (eq buffer (current-buffer)))
      (should (= (point) (overlay-start system)))
      (goto-char (overlay-end system))
      (insert " amended")
      (should (equal (tau-agent--system-text) "Test instructions amended"))
      (should (buffer-modified-p))
      (goto-char (overlay-start tau-agent--draft))
      (insert "hello")
      (cl-letf (((symbol-function 'tau-agent-transport-start)
                 (lambda (data _callback) (setq payload data) nil)))
        (tau-agent-send)
        (should (equal (plist-get payload :instructions) "Test instructions amended"))
        (should (equal (plist-get payload :input) [(:role "user" :content "hello")]))
        (tau-agent-cancel)))))

(ert-deftest tau-agent-session-relative-path ()
  (let* ((directory (make-temp-file "tau-save-path-" t))
         (file (expand-file-name "session.json" directory)) restored)
    (unwind-protect
        (tau-agent-test--buffer
          (tau-agent-save-session file)
          (let ((default-directory directory))
            (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
              (setq restored (tau-agent-load-session "session.json"))))
          (with-current-buffer restored
            (should (equal tau-agent--session-file file))))
      (when (buffer-live-p restored) (kill-buffer restored))
      (delete-directory directory t))))

(ert-deftest tau-agent-http-error-details ()
  (should (string-match-p
           "Unsupported effort"
           (tau-agent-transport--http-error
            (make-tau-agent-stream :pending "{\"error\":{\"message\":\"Unsupported effort\"}}")
            "HTTP 400"))))

(ert-deftest tau-agent-tool-loop-and-reasoning ()
  (tau-agent-test--buffer
    (let (callbacks payloads calls)
      (setq tau-agent-tools
            (list (tau-agent-make-tool :name "test" :description "test"
                                      :args '((:name "value" :type string))
                                      :function (lambda (value) (push value calls) (concat "result " value)))))
      (tau-agent-set-reasoning-effort "high")
      (insert "question")
      (cl-letf (((symbol-function 'tau-agent-transport-start)
                 (lambda (payload callback) (push payload payloads) (push callback callbacks) nil)))
        (tau-agent-send)
        (should (equal (plist-get (plist-get (car payloads) :reasoning) :effort) "high"))
        (should-error (tau-agent-set-reasoning-effort "low"))
        ;; The same call appears in both event and terminal payloads.  It
        ;; must execute only once, before the second call in that response.
        (funcall (car callbacks) 'event
                 '(:type "response.output_item.done"
                   :item (:type "function_call" :id "fc1" :call_id "c1"
                          :name "test" :arguments "{\"value\":\"one\"}")))
        (funcall (car callbacks) 'done
                 '(:response (:output [(:type "function_call" :id "fc1" :call_id "c1" :name "test" :arguments "{\"value\":\"one\"}")
                                       (:type "function_call" :id "fc2" :call_id "c2" :name "test" :arguments "{\"value\":\"two\"}")])))
        (should (equal (reverse calls) '("one" "two")))
        (should (= (length payloads) 2))
        (should (equal (plist-get (plist-get (car payloads) :reasoning) :effort) "high"))
        (should (= (length (plist-get (car payloads) :input)) 5))
        (funcall (car callbacks) 'done
                 '(:response (:output [(:type "message" :id "m1" :content [(:type "output_text" :text "done")])])) )
        (should-not tau-agent--active)
        (should tau-agent--draft)
        (should (tau-agent-session--validate (tau-agent-session--data)))
        (should-not (featurep 'gptel))))))

(ert-deftest tau-agent-cancel-stale-callback ()
  (tau-agent-test--buffer
    (let (callback)
      (insert "question")
      (cl-letf (((symbol-function 'tau-agent-transport-start)
                 (lambda (_payload cb) (setq callback cb) nil)))
        (tau-agent-send)
        (tau-agent-cancel)
        (let ((text (buffer-string)))
          (funcall callback 'event '(:type "response.output_text.delta" :item_id "m" :delta "late"))
          (should (equal text (buffer-string))))
        (should (equal tau-agent--activity "Canceled"))
        (should-not buffer-read-only)))))

(ert-deftest tau-agent-history-edits-change-input ()
  (tau-agent-test--buffer
    (insert "old")
    (overlay-put tau-agent--draft 'tau-draft nil)
    (setq tau-agent--draft nil)
    (tau-agent--append 'assistant "later")
    (tau-agent--new-draft)
    (let ((first (cl-find 'user tau-agent--messages
                         :key (lambda (ov) (overlay-get ov 'tau-role)))))
      (goto-char (overlay-start first))
      (delete-region (overlay-start first) (overlay-end first))
      (insert "changed"))
    (should (equal (plist-get (aref (tau-agent--input) 0) :content) "changed"))
    (should (equal (plist-get (aref (tau-agent--input) 1) :content) "later"))))

(ert-deftest tau-agent-auth-refresh ()
  (let ((tau-agent-token-file (make-temp-file "tau-token-test-")))
    (unwind-protect
        (progn
          (tau-agent-auth--persist '(:access_token "old" :refresh_token "refresh" :expires_in -1))
          (cl-letf (((symbol-function 'tau-agent-auth--post)
                     (lambda (&rest _) '(:access_token "new" :expires_in 3600))))
            (should (equal (cdr (assoc "Authorization" (tau-agent-auth-headers))) "Bearer new"))
            (should (equal (plist-get (tau-agent-auth--read) :refresh_token) "refresh"))
            (should (= (logand (file-modes tau-agent-token-file) #o777) #o600)))
          (tau-agent-auth--persist '(:access_token "old" :refresh_token "refresh" :expires_in -1))
          (cl-letf (((symbol-function 'tau-agent-auth--post) (lambda (&rest _) (error "Refresh denied"))))
            (should-error (tau-agent-auth-headers))
            (should (equal (plist-get (tau-agent-auth--read) :access_token) "old"))))
      (delete-file tau-agent-token-file))))

(ert-deftest tau-agent-project-isolation ()
  (let ((one (make-temp-file "tau-project-one-" t))
        (two (make-temp-file "tau-project-two-" t)) buffers)
    (unwind-protect
        (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
          (dolist (root (list one two))
            (write-region (concat "Instructions for " root) nil (expand-file-name "AGENTS.md" root) nil 'silent)
            (push (tau-agent root) buffers))
          (with-current-buffer (car buffers)
            (should (eq (overlay-get (car tau-agent--messages) 'tau-role) 'system))
            (should (string-match-p (regexp-quote two) (tau-agent--system-text)))
            (should-not (string-match-p (regexp-quote one) (tau-agent--system-text)))
            (tau-agent-set-reasoning-effort "low"))
          (with-current-buffer (cadr buffers)
            (should (equal tau-agent-reasoning-effort "medium"))
            (should (equal (tau-agent-tools--root) (file-name-as-directory one)))))
      (mapc #'kill-buffer buffers)
      (delete-directory one t)
      (delete-directory two t))))

(ert-deftest tau-agent-stream-item-order-and-interruption ()
  (tau-agent-test--buffer
    (let (callback)
      (insert "question")
      (cl-letf (((symbol-function 'tau-agent-transport-start)
                 (lambda (_payload cb) (setq callback cb) nil)))
        (tau-agent-send)
        (funcall callback 'event '(:type "response.output_item.added" :item (:type "reasoning" :id "r")))
        (funcall callback 'event '(:type "response.output_item.done" :item (:type "reasoning" :id "r" :encrypted_content "opaque")))
        (funcall callback 'event '(:type "response.output_text.delta" :item_id "m" :delta "hello"))
        (funcall callback 'event '(:type "response.output_item.done" :item (:type "function_call" :id "f" :call_id "c" :name "shell" :arguments "{\"command\":\"true\"}")))
        (tau-agent-cancel)
        (let ((input (tau-agent--input)))
          (should (= (length input) 5))
          (should (equal (plist-get (aref input 1) :encrypted_content) "opaque"))
          (should (equal (plist-get (aref input 2) :content) "hello"))
          (should (equal (plist-get (aref input 4) :call_id) "c")))
        (should (tau-agent-session--validate (tau-agent-session--data)))))))

(ert-deftest tau-agent-auth-pkce ()
  (let ((verifier (tau-agent-auth--random)))
    (should (= (length verifier) 43))
    (should (string-match-p "\\`[A-Za-z0-9_-]+\\'" verifier))
    (should-not (equal verifier (tau-agent-auth--random)))))

(ert-deftest tau-agent-transport-process-lifecycle ()
  ;; Exercise actual filters/sentinels and UTF-8 decoding using a local
  ;; subprocess in place of curl.  No HTTP requests or real tokens are used.
  (let ((original (symbol-function 'make-process)))
    (dolist (scenario '(success incomplete http-error malformed))
      (let (events done stream config)
        (cl-letf (((symbol-function 'tau-agent-auth-headers)
                   (lambda () '(("Authorization" . "Bearer test-secret"))))
                  ((symbol-function 'make-process)
                   (lambda (&rest args)
                     (let ((command (plist-get args :command)))
                       (should-not (member "Bearer test-secret" command))
                       (setq config (nth (1+ (cl-position "--config" command :test #'equal)) command))
                       (should (= (logand (file-modes config) #o777) #o600)))
                     (apply original
                            (plist-put args :command
                                       (list "sh" "-c"
                                             (concat "cat >/dev/null; "
                                                     (pcase scenario
                                                       ('success "printf 'data: {\"type\":\"response.output_text.delta\",\"delta\":\"hé🌱\"}\\n\\ndata: {\"type\":\"response.completed\",\"response\":{\"output\":[]}}\\n\\n'")
                                                       ('incomplete "printf 'data: {\"type\":\"response.created\"}\\n\\n'")
                                                       ('http-error "printf 'HTTP 401' >&2; exit 22")
                                                       ('malformed "printf 'data: invalid\\n\\n'; sleep 1")))))))))
          (unwind-protect
              (progn
                (setq stream (tau-agent-transport-start
                              '(:model "test")
                              (lambda (kind data)
                                (if (eq kind 'done) (push data done) (push data events)))))
                (let ((deadline (+ (float-time) 5)))
                  (while (and (not done) (< (float-time) deadline))
                    (accept-process-output nil 0.05)))
                (should (= (length done) 1))
                (if (eq scenario 'success)
                    (progn
                      (should (plist-get (car done) :response))
                      (should (equal (plist-get (cadr events) :delta) "hé🌱")))
                  (should (plist-get (car done) :error)))
                (should-not (file-exists-p config))
                (should-not (buffer-live-p (tau-agent-stream-stderr stream))))
            (when stream (tau-agent-transport-cancel stream))))))))

(ert-deftest tau-agent-streamed-shell-without-terminal-output ()
  ;; Some streaming responses deliver output only in item events.  The
  ;; terminal response must not discard those calls or open a new draft.
  (let ((directory (make-temp-file "tau-shell-project-" t)))
    (unwind-protect
        (tau-agent-test--buffer
          (setq tau-agent--root (file-name-as-directory directory))
          ;; The captured project directory must win over the current buffer
          ;; directory, even when a callback runs from a different buffer.
          (setq default-directory temporary-file-directory)
          (let (callbacks payloads)
            (insert "List the directory")
            (cl-letf (((symbol-function 'tau-agent-transport-start)
                       (lambda (payload cb) (push payload payloads) (push cb callbacks) nil)))
              (tau-agent-send)
              (funcall (car callbacks) 'event
                       '(:type "response.output_item.done"
                         :item (:type "function_call" :id "fc" :call_id "call"
                                :name "shell" :arguments "{\"command\":\"pwd\",\"timeout\":2}")))
              (funcall (car callbacks) 'done '(:response (:output [])))
              (should tau-agent--active)
              (should-not tau-agent--draft)
              (let ((deadline (+ (float-time) 4)))
                (while (and (= (length payloads) 1) (< (float-time) deadline))
                  (with-temp-buffer (accept-process-output nil 0.02))))
              (should (= (length payloads) 2))
              (let* ((input (plist-get (car payloads) :input))
                     (result (aref input 2)))
                (should (equal (plist-get result :type) "function_call_output"))
                (should (equal (plist-get result :call_id) "call"))
                (should (equal (plist-get result :output)
                               (format "exit code: 0\n%s\n" (directory-file-name (file-truename directory))))))
              (funcall (car callbacks) 'done '(:response (:output [])))
              (should-not tau-agent--active)
              (should (tau-agent-session--validate (tau-agent-session--data))))))
      (delete-directory directory))))

(ert-deftest tau-agent-generated-tools-list ()
  (tau-agent-test--buffer
    (let ((view (cadr tau-agent--messages)) payload)
      (should (eq (overlay-get view 'tau-role) 'tools))
      (should (string-match-p (regexp-quote "shell(command: string, timeout?: number)")
                              (tau-agent--text view)))
      (should (string-match-p (regexp-quote (tau-agent-tool-description tau-agent-tools-shell-tool))
                              (tau-agent--text view)))
      (goto-char (overlay-start view))
      (should-error (insert "edit") :type 'user-error)
      (should-error (delete-region (overlay-start view) (overlay-end view)) :type 'user-error)
      (setq tau-agent-tools (list tau-agent-tools-read-file-tool))
      (tau-agent-refresh-tools)
      (should (string-match-p "#### read(" (tau-agent--text view)))
      (should-not (string-match-p "#### shell(" (tau-agent--text view)))
      (should-not (seq-find (lambda (message) (equal (plist-get message :role) "tools"))
                           (plist-get (tau-agent-session--data) :messages)))
      (setq tau-agent-tools nil)
      (goto-char (overlay-start tau-agent--draft))
      (insert "hello")
      (cl-letf (((symbol-function 'tau-agent-transport-start)
                 (lambda (data _callback) (setq payload data) nil)))
        (tau-agent-send)
        (should (equal (tau-agent--text view) "No tools enabled."))
        (should (equal (plist-get payload :tools) []))
        (should (equal (plist-get payload :instructions) "Test instructions"))
        (should (equal (plist-get payload :input) [(:role "user" :content "hello")]))
        (tau-agent-cancel)))))

(ert-deftest tau-agent-tool-folding ()
  (tau-agent-test--buffer
    (let* ((call '(:type "function_call" :id "fc" :call_id "c"
                   :name "shell" :arguments "{\"command\":\"pwd\"}"))
           (ov (tau-agent--wire-overlay call)))
      (tau-agent--accept-item call)
      (should (overlay-get ov 'tau-collapsed))
      (should (string-match-p "shell" (overlay-get ov 'display)))
      (let ((input (tau-agent--input)) (text (buffer-string)))
        (set-buffer-modified-p nil)
        ;; Folding is allowed even while a request protects the buffer.
        (let ((tau-agent--active t) (buffer-read-only t))
          (goto-char (+ 3 (overlay-get ov 'tau-heading)))
          (tau-agent-toggle-tool)
          (should-not (overlay-get ov 'display))
          (goto-char (overlay-end ov))
          (tau-agent-toggle-tool)
          (should (overlay-get ov 'display)))
        (should-not (buffer-modified-p))
        (should (equal text (buffer-string)))
        (should (equal input (tau-agent--input))))
      (let ((result (tau-agent--tool-result call (make-string 2000 ?x))))
        (should (< (length (overlay-get result 'display)) 150))
        (should (= (length (tau-agent--text result)) 2000))
        (should-error (delete-region (overlay-start result) (overlay-end result))
                      :type 'user-error))
      (let ((tau-agent-collapse-tools nil))
        (should-not (overlay-get (tau-agent--append 'tool-result "expanded") 'display))))))

(ert-deftest tau-agent-reference-project-relative ()
  (tau-agent-test--buffer
    (let ((default-directory "/tmp/project/subdir/"))
      (cl-letf (((symbol-function 'project-current) (lambda (&rest _) 'test-project))
                ((symbol-function 'project-root) (lambda (_) "/tmp/project/"))
                ((symbol-function 'project-files)
                 (lambda (_) '("/tmp/project/one.el" "subdir/two.el")))
                ((symbol-function 'completing-read)
                 (lambda (_prompt candidates &rest _)
                   (should (equal candidates '("one.el" "subdir/two.el")))
                   "subdir/two.el")))
        (tau-agent-insert-reference)
        (should (equal (tau-agent--text tau-agent--draft) "subdir/two.el"))))))

(ert-deftest tau-agent-reference-directory-fallback ()
  (let ((directory (make-temp-file "tau-reference-" t)))
    (unwind-protect
        (tau-agent-test--buffer
          (let ((default-directory (file-name-as-directory directory)))
            (write-region "test" nil (expand-file-name "a file.el" directory) nil 'silent)
            (make-directory (expand-file-name "subdir" directory))
            (cl-letf (((symbol-function 'project-current) (lambda (&rest _) nil))
                      ((symbol-function 'completing-read)
                       (lambda (_prompt candidates &rest _)
                         (should (equal candidates '("a file.el")))
                         "a file.el")))
              (tau-agent-insert-reference)
              (should (equal (tau-agent--text tau-agent--draft) "a file.el")))))
      (delete-directory directory t))))

(ert-deftest tau-agent-reference-cancel-and-empty ()
  (tau-agent-test--buffer
    (cl-letf (((symbol-function 'project-current) (lambda (&rest _) 'test-project))
              ((symbol-function 'project-root) (lambda (_) "/tmp/"))
              ((symbol-function 'project-files) (lambda (_) '("test.el")))
              ((symbol-function 'completing-read) (lambda (&rest _) (signal 'quit nil))))
      (tau-agent-insert-reference)
      (should (equal (tau-agent--text tau-agent--draft) "@"))
      (cl-letf (((symbol-function 'project-files) (lambda (_) nil)))
        (tau-agent-insert-reference)
        (should (equal (tau-agent--text tau-agent--draft) "@@"))))))

(ert-deftest tau-agent-usage-header-and-continuation ()
  (tau-agent-test--buffer
    (let (callbacks)
      (setq tau-agent-tools
            (list (tau-agent-make-tool :name "test" :function (lambda () "ok"))))
      (should (string-match-p "in:?" (tau-agent--usage-text)))
      (should (string-match-p "Tokens" (tau-agent--tab-line)))
      (should (string-prefix-p "✅" (tau-agent--status)))
      (insert "question")
      (cl-letf (((symbol-function 'tau-agent-transport-start)
                 (lambda (_data callback) (push callback callbacks) nil)))
        (tau-agent-send)
        (should (string-prefix-p "🤔" (tau-agent--status)))
        (funcall (car callbacks) 'event
                 '(:type "response.completed" :response (:usage (:total_tokens 120))))
        (should-not tau-agent--usage-total)
        (funcall (car callbacks) 'done
                 '(:response (:usage (:input_tokens 100 :output_tokens 20 :total_tokens 120
                                      :input_tokens_details (:cached_tokens 50)
                                      :output_tokens_details (:reasoning_tokens 10))
                              :output [(:type "function_call" :id "f" :call_id "c"
                                        :name "test" :arguments "{}")])))
        (should (= (length callbacks) 2))
        (should (equal (tau-agent--usage-text)
                       "Tokens in:100 out:20 cache:50 reason:10 | Σ:120"))
        (funcall (car callbacks) 'done
                 '(:response (:usage (:input_tokens 200 :output_tokens 30) :output [])))
        (should (= tau-agent--usage-total 350))
        (should (equal (tau-agent--usage-text)
                       "Tokens in:200 out:30 cache:? reason:? | Σ:350"))
        (tau-agent--record-usage '(:output []))
        (should (equal (tau-agent--usage-text)
                       "Tokens in:? out:? cache:? reason:? | Σ:350"))
        (should (tau-agent-session--validate (tau-agent-session--data)))))))

(provide 'tau-agent-tests)
;;; tau-agent-tests.el ends here
