;;; cargo-extra.el --- Cargo commands -*- lexical-binding: t; -*-
;;; Commentary:
;;; Code:

(require 'subr-x)
(require 'treesit)

(defun cargo-extra--test-at-point ()
  "Return the function name at point if it is preceded by a `#[test]` attribute."
  (when (and (treesit-parser-list) (treesit-node-at (point)))
    (let ((node (treesit-node-at (point))))
      (while (and node (not (member (treesit-node-type node)
                                    '("function_item" "function_definition"))))
        (setq node (treesit-node-parent node)))
      (when node
        (let ((attribute (treesit-node-prev-sibling node)))
          (when (and attribute
                     (member (treesit-node-type attribute)
                             '("attribute_item" "attribute"))
                     (string-match-p "#\\[test\\]"
                                     (treesit-node-text attribute t)))
            (let ((name (or (treesit-node-child-by-field-name node "name")
                            (treesit-node-child-by-field-name node "declarator"))))
              (when name
                (treesit-node-text name t)))))))))

(defun cargo-workspace-root (&optional dir)
  "The root of the current workspace with working directory DIR.

`default-directory' is used if DIR is nil."
  (let ((default-directory (or dir default-directory)))
    (string-trim
     (shell-command-to-string
      "cargo metadata --format-version 1 | jq -r \".workspace_root\""))))

(defun cargo-package (&optional dir)
  "The package name for working directory DIR, or nil if none.

`default-directory' is used if DIR is nil."
  (let* ((default-directory (or dir default-directory))
         (pkg (string-trim
               (shell-command-to-string
                "cargo metadata --no-deps --format-version 1 2>/dev/null | jq -r --arg manifest \"$(cargo locate-project --message-format plain 2>/dev/null)\" '.packages[] | select(.manifest_path == $manifest) | .name'"))))
    (unless (string-empty-p pkg)
      pkg)))

;;;###autoload
(defmacro cargo-cmd (command)
  "Run COMMAND with cargo at the project root."
  `(let ((cmd (concat "cargo " ,command))
         (default-directory (cargo-workspace-root)))
     (compile cmd)))

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
(defun cargo-test (&optional arg)
  "Run cargo nextest at the project root.

With ARG, run only tests for the current package."
  (interactive "P")
  (let ((pkg (if arg nil (cargo-package))))
    (cargo-cmd
     (if pkg
         (concat "nextest run -p " pkg)
       "nextest run"))))

;;;###autoload
(defun cargo-test-at-point ()
  "Run the test at point, or all tests if point is not on a test."
  (interactive)
  (let ((test-name (cargo-extra--test-at-point))
        (pkg (cargo-package)))
    (cargo-cmd
     (cond
      ((and test-name pkg)
       (concat "nextest run -p " pkg " " test-name))
      (test-name
       (concat "nextest run " test-name))
      (pkg (concat "nextest run -p " pkg))
      (t "nextest run")))))

;;;###autoload
(defun cargo-doc (&optional arg)
  "Run cargo doc at the project root.

With ARG, pass the \"--open\" flag."
  (interactive "P")
  (cargo-cmd
   (if arg "doc --open" "doc")))


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

(defvar cargo-minor-mode-inhibit-function nil
  "Function of no arguments called in the buffer being set up.
When it returns non-nil, `cargo-minor-mode-maybe-enable' leaves
`cargo-minor-mode' off.  Useful for build environments that do not
use Cargo, where the mode's key bindings only get in the way.")

;;;###autoload
(defun cargo-minor-mode-maybe-enable ()
  "Enable `cargo-minor-mode' unless `cargo-minor-mode-inhibit-function' vetoes it."
  (unless (and (functionp cargo-minor-mode-inhibit-function)
               (funcall cargo-minor-mode-inhibit-function))
    (cargo-minor-mode 1)))

(provide 'cargo-extra)
;;; cargo-extra.el ends here
