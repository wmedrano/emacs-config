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

(defvar eglot-server-programs)
(defvar eglot-workspace-configuration)

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

(defvaralias 'chromium-dev--compile-commands-generating
  'chromium-dev--one-time-setup-done)

(defvar chromium-dev--one-time-setup-done nil
  "Non-nil if one-time setup has run this session.")

(defun chromium-dev--ensure-depot-tools-on-path ()
  "Ensure `chromium-dev-depot-tools-path' is on `exec-path' and PATH.
Needed because `compile' runs via shell which uses PATH, not just
`exec-path'.  Safe to call repeatedly."
  (when (file-directory-p chromium-dev-depot-tools-path)
    (add-to-list 'exec-path chromium-dev-depot-tools-path)
    (let ((path (or (getenv "PATH") "")))
      (unless (string-match-p (regexp-quote chromium-dev-depot-tools-path) path)
        (setenv "PATH" (concat chromium-dev-depot-tools-path
                               path-separator path))))))

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

(defun chromium-dev--clangd-config-path ()
  "Return path to clangd's config.yaml."
  (expand-file-name "clangd/config.yaml"
                    (or (let ((xdg (getenv "XDG_CONFIG_HOME")))
                          (and xdg (not (string-empty-p xdg)) xdg))
                        (expand-file-name "~/.config"))))

(defun chromium-dev--remote-index-configured-p (root config-file)
  "Return non-nil if CONFIG-FILE already contains remote-index entry for ROOT."
  (when (file-exists-p config-file)
    (let ((root-dir (file-name-as-directory (expand-file-name root))))
      (with-temp-buffer
        (insert-file-contents config-file)
        (search-forward root-dir nil t)))))

(defun chromium-dev--write-remote-index-config (root config-file)
  "Write clangd remote-index config for ROOT to CONFIG-FILE.
Appends snippet with PathMatch/Server/MountPoint, creating parent dirs.
Caller should ensure not already configured."
  (let* ((server "linux.clangd-index.chromium.org:5900")
         (root-dir (file-name-as-directory (expand-file-name root)))
         (snippet (format "If:\n  PathMatch: %s.*\nIndex:\n  External:\n    Server: %s\n    MountPoint: %s\n"
                          root-dir server root-dir)))
    (make-directory (file-name-directory config-file) t)
    (with-temp-buffer
      (when (file-exists-p config-file)
        (insert-file-contents config-file)
        (goto-char (point-max))
        (unless (bolp) (insert "\n")))
      (insert snippet)
      (write-region (point-min) (point-max) config-file nil 'silent))
    (message "Configured clangd remote-index for %s -> %s" root config-file)))

(defun chromium-dev--vendored-rust-analyzer-path (root)
  "Return vendored rust-analyzer path for ROOT."
  (expand-file-name "third_party/rust-toolchain/bin/rust-analyzer" root))

(defun chromium-dev--rust-analyzer-resolve (&optional _interactive _project)
  "Return vendored rust-analyzer contact if in Chromium checkout.
Used as dynamic CONTACT in `eglot-server-programs'.
Returns a list like (\"/path/to/rust-analyzer\") suitable for eglot."
  (let* ((root (ignore-errors (chromium-dev--project-root)))
         (cr (or root (locate-dominating-file default-directory "rust-project.json")))
         (prog (if cr
                   (let ((vendored (chromium-dev--vendored-rust-analyzer-path cr)))
                     (if (file-executable-p vendored) vendored "rust-analyzer"))
                 "rust-analyzer")))
    (list prog)))

(defun chromium-dev--rust-project-json-path (root)
  "Return path to `rust-project.json' symlink at ROOT."
  (expand-file-name "rust-project.json" root))

(defun chromium-dev--rust-project-build-path (root)
  "Return path to `rust-project.json' in build dir for ROOT."
  (expand-file-name "rust-project.json" (expand-file-name chromium-dev-out-dir root)))

(defun chromium-dev--generate-rust-project-json (root)
  "Generate `rust-project.json' in ROOT via `gn gen'.
Asynchronously runs `gn gen --export-rust-project'."
  (let* ((default-directory root)
         (cmd (format "%s gen %s --export-rust-project"
                      (shell-quote-argument "gn")
                      (shell-quote-argument chromium-dev-out-dir))))
    (message "Generating rust-project.json...")
    (start-process-shell-command "chromium-rust-project" "*chromium-rust-project*" cmd)))

(defun chromium-dev--ensure-rust-project-symlink (root)
  "Ensure `rust-project.json' symlink at ROOT points to build dir.
Creates relative symlink `out/Default/rust-project.json' if missing."
  (let* ((dst (chromium-dev--rust-project-json-path root))
         (target (concat (file-name-as-directory chromium-dev-out-dir) "rust-project.json")))
    (unless (or (file-symlink-p dst) (file-exists-p dst))
      (make-symbolic-link target dst t)
      (message "Linked %s -> %s" dst target))))

(defun chromium-dev-regen-rust-project-json ()
  "Regenerate `rust-project.json' via `gn gen'.
Ensures symlink at repo root; works even if setup already ran."
  (interactive)
  (let ((root (chromium-dev--project-root)))
    (setq chromium-dev--one-time-setup-done t)
    (chromium-dev--generate-rust-project-json root)
    (chromium-dev--ensure-rust-project-symlink root)))

(defun chromium-dev--maybe-ensure-rust-project ()
  "Ensure `rust-project.json' exists, generation is async.
Idempotent check for one-time setup path."
  (unless chromium-dev--one-time-setup-done
    (when-let* ((root (ignore-errors (chromium-dev--project-root)))
                (dst (chromium-dev--rust-project-json-path root))
                (build (chromium-dev--rust-project-build-path root))
                ((not (file-exists-p dst))))
      (if (file-exists-p build)
          (chromium-dev--ensure-rust-project-symlink root)
        (chromium-dev-regen-rust-project-json)))))

(defun chromium-dev--setup-eglot-rust-analyzer ()
  "Configure eglot to use vendored rust-analyzer for Chromium.
Adds dynamic resolver to `eglot-server-programs' and sets
`eglot-workspace-configuration' for rust-analyzer.
Safe to call repeatedly; only adds once."
  (with-eval-after-load 'eglot
    (let ((resolver #'chromium-dev--rust-analyzer-resolve))
      (dolist (mode '(rust-mode rust-ts-mode))
        (let ((entry (assq mode eglot-server-programs)))
          (if entry
              (unless (eq (cdr entry) resolver)
                (setf (cdr entry) resolver))
            (add-to-list 'eglot-server-programs (cons mode resolver))))))
    ;; Workspace config: linkedProjects, procMacro, extraEnv PATH.
    ;; Merge with existing default without clobbering unrelated keys.
    (let ((desired '(:rust-analyzer (:linkedProjects ["rust-project.json"]
                                      :procMacro (:enable t)
                                      :cargo (:extraEnv (:PATH "third_party/rust-toolchain/bin:/usr/bin:/bin"))))))
      (unless (equal eglot-workspace-configuration desired)
        ;; Only set if not already set to desired; preserve if user customized differently
        (when (or (null eglot-workspace-configuration)
                  (equal eglot-workspace-configuration desired)
                  ;; If nil or default, set it; otherwise don't clobber user value
                  (not (boundp 'eglot-workspace-configuration)))
          (setq-default eglot-workspace-configuration desired))))))

;; Eagerly register vendored resolver so `M-x eglot` works even before `chromium-dev-mode`.
(chromium-dev--setup-eglot-rust-analyzer)

(defun chromium-dev-setup-remote-index ()
  "Setup clangd remote-index config for current checkout.
Creates config.yaml entry for project root.
Idempotent if already configured."
  (interactive)
  (let* ((root (chromium-dev--project-root))
         (config-file (chromium-dev--clangd-config-path)))
    (setq chromium-dev--one-time-setup-done t)
    (if (chromium-dev--remote-index-configured-p root config-file)
        (message "clangd remote-index already configured for %s" root)
      (chromium-dev--write-remote-index-config root config-file))))

(defun chromium-dev--generate-compile-commands (root)
  "Asynchronously generate `compile_commands.json' in ROOT."
  (let* ((default-directory root)
         (cmd (format "%s -p %s > %s"
                      (shell-quote-argument "tools/clang/scripts/generate_compdb.py")
                      (shell-quote-argument chromium-dev-out-dir)
                      (shell-quote-argument "compile_commands.json"))))
    (message "Generating compile_commands.json...")
    (start-process-shell-command "chromium-compdb" "*chromium-compdb*" cmd)))

(defun chromium-dev-regen-compile-json ()
  "Regenerate `compile_commands.json' asynchronously.
Runs \"tools/clang/scripts/generate_compdb.py -p out/Default >
compile_commands.json\" in the project root, where `out/Default'
is `chromium-dev-out-dir'.  Can be invoked manually even if
generation was already attempted."
  (interactive)
  (let ((root (chromium-dev--project-root)))
    (setq chromium-dev--one-time-setup-done t)
    (chromium-dev--generate-compile-commands root)))

(defun chromium-dev--maybe-generate-compile-commands ()
  "Generate `compile_commands.json' if missing, asynchronously."
  (unless chromium-dev--one-time-setup-done
    (when-let* ((root (ignore-errors (chromium-dev--project-root)))
                (compdb (expand-file-name "compile_commands.json" root))
                ((not (file-exists-p compdb))))
      (chromium-dev-regen-compile-json))))

(defun chromium-dev--ensure-remote-index ()
  "Ensure clangd remote-index config exists for current checkout, once."
  (unless chromium-dev--one-time-setup-done
    (when-let* ((root (ignore-errors (chromium-dev--project-root)))
                (config-file (chromium-dev--clangd-config-path))
                ((not (chromium-dev--remote-index-configured-p root config-file))))
      (chromium-dev-setup-remote-index))))

(defun chromium-dev--one-time-setup ()
  "Run one-time setup checks once per session.
Guards compile_commands, clangd remote-index, rust-project.json and eglot setup."
  (unless chromium-dev--one-time-setup-done
    (when-let* ((root (ignore-errors (chromium-dev--project-root))))
      (setq chromium-dev--one-time-setup-done t)
      ;; Ensure eglot uses vendored rust-analyzer (idempotent, global).
      (chromium-dev--setup-eglot-rust-analyzer)
      (let ((compdb (expand-file-name "compile_commands.json" root))
            (config-file (chromium-dev--clangd-config-path))
            (rust-dst (chromium-dev--rust-project-json-path root))
            (rust-build (chromium-dev--rust-project-build-path root)))
        (unless (file-exists-p compdb)
          (chromium-dev--generate-compile-commands root))
        (unless (chromium-dev--remote-index-configured-p root config-file)
          (chromium-dev--write-remote-index-config root config-file))
        ;; Rust: ensure rust-project.json symlink / generation.
        (unless (file-exists-p rust-dst)
          (if (file-exists-p rust-build)
              (chromium-dev--ensure-rust-project-symlink root)
            (progn
              (chromium-dev--generate-rust-project-json root)
              (chromium-dev--ensure-rust-project-symlink root))))))))

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
            keymap)
  (when chromium-dev-mode
    (chromium-dev--one-time-setup)))

(provide 'chromium-dev-mode)
;;; chromium-dev-mode.el ends here
