;;; init.el --- User configuration -*- lexical-binding: t; -*-

;;; Commentary:
;; Personal Emacs configuration.

;;; Code:
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
 '(display-line-numbers-width 3)
 '(enable-recursive-minibuffers t)
 '(fill-column 80)
 '(gc-cons-percentage 2.0)
 '(gc-cons-threshold 1000000)
 '(global-auto-revert-mode t)
 '(inhibit-startup-screen t)
 '(make-backup-files nil)
 '(package-selected-packages
   '(ace-window auto-highlight-symbol clang-format consult consult-yasnippet
                corfu diff-hl doom-modeline dracula-theme eat eglot evil
                evil-commentary gn-mode markdown-mode orderless posframe rg
                smartparens ttx-mode vertico vundo yasnippet))
 '(ring-bell-function 'ignore)
 '(safe-local-variable-values
   '((compilation-scroll-output . first-error) (vc-handled-backends)))
 '(scroll-conservatively 101)
 '(select-enable-clipboard t)
 '(select-enable-primary t)
 '(tab-width 4)
 '(use-short-answers t)
 '(warning-suppress-log-types '((treesit))))
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

(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(use-package posframe
  :ensure t
  :defer t)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Completions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(use-package vertico
  :ensure t
  :defer nil
  :commands (vertico-mode)
  :config (vertico-mode 1))

(use-package consult
  :ensure t
  :defer t
  :commands (consult-buffer
             consult-flymake
             consult-imenu
             consult-line
             consult-line-multi
             consult-ripgrep
             consult-xref
             consult-yank-pop)
  :custom
  (xref-show-xrefs-function       #'consult-xref)
  (xref-show-definitions-function #'consult-xref)
  :init
  (global-set-key (kbd "C-x b") #'consult-buffer)
  (global-set-key (kbd "M-y")   #'consult-yank-pop))

(use-package orderless
  :ensure t
  :defer nil
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
  :commands (corfu-history-mode corfu-popupinfo-mode global-corfu-mode)
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

(use-package yasnippet
  :ensure t
  :defer t
  :commands (yas-minor-mode))

(use-package consult-yasnippet
  :ensure t
  :defer t
  :commands (consult-yasnippet)
  :init
  (global-set-key (kbd "C-c y") #'consult-yasnippet)
  :config (yas-minor-mode))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Search
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(use-package rg
  :ensure t
  :defer t
  :commands (rg))

(use-package paths-extra
  :ensure nil ;; Defined under user-lisp/
  :defer t
  :commands (copy-filename copy-filename-absolute))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Window management
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(use-package window
  :ensure nil
  :custom
  (display-buffer-alist
   '(("\\`\\*Warnings\\*\\'"
      (display-buffer-in-side-window)
      (side . bottom)
      (slot . 0)
      (window-height . 0.2)
      (window-parameters . ((no-other-window . t))))
     ((or (derived-mode . flymake-diagnostics-buffer-mode)
          (derived-mode . flymake-project-diagnostics-mode))
      (display-buffer-in-side-window)
      (side . bottom)
      (slot . 0)
      (window-height . 0.2)
      (window-parameters . ((no-other-window . t)))))))

(use-package ace-window
  :ensure t
  :defer t
  :commands (ace-window ace-window-posframe-mode)
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
  :commands (smartparens-mode)
  :init
  (add-hook 'prog-mode-hook #'smartparens-mode)
  :config
  (require 'smartparens-config))

(use-package auto-highlight-symbol
  :ensure t
  :defer t
  :commands (auto-highlight-symbol-mode)
  :custom
  (ahs-idle-interval 0.4)
  :init
  (add-hook 'prog-mode-hook #'auto-highlight-symbol-mode))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Appearance
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(use-package dracula-theme
  :ensure t
  :defer nil
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
  :commands (doom-modeline-mode)
  :config (doom-modeline-mode 1))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Languages
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(use-package flymake
  :ensure nil ;; builtin
  :defer t
  :commands (flymake-show-buffer-diagnostics flymake-show-project-diagnostics))

(use-package eglot
  :ensure t
  :defer t
  :commands (eglot
             eglot-code-actions
             eglot-ensure
             eglot-format
             eglot-inlay-hints-mode
             eglot-rename)
  :config
  (add-hook 'eglot-managed-mode-hook #'eglot-extra-disable-inlay-hints))

(use-package elisp-mode
  :ensure nil ;; builtin
  :defer t
  :config
  (add-hook 'emacs-lisp-mode-hook #'flymake-mode))

(use-package eglot-extra
  :ensure nil ;; Defined in user-lisp/eglot-extra.el
  :defer t
  :commands (eglot-autofix-next)
  :autoload (eglot-format-on-save-mode eglot-extra-disable-inlay-hints))

(use-package clang-format
  :ensure t
  :defer t
  :commands (clang-format-on-save-mode clang-format-buffer clang-format-region))

(use-package c-mode
  :ensure nil ;; builtin (cc-mode)
  :defer t
  :defines c-mode-map
  :init
  (add-hook 'c-mode-hook #'eglot-ensure)
  (with-eval-after-load 'cc-mode
    (define-key c-mode-map (kbd "C-c C-f") #'clang-format-region)))

(use-package c++-mode
  :ensure nil ;; builtin (cc-mode)
  :defer t
  :defines c++-mode-map
  :init
  (add-hook 'c++-mode-hook #'eglot-ensure)
  (with-eval-after-load 'cc-mode
    (define-key c++-mode-map (kbd "C-c C-f") #'clang-format-region)))

(defun set-fill-column-100 ()
  "Set `fill-column' to 100."
  (setq fill-column 100))

;; Requires M-x treesit-install-language-grammar for rust
(use-package rust-ts-mode
  :ensure nil ;; builtin
  :defer t
  :init
  (add-to-list 'auto-mode-alist '("\\.rs\\'" . rust-ts-mode))
  :config
  (add-hook 'rust-ts-mode-hook #'eglot-ensure)
  (add-hook 'rust-ts-mode-hook #'eglot-format-on-save-mode)
  (add-hook 'rust-ts-mode-hook #'set-fill-column-100)
  (add-hook 'rust-ts-mode-hook #'cargo-minor-mode)
  (define-key rust-ts-mode-map (kbd "C-c C-f") #'eglot-format)
  (define-key rust-ts-mode-map (kbd "C-c C-l") #'cargo-clippy)
  (define-key rust-ts-mode-map (kbd "C-c C-t") #'cargo-test))

(use-package cargo-extra
  :ensure nil ;; Defined in user-lisp/
  :defer t
  :autoload (cargo-cmd)
  :commands (cargo-minor-mode
             cargo-check cargo-build cargo-criterion cargo-test cargo-doc
             cargo-clippy cargo-fix))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Aux Languages
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Install from https://github.com/tree-sitter-grammars/tree-sitter-yaml
(use-package yaml-ts-mode
  :ensure nil ;; builtin
  :defer t
  :init
  (add-to-list 'auto-mode-alist '("\\.ya?ml\\'" . yaml-ts-mode)))

(use-package json-ts-mode
  :ensure nil ;; builtin
  :mode ("\\.json\\'" "\\.json5\\'"))

(use-package toml-ts-mode
  :ensure nil ;; builtin
  :defer t
  :mode ("\\.toml\\'" . toml-ts-mode))

(use-package cargo-toml-mode
  :ensure nil ;; Defined in user-lisp/
  :defer t
  :mode ("/Cargo\\.toml\\'" . cargo-toml-mode)
  :config
  (add-hook 'cargo-toml-mode-hook #'cargo-minor-mode))

;; Defined in user-lisp/
(use-package disasm
  :ensure nil ;; Defined in user-lisp/
  :defer t
  :commands (disasm))

(use-package gn-mode
  :ensure t
  :defer t
  :mode ("\\.gn\\'" . gn-mode))

(use-package ttx-mode
  :ensure t
  :defer t)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Weird dev environments
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(use-package chromium-dev-mode
  :ensure nil ;; Under user-lisp/
  :defer t
  :commands (chromium-dev-mode)
  :init
  ;; `compile' runs via shell, so `exec-path' alone is not enough — the
  ;; shell's PATH (in `process-environment') must also contain depot_tools.
  ;; Use :init (not :config) so this runs eagerly despite :defer t.
  (let ((depot-tools-path (expand-file-name "~/src/chromium/depot_tools")))
    (when (file-directory-p depot-tools-path)
      (add-to-list 'exec-path depot-tools-path)
      (let ((path (or (getenv "PATH") "")))
        (unless (string-match-p (regexp-quote depot-tools-path) path)
          (setenv "PATH" (concat depot-tools-path "/" path)))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Org/Markdown
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(use-package org
  :ensure nil ;; builtin
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
(setenv "JJ_PAGER" "cat")
(use-package compile
  :ensure nil ;; builtin
  :defer t
  :custom
  (compilation-scroll-output 'first-error)
  ;; 2 = skip warnings/info (only errors), 1 = skip info, 0 = don't skip
  (compilation-skip-threshold 2)
  (compile-command           "")
  :config
  (add-hook 'compilation-filter-hook #'ansi-color-compilation-filter)
  (add-hook 'compilation-filter-hook #'ansi-osc-compilation-filter))

(use-package eat
  :ensure t
  :defer t
  :commands (eat-eshell-mode))

(use-package eshell
  :ensure nil ;; builtin
  :defer t
  :config
  (add-hook 'eshell-mode-hook #'eat-eshell-mode))

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
  :commands (diff-hl-flydiff-mode global-diff-hl-mode)
  :config
  (global-diff-hl-mode 1)
  (add-hook 'diff-hl-mode-hook #'diff-hl-flydiff-mode))

(use-package vundo
  :ensure t
  :defer t)

(use-package jj
  :ensure nil ;; Defined under user-lisp/
  :defer t
  :commands
  (jj-new jj-edit
          jj-git-push jj-git-fetch
          jj-abandon jj-duplicate
          jj-rebase jj-rebase-onto
          jj-bookmark-set jj-bookmark-delete jj-bookmark-track))

(use-package jj-diff
  :ensure nil ;; Defined under user-lisp/
  :defer t
  :commands (jj-diff-at jj-diff-from))

(use-package jj-describe
  :ensure nil ;; Defined under user-lisp/
  :defer t
  :commands (jj-describe jj-describe-accept jj-describe-reject jj-describe-diff))

(use-package monorepo
  :ensure nil ;; Defined under user-lisp/
  :defer t
  :autoload (project-try-monorepo))

(use-package project
  :ensure nil ;; builtin
  :defer t
  :config
  (add-to-list 'project-find-functions #'project-try-monorepo))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Keybindings
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(use-package which-key
  :ensure nil ;; builtin
  :defer 1
  :custom
  (which-key-idle-delay 1)
  :init
  (which-key-mode 1))

(defun unhighlight-all ()
  "Remove all highlighting from the current buffer."
  (interactive)
  (unhighlight-regexp t))

(use-package evil-commentary
  :ensure t
  :defer t
  :commands (evil-commentary-mode))

(use-package evil
  :ensure t
  :defer nil
  :defines (evil-motion-state-map
            evil-motion-state-modes
            evil-normal-state-map
            evil-visual-state-map)
  :functions (evil-backward-char
              evil-forward-char
              evil-insert
              evil-mode
              evil-next-line
              evil-previous-line
              evil-ret)
  :config
  (evil-mode 1)
  (evil-commentary-mode 1)
  ;; Modes
  (add-to-list 'evil-motion-state-modes 'diff-mode)
  ;; Motion
  (define-key evil-motion-state-map (kbd "RET") nil)
  (define-key evil-normal-state-map (kbd "RET") #'evil-ret)
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
  (define-key evil-motion-state-map (kbd "gx") #'xref-find-references)
  (define-key evil-normal-state-map (kbd "gx") #'xref-find-references)
  ;; Leader (SPC)
  (let ((leader-map (make-sparse-keymap)))
    (define-key special-mode-map      (kbd "SPC") leader-map)
    (define-key evil-motion-state-map (kbd "SPC") leader-map)
    (define-key leader-map (kbd "b") #'consult-buffer)
    (define-key leader-map (kbd "p") project-prefix-map)
    (define-key leader-map (kbd "w") #'ace-window)
    (define-key leader-map (kbd "r") (make-sparse-keymap))
    (define-key leader-map (kbd "ra") #'jj-abandon)
    (define-key leader-map (kbd "rb") #'jj-bookmark-set)
    (define-key leader-map (kbd "rB") #'jj-bookmark-delete)
    (define-key leader-map (kbd "rd") #'jj-diff-at)
    (define-key leader-map (kbd "rD") #'jj-diff-from)
    (define-key leader-map (kbd "rf") #'jj-git-fetch)
    (define-key leader-map (kbd "rm") #'jj-describe)
    (define-key leader-map (kbd "re") #'jj-edit)
    (define-key leader-map (kbd "rn") #'jj-new)
    (define-key leader-map (kbd "rp") #'jj-git-push)
    (define-key leader-map (kbd "rt") #'jj-bookmark-track)
    (define-key leader-map (kbd "h") (make-sparse-keymap))
    (define-key leader-map (kbd "hK") #'unhighlight-regexp)
    (define-key leader-map (kbd "he") #'eldoc)
    (define-key leader-map (kbd "hh") #'highlight-symbol-at-point)
    (define-key leader-map (kbd "hH") #'unhighlight-all)
    (define-key leader-map (kbd "hf") #'describe-function)
    (define-key leader-map (kbd "hk") #'describe-key)
    (define-key leader-map (kbd "hv") #'describe-variable)
    (define-key leader-map (kbd "s") (make-sparse-keymap))
    (define-key leader-map (kbd "sa") #'consult-line)
    (define-key leader-map (kbd "se") #'consult-flymake)
    (define-key leader-map (kbd "st") #'query-replace)
    (define-key leader-map (kbd "si") #'consult-imenu)
    (define-key leader-map (kbd "so") #'occur)
    (define-key leader-map (kbd "sr") #'rg)
    (define-key leader-map (kbd "ss") #'consult-ripgrep)
    (define-key leader-map (kbd "e") (make-sparse-keymap))
    (define-key leader-map (kbd "ea") #'eglot-code-actions)
    (define-key leader-map (kbd "ed") #'flymake-show-buffer-diagnostics)
    (define-key leader-map (kbd "eD") #'flymake-show-project-diagnostics)
    (define-key leader-map (kbd "ee") #'consult-flymake)
    (define-key leader-map (kbd "ei") #'eglot-inlay-hints-mode)
    (define-key leader-map (kbd "er") #'eglot-rename)
    (define-key leader-map (kbd "es") #'eglot)
    (define-key leader-map (kbd "n") (make-sparse-keymap))
    (define-key leader-map (kbd "nn") #'consult-yasnippet)
    (define-key leader-map (kbd "ns") #'sort-lines)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Extra private stuff
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(let ((custom-file (expand-file-name "custom.el" user-emacs-directory)))
  (when (file-exists-p custom-file)
    (load-file custom-file)))

(provide 'init)
;;; init.el ends here
