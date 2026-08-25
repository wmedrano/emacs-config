;; -*- lexical-binding: t -*-

(require 'ert)
(require 'jj)
(require 'jj-diff)
(require 'jj-describe)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Helpers
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun test-sh (&rest commands)
  "Run all shell commands in COMMANDS.

Each element of COMMANDS must either be:
- A string
- A list of strings, that are concatenated to form a single command.

Each command is run synchronously. Fails if any of the commands fails."
  (with-temp-buffer
    (dolist (cmd commands)
      (let ((cmd-str (if (stringp cmd) cmd (string-join cmd " "))))
        (erase-buffer)
        (should (zerop (call-process shell-file-name nil t nil
                                     shell-command-switch cmd-str)))))
    (buffer-string)))

(defmacro with-test-repo (&rest body)
  "Run BODY in a new jj repository.

During execution, the following variables are bound:

`test-repo-directory' - The root directory of the test repo.
`test-repo-buffer' - A temporary buffer where `default-directory' is at the root
                     of the repo.

The jj repository is deleted upon successful completion. However, it is retained
(for debugging purposes) if there is a failure."
  (declare (indent 0) (debug body))
  (let ((succeeded (gensym "test-repo-succeeded")))
    `(let* ((test-repo-directory (make-temp-file "jj-test" t))
            (default-directory   test-repo-directory)
            ;; Suppress noisy test output
            (jj--display-function #'ignore)
            (,succeeded nil))
       (unwind-protect
           (with-temp-buffer
             (test-sh "jj git init")
             (let ((test-repo-buffer (current-buffer)))
               (ignore test-repo-buffer) ;; For byte compile warning
               ,@body)
             (setq ,succeeded t))
         (if ,succeeded
             (delete-directory test-repo-directory t)
           (message "Test failed; temp repo kept at: %s"
                    test-repo-directory))))))

(defmacro as-temp-buffer (buffer &rest body)
  "Run BODY with current buffer as BUFFER and kill BUFFER when done.

Upon completion, the previous current buffer is restored."
  (declare (indent 1))
  (let ((buf (gensym "buf"))
        (prev (gensym "prev")))
    `(let* ((,prev (current-buffer))
            (,buf ,buffer))
       (unwind-protect
           (with-current-buffer ,buf
             ,@body)
         (when-let* ((proc (get-buffer-process ,buf)))
           (kill-process proc))
         (when (buffer-live-p ,buf)
           (kill-buffer ,buf))
         (when (buffer-live-p ,prev)
           (set-buffer ,prev))))))

(defun test-write-file (filename contents)
  "Sets the contents of FILENAME to CONTENTS.

Overwrites the contents if they exist."
  (when-let* ((dir (file-name-directory filename)))
    (make-directory dir t))
  (write-region contents nil filename nil 'silent))

(defun test-jj-change-id (revision)
  "Return the change ID for REVISION."
  (with-temp-buffer
    (should (zerop (call-process "jj" nil t nil "log" "-r" revision
                                 "--no-graph" "-T" "change_id")))
    (string-trim (buffer-string))))

(defun test-jj-description (revision)
  "Return the description of REVISION."
  (with-temp-buffer
    (let* ((result (call-process "jj" nil t nil "log" "-r" revision
                                 "--no-graph" "-T" "description"))
           (output (buffer-string)))
      (unless (zerop result)
        (error "jj log failed %d:\n%s" result output))
      (string-trim output))))

(defun test-jj-parent-change-id (revision)
  "Return the first parent change ID for REVISION."
  (with-temp-buffer
    (let* ((result (call-process "jj" nil t nil "log" "-r" revision
                                 "--no-graph" "-T"
                                 "parents.map(|p| p.change_id()).join(\" \")"))
           (output (buffer-string)))
       (unless (zerop result)
        (error "jj log failed %d:\n%s" result output))
      (car (string-split (string-trim output))))))


(defun test-wait-for-process (&optional buffer)
  "Wait for the `jj' process running in BUFFER to finish and run sentinels."
  (let* ((buffer         (or buffer (current-buffer)))
         (proc           (get-buffer-process buffer))
         (sleep-duration 0.1)
         (timeout        10)
         (remaining      (ceiling (/ timeout sleep-duration))))
    (while (and proc (process-live-p proc) (> remaining 0))
      (accept-process-output proc sleep-duration)
      (setq remaining (1- remaining)))
    (when (and proc (process-live-p proc))
      (error "Process %S did not finish within %s seconds"
             proc timeout))
    ;; The process has exited.  Flush any still-pending process events so the
    ;; sentinel has run before the caller asserts on the buffer.
    (when proc
      (accept-process-output proc sleep-duration))))



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; root
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(ert-deftest root-returns-root-directory ()
  (with-test-repo
    (should (string= test-repo-directory
                     (jj-root)))))

(ert-deftest root-in-subdirectory-returns-root-directory ()
  (with-test-repo
    (test-write-file "foo/bar/baz.txt" "")
    (as-temp-buffer (find-file "foo/bar/baz.txt")
      (should (string= test-repo-directory
                       (jj-root))))))

(ert-deftest root-outside-of-repo-is-error ()
  (let ((temp-dir (make-temp-file "jj-outside-repo" t)))
    (unwind-protect
        (let ((default-directory temp-dir))
          (with-temp-buffer
            (should-error (jj-root) :type 'jj-error)))
      (delete-directory temp-dir t))))

;; 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; read revision
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(ert-deftest read-revision-returns-all-revisions ()
  (with-test-repo
    (test-sh
     "jj new")
    (let* ((got-collection nil)
           (completing-read-function (lambda (_ collection &rest _)
                                       (setq got-collection collection)
                                       "")))
      (jj-read-revision "" "")
      (cl-destructuring-bind (first second third) got-collection
        ;; Newest working copy
        (should (stringp (car first)))
        (should (overlayp (cdr first)))
        ;; Old working copy
        (should (stringp (car second)))
        (should (overlayp (cdr second)))
        ;; Root
        (should (stringp (car third)))
        (should (overlayp (cdr third)))))))

(ert-deftest read-revision-shows-preview-in-side-window ()
  (with-test-repo
    (test-sh "jj new")
    (let* ((got-buffer nil)
           (got-window nil)
           (completing-read-function
            (lambda (_ _ &rest _)
              (let ((buffer (get-buffer "*jj-log*"))
                    (window (get-buffer-window "*jj-log*")))
                (with-current-buffer buffer
                  (should (buffer-live-p buffer))
                  (should (derived-mode-p 'jj--log-mode))
                  (should (window-live-p window))
                  (should (window-at-side-p window 'bottom))
                  (setq got-buffer buffer
                        got-window window))
                ""))))
      (jj-read-revision "" "")
      (should-not (buffer-live-p got-buffer))
      (should-not (window-live-p got-window)))))

(ert-deftest read-revision-preview-shows-revisions ()
  (with-test-repo
    (test-sh "jj bookmark set bookmark1"
             "jj new"
             "jj describe -m 'Make feature'"
             "jj new bookmark1")
    (let* ((rev-line
            (concat "[a-z]\\{8\\} [^ ]+@[^ ]+ "
                    "[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\} "
                    "[0-9]\\{2\\}:[0-9]\\{2\\}:[0-9]\\{2\\} "
                    "\\(bookmark1 \\)?[0-9a-f]\\{8\\}"))
           (completing-read-function
            (lambda (_ _ &rest _)
              (with-current-buffer "*jj-log*"
                (should (string-match-p
                         (concat
                          "^@  " rev-line "\n"
                          "│  (empty) (no description set)\n"
                          "│ ○  " rev-line "\n"
                          "├─╯  (empty) Make feature\n"
                          "○  " rev-line "\n"
                          "│  (empty) (no description set)\n"
                          "◆  zzzzzzzz root() 00000000")
                         (buffer-string))))
              "")))
      (jj-read-revision "" ""))))

(ert-deftest read-revision-contains-change-id-description-tags ()
  (with-test-repo
    (test-sh
     "printf 'First Line\nSecondLine\n' | jj describe --stdin"
     "jj bookmark set bookmark1"
     "jj bookmark set bookmark2")
    (let* ((got-collection nil)
           (completing-read-function (lambda (_ collection &rest _)
                                       (setq got-collection collection)
                                       "")))
      (jj-read-revision "" "")
      (let ((entry (substring-no-properties (caar got-collection))))
        (should (string-match-p "\\`[a-z]\\{8\\}\\s-+First Line\\s-+bookmark1 bookmark2\\'" entry))))))


(ert-deftest read-revision-uses-prompt-prefix-and-default ()
  (with-test-repo
    (let* ((got-prompt nil)
           (completing-read-function (lambda (prompt _ &rest _)
                                       (setq got-prompt prompt)
                                       "")))
      (jj-read-revision "my-prefix" "default-rev")
      (should (equal "my-prefix revision (default default-rev): " got-prompt)))))

(ert-deftest read-revision-with-no-default-omits-default-from-prompt ()
  (with-test-repo
    (let* ((got-prompt nil)
           (completing-read-function (lambda (prompt _ &rest _)
                                       (setq got-prompt prompt)
                                       "")))
      (should (equal nil (jj-read-revision "my-prefix" nil)))
      (should (equal "my-prefix revision: " got-prompt)))))

(ert-deftest read-revision-with-arbitrary-default-returns-that-default ()
  (with-test-repo
    (let* ((got-prompt nil)
           (completing-read-function (lambda (prompt _ &rest _)
                                       (setq got-prompt prompt)
                                       "")))
      (should (equal '(1 2 3)
                     (jj-read-revision "my-prefix" '(1 2 3))))
      (should (string-equal "my-prefix revision (default (1 2 3)): "
                            got-prompt)))))

(ert-deftest read-revision-empty-string-selected-returns-default ()
  (with-test-repo
    (test-sh
     "printf 'First Line\nSecondLine\n' | jj describe --stdin"
     "jj bookmark set bookmark1"
     "jj bookmark set bookmark2")
    (let* ((completing-read-function (lambda (_ _ &rest _)
                                       "Completing read that returns empty string."
                                       "")))
      (should (equal "the-default"
                     (jj-read-revision "" "the-default"))))))

(ert-deftest read-revision-non-matching-returns-raw-string ()
  (with-test-repo
    (let* ((completing-read-function (lambda (_ _ &rest _)
                                       "Completing read that returns empty string."
                                       "totally-custom-string")))
      (should (equal "totally-custom-string"
                     (jj-read-revision "" "the-default"))))))

(ert-deftest read-revision-candidate-returns-change-id ()
  (with-test-repo
    (let* ((selected-overlay nil)
           (completing-read-function (lambda (_ collection &rest _)
                                       "Completing read that returns empty string."
                                       (let ((selected (car collection)))
                                         (setq selected-overlay (cdr selected))
                                         (car selected))))
           (result (jj-read-revision "" "the-default"))
           ;; Note: expected can only be generated after
           ;; jj-read-revision has run and populated selected-overlay.
           (expected (jj--revision-change-id
                      (overlay-get selected-overlay 'jj--revision))))
      (should (stringp result))
      (should (equal result expected)))))



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; run command
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(ert-deftest run-command-success-creates-change-and-displays-output ()
  (with-test-repo
    (let ((initial-change-id (test-jj-change-id "@"))
          (displayed-output  nil))
      (cl-letf (((default-value 'jj--display-function)
                 (lambda (output) (setq displayed-output output))))
        (jj-run-command '("new")))
      (should-not (equal initial-change-id
                         (test-jj-change-id "@")))
      (should (string-match-p "Working copy .* now at: "
                              displayed-output)))))

(ert-deftest run-command-failure-signals-error ()
  (with-test-repo
    (should-error (jj-run-command '("command-does-not-exist"))
                  :type 'jj-error)))

(ert-deftest run-command-deprecated-alias-runs-and-warns ()
  (with-test-repo
    (let (warnings)
      (cl-letf (((symbol-function 'lwarn)
                 (lambda (&rest args) (push args warnings)))
                (jj--run-command-warned nil))
        (with-no-warnings
          (jj--run-command '("log" "--limit" "2"))))
      (should warnings)
      (should (string-match-p
               "jj--run-command' is deprecated"
               (format "%S" (car warnings)))))))



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; new
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(ert-deftest new-creates-new-revision ()
  (with-test-repo
    (let ((initial-change-id (test-jj-change-id "@")))
      (jj-new "@")
      (should-not (equal initial-change-id
                         (test-jj-change-id "@")))
      (should (equal initial-change-id
                     (test-jj-change-id "@-"))))))

(ert-deftest new-on-bookmark-adds-child-to-bookmarked-revision ()
  (with-test-repo
    (test-sh
     "jj bookmark create bookmark1"
     "jj new")
    (let ((bookmark-change-id     (test-jj-change-id "bookmark1"))
          (working-copy-change-id (test-jj-change-id "@")))
      (jj-new "bookmark1")
      (should (equal bookmark-change-id
                     (test-jj-change-id "@-")))
      (should-not (equal working-copy-change-id
                         (test-jj-change-id "@")))
      (should (equal bookmark-change-id
                     (test-jj-change-id "bookmark1"))))))

(ert-deftest new-errors-on-unresolvable-revision ()
  (with-test-repo
    (should-error (jj-new "no-such-revision")
                  :type 'jj-error)))

;; 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; edit
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(ert-deftest edit-moves-working-copy-to-specified-revision ()
  (with-test-repo
    (test-sh
     "jj new"
     "printf 'Edit me\n' | jj describe --stdin")
    (let* ((new-change-id    (test-jj-change-id "@"))
           (parent-change-id (test-jj-change-id "@-")))
      (jj-edit parent-change-id)
      (should (equal parent-change-id
                     (test-jj-change-id "@")))
      (should-not (equal new-change-id
                         (test-jj-change-id "@"))))))

(ert-deftest edit-of-current-working-copy-revision-succeeds ()
  (with-test-repo
    (let ((change-id (test-jj-change-id "@")))
      (jj-edit "@")
      (should (equal change-id
                     (test-jj-change-id "@"))))))

(ert-deftest edit-errors-on-unresolvable-revision ()
  (with-test-repo
    (should-error (jj-edit "no-such-revision")
                  :type 'jj-error)))


;; 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; abandon
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(ert-deftest abandon-removes-revision ()
  (with-test-repo
    (test-sh
     "jj new"
     "printf 'Doomed\n' | jj describe --stdin")
    (let* ((abandon-change-id (test-jj-change-id "@"))
           (root-change-id    (test-jj-change-id "@-")))
      (jj-abandon abandon-change-id)
      (should-not (equal abandon-change-id
                         (test-jj-change-id "@")))
      (should (equal root-change-id
                     (test-jj-change-id "@-")))
      (with-temp-buffer
        (should-not (zerop (call-process "jj" nil t nil
                                         "log" "-r" abandon-change-id)))))))

(ert-deftest abandon-errors-on-unresolvable-revision ()
  (with-test-repo
    (should-error (jj-abandon "no-such-revision")
                  :type 'jj-error)))


;; 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; duplicate
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(ert-deftest duplicate-creates-copy-of-revision ()
  (with-test-repo
    (test-sh
     "printf 'Original\n' | jj describe --stdin")
    (let* ((original-change-id (test-jj-change-id "@")))
      (jj-duplicate "@")
      (should (equal original-change-id
                     (test-jj-change-id "@")))
      (with-temp-buffer
        (should (zerop (call-process "jj" nil t nil "log" "--no-graph"
                                     "-T" "description")))
        (goto-char (point-min))
        (should (equal 2
                       (count-matches "^Original$")))))))

(ert-deftest duplicate-errors-on-unresolvable-revision ()
  (with-test-repo
    (should-error (jj-duplicate "no-such-revision")
                  :type 'jj-error)))



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; rebase
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(ert-deftest rebase-moves-source-and-descendants-onto-destination ()
  (with-test-repo
    (test-sh
     "jj describe -m 'A'"
     "jj bookmark create A"
     "jj new -m 'B'"
     "jj bookmark create B"
     "jj new -m 'C'"
     "jj bookmark create C"
     "jj new A -m 'D'"
     "jj bookmark create D")
    (let ((d-change (test-jj-change-id "D"))
          (b-change (test-jj-change-id "B")))
      (jj-rebase "B" "D")
      (should (string= d-change (test-jj-parent-change-id "B")))
      (should (string= b-change (test-jj-parent-change-id "C"))))))

(ert-deftest rebase-errors-on-unresolvable-source ()
  (with-test-repo
    (should-error (jj-rebase "no-such-revision" "root()")
                  :type 'jj-error)))

(ert-deftest rebase-errors-on-unresolvable-destination ()
  (with-test-repo
    (should-error (jj-rebase "root()" "no-such-revision")
                  :type 'jj-error)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; rebase onto
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(ert-deftest rebase-onto-moves-single-revision-onto-destination ()
  (with-test-repo
    (test-sh
     "jj describe -m 'A'"
     "jj bookmark create A"
     "jj new -m 'B'"
     "jj bookmark create B"
     "jj new -m 'C'"
     "jj bookmark create C"
     "jj new A -m 'D'"
     "jj bookmark create D")
    (let ((d-change (test-jj-change-id "D")))
      (jj-rebase-onto "B" "D")
      (should (string= d-change (test-jj-parent-change-id "B"))))))

(ert-deftest rebase-onto-leaves-descendants-on-original-parent ()
  (with-test-repo
    (test-sh
     "jj describe -m 'A'"
     "jj bookmark create A"
     "jj new -m 'B'"
     "jj bookmark create B"
     "jj new -m 'C'"
     "jj bookmark create C"
     "jj new A -m 'D'"
     "jj bookmark create D")
    (let ((a-change (test-jj-change-id "A"))
          (d-change (test-jj-change-id "D")))
      (jj-rebase-onto "B" "D")
      (should (string= d-change (test-jj-parent-change-id "B")))
      (should (string= a-change (test-jj-parent-change-id "C"))))))

(ert-deftest rebase-onto-errors-on-unresolvable-source ()
  (with-test-repo
    (should-error (jj-rebase-onto "no-such-revision" "root()")
                  :type 'jj-error)))

(ert-deftest rebase-onto-errors-on-unresolvable-destination ()
  (with-test-repo
    (should-error (jj-rebase-onto "root()" "no-such-revision")
                  :type 'jj-error)))


;; 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; describe
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(ert-deftest describe-creates-buffer-with-mode-and-description ()
  (with-test-repo
    (test-sh
     "printf 'First Line\nSecondLine\n' | jj describe --stdin")
    (as-temp-buffer (jj-describe "@")
      (should (derived-mode-p 'jj-describe-mode))
      (should (string-prefix-p "First Line\nSecondLine\n\n"
                               (buffer-string)))
      (should (string-match-p "^JJ: Change ID: "
                              (buffer-string)))
      (should (string-match-p "^JJ: Lines starting with \"JJ:\" (like this one) will be removed.\n"
                              (buffer-string))))))

(ert-deftest describe-creates-buffer-with-change-id-header ()
  (with-test-repo
    (let ((change-id-shortest (with-temp-buffer
                                (should (zerop (call-process "jj" nil t nil
                                                             "log" "-r" "@"
                                                             "--no-graph"
                                                             "-T" "change_id.shortest(8)")))
                                (buffer-string))))
      (as-temp-buffer (jj-describe "@")
        (should (string-match-p (concat "^JJ: Change ID: "
                                        change-id-shortest)
                                (buffer-string)))))))

(ert-deftest describe-mode-hook-runs-with-revision-variable ()
  (with-test-repo
    (test-sh
     "printf 'First Line\nSecondLine\n' | jj describe --stdin")
    (let* ((got-revision nil)
           (got-point    nil)
           (got-calls    0)
           (hook (lambda ()
                   (setq got-revision jj--describe-revision
                         got-point (point)
                         got-calls (1+ got-calls)))))
      (unwind-protect
          (progn
            (add-hook 'jj-describe-mode-hook hook)
            (as-temp-buffer (jj-describe "@")
              (should (equal got-point    (point-min)))
              (should (equal got-calls    1))
              (should (equal got-revision (test-jj-change-id "@")))
              (buffer-string)))
        (remove-hook 'jj-describe-mode-hook hook)))))

(ert-deftest describe-on-unresolvable-revision-is-error ()
  (with-test-repo
    (should-error (jj-describe "no-such-revision")
                  :type 'jj-error)))

(ert-deftest describe-accept-sets-description-on-revision ()
  (with-test-repo
    (as-temp-buffer (jj-describe "@")
      (delete-region (point-min) (point-max))
      (insert "This is the new description")
      (jj-describe-accept))
    (should (equal "This is the new description"
                   (test-jj-description "@")))))

(ert-deftest describe-accept-strips-jj-comment-lines ()
  (with-test-repo
    (as-temp-buffer (jj-describe "@")
      (delete-region (point-min) (point-max))
      (insert "New Description\nJJ: Comment to strip\nSecond Line")
      (jj-describe-accept))
    (should (equal "New Description\nSecond Line"
                   (test-jj-description "@")))))

(ert-deftest describe-accept-trims-leading-and-trailing-blank-lines ()
  (with-test-repo
    (as-temp-buffer (jj-describe "@")
      (delete-region (point-min) (point-max))
      (insert "\n\nDescription\n\n")
      (jj-describe-accept))
    (should (equal "Description"
                   (test-jj-description "@")))))

(ert-deftest describe-accept-on-error-leaves-buffer-unchanged ()
  (with-test-repo
    (as-temp-buffer (jj-describe "root()")
      (delete-region (point-min) (point-max))
      (insert "New description")
      (should-error (jj-describe-accept)
                    :type 'jj-error)
      (should (equal (buffer-string) "New description")))))

(ert-deftest describe-accept-outside-describe-buffer-is-error ()
  (with-test-repo
    (as-temp-buffer (jj-describe "@")
      (delete-region (point-min) (point-max))
      (insert "Description")
      (with-temp-buffer
        (should-error (jj-describe-accept)
                      :type 'user-error)))))


(ert-deftest describe-reject-kills-buffer-without-saving-description ()
  (with-test-repo
    (test-sh "jj describe -m 'Initial description'")
    (as-temp-buffer (jj-describe "@")
      (let ((describe-buffer (current-buffer)))
        (delete-region (point-min) (point-max))
        (insert "Modified Description")
        (should (jj-describe-reject))
        (with-current-buffer test-repo-buffer
          (should-not (buffer-live-p describe-buffer))
          (should (equal "Initial description" (test-jj-description "@"))))))))

(ert-deftest describe-reject-outside-describe-buffer-is-error ()
  (with-test-repo
    (with-temp-buffer
      (should-error (jj-describe-reject)
                    :type 'user-error))))

(ert-deftest describe-diff-shows-diff-of-revision ()
  (with-test-repo
    (test-write-file "file.txt" "content\nmore content\n")
    (as-temp-buffer (jj-describe "@")
      (as-temp-buffer (jj-describe-diff)
        (test-wait-for-process)
        (should (eq major-mode 'diff-mode))
        (should (equal (buffer-string)
                       "diff --git a/file.txt b/file.txt
new file mode 100644\nindex 0000000000..86436d0dd5
--- /dev/null
+++ b/file.txt
@@ -0,0 +1,2 @@
+content
+more content
"))))))

(ert-deftest describe-diff-on-empty-is-empty ()
  (with-test-repo
    (as-temp-buffer (jj-describe "@")
      (as-temp-buffer (jj-describe-diff)
        (test-wait-for-process)
        (should (eq major-mode 'diff-mode))
        (should (equal (buffer-string) ""))))))

(ert-deftest describe-diff-outside-describe-buffer-is-error ()
  (with-test-repo
    (with-temp-buffer
      (should-error (jj-describe-diff)
                    :type 'user-error))))



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; diff at
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(ert-deftest diff-at-creates-jj-diff-buffer ()
  (with-test-repo
    (test-write-file "file.txt" "content\n")
    (as-temp-buffer (jj-diff-at "@")
      (test-wait-for-process)
      (should (string-prefix-p "*jj-diff*" (buffer-name)))
      (should (derived-mode-p 'diff-mode)))))

(ert-deftest diff-at-shows-diff-of-revision ()
  (with-test-repo
    (test-write-file "file-a.txt" "target content\n")
    (test-sh "jj bookmark set target")
    (test-sh "jj new")
    (test-write-file "file-b.txt" "other\n")
    (test-sh "jj bookmark set other")
    (as-temp-buffer (jj-diff-at "target")
      (test-wait-for-process)
      (should (eq major-mode 'diff-mode))
      (should (equal "diff --git a/file-a.txt b/file-a.txt
new file mode 100644
index 0000000000..2ceb84c5b3
--- /dev/null
+++ b/file-a.txt
@@ -0,0 +1,1 @@
+target content
" (buffer-string))))))

(ert-deftest diff-at-shows-diff-of-empty-revision-is-empty ()
  (with-test-repo
    (as-temp-buffer (jj-diff-at "@")
      (test-wait-for-process)
      (should (eq major-mode 'diff-mode))
      (should (equal (buffer-string) "")))))

(ert-deftest diff-at-on-unresolvable-revision-shows-error-in-buffer ()
  (with-test-repo
    (as-temp-buffer (jj-diff-at "no-such-revision")
      (test-wait-for-process)
      (should-not (derived-mode-p 'diff-mode))
      (should (equal "Error: Revision `no-such-revision` doesn't exist\n"
                     (buffer-string))))))

(ert-deftest diff-at-navigates-to-buffer ()
  (with-test-repo
    (test-write-file "file.txt" "content\n")
    (let ((diff-buffer (jj-diff-at "@")))
      (test-wait-for-process diff-buffer)
      (unwind-protect
          (should (eq diff-buffer (current-buffer)))
        (kill-buffer diff-buffer)))))



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; diff from
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(ert-deftest diff-from-creates-jj-diff-buffer ()
  (with-test-repo
    (test-write-file "file.txt" "content\n")
    (as-temp-buffer (jj-diff-from "root()")
      (test-wait-for-process)
      (should (string-prefix-p "*jj-diff*" (buffer-name)))
      (should (derived-mode-p 'diff-mode)))))

(ert-deftest diff-from-shows-diff-of-revision ()
  (with-test-repo
    ;; rev1
    (test-write-file "file-a.txt" "target content\n")
    (test-sh "jj bookmark set rev1")
    ;; rev2
    (test-sh "jj new")
    (test-write-file "file-b.txt" "other\n")
    ;; rev3
    (test-sh "jj new")
    (test-write-file "file-c.txt" "this one too\n")
    (as-temp-buffer (jj-diff-from "rev1")
      (test-wait-for-process)
      (should (eq major-mode 'diff-mode))
      (should (equal "diff --git a/file-b.txt b/file-b.txt
new file mode 100644
index 0000000000..e45c9c2666
--- /dev/null
+++ b/file-b.txt
@@ -0,0 +1,1 @@
+other
diff --git a/file-c.txt b/file-c.txt
new file mode 100644
index 0000000000..b28a266836
--- /dev/null
+++ b/file-c.txt
@@ -0,0 +1,1 @@
+this one too
"
                     (buffer-string))))))

(ert-deftest diff-from-with-arg-to-revision-shows-diff-between-revisions ()
  (with-test-repo
    ;; rev1
    (test-write-file "file-a.txt" "first\n")
    (test-sh "jj bookmark set rev1")
    ;; rev2
    (test-sh "jj new")
    (test-write-file "file-b.txt" "second\n")
    (test-sh "jj bookmark set rev2")
    ;; rev3
    (test-sh "jj new")
    (test-write-file "file-c.txt" "third\n")
    ;; test
    (as-temp-buffer (jj-diff-from "rev1" "rev2")
      (test-wait-for-process)
      (should (eq major-mode 'diff-mode))
      (should (equal "diff --git a/file-b.txt b/file-b.txt
new file mode 100644
index 0000000000..e019be006c
--- /dev/null
+++ b/file-b.txt
@@ -0,0 +1,1 @@
+second
" (buffer-string))))))

(ert-deftest diff-from-empty-diff-is-empty ()
  (with-test-repo
    (as-temp-buffer (jj-diff-from "@")
      (test-wait-for-process)
      (should (eq major-mode 'diff-mode))
      (should (equal (buffer-string) "")))))

(ert-deftest diff-from-on-unresolvable-revision-shows-error-in-buffer ()
  (with-test-repo
    (as-temp-buffer (jj-diff-from "no-such-revision")
      (test-wait-for-process)
      (should-not (derived-mode-p 'diff-mode))
      (should (equal "Error: Revision `no-such-revision` doesn't exist\n"
                     (buffer-string))))))

(ert-deftest diff-from-navigates-to-buffer ()
  (with-test-repo
    (test-write-file "file.txt" "content\n")
    (let ((diff-buffer (jj-diff-from "root()")))
      (test-wait-for-process diff-buffer)
      (unwind-protect
          (should (eq diff-buffer (current-buffer)))
        (kill-buffer diff-buffer)))))
