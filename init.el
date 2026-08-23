;; -*- lexical-binding: t; -*-
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(auto-save-default nil)
 '(auto-save-interval 0)
 '(blink-cursor-mode nil)
 '(c-basic-offset 2)
 '(c-default-style '((java-mode . "java") (awk-mode . "awk") (other . "k&r")))
 '(comment-fill-column 80)
 '(display-line-numbers-width 3)
 '(enable-recursive-minibuffers t)
 '(gc-cons-percentage 2.0)
 '(gc-cons-threshold 1000000)
 '(global-auto-revert-mode t)
 '(inhibit-startup-screen t)
 '(make-backup-files nil)
 '(package-selected-packages
   '(ace-window auto-highlight-symbol clang-format consult corfu diff-hl
                doom-modeline dracula-theme eglot evil gn-mode
                markdown-mode orderless posframe rg smartparens
                ttx-mode vertico))
 '(ring-bell-function 'ignore)
 '(scroll-conservatively 4)
 '(tab-width 4)
 '(use-short-answers t))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )

(global-display-line-numbers-mode 1)
(savehist-mode 1)
(tool-bar-mode -1)
(menu-bar-mode -1)
(scroll-bar-mode -1)
(setq-default indent-tabs-mode nil)
(add-hook 'before-save-hook #'delete-trailing-whitespace)
(add-to-list 'default-frame-alist '(fullscreen . maximized))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Packages
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(when (< emacs-major-version 32)
  (add-to-list 'load-path
               (expand-file-name "user-lisp" user-emacs-directory)))

