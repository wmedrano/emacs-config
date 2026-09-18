;;; tau-agent-auth.el --- ChatGPT OAuth authentication -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Karthik Chikmagalur
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Adapted from gptel-openai-oauth.el and gptel-oauth.el.  Reuses the
;; existing token file, without requiring gptel or copying refresh tokens.

;;; Code:

(require 'tau-agent-core)
(require 'url)
(require 'url-http)
(require 'browse-url)
(defvar url-http-response-status)

(defconst tau-agent-auth--client "app_EMoamEEZ73f0CkXaXp7hrann")
(defconst tau-agent-auth--host "https://auth.openai.com")
(defcustom tau-agent-token-file
  (expand-file-name ".cache/gptel-openai/openai-oauth-token" user-emacs-directory)
  "OAuth token file, shared with the previous gptel configuration."
  :type 'file :group 'tau-agent)
(defcustom tau-agent-login-method 'authorization-code
  "Login flow used by `tau-agent-login'."
  :type '(choice (const authorization-code) (const device)) :group 'tau-agent)

(defun tau-agent-auth--post (path data &optional form)
  "POST DATA to authentication PATH, using FORM encoding when non-nil."
  (let* ((url-request-method "POST")
         (url-request-extra-headers
          `(("Content-Type" . ,(if form "application/x-www-form-urlencoded"
                                  "application/json"))))
         (url-request-data
          (encode-coding-string
           (if form (url-build-query-string data) (tau-agent--json data)) 'utf-8))
         (buffer (url-retrieve-synchronously
                  (concat tau-agent-auth--host path) t t 30)))
    (unless buffer (error "OAuth request timed out"))
    (unwind-protect
        (with-current-buffer buffer
          (goto-char (point-min))
          (unless (re-search-forward "\r?\n\r?\n" nil t)
            (error "Invalid OAuth response"))
          (let ((data (tau-agent--json-read
                       (decode-coding-string
                        (buffer-substring-no-properties (point) (point-max))
                        'utf-8))))
            (unless (and url-http-response-status
                         (<= 200 url-http-response-status 299))
              (error "OAuth HTTP %s: %s" url-http-response-status
                     (or (plist-get data :error_description)
                         (plist-get data :error) "Request failed")))
            data))
      (kill-buffer buffer))))

(defun tau-agent-auth--base64url (bytes)
  "Encode BYTES using unpadded base64url."
  (string-replace "=" "" (string-replace "/" "_"
    (string-replace "+" "-" (base64-encode-string bytes t)))))

(defun tau-agent-auth--random ()
  "Return a cryptographically random PKCE-compatible string."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (unless (and (zerop (call-process "head" nil t nil "-c" "32" "/dev/urandom"))
                 (= (buffer-size) 32))
      (error "Could not read operating-system randomness"))
    (tau-agent-auth--base64url (buffer-string))))

(defun tau-agent-auth--jwt (token)
  "Decode the claims of TOKEN, without treating them as verified claims."
  (when (stringp token)
    (condition-case nil
        (let* ((body (nth 1 (split-string token "\\.")))
               (text (string-replace "_" "/" (string-replace "-" "+" body))))
          (tau-agent--json-read
           (decode-coding-string
            (base64-decode-string
             (concat text (make-string (mod (- (length text)) 4) ?=))) 'utf-8)))
      (error nil))))

(defun tau-agent-auth--read ()
  "Read the existing token plist without evaluating Lisp."
  (when (file-readable-p tau-agent-token-file)
    (with-temp-buffer
      (insert-file-contents tau-agent-token-file)
      (let ((read-circle nil)) (read (current-buffer))))))

(defun tau-agent-auth--persist (response &optional previous)
  "Validate and persist token RESPONSE, retaining omitted PREVIOUS fields."
  (let ((access (plist-get response :access_token))
        (expiry (plist-get response :expires_in))
        (refresh (or (plist-get response :refresh_token)
                     (plist-get previous :refresh_token))))
    (unless (and (stringp access) (numberp expiry) (stringp refresh))
      (error "OAuth response did not contain valid credentials"))
    (let* ((token (list :access_token access :refresh_token refresh
                        :expires_at (+ (float-time) expiry)
                        :id_token (or (tau-agent-auth--jwt
                                       (plist-get response :id_token))
                                      (plist-get previous :id_token))))
           (directory (file-name-directory tau-agent-token-file))
           temporary)
      (make-directory directory t)
      (unwind-protect
          (progn
            (setq temporary (make-temp-file (expand-file-name ".tau-token-" directory)))
            (set-file-modes temporary #o600)
            (let ((coding-system-for-write 'utf-8-unix)
                  (print-length nil) (print-level nil))
              (write-region (prin1-to-string token) nil temporary nil 'silent))
            (rename-file temporary tau-agent-token-file t)
            token)
        (when (and temporary (file-exists-p temporary)) (delete-file temporary))))))

(defun tau-agent-auth--browser-code (verifier state)
  "Obtain an authorization code using VERIFIER and matching STATE."
  (when (or (getenv "SSH_CONNECTION") (getenv "SSH_TTY"))
    (user-error "Use M-x tau-agent-login with a prefix argument for device login"))
  (let* ((redirect "http://localhost:1455/auth/callback")
         (url (concat tau-agent-auth--host "/oauth/authorize?"
                      (url-build-query-string
                       `(("response_type" "code") ("client_id" ,tau-agent-auth--client)
                         ("redirect_uri" ,redirect)
                         ("scope" "openid profile email offline_access")
                         ("code_challenge" ,(tau-agent-auth--base64url
                                              (secure-hash 'sha256 verifier nil nil t)))
                         ("code_challenge_method" "S256")
                         ("id_token_add_organizations" "true")
                         ("codex_cli_simplified_flow" "true")
                         ("state" ,state) ("originator" "tau-agent")))))
         (deadline (+ (float-time) 300)) code failure server clients)
    (unwind-protect
        (progn
          (setq server
                (make-network-process
                 :name "tau-agent-oauth" :server t :host "127.0.0.1" :service 1455
                 :noquery t
                 :filter
                 (lambda (proc chunk)
                   (cl-pushnew proc clients)
                   (let ((request (concat (process-get proc 'request) chunk)))
                     (process-put proc 'request request)
                     (when (string-match "\r\n\r\n" request)
                       (let ((ok nil))
                         (when (string-match "\\`GET /auth/callback?\\([^ ]+\\) HTTP/" request)
                           (let* ((args (url-parse-query-string (match-string 1 request)))
                                  (received (cadr (assoc "state" args))))
                             (when (equal state received)
                               (setq code (cadr (assoc "code" args))
                                     failure (cadr (assoc "error" args))
                                     ok code))))
                         (process-send-string
                          proc (concat "HTTP/1.1 " (if ok "200 OK" "400 Bad Request")
                                       "\r\nConnection: close\r\nContent-Type: text/plain\r\n\r\n"
                                       (if ok "Authentication complete. You may close this tab."
                                         "Invalid OAuth callback.")))
                         (delete-process proc)))))))
          (browse-url url)
          (while (and (not code) (not failure) (< (float-time) deadline))
            (accept-process-output nil 0.2))
          (or code (user-error "OAuth login failed: %s" (or failure "timed out"))))
      (dolist (proc (cons server clients))
        (when (and (processp proc) (process-live-p proc)) (delete-process proc))))))

(defun tau-agent-auth--device ()
  "Authenticate using the device authorization flow."
  (let* ((device (tau-agent-auth--post
                  "/api/accounts/deviceauth/usercode"
                  (list :client_id tau-agent-auth--client)))
         (code (plist-get device :user_code))
         (deadline (+ (float-time) 300)) response)
    (unless (and code (plist-get device :device_auth_id))
      (error "Invalid device authorization response"))
    (message "Visit https://auth.openai.com/codex/device and enter %s" code)
    (ignore-errors (gui-set-selection 'CLIPBOARD code))
    (unless (getenv "SSH_CONNECTION")
      (browse-url "https://auth.openai.com/codex/device"))
    (while (and (not response) (< (float-time) deadline))
      (condition-case err
          (setq response
                (tau-agent-auth--post "/api/accounts/deviceauth/token"
                                     (list :device_auth_id (plist-get device :device_auth_id)
                                           :user_code code)))
        (error (unless (string-match-p "OAuth HTTP \\(403\\|404\\)" (error-message-string err))
                 (signal (car err) (cdr err)))))
      (unless (plist-get response :authorization_code)
        (setq response nil)
        (sit-for 2)))
    (unless response (user-error "Device login timed out"))
    (tau-agent-auth--post
     "/oauth/token"
     `(("grant_type" "authorization_code") ("client_id" ,tau-agent-auth--client)
       ("code" ,(plist-get response :authorization_code))
       ("code_verifier" ,(plist-get response :code_verifier))
       ("redirect_uri" "https://auth.openai.com/deviceauth/callback")) t)))

;;;###autoload
(defun tau-agent-login (&optional method)
  "Log in with METHOD, either authorization-code or device.
Interactively, a prefix argument selects device login."
  (interactive (list (if current-prefix-arg 'device tau-agent-login-method)))
  (tau-agent-auth--persist
   (pcase (or method tau-agent-login-method)
     ('device (tau-agent-auth--device))
     ('authorization-code
      (let* ((verifier (tau-agent-auth--random))
             (code (tau-agent-auth--browser-code verifier (tau-agent-auth--random))))
        (tau-agent-auth--post
         "/oauth/token"
         `(("grant_type" "authorization_code") ("client_id" ,tau-agent-auth--client)
           ("code" ,code) ("code_verifier" ,verifier)
           ("redirect_uri" "http://localhost:1455/auth/callback")) t)))
     (_ (user-error "Unknown login method"))))
  (message "Tau-agent authentication complete"))

(defun tau-agent-auth-headers ()
  "Return authorization headers, refreshing expired credentials as needed."
  (let ((token (tau-agent-auth--read)))
    (unless token
      (tau-agent-login)
      (setq token (tau-agent-auth--read)))
    (unless (> (or (plist-get token :expires_at) 0) (+ (float-time) 30))
      (setq token
            (tau-agent-auth--persist
             (tau-agent-auth--post
              "/oauth/token"
              `(("grant_type" "refresh_token") ("client_id" ,tau-agent-auth--client)
                ("refresh_token" ,(plist-get token :refresh_token))) t) token)))
    (let* ((claims (plist-get (plist-get token :id_token) :https://api.openai.com/auth))
           (account (or (plist-get claims :chatgpt_account_id)
                        (plist-get (elt (plist-get claims :organizations) 0) :id))))
      (append `(("Authorization" . ,(concat "Bearer " (plist-get token :access_token)))
                ("Originator" . "tau-agent"))
              (when account `(("ChatGPT-Account-Id" . ,account)))))))

(provide 'tau-agent-auth)
;;; tau-agent-auth.el ends here
