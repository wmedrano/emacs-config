;; -*- lexical-binding: t; -*-
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(package-selected-packages
   '(company counsel doom-modeline doom-themes eglot ivy magit rg
             rust-mode)))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )

;; Initialize packages. See https://melpa.org/#/getting-started.
(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(package-initialize)

(setq-default
 ;; Prevents the Emacs startup screen(buffer) from opening.
 inhibit-startup-screen t
 ;; Do not trigger any audio for "ring-bell". This is most often triggered when
 ;; the cursor attempts to go out of bounds.
 ring-bell-function     #'ignore
 ;; Setting scroll-conservatively above 100 makes it so that Emacs does the
 ;; minimum amount of scrolling to put the cursor into view. The default value
 ;; (0) recenters the entire window around the cursor when the cursor is out of
 ;; view. 
 scroll-conservatively  101
 ;; Emacs uses a combination of tabs and spaces when auto-indenting. These
 ;; pleases neither the space nor tab crowd. Disabling tabs makes it so Emacs
 ;; always uses spaces.
 indent-tabs-mode       nil)


(setq-default
 ;; Do not produce auto save file. Autosaves happen every n events and saves the
 ;; file as "#<filename>#".
 auto-save-interval 0
 ;; Emacs makes a backup of a file when first visiting it. The file is named
 ;; `~<filename>`. These backups remain indefinitely, though re-opening the file
 ;; will overwrite the old backup.
 make-backup-files  nil)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Appearance
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(load-theme 'doom-dracula t)
(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode -1)
(global-display-line-numbers-mode t)
(global-hl-line-mode t)
(doom-modeline-mode t)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Editor completions
;;
;; Uses ivy-mode to display completions better, compared to the Emacs default
;; and even the built-in ido-mode. Additionally, counsel-mode wraps some common
;; functions like `counsel-M-x' to provide a little bit more context.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(ivy-mode t)
(counsel-mode t)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; LSP
;;
;; The built in `eglot' package provides interaction with LSP servers. `eglot'
;; provides a backend for many things, such as:
;; - `company-mode' - Autocomplete text.
;; - `flymake' - Syntax checking.
;; - Formatting with `eglot-format-buffer'.
;; - `xref' - Find definition and references.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(add-hook 'rust-mode-hook #'eglot-ensure)

(defun eglot-format-on-save ()
  (when (eglot-managed-p)
    (eglot-format-buffer)))
(add-hook 'before-save-hook #'eglot-format-on-save)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Autocomplete
;;
;; Company provides the frontend to display completion candidates inline. The
;; backend is usually autoselected, with `eglot' being the most common way to
;; provide good autocompletion.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(global-company-mode t)
