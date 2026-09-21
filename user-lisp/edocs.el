;;; edocs.el --- Export file documentation to HTML -*- lexical-binding: t -*-

;; Author: wmedrano
;; Version: 0.1.0
;; Package-Requires: ((emacs "28.1"))

;;; Commentary:
;; Run M-x edocs to browse documentation for functions and variables
;; defined in the current Emacs Lisp buffer, without evaluating it.  Symbols
;; containing "--" are omitted.  Generated Org and HTML files stay in /tmp.

;;; Code:

(require 'browse-url)
(require 'cl-lib)
(require 'subr-x)
(require 'ox-html)

(defconst edocs--html-style
  "<link rel=\"preconnect\" href=\"https://fonts.googleapis.com\">
<link rel=\"preconnect\" href=\"https://fonts.gstatic.com\" crossorigin>
<link rel=\"stylesheet\" href=\"https://fonts.googleapis.com/css2?family=Roboto:ital,wght@0,400;0,700;1,400;1,700&amp;family=Roboto+Mono:wght@400;700&amp;family=Roboto+Serif:opsz,wght@8..144,400;8..144,700&amp;display=swap\">
<style>
body { font-family: 'Roboto', sans-serif; font-size: 17px;
       color: #334155; background: #fff;
       margin: 0; padding: 2rem 1.25rem; }
#content { display: grid; grid-template-columns: minmax(13rem, 17rem) minmax(0, 75ch);
           column-gap: 3rem; max-width: none; margin: auto; }
h1 { grid-column: 1 / -1; }
#content > :not(h1):not(#table-of-contents) { grid-column: 2; }
h1, h2, h3 { font-family: 'Roboto Serif', serif; color: #172033; }
h1 { text-align: left; }
h2 { margin-top: 2.5rem; border-bottom: 1px solid #dce2eb;
     padding-bottom: .5rem; }
h3 { margin-top: 2rem; overflow-wrap: anywhere; }
p { margin: .8rem 0; }
a { color: #235ca8; }
#table-of-contents { grid-column: 1; grid-row: 2;
                     align-self: start; position: sticky; top: 1.5rem;
                     max-height: calc(100vh - 3rem); overflow-y: auto;
                     font-size: .95em; background: #f8fafc;
                     border: 1px solid #dce2eb; border-radius: 6px;
                     padding: .75rem 1rem; }
#table-of-contents ul { padding-left: 1.5rem; }
#table-of-contents a { text-decoration: none; overflow-wrap: anywhere; }
#table-of-contents a:hover { text-decoration: underline; }
pre, code { font-family: 'Roboto Mono', monospace; font-size: .9em;
            overflow-wrap: anywhere; }
pre { background: #f4f6f9; border: 1px solid #dce2eb; border-radius: 6px;
      padding: 1rem; overflow-x: auto; overflow-wrap: anywhere;
      box-shadow: none; }
code { background: #f4f6f9; padding: .1em .25em; border-radius: 3px; }
@media (max-width: 900px) {
  body { padding: 1.5rem 1rem; }
  #content { display: block; max-width: 75ch; }
  #table-of-contents { position: static; max-height: none; overflow: visible;
                       margin: 1.5rem 0 2.5rem; }
}
</style>"
  "Styles for the generated documentation page.")

(defun edocs--org-prose (text &optional symbol-links)
  "Turn docstring TEXT into an ordinary Org paragraph.
Escape Org syntax before adding markup for quoted symbol names.
SYMBOL-LINKS is an alist mapping uniquely defined symbol names to IDs."
  (let ((link-replacements nil)
        (link-number 0))
    (setq text (replace-regexp-in-string "`\\([[:alnum:]-]+\\)'" "=\\1=" text))
    ;; Protect links while escaping the rest of the prose.  Inserting the Org
    ;; link syntax first would cause the escaping below to escape the link.
    (setq text
          (replace-regexp-in-string
           "=\\([^=\n]+\\)="
           (lambda (match)
             (let* ((name (match-string 1 match))
                    (id (cdr (assoc name symbol-links)))
                    (token (format "\uE000%d\uE001" link-number)))
               (setq link-number (1+ link-number))
               (push (cons token (if id
                                     (format "[[#%s][=%s=]]" id name)
                                   match))
                     link-replacements)
               token))
           text t t))
  (setq text (replace-regexp-in-string "\\\\" "\\\u200b" text t t))
  ;; Break links, macros and export snippets before adding Org entities.
  (setq text (replace-regexp-in-string "[][{@]" "\\&\u200b" text))
  (setq text
        (replace-regexp-in-string
         "[*~=/+_<>|:]"
         (lambda (character)
           (concat "\\"
                   (cdr (assoc character
                               '(("*" . "ast")
                                 ("~" . "tilde") ("=" . "equal")
                                 ("/" . "slash") ("+" . "plus")
                                 ("_" . "under") ("<" . "lt")
                                 (">" . "gt") ("|" . "vert")
                                 (":" . "colon"))))
                   "{}"))
         text t t))
  (when (string-match-p "\\`\\(?:[#:]\\|-[ \t]\\|[0-9]+[.)][ \t]\\)" text)
    (setq text (concat "\u200b" text)))
  (dolist (replacement link-replacements text)
    (setq text (replace-regexp-in-string
                (regexp-quote (car replacement))
                (cdr replacement) text t t)))))

(defun edocs--struct-source-without-docstring (source)
  "Return SOURCE with a `cl-defstruct' docstring removed.
Use the reader to identify the third form element, rather than matching the
docstring text, so escaped quotes and arbitrary formatting are preserved."
  (condition-case nil
      (with-temp-buffer
        (insert source)
        (goto-char (point-min))
        (forward-char 1)
        (read (current-buffer))
        (read (current-buffer))
        (forward-comment (point-max))
        (let ((doc-start (point)))
          (when (stringp (read (current-buffer)))
            (let* ((doc-end (point))
                   (line-start (line-beginning-position))
                   (remove-start
                    (if (string-match-p
                         "\\`[ \\t]*\\'"
                         (buffer-substring-no-properties line-start doc-start))
                        line-start
                      doc-start))
                   (remove-end doc-end))
              (goto-char remove-end)
              (when (looking-at "[ \\t]*\\n")
                (setq remove-end (match-end 0)))
              (delete-region remove-start remove-end)
              (goto-char remove-start)
              (delete-blank-lines)))
          (buffer-string)))
    (error source)))

(defun edocs--headline-id (text)
  "Return a stable HTML ID derived from headline TEXT."
  (let ((id (replace-regexp-in-string "[^[:alnum:]_-]+" "-" text)))
    (setq id (replace-regexp-in-string "\\`[-_]+\\|[-_]+\\'" "" id))
    (if (string-empty-p id) "heading" id)))

(defun edocs--assign-entry-ids (sections)
  "Add unique `:id' properties to definition entries in SECTIONS.
SECTIONS is an alist of section names and entry lists.  Prefer the symbol
name as the ID, adding a section suffix only when the name is duplicated."
  (let ((counts (make-hash-table :test #'equal))
        (entries nil))
    (dolist (section sections)
      (dolist (entry (cdr section))
        (let ((base (edocs--headline-id (plist-get entry :name))))
          (push (list entry (car section) base) entries)
          (puthash base (1+ (gethash base counts 0)) counts))))
    (let ((used (make-hash-table :test #'equal)))
      (dolist (item (nreverse entries))
        (pcase-let ((`(,entry ,section ,base) item))
          (let* ((candidate (if (> (gethash base counts) 1)
                                (format "%s-%s" base section)
                              base))
                 (suffix 1)
                 (id candidate))
            (while (gethash id used)
              (setq suffix (1+ suffix)
                    id (format "%s-%d" candidate suffix)))
            (puthash id t used)
            (setf (plist-get entry :id) id)))))))

(defun edocs--symbol-links (sections)
  "Return links for uniquely defined symbols in SECTIONS.
SECTIONS is an alist of section names and definition entries.  Each returned
element is a symbol name and its assigned headline ID."
  (let ((counts (make-hash-table :test #'equal))
        (ids (make-hash-table :test #'equal)))
    (dolist (section sections)
      (dolist (entry (cdr section))
        (let ((name (plist-get entry :name)))
          (puthash name (1+ (gethash name counts 0)) counts)
          (puthash name (plist-get entry :id) ids))))
    (let (links)
      (maphash (lambda (name count)
                 (when (= count 1)
                   (push (cons name (gethash name ids)) links)))
               counts)
      links)))

(defun edocs--commentary ()
  "Return the source buffer's top-level Commentary section.
Strip comment prefixes and return nil when no Commentary section exists."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^;;; Commentary:[ \t]*$" nil t)
      (let ((start (line-beginning-position 2))
            end)
        (goto-char start)
        (setq end (if (re-search-forward "^;;; Code:[ \t]*$" nil t)
                      (line-beginning-position)
                    (point-max)))
        (let ((text (buffer-substring-no-properties start end)))
          (setq text
                (mapconcat
                 (lambda (line)
                   (replace-regexp-in-string "\\`[ \t]*;;[ \t]?" "" line))
                 (split-string text "\n" nil)
                 "\n"))
          (string-trim text))))))

(defun edocs--definitions ()
  "Read function and variable definitions from the current buffer.
Return (FUNCTIONS VARIABLES STRUCTURES), with definition plist entries.
Read source docstrings and struct source forms without evaluating forms or
consulting the session."
  (let (functions variables structures)
    (cl-labels
        ((record (name doc args variablep &optional source)
           (when (and (symbolp name) name
                      (not (string-match-p "--" (symbol-name name))))
             (let ((entry (append (list :name (symbol-name name)
                                        :doc (if (stringp doc) doc
                                               "No documentation available.")
                                        :args args
                                        :id nil)
                                  (when source (list :source source)))))
               (cond ((eq variablep 'structure) (push entry structures))
                     (variablep (push entry variables))
                     (t (push entry functions))))))
         (visit (form &optional source)
           (when (consp form)
             (pcase (car form)
               ((or 'defun 'defmacro 'defsubst
                    'cl-defun 'cl-defmacro 'cl-defsubst 'cl-defgeneric)
                (record (nth 1 form) (nth 3 form) (nth 2 form) nil))
               ('cl-defmethod
                ;; Method qualifiers precede the specialized argument list.
                (let ((body (cddr form)))
                  (while (and body (not (listp (car body))))
                    (setq body (cdr body)))
                  (record (nth 1 form) (cadr body) (car body) nil)))
               ('cl-defstruct
                (let ((name (nth 1 form)))
                  (record (if (consp name) (car name) name)
                          (nth 2 form) nil 'structure
                          (when source
                            (edocs--struct-source-without-docstring source)))))
               ((or 'defvar 'defconst 'defcustom 'defvar-local)
                (record (nth 1 form) (nth 3 form) nil t))
               ('define-derived-mode
                (record (nth 1 form) (nth 4 form) nil nil))
               ('define-minor-mode
                (record (nth 1 form) (nth 2 form) nil nil)
                (record (nth 1 form) (nth 2 form) nil t))
               ((or 'progn 'eval-and-compile 'eval-when-compile)
                (mapc #'visit (cdr form)))))))
      (save-excursion
        (save-restriction
          (widen)
          (goto-char (point-min))
          (forward-comment (point-max))
          (while (not (eobp))
            (let ((start (point)))
              (condition-case err
                  (let ((form (read (current-buffer))))
                    (visit form (buffer-substring-no-properties start (point))))
                (error
                 (user-error "Cannot read definition at position %d: %s"
                             start (error-message-string err)))))
            (forward-comment (point-max))))))
    (list (sort functions (lambda (a b)
                            (string-lessp (plist-get a :name)
                                          (plist-get b :name))))
          (sort variables (lambda (a b)
                            (string-lessp (plist-get a :name)
                                          (plist-get b :name))))
          (sort structures (lambda (a b)
                             (string-lessp (plist-get a :name)
                                           (plist-get b :name)))))))

(defun edocs--insert-entry (entry &optional symbol-links)
  "Insert an Org entry for definition plist ENTRY.
Render an original struct source form when ENTRY contains :source.
SYMBOL-LINKS contains links for uniquely defined symbols."
  (let* ((name (plist-get entry :name))
         (id (plist-get entry :id))
         (source (plist-get entry :source))
         (args (plist-get entry :args)))
    (insert "** " (edocs--org-prose
            (replace-regexp-in-string "[\n\r]" " " name))
            "\n:PROPERTIES:\n:CUSTOM_ID: " id "\n:END:\n\n")
    (when source
      (insert "#+begin_example\n"
              (org-escape-code-in-string source)
              "\n#+end_example\n\n"))
    (when args
      (insert "#+begin_example\n"
              (org-escape-code-in-string (format "%s %S" name args))
              "\n#+end_example\n\n"))
  (dolist (paragraph (split-string (string-trim (plist-get entry :doc)
                                                   "\n+" "\n+")
                                  "\n[ \t]*\n+" t))
    (if (string-match-p "\\`[ \t]" paragraph)
        (insert "#+begin_example\n"
                (org-escape-code-in-string paragraph)
                "\n#+end_example\n\n")
      (insert (edocs--org-prose paragraph symbol-links) "\n\n")))))

(defun edocs--insert-commentary (commentary symbol-links)
  "Insert COMMENTARY as introductory Org prose.
SYMBOL-LINKS contains links for uniquely defined symbols."
  (dolist (paragraph (split-string commentary "\n[ \t]*\n+" t))
    (insert (edocs--org-prose paragraph symbol-links) "\n\n")))

;;;###autoload
(defun edocs ()
  "Export documentation from the current Emacs Lisp file and browse it.
Read definitions and literal docstrings from the entire current buffer,
including unsaved edits, without evaluating the file.  Skip names
containing \"--\".  Include function, generic function, method, macro,
variable, customization, struct, and mode definitions, including those
in top-level progn and compile
wrappers.  Quoted forms and definitions generated at runtime are omitted.

Write a unique Org file and its HTML export under /tmp, open the HTML
in the browser, and return the HTML filename."
  (interactive)
  (unless (derived-mode-p 'emacs-lisp-mode 'lisp-interaction-mode)
    (user-error "Run edocs in an Emacs Lisp buffer"))
  (let* ((definitions (edocs--definitions))
         (functions (car definitions))
         (variables (cadr definitions))
         (structures (nth 2 definitions))
         (commentary (edocs--commentary)))
    (let* ((sections `((structures . ,structures)
                       (variables . ,variables)
                       (functions . ,functions)))
           (symbol-links (progn
                           (edocs--assign-entry-ids sections)
                           (edocs--symbol-links sections))))
    (let ((org-file (make-temp-file "/tmp/edocs-" nil ".org"))
          (org-export-use-babel nil)
          html-file)
      (with-temp-buffer
        (insert "#+TITLE: Emacs documentation\n"
                "#+OPTIONS: toc:2 num:nil ^:nil author:nil date:nil\n\n"
                "Autogenerated documentation for the current Emacs Lisp file.\n\n"
                "")
        (when commentary
          (edocs--insert-commentary commentary symbol-links))
        (when structures
          (insert "* Structures\n"
                  ":PROPERTIES:\n:CUSTOM_ID: structures\n:END:\n\n")
          (dolist (structure structures)
            (edocs--insert-entry structure symbol-links)))
        (when variables
          (insert "* Variables\n"
                  ":PROPERTIES:\n:CUSTOM_ID: variables\n:END:\n\n")
          (dolist (symbol variables)
            (edocs--insert-entry symbol symbol-links)))
        (when functions
          (insert "* Functions\n"
                  ":PROPERTIES:\n:CUSTOM_ID: functions\n:END:\n\n")
          (dolist (symbol functions)
            (edocs--insert-entry symbol symbol-links)))
        (let ((coding-system-for-write 'utf-8-unix))
          (write-region (point-min) (point-max) org-file nil 'silent))
        ;; This is a disposable export buffer, not a visiting file buffer.
        ;; The export destination is supplied explicitly below.
        (set-buffer-modified-p nil)
        (org-mode)
        (message "Exporting documentation to HTML...")
        (setq html-file
              (org-export-to-file
               'html (concat (file-name-sans-extension org-file) ".html")
               nil nil nil nil
               ;; Keep personal site templates out of standalone documentation.
               `(:html-head ,edocs--html-style
                 :html-head-extra ""
                 :html-head-include-default-style nil
                 :html-head-include-scripts nil
                 :html-preamble nil
                 :html-postamble nil))))
      (browse-url-of-file html-file)
      (message "Exported %d functions, %d variables, and %d structures to %s"
               (length functions) (length variables) (length structures)
               html-file)
      html-file))))

(provide 'edocs)
;;; edocs.el ends here
