;;; init-ui.el --- Theme, modeline, fonts, and frame settings -*- lexical-binding: t; -*-
;;; Commentary:
;;; Visual configuration: theme, modeline, fonts, frame, and display settings.
;;; Code:

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
(when (display-graphic-p)
  (scroll-bar-mode -1))
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

(provide 'init-ui)
;;; init-ui.el ends here
