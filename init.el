;; -*- lexical-binding: t; -*-
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(package-selected-packages
   '(company doom-modeline dracula-theme eglot magit rg rust-mode)))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )

(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(package-initialize)

(setq-default inhibit-startup-screen t
	      ring-bell-function     #'ignore
	      scroll-conservatively  101
              indent-tabs-mode       nil)
(setq-default auto-save-interval 0
              make-backup-files  nil)
(tool-bar-mode -1)
(menu-bar-mode -1)
(scroll-bar-mode -1)
(ido-mode 1)

(doom-modeline-mode t)
(global-company-mode t)
(global-display-line-numbers-mode t)
(global-hl-line-mode t)
(load-theme 'dracula t)