(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(use-package posframe
  :ensure t
  :defer t)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Completions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(use-package vertico
  :ensure t
  :config (vertico-mode 1))

(use-package consult
  :ensure t
  :defer t
  :custom
  (xref-show-xrefs-function       #'consult-xref)
  (xref-show-definitions-function #'consult-xref)
  :init
  (global-set-key (kbd "C-x b") #'consult-buffer)
  (global-set-key (kbd "M-y")   #'consult-yank-pop))

(use-package orderless
  :ensure t
  :custom
  ;; Configure a custom style dispatcher (see the Consult wiki)
  ;; (orderless-style-dispatchers '(+orderless-consult-dispatch orderless-affix-dispatch))
  ;; (orderless-component-separator #'orderless-escapable-split-on-space)
  (completion-styles '(orderless basic))
  (completion-category-overrides '((file (styles partial-completion))))
  (completion-category-defaults nil) ;; Disable defaults, use our settings
  (completion-pcm-leading-wildcard t)) ;; Emacs 31: partial-completion behaves like substring

(use-package corfu
  :ensure t
  :defer 1
  :custom
  (corfu-auto t)
  (corfu-auto-delay 0.3)
  (corfu-candidates 100)
  (corfu-cycle t)
  (corfu-min-width 64)
  :config
  (global-corfu-mode 1)
  (corfu-history-mode 1)
  (corfu-popupinfo-mode 1))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Search
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(use-package rg
  :ensure t
  :defer t)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Window management
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(use-package ace-window
  :ensure t
  :defer t
  :custom
  (aw-dispatch-always t)
  :custom-face
  (aw-leading-char-face ((t (:foreground "#FF5555" :height 1536 :font "Lobster"))))
  :config
  (when (display-graphic-p)
    (ace-window-posframe-mode 1)))

(use-package smartparens
  :ensure t
  :defer t
  :init
  (add-hook 'prog-mode-hook #'smartparens-mode)
  :config
  (require 'smartparens-config))

(use-package auto-highlight-symbol
  :ensure t
  :defer t
  :init
  (add-hook 'prog-mode-hook #'auto-highlight-symbol-mode))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Appearance
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(use-package dracula-theme
  :ensure t
  :custom
  (doom-modeline-buffer-encoding nil)
  :config
  (load-theme 'dracula t)
  (set-face-attribute 'line-number-current-line nil
                      :inherit 'highlight
                      :weight 'bold)
  (set-face-attribute 'default nil :font "Inconsolata-14")
  ;; Makes emojis have the same height as the monospace font 😀
  (set-fontset-font t 'emoji (font-spec :family "Noto Color Emoji" :size 18)))

(use-package doom-modeline
  :ensure t
  :defer 1
  :config (doom-modeline-mode 1))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Languages
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(use-package eglot
  :ensure t
  :defer t
  :config
  (require 'eglot-extra))

;; In user-lisp/eglot-extra.el
(use-package eglot-extra
  :defer t
  :autoload (eglot-format-on-save-mode))

(use-package clang-format
  :ensure t
  :defer t
  :init
  (add-hook 'c-mode-hook #'clang-format-on-save-mode))

(use-package rust-ts-mode
  :defer t
  :init
  (add-to-list 'auto-mode-alist '("\\.rs\\'" . rust-ts-mode))
  :config
  (add-hook 'rust-ts-mode-hook #'eglot-ensure)
  (add-hook 'rust-ts-mode-hook #'eglot-format-on-save-mode)
  (define-key rust-ts-mode-map (kbd "C-c C-f") #'eglot-format)
  (define-key rust-ts-mode-map (kbd "C-c C-t") #'cargo-test))

;; Defined in user-lisp/
(use-package rust-extra
  :defer t
  :autoload (cargo-cmd
             cargo-check cargo-build cargo-criterion cargo-test
             cargo-doc cargo-clippy cargo-fix))

;; Defined in user-lisp/
(use-package disasm
  :defer t
  :commands (disasm))

(use-package gn-mode
  :ensure t
  :defer t)

(use-package ttx-mode
  :ensure t
  :defer t
  :mode ("\\.[ot]tf\\'" "\\.woff2\\'")
  :commands (ttx-mode ttx-load-table ttx-load-all-tables ttx-unload-table))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Org/Markdown
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(use-package org
  :ensure t
  :defer t
  :custom
  (org-src-preserve-indentation t)
  (org-html-postamble nil)
  (org-use-sub-superscripts nil)
  (org-export-with-sub-superscripts nil)
  (org-fontify-special-blocks t))

(use-package markdown-mode
  :ensure t
  :defer t)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Shell/Compilation
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(use-package compile
  :defer t
  :custom
  (compilation-scroll-output 'first-error)
  (compile-command           ""))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Performance
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defvar gc--idle-timer nil)
(unless gc--idle-timer
  (setq gc--idle-timer
        (run-with-idle-timer 4 t #'garbage-collect)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Project Management + Version Control
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(use-package diff-hl
  :ensure t
  :defer 1
  :config (global-diff-hl-mode 1))

(use-package vundo
  :ensure t
  :defer t)

;; Defined under user-lisp/
(use-package jj
  :defer t
  :commands (jj-new jj-edit jj-git-push jj-git-fetch jj-abandon jj-duplicate jj-rebase jj-rebase-onto))
(use-package jj-diff
  :defer t
  :commands (jj-diff-at jj-diff-from))
(use-package jj-describe
  :defer t
  :commands (jj-describe jj-describe-accept jj-describe-reject jj-describe-diff))

;; Defined in user-lisp/
(use-package monorepo
  :defer t
  :autoload (project-try-monorepo))

(use-package project
  :defer t
  :config
  (add-to-list 'project-find-functions #'project-try-monorepo))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Keybindings
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(use-package which-key
  :defer 3
  :custom
  (which-key-idle-delay 1)
  :init
  (which-key-mode 1))

(defun unhighlight-all ()
  "Remove all highlighting from the current buffer."
  (interactive)
  (unhighlight-regexp t))

(use-package evil
  :ensure t
  :config
  (evil-mode 1)
  ;; Motion
  (define-key evil-motion-state-map (kbd "h") #'evil-backward-char)
  (define-key evil-normal-state-map (kbd "h") nil)
  (define-key evil-visual-state-map (kbd "h") nil)
  (define-key evil-motion-state-map (kbd "n") #'evil-next-line)
  (define-key evil-normal-state-map (kbd "n") nil)
  (define-key evil-visual-state-map (kbd "n") nil)
  (define-key evil-motion-state-map (kbd "e") #'evil-previous-line)
  (define-key evil-normal-state-map (kbd "e") nil)
  (define-key evil-visual-state-map (kbd "e") nil)
  (define-key evil-motion-state-map (kbd "i") #'evil-forward-char)
  (define-key evil-normal-state-map (kbd "i") nil)
  (define-key evil-visual-state-map (kbd "i") nil)
  ;; Insert
  (define-key evil-normal-state-map (kbd "s") #'evil-insert)
  ;; Search
  (define-key evil-motion-state-map (kbd "/") #'consult-line)
  (define-key evil-motion-state-map (kbd "?") #'consult-line-multi)
  ;; Leader (SPC)
  (defvar leader-map (make-sparse-keymap))
  (require 'simple)
  (define-key special-mode-map      (kbd "SPC") leader-map)
  (define-key evil-motion-state-map (kbd "SPC") leader-map)
  (define-key leader-map (kbd "b") #'consult-buffer)
  (define-key leader-map (kbd "p") project-prefix-map)
  (define-key leader-map (kbd "w") #'ace-window)
  (let ((vc-map (make-sparse-keymap)))
    (define-key leader-map (kbd "r") vc-map)
    (define-key vc-map (kbd "d") #'jj-diff-at)
    (define-key vc-map (kbd "D") #'jj-diff-from)
    (define-key vc-map (kbd "m") #'jj-describe)
    (define-key vc-map (kbd "e") #'jj-edit)
    (define-key vc-map (kbd "n") #'jj-new))
  (let ((highlight-map (make-sparse-keymap)))
    (define-key leader-map (kbd "h") highlight-map)
    (define-key highlight-map (kbd "K") #'unhighlight-regexp)
    (define-key highlight-map (kbd "e") #'eldoc)
    (define-key highlight-map (kbd "h") #'highlight-symbol-at-point)
    (define-key highlight-map (kbd "k") #'unhighlight-all))
  (let ((search-map (make-sparse-keymap)))
    (define-key leader-map (kbd "s") search-map)
    (define-key search-map (kbd "a") #'consult-line)
    (define-key search-map (kbd "f") #'consult-flymake)
    (define-key search-map (kbd "i") #'consult-imenu)
    (define-key search-map (kbd "o") #'occur)
    (define-key search-map (kbd "r") #'rg)
    (define-key search-map (kbd "s") #'consult-ripgrep))
  (let ((lsp-map (make-sparse-keymap)))
    (define-key leader-map (kbd "e") lsp-map)
    (define-key lsp-map (kbd "a") #'eglot-code-actions)
    (define-key lsp-map (kbd "r") #'eglot-rename)
    (define-key lsp-map (kbd "s") #'eglot))
  (let ((edit-map (make-sparse-keymap)))
    (define-key leader-map (kbd "n") edit-map)
    (define-key edit-map (kbd "s") #'sort-lines)))
