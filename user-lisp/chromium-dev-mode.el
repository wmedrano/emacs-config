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

(defcustom chromium-dev-targets
  '("chrome"
    "blink_unittests"
    "blink_common_unittests"
    "blink_platform_unittests"
    "blink_heap_unittests")
  "List of GN targets offered by `chromium-dev--read-target'."
  :type '(repeat string)
  :group 'chromium-dev)

(defun chromium-dev--project-root ()
  "Return the current project root or signal a `user-error'."
  (let ((project (project-current)))
    (unless project
      (user-error "Not in a project"))
    (project-root project)))

(defun chromium-dev--read-target ()
  "Read a chromium target."
  (completing-read "Target: " chromium-dev-targets))

(defvar chromium-dev--run-args-history nil
  "Alist mapping TARGET string to list of past ARGS strings.
Most recent first, per target.  Used for history in `chromium-dev-run'.")

(defvar chromium-dev--run-args-temp-history nil
  "Temporary history variable for `completing-read' in `chromium-dev--read-args'.")

(defun chromium-dev--run-args-history-get (target)
  "Return history list for TARGET."
  (alist-get target chromium-dev--run-args-history nil nil #'equal))

(defun chromium-dev--run-args-history-push (target args)
  "Push ARGS onto history for TARGET if non-empty.
Keeps most recent first, de-duplicated, capped at 20 entries."
  (when (and args (not (string-empty-p args)))
    (let* ((old (alist-get target chromium-dev--run-args-history nil nil #'equal))
           (new (cons args (delete args (copy-sequence old)))))
      (when (> (length new) 20)
        (setcdr (nthcdr 19 new) nil))
      (setf (alist-get target chromium-dev--run-args-history nil nil #'equal) new))))

(defun chromium-dev--read-args (target)
  "Read args for TARGET with per-target history and completion."
  (let* ((hist (chromium-dev--run-args-history-get target)))
    (setq chromium-dev--run-args-temp-history hist)
    (completing-read (format "Args for %s (empty for none): " target)
                     hist nil nil nil 'chromium-dev--run-args-temp-history nil)))

(defun chromium-dev-build (target)
  "Build TARGET with autoninja."
  (interactive (list (chromium-dev--read-target)))
  (let* ((default-directory (chromium-dev--project-root))
         (cmd (format "autoninja -C %s %s"
                      (shell-quote-argument chromium-dev-out-dir)
                      (shell-quote-argument target))))
    (compile cmd)))

(defun chromium-dev-run (target &optional args)
  "Build and run the unit tests.

Builds TARGET with autoninja, then runs the resulting binary.  With ARGS, append
ARGS to the run command.

ARGS history is kept per TARGET in `chromium-dev--run-args-history' and offered
for completion on subsequent invocations."
  (interactive (let ((target (chromium-dev--read-target)))
                 (list target (chromium-dev--read-args target))))
  (chromium-dev--run-args-history-push target args)
  (let* ((default-directory (chromium-dev--project-root))
          (binary            (format "%s/%s"
                                     chromium-dev-out-dir
                                     target))
          (args-str          (if (and args (not (string-empty-p args)))
                                 (format " %s" args)
                               ""))
          (build-cmd         (format "autoninja -C %s %s"
                                     (shell-quote-argument chromium-dev-out-dir)
                                     (shell-quote-argument target)))
          (run-cmd           (format "%s%s" binary args-str))
          (cmd (string-join (list build-cmd run-cmd)
                            " &&")))
    (compile cmd)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Remote index
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

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

(defun chromium-dev--clangd-config-path ()
  "Return path to clangd's config.yaml."
  (expand-file-name "clangd/config.yaml"
                    (or (let ((xdg (getenv "XDG_CONFIG_HOME")))
                          (and xdg (not (string-empty-p xdg)) xdg))
                        (expand-file-name "~/.config"))))

(defun chromium-dev-setup-remote-index ()
  "Setup clangd remote-index config for current checkout.
Creates config.yaml entry for project root.
Idempotent if already configured."
  (interactive)
  (let* ((root (chromium-dev--project-root))
         (config-file (chromium-dev--clangd-config-path)))
    (if (chromium-dev--remote-index-configured-p root config-file)
        (message "clangd remote-index already configured for %s" root)
      (chromium-dev--write-remote-index-config root config-file))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; compile_commands.json
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun chromium-dev-regen-compile-json (root)
  "Regenerate `compile_commands.json' asynchronously.

Assumes that chromium is at ROOT.  ROOT is inferred when called interactively."
  (interactive (list (chromium-dev--project-root)))
  (let* ((default-directory root)
         (cmd (format "%s -p %s > %s"
                      (shell-quote-argument "tools/clang/scripts/generate_compdb.py")
                      (shell-quote-argument chromium-dev-out-dir)
                      (shell-quote-argument "compile_commands.json"))))
    (message "Generating compile_commands.json...")
    (start-process-shell-command "chromium-compdb" "*chromium-compdb*" cmd)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Rust Analyzer (Needs Cleanup)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun chromium-dev--rust-project-json-path (root)
  "Return path to `rust-project.json' symlink at ROOT."
  (expand-file-name "rust-project.json" root))

(defun chromium-dev--ensure-rust-project-symlink (root)
  "Ensure `rust-project.json' symlink at ROOT points to build dir.
Creates relative symlink `out/Default/rust-project.json' if missing."
  (let* ((dst (chromium-dev--rust-project-json-path root))
         (target (concat (file-name-as-directory chromium-dev-out-dir) "rust-project.json")))
    (unless (or (file-symlink-p dst) (file-exists-p dst))
      (make-symbolic-link target dst t)
      (message "Linked %s -> %s" dst target))))

(defun chromium-dev--generate-rust-project-json (root)
  "Generate `rust-project.json' in ROOT via `gn gen'.
Asynchronously runs `gn gen --export-rust-project'."
  (let* ((default-directory root)
         (cmd (format "%s gen %s --export-rust-project"
                      (shell-quote-argument "gn")
                      (shell-quote-argument chromium-dev-out-dir))))
    (message "Generating rust-project.json...")
    (start-process-shell-command "chromium-rust-project" "*chromium-rust-project*" cmd)))

(defun chromium-dev-regen-rust-project-json ()
  "Regenerate `rust-project.json' via `gn gen'.
Ensures symlink at repo root; works even if setup already ran."
  (interactive)
  (let ((root (chromium-dev--project-root)))
    (chromium-dev--generate-rust-project-json root)
    (chromium-dev--ensure-rust-project-symlink root)))

(defun chromium-dev--rust-analyzer-resolve (&optional _interactive _project)
  "Return vendored rust-analyzer contact if in Chromium checkout.
Used as dynamic CONTACT in `eglot-server-programs'.
Returns a list like (\"/path/to/rust-analyzer\") suitable for eglot."
  (let* ((root (ignore-errors (chromium-dev--project-root)))
         (cr (or root (locate-dominating-file default-directory "rust-project.json")))
         (prog (if cr
                   (let ((vendored (expand-file-name
                                    "third_party/rust-toolchain/bin/rust-analyzer"
                                    cr)))
                     (if (file-executable-p vendored) vendored "rust-analyzer"))
                 "rust-analyzer")))
    (list prog)))

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

(defun chromium-dev--rust-project-build-path (root)
  "Return path to `rust-project.json' in build dir for ROOT."
  (expand-file-name "rust-project.json" (expand-file-name chromium-dev-out-dir root)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; chromium-dev-mode
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun chromium-dev--one-time-setup ()
  "Run one-time setup checks once per session.
Guards compile_commands, clangd remote-index, rust-project.json and eglot setup."
  (when-let* ((root (ignore-errors (chromium-dev--project-root))))
    ;; Ensure eglot uses vendored rust-analyzer (idempotent, global).
    (chromium-dev--setup-eglot-rust-analyzer)
    (let ((compdb (expand-file-name "compile_commands.json" root))
          (clangd-config-path (chromium-dev--clangd-config-path))
          (rust-dst (chromium-dev--rust-project-json-path root))
          (rust-build (chromium-dev--rust-project-build-path root)))
      (unless (file-exists-p compdb)
        (chromium-dev-regen-compile-json root))
      (unless (chromium-dev--remote-index-configured-p root clangd-config-path)
        (chromium-dev--write-remote-index-config root clangd-config-path))
      ;; Rust: ensure rust-project.json symlink / generation.
      (unless (file-exists-p rust-dst)
        (if (file-exists-p rust-build)
            (chromium-dev--ensure-rust-project-symlink root)
          (progn
            (chromium-dev--generate-rust-project-json root)
            (chromium-dev--ensure-rust-project-symlink root)))))))

(defvar chromium-dev--one-time-setup-done nil
  "Non-nil if one-time setup has run this session.")

(define-minor-mode chromium-dev-mode
  "Stuff for working with Chromium."
  :keymap (let ((keymap (make-sparse-keymap)))
            (define-key keymap (kbd "C-c C-e") #'chromium-dev-build)
            (define-key keymap (kbd "C-c C-t") #'chromium-dev-run)
            keymap)
  (when (and chromium-dev-mode
             (ignore-errors (chromium-dev--project-root))
             (not chromium-dev--one-time-setup-done))
    (setq chromium-dev--one-time-setup-done t)
    (chromium-dev--one-time-setup)))

(provide 'chromium-dev-mode)
;;; chromium-dev-mode.el ends here
