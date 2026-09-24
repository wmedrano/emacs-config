;;; gptel-ops-tests.el --- Bash tool regression tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'gptel-ops)

(defun gptel-ops-tests--run (command &optional timeout inspect)
  "Run COMMAND with TIMEOUT, calling INSPECT with the running process."
  (let ((make-process-function (symbol-function 'make-process))
        process output-buffer results)
    (unwind-protect
        (progn
          (cl-letf (((symbol-function 'make-process)
                     (lambda (&rest args)
                       (setq process (apply make-process-function args)
                             output-buffer (process-buffer process))
                       process)))
            (gptel-agent-tools-bash--impl
             (lambda (result) (push result results)) command timeout))
          (when inspect
            (funcall inspect process)
            (should-not results)
            (should (buffer-live-p output-buffer)))
          (let ((deadline (+ (float-time) 5)))
            (while (and (not results) (< (float-time) deadline))
              (accept-process-output nil 0.05)))
          (should (= (length results) 1))
          (should-not (process-live-p process))
          (should-not (buffer-live-p output-buffer))
          ;; A duplicate terminal notification must not call back again.
          (funcall (process-sentinel process) process "finished\n")
          (should (= (length results) 1))
          (car results))
      (when (and process (process-live-p process))
        (delete-process process))
      (when (buffer-live-p output-buffer)
        (kill-buffer output-buffer)))))

(ert-deftest gptel-ops-bash-success ()
  (should (equal (gptel-ops-tests--run "printf hello") "hello")))

(ert-deftest gptel-ops-bash-nonzero-stderr ()
  (should (equal (gptel-ops-tests--run "printf 'bad argument' >&2; exit 2")
                 "Command exited with code 2.\nOutput:\nbad argument")))

(ert-deftest gptel-ops-bash-nonzero-empty ()
  (should (equal (gptel-ops-tests--run "exit 2")
                 "Command exited with code 2.\nOutput:\n(no output)")))

(ert-deftest gptel-ops-bash-signal ()
  (let ((result (gptel-ops-tests--run "printf partial; kill -TERM $$")))
    (should (string-match-p "Command terminated by signal 15" result))
    (should (string-match-p "Output:\npartial" result))))

(ert-deftest gptel-ops-bash-timeout ()
  (should (equal (gptel-ops-tests--run "printf partial; exec sleep 10" 0.2)
                 "Command timed out after 0.2 seconds.\nOutput:\npartial")))

(ert-deftest gptel-ops-bash-nonterminal-notification ()
  (should
   (equal
    (gptel-ops-tests--run
     "sleep 0.1; printf done" nil
     (lambda (process)
       (funcall (process-sentinel process) process "running\n")))
    "done")))

(ert-deftest gptel-ops-bash-launch-error ()
  (let (results)
    (cl-letf (((symbol-function 'make-process)
               (lambda (&rest _) (error "Cannot launch bash"))))
      (gptel-agent-tools-bash--impl
       (lambda (result) (push result results)) "true"))
    (should (equal results '("bash tool call failure: Cannot launch bash")))))

(provide 'gptel-ops-tests)
;;; gptel-ops-tests.el ends here
