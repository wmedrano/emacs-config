;;; paths-extra.el --- Extra path utilities -*- lexical-binding: t; -*-
;; Package-Requires: ((emacs "30"))
;;; Commentary:
;;; Code:

(require 'project)

;;;###autoload
(defun copy-filename ()
  "Copy the current buffer's filename to the kill ring.
If within a project, the path is relative to the project root.
Otherwise, the path is relative to `default-directory'."
  (interactive)
  (when-let* ((path          (buffer-file-name))
              (project       (project-current))
              (root          (project-root project))
              (relative-path (file-relative-name path root)))
    (kill-new relative-path)
    (message "Copied: %s" relative-path)))

;;;###autoload
(defun copy-filename-absolute ()
  "Copy the current buffer's absolute filename to the kill ring."
  (interactive)
  (when-let* ((file (buffer-file-name)))
    (kill-new file)
    (message "Copied: %s" file)))

(provide 'paths-extra)
;;; paths-extra.el ends here
