;;; init-completion.el --- Completion configuration -*- lexical-binding: t; -*-
;;; Commentary:
;;; Minibuffer and code completion settings.
;;; Code:

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Minibuffer Completion
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(setq-default completion-styles '(orderless basic)
              completion-category-overrides '((file (styles partial-completion)))
              completion-category-defaults nil)
(setq-default enable-recursive-minibuffers t)
(vertico-mode t)

(setq-default
 ;; For the rare occasion I feel like `vertico-posframe-mode'.
 vertico-posframe-poshandler #'posframe-poshandler-frame-top-center)

(marginalia-mode t)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Code Completion
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(setq-default completion-in-region-function #'consult-completion-in-region
              company-tooltip-minimum-width 64)
(global-company-mode t)
(define-key company-active-map (kbd "C-s") #'completion-at-point)

;; Embark
(setq-default
 embark-verbose-indicator-display-action
 '(display-buffer-in-side-window display-buffer-reuse-window))

(provide 'init-completion)
;;; init-completion.el ends here