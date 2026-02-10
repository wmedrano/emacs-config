(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(package-selected-packages
   '(agent-shell anzu company consult diff-hl doom-modeline dracula-theme
                 embark embark-consult evil lua-mode orderless
                 rust-mode vertico)))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )

(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(package-initialize)
(add-to-list 'load-path "~/src/ttx-el/")
(require 'ttx)

(setq-default make-backup-files nil
              backup-inhibited  t
              auto-save-default nil
              auto-save-timeout nil)

;; Garbage collection
(setq gc-cons-threshold (* 100 1024 1024))  ; 100MB
(defvar gc-timer nil
  "Timer for idle garbage collection.")
(when gc-timer
  (cancel-timer gc-timer))
(setq gc-timer (run-with-idle-timer 4 t #'garbage-collect))

;; Startup
(setq-default inhibit-startup-screen t
              use-short-answers t)

;; Theme
(load-theme 'dracula t)
(doom-modeline-mode t)
(tool-bar-mode -1)
(menu-bar-mode -1)
(scroll-bar-mode -1)

(set-face-attribute 'default nil
            :font "Inconsolata"
            :height 140)

;; Line numbers
(setq-default display-line-numbers-grow-only t)
(global-display-line-numbers-mode t)
(global-hl-line-mode t)

;; Scrolling
(setq-default scroll-conservatively 101
              scroll-margin 0
              scroll-preserve-screen-position t
              auto-window-vscroll nil
              fast-but-imprecise-scrolling t)

;; Editor completion
(setq-default completion-styles '(orderless basic)
              completion-category-overrides '((file (styles partial-completion)))
              completion-category-defaults nil)
(setq history-length 1000)
(savehist-mode 1)
(global-anzu-mode t)
(vertico-mode t)
(global-set-key (kbd "C-x b") #'consult-buffer)
(global-set-key (kbd "M-y")  #'consult-yank-pop)
(global-set-key (kbd "C-.")   #'embark-act)
(global-set-key (kbd "M-i")   #'consult-imenu)
(global-set-key (kbd "M-I")   #'consult-imenu-multi)
(global-set-key (kbd "C-z")   #'undo)

;; Evil mode
(setq
 evil-cross-lines t)
(require 'evil)
(evil-mode 1)

;; Colemak bindings
(define-key evil-motion-state-map "h" 'evil-backward-char)
(define-key evil-motion-state-map "n" 'evil-next-line)
(define-key evil-motion-state-map "e" 'evil-previous-line)
(define-key evil-motion-state-map "i" 'evil-forward-char)
(define-key evil-normal-state-map "h" 'evil-backward-char)
(define-key evil-normal-state-map "n" 'evil-next-line)
(define-key evil-normal-state-map "e" 'evil-previous-line)
(define-key evil-normal-state-map "i" 'evil-forward-char)
(define-key evil-visual-state-map "h" 'evil-backward-char)
(define-key evil-visual-state-map "n" 'evil-next-line)
(define-key evil-visual-state-map "e" 'evil-previous-line)
(define-key evil-visual-state-map "i" 'evil-forward-char)

;; "s" for insert mode
(define-key evil-normal-state-map "s" 'evil-insert)
(define-key evil-normal-state-map "S" 'evil-insert-line)

;; Remap displaced keys
(define-key evil-normal-state-map "k" 'evil-search-next)
(define-key evil-normal-state-map "K" 'evil-search-previous)

;; Remap search to consult
(define-key evil-normal-state-map "/" 'consult-line)
(define-key evil-normal-state-map "?" 'consult-line-multi)

;; Embark in evil mode
(define-key evil-normal-state-map (kbd "C-.") 'embark-act)

;; Code completion
(setq-default completion-in-region-function #'consult-completion-in-region
              company-tooltip-minimum-width 64)
(global-company-mode t)
(require 'company)
(define-key company-active-map (kbd "C-s") #'completion-at-point)

;; Compilation mode
(setq-default
 ;; The default is make, which I rarely use.
 compile-command "")
(global-set-key (kbd "<f5>") #'recompile)
(add-hook 'compilation-filter-hook #'ansi-color-compilation-filter)
(add-hook 'compilation-filter-hook #'ansi-osc-compilation-filter)

;; Formatting
(setq-default indent-tabs-mode nil
              tab-width 4)

(defun format-buffer-dwim ()
  "Format the current buffer."
  (interactive)
  (cond
   ((eglot-managed-p)
    (eglot-format-buffer))
   (t
    (delete-trailing-whitespace))))
(add-hook 'before-save-hook #'format-buffer-dwim)

;; Eglot stuff
(defun eglot-inlay-hints-off ()
  "Disable inlay hints mode."
  (interactive)
  (eglot-inlay-hints-mode -1))
(add-hook 'eglot-managed-mode-hook #'eglot-inlay-hints-off)

(defun eglot-inlay-hints-preview ()
  "Temporarily show inlay hints."
  (interactive)
  (eglot-inlay-hints-mode t)
  (run-with-timer 10 nil #'eglot-inlay-hints-mode-off))

(setq-default auto-revert-interval 3)
(global-auto-revert-mode)

(which-key-mode t)

;; Flymake
(add-to-list 'display-buffer-alist
             '("\\*Flymake diagnostics.*\\*"
               (display-buffer-in-side-window)
               (side . bottom)
               (slot . 0)
               (window-height . 0.25)))

;; Embark (right click, sort of)
(setq-default
 embark-verbose-indicator-display-action
 '(display-buffer-in-side-window display-buffer-reuse-window))

;; Emacs Lisp
(cl-loop for path in load-path
         do (add-to-list
             'elisp-flymake-byte-compile-load-path
             path))

;; Rust
(add-hook 'rust-mode-hook #'eglot-ensure)


(require 'agent-shell)
(add-to-list 'exec-path "~/.local/bin")
