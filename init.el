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
   '(ace-window anzu auto-highlight-symbol company consult diff-hl doom-modeline
                doom-themes dracula-theme eglot eldoc embark embark-consult erc
                evil flycheck flymake gn-mode gnuplot htmlize lua-mode
                marginalia markdown-mode orderless org peg posframe python rg
                rust-mode smartparens tramp transient typescript-mode vertico
                vertico-posframe vundo which-key)))
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
(require 'ace-window-posframe)
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
(require 'eglot)
(require 'embark)
(require 'evil)
(require 'flymake)
(require 'jj)
(require 'marginalia)
(require 'posframe)
(require 'smartparens)
(require 'ttx-mode)
(require 'vertico)
(require 'vertico-posframe)
(require 'which-key)

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

;; Formatting
(setq-default fill-column      80
              indent-tabs-mode nil
              tab-width        4)

(require 'smartparens)
(require 'smartparens-config)
(add-hook 'prog-mode-hook #'smartparens-mode)

;; Theme and UI
(setq-default dracula-bolder-keywords nil)
(require 'dracula-theme)
(let ((color-scheme (string-trim (shell-command-to-string
                                  "gsettings get org.gnome.desktop.interface color-scheme"))))
  (unless (string-equal color-scheme "'prefer-light'")
    (load-theme 'dracula t)))
(setq-default doom-modeline-buffer-encoding nil)
(doom-modeline-mode t)

(add-to-list 'default-frame-alist '(fullscreen . maximized))

;; Custom segment: Python virtualenv indicator
(doom-modeline-def-segment venv
  "Python virtualenv indicator. Displays a terminal icon when VIRTUAL_ENV is set."
  (when (getenv "VIRTUAL_ENV")
    (doom-modeline-icon-with-height
     (nerd-icons-sucicon "nf-seti-powershell" :face 'doom-modeline-info)
     (doom-modeline-vspc))))
;; Add venv segment to modeline after major-mode on the right side
(doom-modeline-add-segment 'venv 'major-mode :after)
(column-number-mode t)
(tool-bar-mode -1)
(menu-bar-mode -1)
(scroll-bar-mode -1)
(set-face-attribute 'default nil
                    :font "Fira Code"
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Minibuffer Completion
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(setq-default completion-styles '(orderless basic)
              completion-category-overrides '((file (styles partial-completion)))
              completion-category-defaults nil)
(setq-default enable-recursive-minibuffers t)
(vertico-mode t)

(setq-default
 ;; For the rare occasion I feel like `vertico-posframe-mode'.
 vertico-posframe-poshandler #'posframe-poshandler-frame-top-center)

(marginalia-mode t)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Code Completion
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(setq-default completion-in-region-function #'consult-completion-in-region
              company-tooltip-minimum-width 64)
(global-company-mode t)
(define-key company-active-map (kbd "C-s") #'completion-at-point)

;; Embark
(setq-default
 embark-verbose-indicator-display-action
 '(display-buffer-in-side-window display-buffer-reuse-window))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Compilation
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(setq-default
 compilation-scroll-output t
 compile-command "")
(add-hook 'compilation-filter-hook #'ansi-color-compilation-filter)
(add-hook 'compilation-filter-hook #'ansi-osc-compilation-filter)

(defun wezterm-open (directory)
  "Open a WezTerm terminal in DIRECTORY."
  (interactive "DDirectory: ")
  (start-process "wezterm" nil "wezterm" "start" "--cwd" (expand-file-name directory)))

(defun wezterm-run (directory command)
  "Run COMMAND in a WezTerm terminal in DIRECTORY."
  (interactive
   (let ((dir (read-directory-name "Directory: " default-directory))
         (cmd (read-string "Command: " (bound-and-true-p compile-command))))
     (list dir cmd)))
  (start-process "wezterm" nil "wezterm"
                 "start" "--cwd" (expand-file-name directory)
                 "--" "bash" "-ic"
(concat command "; exec bash")))

(defun http-server (directory port)
  "Start an HTTP server in DIRECTORY on PORT."
  (interactive
   (list (read-directory-name "Directory: " default-directory)
         (read-string "Port: " nil nil "8000")))
  (let ((default-directory (expand-file-name directory)))
    (async-shell-command (format "python -m http.server %s" port)
                         (format "*http-server %s*" port)))
  (browse-url (format "http://localhost:%s" port)))

;; VC
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(global-diff-hl-mode)
(add-hook 'diff-hl-mode #'diff-hl-flydiff-mode)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Eglot
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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

;; Rust
(defun rust-mode-setup ()
  "Setup rust-mode configuration."
  (setq fill-column 100))

(add-hook 'rust-mode-hook #'eglot-ensure)
(add-hook 'rust-mode-hook #'rust-mode-setup)

(defmacro cargo-cmd (command)
  "Run COMMAND with cargo at the project root."
  `(let ((default-directory (project-root (project-current t))))
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

(defun cargo-clippy ()
  "Run cargo clippy at the project root."
  (interactive)
  (cargo-cmd "clippy"))

(defun cargo-fix ()
  "Run cargo fix --allow-dirty at the project root."
  (interactive)
  (cargo-cmd "fix --allow-dirty"))

;; Generate Ninja

(add-to-list 'auto-mode-alist '("\\.gn\\'" . gn-mode))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Contextual functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun format-buffer-dwim ()
  "Format the current buffer."
  (interactive)
  (cond
   ((eglot-managed-p)
    (eglot-format-buffer))
   (t
    (delete-trailing-whitespace))))
(add-hook 'before-save-hook #'format-buffer-dwim)


(defun compile-dwim ()
  "Compile based on context.
If a *compilation* buffer window exists, recompile.
If in `rust-mode' or editing Cargo.toml, run `cargo-test'.
If in `emacs-lisp-mode', `eval-buffer'.
Otherwise, call compile interactively."
  (interactive)
  (cond
   ((get-buffer-window "*compilation*")
    (with-current-buffer "*compilation*"
      (recompile)))
   ((or (eq major-mode 'rust-mode)
        (string-suffix-p "/Cargo.toml" (buffer-file-name)))
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Org mode
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(setq-default
 initial-major-mode 'org-mode
 initial-scratch-message "\n#+BEGIN_SRC\n#+END_SRC\n"
 org-src-preserve-indentation t
 org-html-postamble nil
 org-use-sub-superscripts nil
 org-export-with-sub-superscripts nil)
(org-babel-do-load-languages
 'org-babel-load-languages
 '((dot . t)
   (emacs-lisp . t)
   (gnuplot . t)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Evil Mode
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(setq-default evil-cross-lines t
              evil-move-beyond-eol t
              evil-move-cursor-back nil)
(evil-mode 1)
(global-anzu-mode t)

;; Keybinds
(dolist (map (list evil-motion-state-map evil-normal-state-map evil-visual-state-map))
  (define-key map "h" #'evil-backward-char)
  (define-key map "n" #'evil-next-line)
  (define-key map "e" #'evil-previous-line)
  (define-key map "i" #'evil-forward-char))
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

;; SPC s
(define-key leader-map "ss" #'consult-ripgrep)
(define-key leader-map "sr" #'rg)
(define-key leader-map "so" #'occur)
(define-key leader-map "sa" #'consult-line)
(define-key leader-map "sA" #'consult-line-multi)
(define-key leader-map "si" #'consult-imenu)
(define-key leader-map "sI" #'consult-imenu-multi)
(define-key leader-map "sf" #'consult-flymake)

;; SPC e
(define-key leader-map "ea" #'eglot-code-actions)
(define-key leader-map "ee" #'consult-flymake)
(define-key leader-map "ef" #'flymake-eglot-fix-all)
(define-key leader-map "ei" #'eglot-inlay-hints-mode)
(define-key leader-map "er" #'eglot-rename)

;; Ace Window
(setq-default aw-dispatch-always t)
(when (posframe-workable-p)
  (ace-window-posframe-mode t))
(set-face-attribute 'aw-leading-char-face nil
                    :foreground "#FF5555"
                    :height 1024
                    :font "Lobster")
(define-key evil-motion-state-map (kbd "C-w") #'ace-window)
(define-key evil-insert-state-map (kbd "C-w") #'ace-window)

;; Motion modes
(cl-loop for mode in '(diff-mode
                       xref--xref-buffer-mode
                       ttx-mode)
         do (add-to-list 'evil-motion-state-modes mode))

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
