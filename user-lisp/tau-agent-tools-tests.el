;;; tau-agent-tools-tests.el --- File tool tests -*- lexical-binding: t -*-

(require 'ert)
(require 'tau-agent-tools)

(defun tau-agent-tools-test--wait (process)
  "Wait up to five seconds for PROCESS to complete."
  (let ((deadline (+ (float-time) 5)))
    (while (and (process-live-p process) (< (float-time) deadline))
      (accept-process-output process 0.05))
    (should-not (process-live-p process))))

(defun tau-agent-tools-test--shell-result (command &optional timeout)
  "Run COMMAND and verify single callback delivery and buffer cleanup."
  (let* (results
         (process (tau-agent-tools--shell-tool-impl
                   (lambda (result) (push result results)) command timeout))
         (buffer (process-buffer process)))
    (unwind-protect
        (progn
          (tau-agent-tools-test--wait process)
          (funcall (process-sentinel process) process "finished\n")
          (should (= (length results) 1))
          (should-not (buffer-live-p buffer))
          (car results))
      (when (process-live-p process) (delete-process process))
      (when (buffer-live-p buffer) (kill-buffer buffer)))))

(ert-deftest tau-agent-tools-shell-async ()
  (should (tau-agent-tool-async tau-agent-tools-shell-tool))
  (let* (result
         (process (tau-agent-tools--shell-tool-impl
                   (lambda (value) (setq result value)) "sleep 0.2; printf done")))
    (unwind-protect
        (progn
          (should (process-live-p process))
          (should-not result)
          (tau-agent-tools-test--wait process)
          (should (equal result "exit code: 0\ndone")))
      (when (process-live-p process) (delete-process process)))))

(ert-deftest tau-agent-tools-shell-output ()
  (should (equal (tau-agent-tools-test--shell-result
                  "printf out; printf err >&2; exit 7")
                 "exit code: 7\nouterr"))
  (should (equal (tau-agent-tools-test--shell-result "cat") "exit code: 0\n"))
  (let ((tau-agent-tools-shell-output-limit 3))
    (let ((result (tau-agent-tools-test--shell-result "printf abcdef")))
      (should (string-prefix-p "exit code: 0\ndef\n[Showing last 3 characters." result))
      (should (string-match "Full output: \\(.*\\)]" result))
      (let ((file (match-string 1 result)))
        (unwind-protect
            (should (equal (with-temp-buffer
                             (insert-file-contents file) (buffer-string)) "abcdef"))
          (delete-file file)))))
  (let ((tau-agent-tools-shell-output-limit 0))
    (should (equal (tau-agent-tools-test--shell-result "printf abcdef")
                   "exit code: 0\nabcdef"))))

(ert-deftest tau-agent-tools-shell-directory ()
  (let ((directory (make-temp-file "gptel-shell-test-" t)))
    (unwind-protect
        (cl-letf (((symbol-function 'tau-agent-tools--root) (lambda () directory)))
          (should (equal (tau-agent-tools-test--shell-result "pwd")
                         (format "exit code: 0\n%s\n" (file-truename directory)))))
      (delete-directory directory))))

(ert-deftest tau-agent-tools-shell-signal ()
  (let ((shell-file-name "/bin/sh"))
    (should (equal (tau-agent-tools-test--shell-result "kill -TERM $$")
                   "exit code: 143\n"))
    (should (equal (tau-agent-tools-test--shell-result "exit 143")
                   "exit code: 143\n"))))

(ert-deftest tau-agent-tools-shell-timeout ()
  (let ((result (tau-agent-tools-test--shell-result "printf started; sleep 10" 0.1)))
    (should (string-prefix-p "exit code: 137\nstarted" result))
    (should (string-suffix-p "Command timed out after 0.1 seconds" result)))
  (should (equal (tau-agent-tools-test--shell-result "printf done" 2)
                 "exit code: 0\ndone"))
  (dolist (timeout '(0 -1 "1" 2147484))
    (should-error (tau-agent-tools--shell-tool-impl #'ignore "true" timeout)
                  :type 'user-error)))

(ert-deftest tau-agent-tools-shell-startup-error ()
  (let ((shell-file-name "/nonexistent/gptel-test-shell")
        (buffers (buffer-list))
        results)
    (tau-agent-tools--shell-tool-impl (lambda (value) (push value results)) "true")
    (should (= (length results) 1))
    (should (string-prefix-p "process could not be started:" (car results)))
    (should (equal buffers (buffer-list)))
    (should-error
     (tau-agent-tools--shell-tool-impl (lambda (_) (error "Callback failed")) "true"))
    (should (equal buffers (buffer-list)))))

(ert-deftest tau-agent-tools-shell-callback-error ()
  (let* ((calls 0)
         (process (tau-agent-tools--shell-tool-impl
                   (lambda (_) (cl-incf calls) (error "Callback failed")) "true"))
         (buffer (process-buffer process))
         (sentinel (process-sentinel process)))
    (unwind-protect
        (progn
          ;; Invoke completion ourselves so ERT can catch the callback error.
          (set-process-sentinel process #'ignore)
          (tau-agent-tools-test--wait process)
          (should-error (funcall sentinel process "finished\n"))
          (should-not (buffer-live-p buffer))
          (funcall sentinel process "finished\n")
          (should (= calls 1)))
      (when (process-live-p process) (delete-process process))
      (when (buffer-live-p buffer) (kill-buffer buffer)))))

(ert-deftest tau-agent-tools-read-schema ()
  (should (equal (tau-agent-tool-name tau-agent-tools-read-file-tool) "read"))
  (should (equal (mapcar (lambda (arg) (plist-get arg :name))
                        (tau-agent-tool-args tau-agent-tools-read-file-tool))
                 '("path" "offset" "limit"))))

(ert-deftest tau-agent-tools-read-selection ()
  (should (equal (tau-agent-tools--read-text "" "file" 1 nil) ""))
  (should (equal (tau-agent-tools--read-text "a\nb\n" "file" 1 nil) "a\nb\n"))
  (should (equal (tau-agent-tools--read-text "a\nb\n" "file" 3 nil) ""))
  (should (equal (tau-agent-tools--read-text "a\nb\nc\nd" "file" 2 2)
                 "b\nc\n\n[1 more lines in file. Use offset=4 to continue.]"))
  (should (equal (tau-agent-tools--read-text "a\nb\nc" "file" 2 nil) "b\nc"))
  (should-error (tau-agent-tools--read-text "a\nb" "file" 3 nil)
                :type 'user-error))

(ert-deftest tau-agent-tools-read-line-cap ()
  (let* ((text (mapconcat #'number-to-string (number-sequence 1 2500) "\n"))
         (result (tau-agent-tools--read-text text "file" 1 nil)))
    (should (string-suffix-p
             "2000\n\n[Showing lines 1-2000 of 2500. Use offset=2001 to continue.]"
             result))
    (should (equal (tau-agent-tools--read-text text "file" 2001 nil)
                   (mapconcat #'number-to-string (number-sequence 2001 2500) "\n")))))

(ert-deftest tau-agent-tools-read-byte-cap ()
  ;; Multibyte characters must be counted in UTF-8 bytes, not characters.
  (let* ((line (make-string 1000 ?é))
         (text (mapconcat #'identity (make-list 30 line) "\n"))
         (result (tau-agent-tools--read-text text "file" 1 nil)))
    (should (equal result
                   (concat (mapconcat #'identity (make-list 25 line) "\n")
                           "\n\n[Showing lines 1-25 of 30 (50.0KB limit). Use offset=26 to continue.]")))))

(ert-deftest tau-agent-tools-read-exact-caps ()
  (let ((text (make-string 51200 ?x)))
    (should (equal (tau-agent-tools--read-text text "file" 1 nil) text)))
  (let ((text (mapconcat #'identity (make-list 2000 "x") "\n")))
    (should (equal (tau-agent-tools--read-text (concat text "\n") "file" 1 nil)
                   (concat text "\n")))))

(ert-deftest tau-agent-tools-read-long-line ()
  (let ((result (tau-agent-tools--read-text (make-string 51201 ?x) "a'b.txt" 1 nil)))
    (should (string-prefix-p "[Line 1 is 50.0KB, exceeds 50.0KB limit." result))
    (should (string-match-p (regexp-quote (shell-quote-argument "a'b.txt")) result))))

(ert-deftest tau-agent-tools-read-file-integration ()
  (let ((file (make-temp-file "gptel-read-test-" nil nil "one\ntwo\n")))
    (unwind-protect
        (cl-letf (((symbol-function 'tau-agent-tools--root)
                   (lambda () (file-name-directory file))))
          (should (equal (tau-agent-tools--read-file-tool-impl
                          (file-name-nondirectory file) 2 1)
                         "two\n\n[1 more lines in file. Use offset=3 to continue.]"))
          (should (equal (tau-agent-tools--read-file-tool-impl file) "one\ntwo\n"))
          (dolist (args '((0 nil) (-1 nil) (1.5 nil) (1 0) (1 -1) (1 1.5)))
            (should-error (apply #'tau-agent-tools--read-file-tool-impl file args)
                          :type 'user-error))
          (should-error (tau-agent-tools--read-file-tool-impl (concat file "-missing")))
          (should-error (tau-agent-tools--read-file-tool-impl (file-name-directory file))))
      (delete-file file))))

(ert-deftest tau-agent-tools-read-image ()
  (let ((file (make-temp-file "gptel-read-image-" nil nil "GIF89a")))
    (unwind-protect
        (should (string-prefix-p "[Image not returned:"
                                 (tau-agent-tools--read-file-tool-impl file)))
      (delete-file file))))

(ert-deftest tau-agent-tools-write-file-integration ()
  (let* ((directory (make-temp-file "gptel-write-test-" t))
         (file (expand-file-name "nested/dir/file.txt" directory)))
    (unwind-protect
        (cl-letf (((symbol-function 'tau-agent-tools--root) (lambda () directory)))
          (should (equal (tau-agent-tool-name tau-agent-tools-write-file-tool) "write"))
          (should (equal (tau-agent-tools--write-file-tool-impl
                          "nested/dir/file.txt" "héllo\nworld")
                         "Successfully wrote to nested/dir/file.txt"))
          (should (equal (with-temp-buffer
                           (set-buffer-multibyte nil)
                           (insert-file-contents-literally file)
                           (buffer-string))
                         (encode-coding-string "héllo\nworld" 'utf-8-unix)))
          (with-current-buffer (find-buffer-visiting file)
            (should-not (buffer-modified-p))
            (narrow-to-region 2 4)
            (let ((require-final-newline t)
                  (before-save-hook (list (lambda () (error "Unexpected save hook")))))
              (should (equal (tau-agent-tools--write-file-tool-impl file "replacement")
                             (format "Successfully wrote to %s" file)))))
          (should (equal (tau-agent-tools--read-file-tool-impl file) "replacement"))
          (tau-agent-tools--write-file-tool-impl file "")
          (should (equal (tau-agent-tools--read-file-tool-impl file) ""))
          (with-current-buffer (find-buffer-visiting file)
            (let ((buffer-read-only t))
              (should-error (tau-agent-tools--write-file-tool-impl file "forbidden")
                            :type 'user-error))
            (insert "unsaved")
            (should-error (tau-agent-tools--write-file-tool-impl file "forbidden")
                          :type 'user-error)
            (should (equal (buffer-string) "unsaved")))
          (should (equal (tau-agent-tools--read-file-tool-impl file) ""))
          (should-error (tau-agent-tools--write-file-tool-impl directory "forbidden")
                        :type 'user-error))
      (when-let* ((buffer (find-buffer-visiting file)))
        (with-current-buffer buffer (set-buffer-modified-p nil))
        (kill-buffer buffer))
      (delete-directory directory t))))

(ert-deftest tau-agent-tools-edit-original-matching ()
  (should (equal (tau-agent-tools--apply-edits
                  "alpha beta gamma"
                  [(:oldText "gamma" :newText "")
                   (:oldText "alpha" :newText "beta")
                   (:oldText "beta" :newText "longer")])
                 "beta longer "))
  (should (equal (tau-agent-tools--apply-edits
                  "a\nb" '((:oldText "a\r\nb" :newText "c\r\nd")))
                 "c\nd")))

(ert-deftest tau-agent-tools-edit-validation ()
  (dolist (edits '(nil [] "bad" [(:oldText "a")]
                   [(:oldText "" :newText "x")]
                   [(:oldText "missing" :newText "x")]
                   [(:oldText "A" :newText "x")]
                   [(:oldText "a" :newText "a")]
                   [(:oldText "ab" :newText "x") (:oldText "bc" :newText "y")]))
    (should-error (tau-agent-tools--apply-edits "abc" edits) :type 'user-error))
  (should-error (tau-agent-tools--apply-edits
                 "aaa" [(:oldText "aa" :newText "x")]) :type 'user-error))

(ert-deftest tau-agent-tools-edit-file-integration ()
  (let* ((coding-system-for-write 'utf-8-unix)
         (file (make-temp-file "gptel-edit-test-" nil nil "\ufeffone\r\ntwo\r\n")))
    (unwind-protect
        (progn
          (should (equal (tau-agent-tool-name tau-agent-tools-edit-file-tool) "edit"))
          (cl-letf (((symbol-function 'tau-agent-tools--root)
                     (lambda () (file-name-directory file))))
            (should (equal
                     (tau-agent-tools--edit-file-tool-impl
                      (file-name-nondirectory file) [(:oldText "one" :newText "héllo")])
                     (format "Successfully replaced 1 block(s) in %s."
                             (file-name-nondirectory file)))))
          (should (equal (tau-agent-tools--read-file-tool-impl file)
                         "\ufeffhéllo\r\ntwo\r\n"))
          ;; An invalid later edit must leave both the file and buffer intact.
          (should-error (tau-agent-tools--edit-file-tool-impl
                         file [(:oldText "two" :newText "changed")
                               (:oldText "missing" :newText "bad")]))
          (should (equal (tau-agent-tools--read-file-tool-impl file)
                         "\ufeffhéllo\r\ntwo\r\n"))
          (with-current-buffer (find-buffer-visiting file)
            (should-not (buffer-modified-p))
            (let ((buffer-read-only t))
              (should-error (tau-agent-tools--edit-file-tool-impl
                             file [(:oldText "two" :newText "changed")])
                            :type 'user-error))
            (insert "unsaved")
            (should-error (tau-agent-tools--edit-file-tool-impl
                           file [(:oldText "two" :newText "changed")])
                          :type 'user-error))
          (should-error (tau-agent-tools--edit-file-tool-impl
                         (concat file "-missing") [(:oldText "a" :newText "b")])
                        :type 'user-error))
      (when-let* ((buffer (find-buffer-visiting file)))
        (with-current-buffer buffer (set-buffer-modified-p nil))
        (kill-buffer buffer))
      (delete-file file))))

(provide 'tau-agent-tools-tests)
;;; tau-agent-tools-tests.el ends here
