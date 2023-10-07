;;; package --- init
;;; Commentary:
;;;   Config for will.s.medrano@gmail.com
;;; Code:
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(auto-save-default nil)
 '(inhibit-startup-screen t)
 '(package-selected-packages
   '(toml-mode dracula-theme nord-theme evil-commentary rust-mode
			   modus-themes graphviz-dot-mode dall-e-shell which-key
			   eat htmlize org-preview-html docker
			   evil-textobj-tree-sitter evil-anzu evil
			   transient-posframe spacemacs-theme diff-hl
			   chatgpt-shell julia-ts-mode markdown-mode rg
			   yasnippet-snippets yasnippet anzu magit company
			   doom-modeline monokai-pro-theme ivy counsel swiper)))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )

(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(package-initialize)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; GC
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(setq-default gc-cons-threshold  20000000
	          gc-cons-percentage 1.0)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Backups
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(setq-default make-backup-files nil
	          auto-save-default nil)
(global-auto-revert-mode t)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Theme
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(setq-default inhibit-startup-screen t)

(require 'doom-modeline)
(setq-default doom-modeline-hud t)
(doom-modeline-mode t)
(column-number-mode t)


(defun default-theme ()
  "Set up some pathes on top of the default theme."
  (set-background-color "#ffffff")
  (set-face-foreground 'mode-line "#0f0f0f")
  (set-face-background 'mode-line "#afe0f2")
  (set-face-attribute 'mode-line nil :box "#2f4f44"))
(mapc #'disable-theme custom-known-themes)
(load-theme 'monokai-pro t)

(defun set-up-font (&rest args)
  "Set up the font.  ARGS are ignored."
  (set-frame-font "JetBrains Mono 11"))
(set-up-font)
(add-hook 'after-make-frame-functions #'set-up-font)
(xterm-mouse-mode t)

(setq-default inhibit-startup-screen t
	          ring-bell-function     'ignore)
(setenv "COLORTERM" "truecolor")
(add-hook 'eww-mode-hook         #'disable-display-line-numbers-mode)
(add-hook 'eshell-mode-hook      #'disable-display-line-numbers-mode)
(add-hook 'shell-mode-hook       #'disable-display-line-numbers-mode)
(add-hook 'compilation-mode-hook #'disable-display-line-numbers-mode)
(tool-bar-mode -1)
(scroll-bar-mode -1)

(setq-default display-line-numbers-grow-only t
	          scroll-conservatively          10)
(defun disable-display-line-numbers-mode ()
  "Disable display line numbers mode."
  (display-line-numbers-mode -1))
(global-display-line-numbers-mode t)
(global-hl-line-mode t)
(blink-cursor-mode -1)
(dolist (h '(compilation-mode-hook eshell-mode-hook shell-mode-hook))
  (add-hook h #'disable-display-line-numbers-mode))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Keys
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(require 'evil)
(require 'evil-anzu)
(require 'evil-commentary)
(require 'evil-textobj-tree-sitter)
(require 'evil-textobj-tree-sitter-core)
(defun evil-define-motion-key (key fn)
  "Define FN to run on evil motion with KEY."
  (define-key evil-motion-state-map key fn)
  (define-key evil-normal-state-map key fn))

(defun evil-setup ()
  "Set up evil mode."
  (evil-mode t)
  (evil-commentary-mode t)
  (evil-define-motion-key (kbd "n")        #'evil-next-line)
  (evil-define-motion-key (kbd "e")        #'evil-previous-line)
  (evil-define-motion-key (kbd "j")        #'evil-search-next)
  (evil-define-motion-key (kbd "J")        #'evil-search-previous)
  (evil-define-motion-key (kbd "<escape>") #'wm-transient)
  (define-key evil-normal-state-map (kbd "RET")      #'ignore)
  (define-key evil-outer-text-objects-map "f"
              (evil-textobj-tree-sitter-get-textobj "function.outer"))
  (define-key evil-inner-text-objects-map "f"
              (evil-textobj-tree-sitter-get-textobj "function.inner")))

(defun non-evil-setup ()
  "Set up keys for non-evil mode."
  (cua-mode t)
  (global-set-key (kbd "M-ESC") #'wm-transient))

(defvar wm-use-evil t
  "Non-nil if evil should be used.")
(if wm-use-evil
    (evil-setup)
  (non-evil-setup))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Editor Completions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(require 'ivy)
(require 'counsel)
(ivy-mode t)
(counsel-mode t)
(define-key counsel-mode-map (kbd "C-x b")   #'counsel-switch-buffer)
(define-key counsel-mode-map (kbd "C-x C-b") #'counsel-switch-buffer-other-window)

;; Search
(require 'anzu)
(require 'rg)
(global-anzu-mode t)
(defalias 'project-rg #'rg-project)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Window management
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(setq-default mouse-autoselect-window t)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Search
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(setq-default xref-search-program 'ripgrep)
(with-eval-after-load 'evil
  (add-to-list 'evil-emacs-state-modes 'xref-mode))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; TreeSitter
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(require 'treesit)
(setq-default treesit-language-source-alist
              '((bash "https://github.com/tree-sitter/tree-sitter-bash")
                (cmake "https://github.com/uyha/tree-sitter-cmake")
                (go "https://github.com/tree-sitter/tree-sitter-go")
                (json "https://github.com/tree-sitter/tree-sitter-json")
                (julia "https://github.com/tree-sitter/tree-sitter-julia")
                (make "https://github.com/alemuller/tree-sitter-make")
                (markdown "https://github.com/ikatyang/tree-sitter-markdown")
                (python "https://github.com/tree-sitter/tree-sitter-python")
                (rust "https://github.com/tree-sitter/tree-sitter-rust")
                (toml "https://github.com/tree-sitter/tree-sitter-toml")
                (yaml "https://github.com/ikatyang/tree-sitter-yaml")))
(defun treesit-install-all-grammars ()
  "Install all treesit languages."
  (interactive)
  (mapc #'treesit-install-language-grammar
	    (mapcar #'car treesit-language-source-alist)))

(add-to-list 'auto-mode-alist
	         '("\\.go\\'" . go-ts-mode))
(add-to-list 'auto-mode-alist
	         '("\\.py\\'" . python-ts-mode))
(add-to-list 'auto-mode-alist
	         '("\\.rs\\'" . rust-ts-mode))
(add-to-list 'auto-mode-alist
	         '("\\.toml\\'" . toml-ts-mode))
(add-to-list 'auto-mode-alist
	         '("\\.yml\\'" . yaml-ts-mode))
(add-to-list 'auto-mode-alist
	         '("\\.yaml\\'" . yaml-ts-mode))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Shell and Compile
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(require 'eat)
(require 'ansi-color)
(add-hook 'eshell-mode-hook #'eat-eshell-mode)
(add-hook 'compilation-filter-hook #'ansi-color-compilation-filter)
(with-eval-after-load 'evil
  (setq evil-motion-state-modes (remove 'compilation-mode evil-motion-state-modes))
  (add-to-list 'evil-emacs-state-modes 'compilation-mode))

(define-minor-mode recompile-on-save-mode
  "Automatically run recompile on save."
  :global t
  :group 'recompile-on-save
  (add-hook 'after-save-hook #'recompile-on-save--maybe-recompile))

(defun recompile-on-save--maybe-recompile ()
  "Run recompile if recompile on save mode is on."
  (if recompile-on-save-mode
      (recompile)
    (remove-hook 'after-save-hook #'recompile-on-save--maybe-recompile)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Web
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; TODO: Filter out all the junk.
(defun subreddit ()
  "Visit a subreddit in eww."
  (interactive)
  (eww (format "https://old.reddit.com/r/%s"
               (completing-read "Subreddit: "
                                '("emacs" "clojure" "python" "programming")))))

(defun hacker-news ()
  "Visit hacker news."
  (interactive)
  (eww "news.ycombinator.com"))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Org Mode
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(setq-default org-confirm-babel-evaluate nil)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Language Server
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(require 'eglot)
(setq-default eglot-events-buffer-size 0)
(dolist (hook '(go-mode-hook go-ts-mode-hook python-ts-mode-hook rust-ts-mode-hook))
  (add-hook hook #'eglot-ensure))
(define-key eglot-mode-map (kbd "<f2>") #'eglot-rename)

;; Inlay Hints
(defun eglot-inlay-hints-mode-off ()
  "Disable eglot inlay hints."
  (eglot-inlay-hints-mode -1))
(add-hook 'eglot-managed-mode-hook #'eglot-inlay-hints-mode-off)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Code Formatter
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Eglot formatter
(defun eglot-format-on-save  ()
  "Enable format on save."
  (add-hook 'before-save-hook #'eglot-format-buffer 0 t))

;; ELisp Formatting
(defun indent-buffer ()
  "Format a buffer by indenting."
  (interactive)
  (indent-region (point-min) (point-max)))

(defun elisp-format-on-save ()
  "Enable format on save for Emacs Lisp."
  (add-hook 'before-save-hook #'delete-trailing-whitespace 0 t)
  (add-hook 'before-save-hook #'indent-buffer 0 t))

;; On Save
(add-hook 'emacs-lisp-mode-hook #'elisp-format-on-save)
(dolist (h '(go-mode-hook rust-ts-mode-hook))
  (add-hook h #'eglot-format-on-save))

(setq-default tab-width 4)
(indent-tabs-mode -1)
(add-hook 'emacs-lisp-mode-hook #'electric-pair-mode)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; AutoComplete
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(require 'company)
(setq-default company-tooltip-width-grow-only t
	          company-tooltip-minimum-width   80)
(global-company-mode t)
(define-key company-active-map (kbd "TAB")      #'company-complete-selection)
(define-key company-active-map (kbd "<tab>")    #'company-complete-selection)
(define-key company-active-map (kbd "RET")      nil)
(define-key company-active-map (kbd "<return>") nil)
(define-key company-active-map (kbd "C-h")      #'company-show-doc-buffer)
(define-key company-active-map (kbd "C-w")      #'company-show-location)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Code snippets
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(require 'yasnippet)
(require 'yasnippet-snippets)
(yas-global-mode t)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Flymake
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(require 'flymake)
(setq-default flymake-after-save-hook nil)
(add-hook 'emacs-lisp-mode-hook #'flymake-mode)
(add-hook 'flymake-diagnostics-buffer-mode-hook #'visual-line-mode)
(add-hook 'flymake-project-diagnostics-mode-hook #'visual-line-mode)
(define-key flymake-mode-map (kbd "<f8>") #'flymake-goto-next-error)
(define-key flymake-mode-map (kbd "S-<f8>") #'flymake-goto-prev-error)
(define-key flymake-mode-map (kbd "C-<f8>") #'flymake-show-buffer-diagnostics)

;; Flymake diagnostics buffer
(add-to-list 'evil-emacs-state-modes 'flymake-diagnostics-buffer-mode)
(define-key flymake-diagnostics-buffer-mode-map (kbd "e") #'previous-line)

;; Emacs Lisp
(dolist (p load-path)
  (add-to-list 'elisp-flymake-byte-compile-load-path p))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Emacs Lisp
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun elisp-eval-on-save ()
  "Run `eval-buffer` on save."
  (interactive)
  (add-hook 'after-save-hook #'eval-buffer 0 t))
(defun elisp-eval-on-save-if-init-config ()
  "Run `elisp-eval-on-save` if the file is the init file."
  (when (string= (buffer-file-name) user-init-file)
    (elisp-eval-on-save)))
(add-hook 'emacs-lisp-mode-hook #'elisp-eval-on-save-if-init-config)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Rust
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun cargo-workspace-root ()
  "The current cargo workspace root."
  (let ((cmd "cargo metadata --format-version 1 2>/dev/null | jq .workspace_root -r"))
    (s-trim (shell-command-to-string cmd))))

(defmacro with-cargo-workspace (&rest body)
  "Run BODY with the `default-directory' as the cargo workspace root."
  `(let ((default-directory (cargo-workspace-root)))
     ,@body))

(defun cargo-run ()
  "Call compile with cargo run.

The default directory for the compile command is set to the root
directory given by cargo."
  (interactive)
  (with-cargo-workspace (compile "cargo run" t)))

(defun cargo-build ()
  "Call compile with cargo build."
  (interactive)
  (with-cargo-workspace (compile "cargo build")))

(defun cargo-test ()
  "Call compile with cargo test."
  (interactive)
  (with-cargo-workspace (compile "cargo test")))

(defun cargo-test-fap ()
  "Call compile with cargo test with the function at point."
  (interactive)
  (let ((cmd (format "cargo test %s" (symbol-at-point))))
	(with-cargo-workspace (compile cmd))))

(defun cargo-clippy ()
  "Call compile with cargo clippy."
  (interactive)
  (with-cargo-workspace (compile "cargo clippy")))

(defun cargo-bench ()
  "Call compile with cargo bench."
  (interactive)
  (with-cargo-workspace (compile "cargo bench")))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; VC
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(require 'diff-hl)
(require 'diff-hl-flydiff)
(global-diff-hl-mode t)
(add-hook 'diff-hl-mode-hook #'diff-hl-flydiff-mode)

(require 'magit)
(add-hook 'git-commit-mode-hook #'evil-insert-state)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; AI
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(require 'chatgpt-shell)
(setq-default chatgpt-shell-openai-key
	          (secrets-get-secret "Login" "emacs-openai-api-key"))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Transient
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(require 'transient)
(require 'transient-posframe)
(require 'rg)
(transient-posframe-mode t)
(transient-define-prefix wm-transient ()
  "Commands."
  [["Eglot"
    ("ee" "Code Actions" eglot-code-actions)
    ("et" "Inlay Hints"  eglot-inlay-hints-mode)
    ("er" "Rename"       eglot-rename)
    "Flymake"
    ("ff" "Flymake Next"     flymake-goto-next-error)
    ("fF" "Flymake Previous" flymake-goto-prev-error)
    ("fb" "Flymake Buffer"   flymake-show-buffer-diagnostics)
    ("fp" "Flymake Project"  flymake-show-project-diagnostics)
    ] [
    "References"
    ("xx" "Find References"  xref-find-references)
    ("xd" "Find Definitions" xref-find-definitions)
    "Ripgrep"
    ("rr" "Ripgrep"         rg)
    ("rp" "Ripgrep Project" project-find-regexp)
    ("rf" "isearch File"    rg-isearch-current-file)
    ("rd" "isearch Dir"     rg-isearch-current-dir)
    ] [
    "Project"
    ("pp" "Switch"  project-switch-project)
    ("pf" "File"    project-find-file)
    ("pb" "Buffer"  project-switch-to-buffer)
	("pe" "EShell"  project-eshell)
    ("ps" "Shell"   project-shell)
    ("pc" "Compile" project-compile)
    ] [
    "Magit"
	("gg" "Magit" magit-status)
    "Other"
    ("ESC" "Back" ignore)
    ]])

(provide 'init)
;;; init.el ends here
