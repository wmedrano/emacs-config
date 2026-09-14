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

;;;###autoload
(defun project-insert-file-path ()
  "Select a file under the current root and insert its path at point.
In a project, use `project-files'.  Outside a project, use lazy file-name
completion rooted at `default-directory' rather than recursively enumerating
the directory.  This keeps the fallback usable even in large directories
such as the home directory."
  (interactive)
  (let* ((project (project-current))
         (root (file-name-as-directory
                (expand-file-name (if project
                                      (project-root project)
                                    default-directory))))
         (file (if project
                   (completing-read "Project file: "
                                   (project-files project)
                                   nil t)
                 ;; `read-file-name' completes directories lazily and does
                 ;; not first build a recursive list of their contents.
                 (read-file-name "File under current directory: "
                                 root nil t)))
         (absolute (expand-file-name file root)))
    (unless (file-in-directory-p absolute root)
      (user-error "File is outside the current root: %s" file))
    (insert (file-relative-name absolute root))))

(provide 'paths-extra)
;;; paths-extra.el ends here
