;;; package --- Will's Emacs config.
;;; Commentary:
;;; Code:
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(auto-save-default nil)
 '(package-selected-packages
   '(doom-modeline starhugger dockerfile-mode diff-hl spacemacs-theme evil-commentary evil graphviz-dot-mode ox-hugo markdownfmt modus-themes yasnippet-snippets yasnippet dall-e-shell rg chatgpt-shell nerd-icons-ivy-rich dracula-theme markdown-mode ivy-rich eat yaml-mode magit counsel ivy rust-mode company swiper))
 '(package-vc-selected-packages
   '((starhugger :url "https://gitlab.com/daanturo/starhugger.el"))))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Packages
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(package-initialize)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Startup and appearance
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(setq-default inhibit-startup-screen t
	      ring-bell-function     'ignore
	      scroll-conservatively  5
	      gc-cons-percentage     1.0
	      gc-cons-threshold      (* 256 1024 1024))
(tool-bar-mode -1)
(scroll-bar-mode -1)
(xterm-mouse-mode t)
(seq-doseq (theme custom-enabled-themes)
  (disable-theme theme))
(require 'spacemacs-theme)
(load-theme 'spacemacs-dark t)
(set-frame-font "JetBrainsMono Nerd Font Mono 11")

(require 'doom-modeline)
(doom-modeline-mode t)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; VI like keybindings
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(require 'evil)
(require 'evil-commentary)
(evil-mode t)
(evil-commentary-mode t)
(evil-define-key '(normal visual motion) 'global "j" #'evil-search-next)
(evil-define-key '(normal visual motion) 'global "n" #'evil-next-line)
(evil-define-key '(normal visual motion) 'global "e" #'evil-previous-line)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Saving/Reverting
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(require 'compile)
(setq-default auto-save-default nil
	      make-backup-files nil)
(global-auto-revert-mode t)
(global-set-key (kbd "<f5>") #'recompile)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Lines
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(setq-default display-line-numbers-grow-only   t
	      display-line-numbers-width-start 3)
(global-display-line-numbers-mode t)
(global-hl-line-mode t)
(column-number-mode t)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Editor Complete
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(require 'counsel)
(require 'ivy)
(require 'ivy-rich)
(require 'nerd-icons-ivy-rich)
(ivy-mode t)
(counsel-mode t)
(ivy-rich-mode t)
(nerd-icons-ivy-rich-mode t)
(define-key counsel-mode-map (kbd "C-x b") #'counsel-switch-buffer)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Shells
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(require 'eat)
(add-hook 'eshell-load-hook #'eat-eshell-mode)

(require 'ansi-color)
(add-hook 'compilation-filter-hook #'ansi-color-compilation-filter)
(add-hook 'compilation-filter-hook #'ansi-osc-compilation-filter)

(add-to-list 'evil-emacs-state-modes 'rg-mode)
(add-to-list 'evil-emacs-state-modes 'xref--xref-buffer-mode)

(require 'chatgpt-shell)
(setq-default
 chatgpt-shell-openai-key (secrets-get-secret "Login" "emacs-chatgpt")
 dall-e-shell-openai-key (secrets-get-secret "Login" "emacs-chatgpt"))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Version Control
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(require 'magit)
(add-hook 'git-commit-mode-hook #'evil-insert-state)

(require 'diff-hl)
(global-diff-hl-mode)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Autocomplete
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Code based.
(require 'company)
(setq-default company-tooltip-minimum-width   80
	      company-tooltip-width-grow-only t)
(global-company-mode t)
(define-key company-active-map (kbd "TAB")      #'company-complete-selection)
(define-key company-active-map (kbd "<tab>")    #'company-complete-selection)
(define-key company-active-map (kbd "RET")      nil)
(define-key company-active-map (kbd "<return>") nil)
(define-key company-active-map (kbd "C-h")      #'company-show-doc-buffer)
(define-key company-active-map (kbd "C-w")      #'company-show-location)

;; Snippet based.
(require 'yasnippet)
(require 'yasnippet-snippets)
(yas-global-mode t)

;; AI based.
(require 'starhugger)
(require 's)
(setq-default
 starhugger-api-token (secrets-get-secret "Login" "emacs-huggingface"))
(evil-define-key '(insert) 'global (kbd "<backtab>") #'starhugger-trigger-suggestion)
(define-key starhugger-inlining-mode-map (kbd "TAB") #'starhugger-accept-suggestion)
(define-key starhugger-inlining-mode-map (kbd "<tab>") #'starhugger-accept-suggestion-by-paragraph)
(define-key starhugger-inlining-mode-map (kbd "<backtab>") #'starhugger-show-next-suggestion)
(define-key starhugger-inlining-mode-map (kbd "<down>") #'starhugger-accept-suggestion-by-line)
(define-key starhugger-inlining-mode-map (kbd "<right>") #'starhugger-accept-suggestion-by-word)
(define-key starhugger-inlining-mode-map (kbd "<escape>") #'starhugger-dismiss-suggestion)

(defun starhugger-update-package ()
  "Update the starhugger package."
  (interactive)
  (package-vc-install '(starhugger :url "https://gitlab.com/daanturo/starhugger.el")))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Syntax Checking
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(require 'flymake)
(add-hook 'prog-mode-hook #'flymake-mode)
(define-key flymake-mode-map (kbd "<f8>") #'flymake-goto-next-error)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Formatting and refactoring
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(cua-mode t)
(global-visual-line-mode t)
(defun delete-trailing-whitespace--before-save ()
  "Remove trailing whitespace before saving."
  (add-hook 'before-save-hook #'delete-trailing-whitespace 0 t))
(add-hook 'prog-mode-hook #'delete-trailing-whitespace--before-save)
(add-hook 'text-mode-hook #'delete-trailing-whitespace--before-save)
(add-hook 'conf-mode-hook #'delete-trailing-whitespace--before-save)

(require 'eglot)
(setq-default eglot-confirm-server-initiated-edits nil
	      ;; Disable event logging to improve performance. This is
	      ;; usually useless but should be enabled when debugging
	      ;; eglot itself.
	      eglot-events-buffer-size 0
	      eglot-report-progress    nil)

(defun eglot--format-before-save ()
  "Format the buffer before saving."
  (add-hook 'before-save-hook #'eglot-format-buffer 0 t))
(add-hook 'eglot-managed-mode-hook #'eglot--format-before-save)
(define-key eglot-mode-map (kbd "<f2>") #'eglot-rename)
(global-set-key (kbd "<f3>") nil)
(define-key eglot-mode-map (kbd "<f3>") #'eglot-code-actions)

(defun set-fill-column-100 ()
  "Set the `fill-column' to 100."
  (setq-local fill-column 100))
(add-hook 'rust-mode-hook #'set-fill-column-100)

(require 'markdownfmt)
(setq-default markdownfmt-bin "/home/wmedrano/go/bin/markdownfmt")
(add-hook 'markdown-mode-hook #'markdownfmt-enable-on-save)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; References
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(setq-default eglot-extend-to-xref t)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Org Mode
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(setq-default org-support-shift-select t)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Rust
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(add-hook 'rust-mode-hook #'eglot-ensure)

(defmacro with-cargo-workspace (&rest body)
  "Execute BODY within the root of the cargo workspace."
  `(let* ((root (project-root (project-current)))
	  (default-directory root))
     ,@body))

(defun run-cargo-command (base-cmd &optional comint)
  "Run cargo cmd BASE-CMD with the given PROMPT.
Set COMINT to enable interactivity."
  (with-cargo-workspace (compile (completing-read "Command: " nil nil nil base-cmd) comint)))

(defun cargo-bench ()
  "Execute cargo bench."
  (interactive)
  (run-cargo-command "cargo criterion --color always"))

(defun cargo-build ()
  "Execute cargo build."
  (interactive)
  (run-cargo-command "cargo build --color always "))

(defun cargo-clippy ()
  "Execute cargo clippy."
  (interactive)
  (run-cargo-command "cargo clippy"))

(defun cargo-run ()
  "Execute cargo run."
  (interactive)
  (run-cargo-command "RUST_BACKTRACE=1 cargo run --color always -- " t))

(defun cargo-search ()
  "Execute cargo search."
  (interactive)
  (run-cargo-command "cargo search "))

(defun cargo-test ()
  "Execute cargo test."
  (interactive)
  (run-cargo-command "cargo nextest --color always run "))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Emacs Lisp
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun elisp-eval-after-save ()
  "Evaluate the buffer after save."
  (interactive)
  (add-hook 'after-save-hook #'eval-buffer 0 t))
(seq-doseq (p load-path)
  (add-to-list 'elisp-flymake-byte-compile-load-path p))

(defun elisp-auto-eval-config-file ()
  "Run `elisp-eval-after-save' for the config main config file."
  (when (string= buffer-file-name user-init-file)
    (elisp-eval-after-save)))
(add-hook 'emacs-lisp-mode-hook #'elisp-auto-eval-config-file)

(provide 'init)
;;; init.el ends here.
