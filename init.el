;;; init.el --- Emacs configuration -*- lexical-binding: t; -*-
;;; Commentary:
;;; Code:
;; Custom (managed by Emacs, do not edit by hand)
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(package-selected-packages
   '(ace-window anzu auto-highlight-symbol catppuccin-theme clang-format company
                consult consult-eglot diff-hl doom-modeline doom-themes
                dracula-theme eglot eldoc embark embark-consult erc evil
                evil-terminal-cursor-changer flymake gn-mode gnuplot gptel
                htmlize lua-mode marginalia markdown-mode orderless org
                package-lint peg posframe python rg rust-mode smartparens tramp
                transient ttx-mode typescript-mode vertico vertico-posframe
                vundo which-key yaml-mode zig-mode zig-ts-mode))
 '(safe-local-variable-values
   '((eval and buffer-file-name (not (eq major-mode 'package-recipe-mode))
           (or (require 'package-recipe-mode nil t)
               (let ((load-path (cons "../package-build" load-path)))
                 (require 'package-recipe-mode nil t)))
           (package-recipe-mode)))))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Package Management
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(require 'package)
(require 'cl-lib)
(require 'subr-x)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(package-initialize)
(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))
(let ((lisp-dir (expand-file-name "lisp/" user-emacs-directory)))
  ;; "^[^.]" excludes . and .. and other dotfiles (e.g. .git) from the directory listing
  (cl-loop for dir in (directory-files lisp-dir t "^[^.]")
           when (file-directory-p dir)
           do (add-to-list 'load-path dir)))
(cl-loop for path in '("~/.local/bin" "~/.cargo/bin")
         do (add-to-list 'exec-path path))


(require 'ace-window)
(when (display-graphic-p)
  (require 'ace-window-posframe))
(require 'ansi-color)
(require 'ansi-osc)
(require 'anzu)
(require 'company)
(require 'consult)
(require 'consult-flymake)
(require 'consult-imenu)
(require 'diff-hl)
(require 'diff-hl-flydiff)
(require 'doom-modeline)
(require 'doom-modeline-core)
(require 'doom-modeline-segments)
(require 'eglot)
(require 'embark)
(require 'evil)
(require 'flymake)
(require 'gptel)
(require 'marginalia)
(require 'posframe)
(require 'smartparens)
(require 'ttx-mode)
(require 'vertico)
(require 'vertico-posframe)
(require 'which-key)
(require 'auto-highlight-symbol)

(require 'monorepo)
(require 'jj)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Performance
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(setq-default gc-cons-threshold (* 100 1024 1024))  ; 100MB
(defvar gc-timer nil
  "Timer for idle garbage collection.")
(when gc-timer
  (cancel-timer gc-timer))
(setq gc-timer (run-with-idle-timer 4 t #'garbage-collect))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; General Settings
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(setq-default inhibit-startup-screen t
              use-short-answers t
              make-backup-files nil
              backup-inhibited  t
              auto-save-default nil
              auto-save-timeout nil
              auto-revert-interval 3
              lock-file-name-transforms '(("\\`/.*/\\([^/]+\\)\\'" "/tmp/\\1" t)))
(setq-default history-length 1000)
(savehist-mode 1)
(global-auto-revert-mode t)
(which-key-mode t)

;; Auto Highlight Symbol
(setq-default ahs-idle-interval 0.25)

(defun unhighlight-all ()
  "Remove all highlighting from the current buffer."
  (interactive)
  (unhighlight-regexp t))

;; Formatting
(setq-default fill-column      80
              indent-tabs-mode nil
              tab-width        4)

(require 'smartparens)
(require 'smartparens-config)
(add-hook 'prog-mode-hook #'smartparens-mode)
(add-hook 'prog-mode-hook #'auto-highlight-symbol-mode)

(defun string-filter-whitespace (string)
  (unless (string-match-p "\\`[[:space:]]*\\'" string)
       string))

(setq-default save-interprogram-paste-before-kill t
              kill-transform-function #'string-filter-whitespace)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; UI
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun use-light-theme ()
  (let ((color-scheme (string-trim (shell-command-to-string
                                    "gsettings get org.gnome.desktop.interface color-scheme"))))
    (string-equal color-scheme "'prefer-light'")))

(setq-default dracula-bolder-keywords nil
              catppuccin-dark-line-numbers-background t
              catppuccin-italic-comments t
              catppuccin-flavor (if (use-light-theme)
                                    'latte
                                  'mocha))

(require 'dracula-theme)
(cl-loop for theme in custom-enabled-themes
         do (disable-theme theme))
(load-theme 'dracula t)
(setq-default doom-modeline-buffer-encoding nil)
(doom-modeline-mode t)

(add-to-list 'default-frame-alist '(fullscreen . maximized))
(unless (display-graphic-p)
  (require 'evil-terminal-cursor-changer)
  (evil-terminal-cursor-changer-activate))

(column-number-mode t)
(tool-bar-mode -1)
(menu-bar-mode -1)
(scroll-bar-mode -1)
(set-face-attribute 'default nil
                    :font "Roboto Mono"
                    :height 120)
(setq-default display-line-numbers-grow-only t
              scroll-conservatively 101
              scroll-margin 0
              scroll-preserve-screen-position t
              auto-window-vscroll nil
              fast-but-imprecise-scrolling t)
(global-display-line-numbers-mode t)
(global-hl-line-mode t)
(blink-cursor-mode -1)
(setq-default ring-bell-function 'ignore)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Completion
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(setq-default completion-styles '(orderless basic)
              completion-category-overrides '((file (styles partial-completion)))
              completion-category-defaults nil)
(setq-default enable-recursive-minibuffers t)
(vertico-mode t)

(setq-default
 ;; For the rare occasion I feel like `vertico-posframe-mode'.
 vertico-posframe-poshandler #'posframe-poshandler-frame-top-center)

(marginalia-mode t) ;; Decorate consult-buffer and consult-find-file and the like

(recentf-mode t) ;; Make recentf available

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Code Completion
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(setq-default completion-in-region-function #'consult-completion-in-region
              company-tooltip-minimum-width 64)
(global-company-mode t)
(define-key company-active-map (kbd "C-s") #'completion-at-point)
(define-key company-active-map (kbd "C-h") nil)

;; References
(setq-default
 xref-show-xrefs-function       #'consult-xref
 xref-show-definitions-function #'consult-xref)

;; Embark
(setq-default
 embark-verbose-indicator-display-action
 '(display-buffer-in-side-window display-buffer-reuse-window))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Compilation
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(setq-default
 compilation-scroll-output t
 compile-command ""
 compilation-environment '("TERM=dumb"))
(add-hook 'compilation-filter-hook #'ansi-color-compilation-filter)
(add-hook 'compilation-filter-hook #'ansi-osc-compilation-filter)

;; VC
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(global-diff-hl-mode)
(add-hook 'diff-hl-mode #'diff-hl-flydiff-mode)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Eglot
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(setq-default eglot-events-buffer-config '(:size 0))

(defun eglot-inlay-hints-off ()
  "Disable inlay hints mode."
  (interactive)
  (eglot-inlay-hints-mode -1))
(add-hook 'eglot-managed-mode-hook #'eglot-inlay-hints-off)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Flymake
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(add-to-list 'display-buffer-alist
             '("\\*Flymake diagnostics.*\\*"
               (display-buffer-in-side-window)
               (side . bottom)
               (slot . 0)
               (window-height . 0.25)))

(defun flymake-eglot-fix-all ()
  "Interactively fix all errors with eglot.

Note: A bit buggy at the moment."
  (interactive)
  (condition-case nil
      (while t
        (flymake-goto-next-error)
        (condition-case nil
            (when (eglot-code-actions (point) (point))
              (call-interactively #'eglot-code-actions)
              (flymake-goto-next-error))
          (error
           ;; On error, move to the end of the current diagnostic region
           (let ((diag (get-char-property (point) 'flymake-diagnostic)))
             (when diag
               (goto-char (flymake-diagnostic-end diag)))))))
    (user-error nil)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Languages
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Elisp
(cl-loop for path in load-path
         do (add-to-list
             'elisp-flymake-byte-compile-load-path
             path))

;; Python
(add-hook 'python-mode-hook #'eglot-ensure)

;; Typescript
(setq-default js-indent-level 2
              typescript-indent-level 2)
(defun typescript-mode-setup ()
  "Setup C/C++ mode configuration."
  (setq-local tab-width 2))
(add-hook 'typescript-mode-hook #'typescript-mode-setup)
(add-hook 'typescript-mode-hook #'eglot-ensure)

;; C++
(add-hook 'c++-mode-hook #'eglot-ensure)

;; Rust
(defun rust-mode-setup ()
  "Setup rust-mode configuration."
  (setq fill-column 100))

(add-hook 'rust-mode-hook #'eglot-ensure)
(add-hook 'rust-mode-hook #'rust-mode-setup)

(defun cargo-workspace-root (&optional dir)
  "The root of the current workspace"
  (let ((default-directory (or dir default-directory)))
    (s-trim
     (shell-command-to-string
      "cargo metadata --format-version 1 | jq -r \".workspace_root\""))))

(defmacro cargo-cmd (command)
  "Run COMMAND with cargo at the project root."
  `(let ((default-directory (cargo-workspace-root)))
     (compile (concat "cargo " ,command))))

(defun cargo-check ()
  "Run cargo check at the project root."
  (interactive)
  (cargo-cmd "check"))

(defun cargo-build ()
  "Run cargo build at the project root."
  (interactive)
  (cargo-cmd "build"))

(defun cargo-criterion ()
  "Run cargo criterion at the project root."
  (interactive)
  (cargo-cmd "criterion"))

(setenv "NEXTEST_SHOW_PROGRESS" "none")
(setenv "CARGO_TERM_COLOR" "always")
(defun cargo-test ()
  "Run cargo nextest at the project root."
  (interactive)
  (cargo-cmd "nextest run"))

(defun cargo-doc ()
  "Run cargo doc at the project root."
  (interactive)
  (cargo-cmd "doc"))

(defun cargo-clippy ()
  "Run cargo clippy at the project root."
  (interactive)
  (cargo-cmd "clippy"))

(defun cargo-fix ()
  "Run cargo fix --allow-dirty at the project root."
  (interactive)
  (cargo-cmd "fix --allow-dirty"))

;; C / C++
(setq-default c-default-style '((java-mode . "java")
                                (awk-mode . "awk")
                                (other . "k&r"))
              c-basic-offset 2)

(defun c-mode-setup ()
  "Setup C/C++ mode configuration."
  (setq-local tab-width 2)
  (c-set-offset 'innamespace 0))

(add-hook 'c-mode-hook #'c-mode-setup)
(add-hook 'c++-mode-hook #'c-mode-setup)

;; Generate Ninja

(add-to-list 'auto-mode-alist '("\\.gn\\'" . gn-mode))
(add-to-list 'auto-mode-alist '("\\.lock\\'" . conf-toml-mode))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Contextual functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun format-buffer-dwim ()
  "Format the current buffer.
Uses `rust-format-buffer' in rust-mode, `clang-format-buffer' in
c-mode/c++-mode, `eglot-format-buffer' when eglot is active, or
falls back to `delete-trailing-whitespace'."
  (interactive)
  (cond
   ((memq major-mode '(c-mode c++-mode))
    (clang-format-buffer))
   ((eglot-managed-p)
    (eglot-format-buffer))
   ((eq major-mode 'rust-mode)
    (rust-format-buffer))
   (t
    (delete-trailing-whitespace))))

(add-hook 'before-save-hook #'format-buffer-dwim)
(global-set-key (kbd "C-c C-f") #'format-buffer-dwim)


(defun compile-dwim ()
  "Compile based on context.
If a *compilation* buffer window exists, recompile.
If in a Chromium project, run autoninja.
If in `rust-mode' or editing Cargo.toml, run `cargo-test'.
If in `emacs-lisp-mode', `eval-buffer'.
Otherwise, call compile interactively."
  (interactive)
  (cond
   ((get-buffer-window "*compilation*")
    (with-current-buffer "*compilation*"
      (recompile)))
   ((or (eq major-mode 'rust-mode)
        (when-let ((file (buffer-file-name)))
          (string-suffix-p "/Cargo.toml" file)))
    (cargo-test))
   ((eq major-mode 'emacs-lisp-mode)
    (eval-buffer))
   (t
    (call-interactively #'compile))))

(defun copy-filename ()
  "Copy the current file name to `kill-new'.
If `project-current' returns a project, make the path relative to
the project root."
  (interactive)
  (let* ((file (buffer-file-name))
         (project (and (fboundp 'project-current)
                       (project-current)))
         (root (and project (expand-file-name (project-root project))))
         (name (if (and root (string-prefix-p root file))
                   (file-relative-name file root)
                 file)))
    (unless file
      (user-error "No file name for current buffer"))
    (kill-new name)
    (message "Copied: %s" name)))

(defun copy-absolute-filename ()
  "Copy the current aboslute file name to `kill-new'."
  (interactive)
  (let ((name (buffer-file-name)))
    (unless name
      (user-error "No file name for current buffer"))
    (kill-new name)
    (message "Copied: %s" name)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Org mode
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(setq-default
 initial-major-mode 'org-mode
 initial-scratch-message "\n#+BEGIN_SRC emacs-lisp\n#+END_SRC\n"
 org-src-preserve-indentation t
 org-html-postamble nil
 org-use-sub-superscripts nil
 org-export-with-sub-superscripts nil
 org-fontify-special-blocks t)
(org-babel-do-load-languages
 'org-babel-load-languages
 '((dot . t)
   (emacs-lisp . t)
   (gnuplot . t)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; gptel (Ollama / OpenRouter)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defvar openrouter-backend
  (let ((key (getenv "OPENROUTER_API_KEY")))
    (when (and key (not (string= key "")))
      (gptel-make-openai "OpenRouter"
        :host "openrouter.ai"
        :endpoint "/api/v1/chat/completions"
        :stream t
        :key key
        :models '(qwen/qwen3.6-35b-a3b
                  nvidia/nemotron-3-super-120b-a12b:free
                  deepseek/deepseek-v4-flash
                  deepseek/deepseek-v4-pro
                  google/gemini-3-flash-preview
                  z-ai/glm-5.1)))
    "OpenRouter gptel backend, nil when OPENROUTER_API_KEY is unset."))

(defvar ollama-backend
  (gptel-make-ollama "Ollama"
    :host "localhost:11434"
    :stream t
    :request-params '(think "low")
    :models '(qwen3.6:35b gemma4:26b gemma4:e4b glm-5.1:cloud deepseek-v4-flash:cloud))
  "Local Ollama gptel backend.")

(defvar cerebras-backend
  (let ((key (getenv "CEREBRAS_API_KEY")))
    (when (and key (not (string= key "")))
      (gptel-make-openai "Cerebras"
        :host "api.cerebras.ai"
        :endpoint "/v1/chat/completions"
        :stream nil
        :key (getenv "CEREBRAS_API_KEY")
        :models '(gemma-4-31b)))))

(setq-default
 gptel-directives '((default . "")
                    (brief . "- You provide succint answer to programming questions.
- Assume that the person asking the question is already an experienced programmer.
- Provide brief answer with an example snippet.

* Example:

** Question

How do you define type hints in Python?

** Answer

Type hints use `:` for types and `->` for return values.

*** Example
```python
def add_numbers(a: int, b: int) -> int:
    return a + b
```

-   *`a: int`*: Parameter ~a~ should be an integer.
-   *`-> int`*: The function returns an integer."))
 gptel-default-mode 'org-mode)

(defvar gptel-ollama-backend
  (gptel-make-ollama "Ollama"
    :host "localhost:11434"
    :stream t
    :request-params '(think "low")
    :models '(qwen3.6:35b gemma4:26b gemma4:e4b glm-5.1:cloud deepseek-v4-flash:cloud)))

(defun gptel-set-backend ()
  "Interactively query for a backend and optionally an API key."
  (interactive)
  (let* ((choice (completing-read "Choose backend: " '("openrouter" "cerebras" "ollama")))
         (backend
          (pcase choice
            ("openrouter"
             (let ((key (or (getenv "OPENROUTER_API_KEY")
                            (read-string "OpenRouter API Key (press RET to skip): "))))
               (unless (string= key "") (setenv "OPENROUTER_API_KEY" key))
               (setq-default
                gptel-backend (gptel-make-openai "OpenRouter"
                                :host "openrouter.ai"
                                :endpoint "/api/v1/chat/completions"
                                :stream t
                                :key key
                                :models '(qwen/qwen3.6-35b-a3b
                                          nvidia/nemotron-3-super-120b-a12b:free
                                          deepseek/deepseek-v4-flash
                                          deepseek/deepseek-v4-pro
                                          google/gemini-3-flash-preview
                                          z-ai/glm-5.1))
                gptel-model 'deepseek/deepseek-v4-flash))
             ("cerebras"
              (let ((key (or (getenv "CEREBRAS_API_KEY")
                             (read-string "Cerebras API Key (press RET to skip): "))))
                (unless (string= key "") (setenv "CEREBRAS_API_KEY" key))
                (setq-default
                 gptel-backend (gptel-make-openai "Cerebras"
                                 :host "api.cerebras.ai"
                                 :endpoint "/v1/chat/completions"
                                 :stream nil
                                 :key key
                                 :models '(gpt-oss-120b gemma-4-31b))
                 gptel-model 'gpt-oss-120b)))
             ("ollama" (setq-default gptel-backend gptel-ollama-backend
                                     gptel-model 'gemma4:26b))))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Evil Mode
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(setq-default evil-cross-lines t
              evil-move-beyond-eol t
              evil-move-cursor-back nil)
(unless (display-graphic-p)
  (setq-default evil-normal-state-cursor  '(box  . "#51afef")   ; blue
                evil-insert-state-cursor  '(bar  . "#ff8c00")   ; orange
                evil-visual-state-cursor  '(box  . "#a9a1e1")   ; purple
                evil-emacs-state-cursor   '(box  . "#ffffff")   ; white
                evil-motion-state-cursor  '(box  . "#51afef")   ; blue
                evil-replace-state-cursor '(hbar . "#ff8c00"))) ; orange
(evil-mode 1)
(global-anzu-mode t)

;; Keybinds
(cl-loop for map in (list evil-motion-state-map evil-normal-state-map evil-visual-state-map)
         do (progn
              (define-key map "h" #'evil-backward-char)
              (define-key map "n" #'evil-next-line)
              (define-key map "e" #'evil-previous-line)
              (define-key map "i" #'evil-forward-char)
              (define-key map "gx" #'xref-find-references)))
(define-key evil-normal-state-map "[" nil)
(define-key evil-normal-state-map "]" nil)
(define-key evil-motion-state-map (kbd "RET") nil)
(define-key evil-normal-state-map (kbd "RET") #'ignore)
(define-key evil-motion-state-map "[" #'evil-goto-first-line)
(define-key evil-motion-state-map "]" #'evil-goto-line)
(define-key evil-normal-state-map "s" #'evil-insert)
(define-key evil-normal-state-map "S" #'evil-insert-line)
(define-key evil-motion-state-map "/" #'consult-line)
(define-key evil-motion-state-map "?" #'consult-line-multi)
(define-key evil-motion-state-map (kbd "C-.") #'embark-act)
(define-key evil-normal-state-map (kbd "TAB") #'indent-for-tab-command)

(defvar leader-map (make-sparse-keymap) "Leader key keymap.")
(define-key evil-motion-state-map (kbd "SPC") leader-map)
(define-key leader-map "B" #'consult-buffer-other-window)
(define-key leader-map "b" #'consult-buffer)
(define-key leader-map "ea" #'eglot-code-actions)
(define-key leader-map "ee" #'consult-flymake)
(define-key leader-map "ef" #'flymake-eglot-fix-all)
(define-key leader-map "ei" #'eglot-inlay-hints-mode)
(define-key leader-map "er" #'eglot-rename)
(define-key leader-map "es" #'eglot)
(define-key leader-map "hK" #'unhighlight-regexp)
(define-key leader-map "he" #'eldoc)
(define-key leader-map "hh" #'highlight-symbol-at-point)
(define-key leader-map "hk" #'unhighlight-all)
(define-key leader-map "nf" #'format-buffer-dwim)
(define-key leader-map "nk" #'consult-keep-lines)
(define-key leader-map "ns" #'sort-lines)
(define-key leader-map "oe" #'consult-eglot-symbols)
(define-key leader-map "of" #'project-find-file)
(define-key leader-map "or" #'consult-recent-file)
(define-key leader-map "p" project-prefix-map)
(define-key leader-map "rD" #'jj-diff-from)
(define-key leader-map "rd" #'jj-diff)
(define-key leader-map "rl" #'jj-log)
(define-key leader-map "re" #'jj-edit)
(define-key leader-map "rn" #'jj-new)
(define-key leader-map "rm" #'jj-describe)
(define-key leader-map "rr" #'jj-log)
(define-key leader-map "sA" #'consult-line-multi)
(define-key leader-map "sI" #'consult-imenu-multi)
(define-key leader-map "sa" #'consult-line)
(define-key leader-map "sf" #'consult-flymake)
(define-key leader-map "si" #'consult-imenu)
(define-key leader-map "so" #'occur)
(define-key leader-map "sr" #'rg)
(define-key leader-map "ss" #'consult-ripgrep)
(define-key leader-map "w" #'ace-window)

;; Ace Window
(setq-default aw-dispatch-always t)
(when (posframe-workable-p)
  (ace-window-posframe-mode t)
  ;; Delete all active posframe windows. Fixes buggy posframe when refreshing
  ;; the config file.
  (run-with-timer 0.2 nil #'posframe-delete-all))
(set-face-attribute 'aw-leading-char-face nil
                    :foreground "#FF5555"
                    :height 1536
                    :font "Lobster")
(define-key evil-motion-state-map (kbd "C-w") #'ace-window)
(define-key evil-insert-state-map (kbd "C-w") #'ace-window)

;; Motion modes
(cl-loop for mode in '(diff-mode
                       dired-mode
                       xref--xref-buffer-mode
                       ttx-mode)
         do (add-to-list 'evil-motion-state-modes mode))
(add-to-list 'evil-insert-state-modes 'jj-describe-mode)

;; Global Keybindings
(global-set-key (kbd "C-x b") #'consult-buffer)
(global-set-key (kbd "C-x p b") #'consult-project-buffer)
(global-set-key (kbd "M-y")   #'consult-yank-pop)
(global-set-key (kbd "C-.")   #'embark-act)
(global-set-key (kbd "M-i")   #'consult-imenu)
(global-set-key (kbd "M-I")   #'consult-imenu-multi)
(global-set-key (kbd "C-z")   #'undo)
(global-set-key (kbd "C-w")   #'ace-window)
(global-set-key (kbd "<f1>")  #'eldoc)
(global-set-key (kbd "<f2>")  #'eglot-rename)
(global-set-key (kbd "<f5>")  #'compile-dwim)

(put 'narrow-to-region 'disabled nil)

(provide 'init)

;;; init.el ends here
