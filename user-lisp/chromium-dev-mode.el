;;; chromium-dev-mode.el --- Stuff for working with Chromium -*- lexical-binding: t; -*-

;;; Commentary:
;; Stuff for working with Chromium.
;;
;; Enable via `.dir-locals.el' in your Chromium checkout, e.g.
;; in `src/.dir-locals.el':
;;   ((nil . ((eval . (chromium-dev-mode 1)))))

;;; Code:

(require 'compile)
(require 'project)
(require 'subr-x)

(defcustom chromium-dev-out-dir "out/Default"
  "Directory for Chromium build output, relative to project root."
  :type 'string
  :group 'chromium-dev)

(defcustom chromium-dev-blink-target "blink_unittests"
  "GN target / binary name for Blink unit tests."
  :type 'string
  :group 'chromium-dev)

(defcustom chromium-dev-depot-tools-path (expand-file-name "~/src/chromium/depot_tools")
  "Path to depot_tools checkout containing `autoninja'."
  :type 'directory
  :group 'chromium-dev)

(defun chromium-dev--ensure-depot-tools-on-path ()
  "Ensure `chromium-dev-depot-tools-path' is on `exec-path' and PATH.
Needed because `compile' runs via shell which uses PATH, not just
`exec-path'.  Safe to call repeatedly."
  (when (file-directory-p chromium-dev-depot-tools-path)
    (add-to-list 'exec-path chromium-dev-depot-tools-path)
    (let ((path (or (getenv "PATH") "")))
      (unless (string-match-p (regexp-quote chromium-dev-depot-tools-path) path)
        (setenv "PATH" (concat chromium-dev-depot-tools-path path-delimiter path))))))

(defun chromium-dev--autoninja-executable ()
  "Return absolute path to autoninja or signal a useful error."
  (chromium-dev--ensure-depot-tools-on-path)
  (or (executable-find "autoninja")
      (let ((direct (expand-file-name "autoninja" chromium-dev-depot-tools-path)))
        (when (file-executable-p direct) direct))
      (user-error "Cannot find `autoninja' on PATH. Add depot_tools (%s) to PATH or set `chromium-dev-depot-tools-path'"
                  chromium-dev-depot-tools-path)))

(defun chromium-dev--project-root ()
  "Return the current project root or signal a `user-error'."
  (let ((project (project-current)))
    (unless project
      (user-error "Not in a project"))
    (project-root project)))

(defun chromium-dev-build (&optional verbose)
  "Build Chromium with autoninja.
Pass --quiet to reduce output in `M-x compile'.  With prefix
argument VERBOSE, omit --quiet for this invocation."
  (interactive "P")
  (let* ((default-directory (chromium-dev--project-root))
         (autoninja (shell-quote-argument (chromium-dev--autoninja-executable)))
         (cmd (format "%s %s-C %s %s"
                      autoninja
                      (if verbose "" "--quiet ")
                      (shell-quote-argument chromium-dev-out-dir)
                      "chrome")))
    (compile cmd)))

(defun chromium-dev-build-blink-unittests (&optional verbose)
  "Build the Blink unit tests target with autoninja.
With prefix argument VERBOSE, omit --quiet for this invocation."
  (interactive "P")
  (let* ((default-directory (chromium-dev--project-root))
         (autoninja (shell-quote-argument (chromium-dev--autoninja-executable)))
         (cmd (format "%s %s-C %s %s"
                      autoninja
                      (if verbose "" "--quiet ")
                      (shell-quote-argument chromium-dev-out-dir)
                      (shell-quote-argument chromium-dev-blink-target))))
    (compile cmd)))

(defun chromium-dev-run-blink-unittests (&optional filter)
  "Run the Blink unit tests binary.
With FILTER, pass --gtest_filter=FILTER to the test binary.
When called interactively, prompt for FILTER (empty means run all)."
  (interactive (list (read-string "GTest filter (empty for all): ")))
  (let* ((default-directory (chromium-dev--project-root))
         (binary (format "%s/%s" chromium-dev-out-dir chromium-dev-blink-target))
         (filter-arg (if (and filter (not (string-empty-p filter)))
                         (format " --gtest_filter=%s" (shell-quote-argument filter))
                       ""))
         (cmd (format "%s%s" binary filter-arg)))
    (compile cmd)))

(defun chromium-dev-blink-unittests (&optional filter verbose)
  "Build and run the Blink unit tests.
Builds `chromium-dev-blink-target' with autoninja, then runs the
resulting binary.  With FILTER, pass --gtest_filter=FILTER.
With prefix argument VERBOSE, omit --quiet for the build step.

When called interactively, prompt for FILTER and use the prefix
argument for VERBOSE."
  (interactive (list (read-string "GTest filter (empty for all): ")
                     current-prefix-arg))
  (let* ((default-directory (chromium-dev--project-root))
         (autoninja (shell-quote-argument (chromium-dev--autoninja-executable)))
         (build-cmd (format "%s %s-C %s %s"
                            autoninja
                            (if verbose "" "--quiet ")
                            (shell-quote-argument chromium-dev-out-dir)
                            (shell-quote-argument chromium-dev-blink-target)))
         (binary (format "%s/%s" chromium-dev-out-dir chromium-dev-blink-target))
         (filter-arg (if (and filter (not (string-empty-p filter)))
                         (format " --gtest_filter=%s" (shell-quote-argument filter))
                       ""))
         (run-cmd (format "%s%s" binary filter-arg))
         (cmd (format "%s && %s" build-cmd run-cmd)))
    (compile cmd)))

(define-minor-mode chromium-dev-mode
  "Stuff for working with Chromium."
  :keymap (let ((keymap (make-sparse-keymap)))
            (define-key keymap (kbd "C-c C-e") #'chromium-dev-build)
            (define-key keymap (kbd "C-c C-t") #'chromium-dev-blink-unittests)
            keymap))

(provide 'chromium-dev-mode)
;;; chromium-dev-mode.el ends here
