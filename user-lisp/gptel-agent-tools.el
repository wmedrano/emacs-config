;;; gptel-agent-tools.el --- Run Bash commands as gptel tools -*- lexical-binding: t; -*-

;;; Commentary:

;;; Code:

(require 'gptel)
(require 'gptel-request)
(require 'gptel-ops)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; System prompt
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defvar-local gptel-agent-tools-default-system-prompt--cache nil)
(defvar-local gptel-agent-tools--scratch-dir                 nil)
(defun gptel-agent-tools-default-system-prompt ()
  "Get the default system prompt."
  (unless gptel-agent-tools--scratch-dir
    (setq gptel-agent-tools--scratch-dir (make-temp-file "/tmp/agent-scratch-" t)))
  (unless gptel-agent-tools-default-system-prompt--cache
    (setq gptel-agent-tools-default-system-prompt--cache
          (format "You are an expert assistant operating inside a coding agent harness. You help users by reading files, executing commands, editing code, and writing new files.

working directory: %s
scratch directory: %s
"
                  default-directory
                  gptel-agent-tools--scratch-dir)))
  gptel-agent-tools-default-system-prompt--cache)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Bash
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defconst gptel-agent-tools-bash
  (gptel-make-tool
   :name "bash"
   :description "Call bash commands like

Preferred tools:

- search: rg
- version control: jj
  - Do not use git
  - Be conservative about usage. Most tasks do not require version control.
"
   :confirm t
   :function #'gptel-agent-tools-bash--impl
   :args (list
          '(:name "command"
                  :description "command to run"
                  :type string)
          '(:name "timeout"
                  :description "the number of seconds to wait before canceling"
                  :type integer
                  :optional true))
   :async t))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Read
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


(defconst gptel-agent-tools-read
  (gptel-make-tool
   :name "read_file"
   :description "Read a file

Prefer this over sed and cat for simple use cases"
   :confirm nil
   :function #'gptel-ops-read
   :args (list
          '(:name "path"
                  :description "path to file"
                  :type string)
          '(:name "start_line"
                  :description "the first line to show"
                  :type integer
                  :optional t)
          '(:name "end_line"
                  :description "the last line to show"
                  :type integer
                  :optional t))
   :confirm nil))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Symbol index
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun gptel-agent-tools-symbols--impl (path)
  "List indexed symbols in file PATH with line numbers."
  (let* ((path (expand-file-name path))
         (buffer (and (file-exists-p path)
                      (find-file-noselect path t))))
    (unless buffer
      (error "Could not find file %s" path))
    (gptel-ops-imenu buffer)))

(defconst gptel-agent-tools-symbols
  (gptel-make-tool
   :name "list_symbols"
   :description "List a file's indexed functions, variables, and other symbols with line numbers. Uses Emacs imenu."
   :confirm nil
   :function #'gptel-agent-tools-symbols--impl
   :args (list
          '(:name "path"
            :description "path to file"
            :type string))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Edit
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun gptel-agent-tools-edit--run (path old-text new-text)
  "Edit file PATH by replacing OLD-TEXT with NEW-TEXT."
  (let* ((path (expand-file-name path))
         (buffer (and (file-exists-p path)
                      (find-file-noselect path t))))
    (cond
     ((and (not buffer) (string-empty-p old-text))
      (with-current-buffer (find-file-noselect path)
        (insert new-text))
      (format "Created and wrote to file %s" path))
     ((not buffer)
      (error "Could not find file %s" path))
     (t
      (gptel-ops-replace path buffer
                                       old-text new-text)
      (format "Edited file %s" path)))))

(defun gptel-agent-tools-edit--confirm (path &rest _ignored)
  "True if the edit invocation with PATH requires confirmation."
  (let* ((path (expand-file-name path default-directory))
         (safe (or (file-in-directory-p path default-directory)
                   (file-in-directory-p path gptel-agent-tools--scratch-dir))))
    (not safe)))

(defconst gptel-agent-tools-edit
  (gptel-make-tool
   :name "edit_file"
   :description "Edit a file through text replacement"
   :confirm #'gptel-agent-tools-edit--confirm
   :function #'gptel-agent-tools-edit--run
   :args (list
          '(:name "path"
            :description "path to file to edit"
            :type string)
          '(:name "old_text"
            :description "the text that will be removed"
            :type string)
          '(:name "new_text"
            :description "the text to insert"
            :type string))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Emacs Lisp
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun gptel-agent-tools-elisp--impl (code)
  "Evaluate CODE as Emacs Lisp and return its printed result.

CODE is read as a single Lisp form.  Evaluation happens in the current Emacs
process and can have arbitrary side effects."
  (let ((form (car (read-from-string code))))
    (prin1-to-string (eval form t))))

(defconst gptel-agent-tools-elisp
  (gptel-make-tool
   :name "eval_elisp"
   :description "Evaluate one Emacs Lisp form in the current Emacs process. Use this only when the task specifically requires live Emacs state or an Emacs API. Keep forms narrow and non-destructive."
   :confirm t
   :function #'gptel-agent-tools-elisp--impl
   :args (list
          '(:name "code"
                  :description "Emacs Lisp form to evaluate"
                  :type string))))

(provide 'gptel-agent-tools)
;;; gptel-agent-tools.el ends here
