(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)

(setq-default package-selected-packages
              '(doom-themes
                doom-modeline
                vertico
                consult
                company
                htmlize
                rg
                magit
                rust-mode
                yaml-mode
                markdown-mode
                ))

(package-initialize)

(setq-default inhibit-startup-screen t)

(global-auto-revert-mode t)

(setq-default auto-save-interval 0
              auto-save-default  nil
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

(load-theme 'doom-dracula t)

(doom-modeline-mode t)

(vertico-mode t)

(global-set-key (kbd "C-x b") #'consult-buffer)

(global-set-key (kbd "C-x C-b") #'ibuffer)

(add-hook 'rust-mode-hook #'eglot-ensure)

(setq-default indent-tabs-mode nil)

(setq-default tab-width 4)

(setq-default fill-column 80)

(defun fill-column-100 ()
  (setq-local fill-column 100))

(add-hook 'rust-mode-hook #'fill-column-100)

(add-hook 'before-save-hook #'delete-trailing-whitespace)

(defun eglot-maybe-format-buffer ()
  (when (eglot-managed-p) (eglot-format-buffer)))

(add-hook 'before-save-hook #'eglot-maybe-format-buffer)

(global-company-mode t)

(defun electric-indent-mode-local-off ()
  (electric-indent-local-mode -1))

(add-hook 'org-mode-hook #'electric-indent-mode-local-off)
