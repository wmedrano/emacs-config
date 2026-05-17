;;; disasm.el --- Disassemble binary files -*- lexical-binding: t -*-

;; Author: wmedrano
;; Version: 0.1.0
;; Package-Requires: ((emacs "28.1"))

;;; Commentary:
;; Provides a major mode and command for disassembling binary files.
;; Use `disasm' to select a binary and view its disassembly.

;;; Code:

(require 'asm-mode)
(require 'subr-x)

(defgroup disasm nil
  "Disassemble binary files."
  :group 'tools)

(defcustom disasm-tool "objdump"
  "Tool used to disassemble binaries."
  :type 'string
  :group 'disasm)

(defcustom disasm-tool-args '("-d" "--no-show-raw-insn" "--demangle")
  "Arguments passed to `disasm-tool'."
  :type '(repeat string)
  :group 'disasm)

(defvar disasm-mode-map
  (let ((map (make-sparse-keymap)))
    map)
  "Keymap for `disasm-mode'.")

(define-derived-mode disasm-mode asm-mode "Disasm"
  "Major mode for viewing disassembled binaries."
  :group 'disasm)

;;;###autoload
(defun disasm (file)
  "Disassemble FILE and open the result in a buffer."
  (interactive "fBinary file: ")
  (let ((file (expand-file-name file)))
    (unless (file-executable-p file)
      (user-error "File is not executable: %s" file))
    (let* ((buf-name (format "*disasm: %s*" (file-name-nondirectory file)))
           (buf (get-buffer-create buf-name))
           (args (append disasm-tool-args (list file)))
           (err-buf (generate-new-buffer " *disasm-stderr*"))
           (exit-code (with-current-buffer buf
                        (let ((inhibit-read-only t))
                          (erase-buffer)
                          (apply #'call-process disasm-tool nil (list buf (buffer-name err-buf)) nil args)))))
      (unless (zerop exit-code)
        (let ((err-msg (with-current-buffer err-buf (buffer-string))))
          (kill-buffer err-buf)
          (user-error "Disassembly failed (exit %d): %s" exit-code (string-trim err-msg))))
      (kill-buffer err-buf)
      (with-current-buffer buf
        (disasm-mode)
        (goto-char (point-min))
        (read-only-mode 1))
      (switch-to-buffer buf))))

(provide 'disasm)

;;; disasm.el ends here
