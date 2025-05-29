(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)

(setq-default package-selected-packages
              '(doom-themes
                doom-modeline
                ivy
                counsel
                company
                rust-mode
                htmlize
                magit))

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

(load-theme 'doom-dracula t)

(doom-modeline-mode t)

(ivy-mode t)

(counsel-mode t)

(define-key counsel-mode-map (kbd "C-x b") #'counsel-switch-buffer)

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
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(package-selected-packages '(company counsel doom-themes htmlize ivy parrot rust-mode)))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
