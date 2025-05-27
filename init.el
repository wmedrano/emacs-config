(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)

(package-initialize)

(setq-default inhibit-startup-screen t)

(global-auto-revert-mode t)

(setq-default auto-save-interval 0
              create-lockfiles   nil
              make-backup-files  nil)

(setq-default gc-cons-percentage 1.0)

(run-with-idle-timer 3 t #'garbage-collect)

(menu-bar-mode -1)
(tool-bar-mode -1)

(scroll-bar-mode -1)

(setq-default scroll-conservatively 101)

(global-display-line-numbers-mode t)

(global-hl-line-mode t)

(add-to-list 'package-selected-packages 'doom-themes)
(load-theme 'doom-dracula t)

(add-to-list 'package-selected-packages 'doom-themes)
(doom-modeline-mode t)

(add-to-list 'package-selected-packages 'ivy)
(ivy-mode t)

(add-to-list 'package-selected-packages 'counsel)
(counsel-mode t)

(define-key counsel-mode-map (kbd "C-x b") #'counsel-switch-buffer)

(setq-default indent-tabs-mode nil)

(setq-default tab-width 4)

(setq-default fill-column 80)

(defun fill-column-100 ()
  (setq-local fill-column 100))

(add-hook 'rust-mode-hook #'fill-column-100)

(add-to-list 'package-selected-packages 'rust-mode)

(add-to-list 'package-selected-packages 'htmlize)
