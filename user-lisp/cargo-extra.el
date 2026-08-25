;;; cargo-extra.el --- Cargo commands -*- lexical-binding: t; -*-
;;; Commentary:
;;; Code:

(require 'subr-x)

(defun cargo-workspace-root (&optional dir)
  "The root of the current workspace with working directory DIR.

`default-directory' is used if DIR is nil."
  (let ((default-directory (or dir default-directory)))
    (string-trim
     (shell-command-to-string
      "cargo metadata --format-version 1 | jq -r \".workspace_root\""))))

;;;###autoload
(defmacro cargo-cmd (command)
  "Run COMMAND with cargo at the project root."
  `(let ((default-directory (cargo-workspace-root)))
     (compile (concat "cargo " ,command))))

;;;###autoload
(defun cargo-check ()
  "Run cargo check at the project root."
  (interactive)
  (cargo-cmd "check"))

;;;###autoload
(defun cargo-build ()
  "Run cargo build at the project root."
  (interactive)
  (cargo-cmd "build"))

;;;###autoload
(defun cargo-criterion ()
  "Run cargo criterion at the project root."
  (interactive)
  (cargo-cmd "criterion"))

(setenv "NEXTEST_SHOW_PROGRESS" "none")
(setenv "CARGO_TERM_COLOR" "always")

;;;###autoload
(defun cargo-test ()
  "Run cargo nextest at the project root."
  (interactive)
  (cargo-cmd "nextest run"))

;;;###autoload
(defun cargo-doc ()
  "Run cargo doc at the project root."
  (interactive)
  (cargo-cmd "doc"))

;;;###autoload
(defun cargo-clippy ()
  "Run cargo clippy at the project root."
  (interactive)
  (cargo-cmd "clippy"))

;;;###autoload
(defun cargo-fix ()
  "Run cargo fix --allow-dirty at the project root."
  (interactive)
  (cargo-cmd "fix --allow-dirty"))

;;;###autoload
(define-minor-mode cargo-minor-mode
  "Provides access to cargo commands."
  :keymap (let ((keymap (make-sparse-keymap)))
            (define-key keymap (kbd "C-c C-l") #'cargo-clippy)
            (define-key keymap (kbd "C-c C-t") #'cargo-test)
            (define-key keymap (kbd "C-c C-e") #'cargo-build)
            (define-key keymap (kbd "C-c C-h") #'cargo-doc)
            keymap))

(provide 'cargo-extra)
;;; cargo-extra.el ends here
