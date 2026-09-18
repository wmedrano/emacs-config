;;; gptel-agents-file.el --- Add project AGENTS.md to gptel context -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "30") (gptel "0.9.9"))
;; Version: 0.1.0
;; Keywords: convenience, ai

;;; Commentary:
;;
;; Utilities for constructing gptel's system prompt from the current project.

;;; Code:

(require 'project)
(defconst gptel-agents--system-prompt-buffer "*gptel-system-prompt*"
  "Name of the buffer containing gptel's generated system prompt.")

(defconst gptel-agents-file-default-system-prompt
  "You are an expert coding assistant operating inside Emacs. You help users by reading files, executing commands, editing code, and writing new files.

<rules>
- Use bash for file operations like ls, rg, find
- Be concise in your responses
- Show file paths clearly when working with files
</rules>"
  "Default system prompt.")

(defun gptel-agents--project-root ()
  "Return the current project root, or nil if there is no project."
  (when-let* ((project (project-current)))
    (project-root project)))

(defun gptel-agents--system-prompt-buffer ()
  "Return the buffer containing the generated system prompt.
Create and initialize it when necessary."
  (let ((buffer (get-buffer-create gptel-agents--system-prompt-buffer)))
    (with-current-buffer buffer
      (unless (or (buffer-modified-p) (> (buffer-size) 0))
        (let* ((root (or (gptel-agents--project-root) default-directory))
               (agents (expand-file-name "AGENTS.md" root)))
          (insert gptel-agents-file-default-system-prompt)
          (insert (format "\n\n<cwd>\n%s\n</cwd>" (directory-file-name (expand-file-name root))))
          (when (file-readable-p agents)
            (insert (format "\n\n<project_instructions path=\"%s\">\n"
                            agents))
            (insert-file-contents agents)
            (unless (eq (char-before) ?\n) (insert "\n"))
            (insert "</project_instructions>"))))
      (current-buffer))))

(defun gptel-agents-system-prompt ()
  "Return the generated system prompt for gptel."
  (with-current-buffer (gptel-agents--system-prompt-buffer)
    (buffer-string)))

(provide 'gptel-agents-file)
;;; gptel-agents-file.el ends here
