;;; cargo-toml-mode.el --- Major mode for Cargo.toml files -*- lexical-binding: t; -*-

;; Author: wmedrano
;; Package-Requires: ((emacs "30.1"))
;; Keywords: languages toml cargo rust

;;; Commentary:
;; Major mode for editing Cargo.toml files, derived from `toml-ts-mode'.

;;; Code:

(require 'toml-ts-mode)
(require 'cargo-extra)

;;;###autoload
(define-derived-mode cargo-toml-mode toml-ts-mode "Cargo.toml"
  "Major mode for Cargo.toml files."
  :group 'toml)

;;;###autoload
(add-to-list 'auto-mode-alist '("/Cargo\\.toml\\'" . cargo-toml-mode))

(provide 'cargo-toml-mode)
;;; cargo-toml-mode.el ends here
