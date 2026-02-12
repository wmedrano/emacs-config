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
   '(ace-window agent-shell anzu company consult diff-hl doom-modeline
                doom-themes dracula-theme embark embark-consult evil
                htmlize lua-mode orderless posframe rg rust-mode
                vertico)))
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
(add-to-list 'load-path "~/src/ttx-mode/")
(add-to-list 'exec-path "~/.local/bin")

(require 'ace-window)
(require 'ace-window-posframe)
(require 'agent-shell)
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
(require 'evil)
(require 'flymake)
(require 'posframe)
(require 'shell-maker)
(require 'ttx)
(require 'vertico)
(require 'which-key)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Performance
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(setq gc-cons-threshold (* 100 1024 1024))  ; 100MB
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
              indent-tabs-mode nil
              tab-width 4
              auto-revert-interval 3)
(setq history-length 1000)
(savehist-mode 1)
(global-auto-revert-mode t)
(which-key-mode t)

;; Theme and UI
(load-theme 'dracula t)
(doom-modeline-mode t)
(tool-bar-mode -1)
(menu-bar-mode -1)
(scroll-bar-mode -1)
(set-face-attribute 'default nil
                    :font "Inconsolata"
                    :height 140)
(setq-default display-line-numbers-grow-only t
              scroll-conservatively 101
              scroll-margin 0
              scroll-preserve-screen-position t
              auto-window-vscroll nil
              fast-but-imprecise-scrolling t)
(global-display-line-numbers-mode t)
(global-hl-line-mode t)
(blink-cursor-mode -1)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Minibuffer Completion
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(setq-default completion-styles '(orderless basic)
              completion-category-overrides '((file (styles partial-completion)))
              completion-category-defaults nil)
(vertico-mode t)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Code Completion
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(setq-default completion-in-region-function #'consult-completion-in-region
              company-tooltip-minimum-width 64)
(global-company-mode t)
(require 'company)
(define-key company-active-map (kbd "C-s") #'completion-at-point)

;; Embark
(setq-default
 embark-verbose-indicator-display-action
 '(display-buffer-in-side-window display-buffer-reuse-window))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Compilation
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(setq-default compile-command "")  ; Default is make, which I rarely use.
(add-hook 'compilation-filter-hook #'ansi-color-compilation-filter)
(add-hook 'compilation-filter-hook #'ansi-osc-compilation-filter)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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

(defun eglot-inlay-hints-preview ()
  "Temporarily show inlay hints."
  (interactive)
  (eglot-inlay-hints-mode t)
  (run-with-timer 10 nil #'eglot-inlay-hints-off))

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
;; Agent Shell
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(add-to-list 'display-buffer-alist
             '((major-mode . agent-shell-mode)
               (display-buffer-reuse-window display-buffer-pop-up-window)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Languages
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Elisp
(cl-loop for path in load-path
         do (add-to-list
             'elisp-flymake-byte-compile-load-path
             path))

;; Rust
(add-hook 'rust-mode-hook #'eglot-ensure)

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

(setenv "NEXTEST_SHOW_PROGRESS" "none")
(defun cargo-test ()
  "Run cargo nextest at the project root."
  (interactive)
  (cargo-cmd "nextest run"))

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
        (string= (buffer-name) "Cargo.toml"))
    (cargo-test))
   ((eq major-mode 'emacs-lisp-mode)
    (eval-buffer))
   (t
    (call-interactively #'compile))))

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
  (define-key map "h" 'evil-backward-char)
  (define-key map "n" 'evil-next-line)
  (define-key map "e" 'evil-previous-line)
  (define-key map "i" 'evil-forward-char))
(define-key evil-normal-state-map "[" nil)
(define-key evil-normal-state-map "]" nil)
(define-key evil-motion-state-map "[" 'evil-goto-first-line)
(define-key evil-motion-state-map "]" 'evil-goto-line)
(define-key evil-normal-state-map "s" 'evil-insert)
(define-key evil-normal-state-map "S" 'evil-insert-line)
(define-key evil-motion-state-map "/" 'consult-line)
(define-key evil-motion-state-map "?" 'consult-line-multi)
(define-key evil-motion-state-map (kbd "C-.") 'embark-act)
(defvar leader-map (make-sparse-keymap) "Leader key keymap.")
(define-key evil-motion-state-map (kbd "SPC") leader-map)
(define-key leader-map "ee" #'consult-flymake)
(define-key leader-map "ea" #'eglot-code-actions)
(define-key leader-map "er" #'eglot-rename)
(define-key leader-map "ef" #'flymake-eglot-fix-all)

;; Ace Window
(setq-default aw-dispatch-always t)
(when (posframe-workable-p)
  (ace-window-posframe-mode t))
(set-face-attribute 'aw-leading-char-face nil :height 1024)
(define-key evil-motion-state-map (kbd "C-w") 'ace-window)
(define-key evil-insert-state-map (kbd "C-w") 'ace-window)

;; Agent Shell
(defun agent-shell-clear-and-insert ()
  "Clear the agent shell buffer and enter insert mode."
  (interactive)
  (shell-maker-clear-buffer)
  (evil-insert 1))

(define-key agent-shell-mode-map (kbd "C-c C-k") #'agent-shell-clear-and-insert)
(define-key agent-shell-mode-map (kbd "C-c C-s") #'agent-shell-set-session-mode)
(define-key agent-shell-mode-map (kbd "C-c C-m") #'agent-shell-set-session-model)

;; Global Keybindings
(global-set-key (kbd "C-x b") #'consult-buffer)
(global-set-key (kbd "M-y")   #'consult-yank-pop)
(global-set-key (kbd "C-.")   #'embark-act)
(global-set-key (kbd "M-i")   #'consult-imenu)
(global-set-key (kbd "M-I")   #'consult-imenu-multi)
(global-set-key (kbd "C-z")   #'undo)
(global-set-key (kbd "C-w")   #'ace-window)
(global-set-key (kbd "<f2>")  #'eglot-rename)
(global-set-key (kbd "<f5>")  #'compile-dwim)


(provide 'init)
;;; init.el ends here
