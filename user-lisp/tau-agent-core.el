;;; tau-agent-core.el --- Shared agent types -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Small tool registry and JSON helpers, independent of the conversation UI.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'subr-x)

(defgroup tau-agent nil "A small coding agent." :group 'applications)

(cl-defstruct (tau-agent-tool (:constructor tau-agent-make-tool))
  "A FUNCTION with named ARGS, optionally using an ASYNC callback."
  name description args function async category)

(defun tau-agent--json-read (text)
  "Decode JSON TEXT to plists and vectors."
  (json-parse-string text :object-type 'plist :array-type 'array
                     :null-object nil :false-object :json-false))

(defun tau-agent--json (value)
  "Encode VALUE as JSON."
  (let ((json-false :json-false)) (json-encode value)))

(defun tau-agent--schema (value)
  "Convert Lisp schema VALUE to a JSON-compatible schema."
  (cond ((vectorp value) (vconcat (mapcar #'tau-agent--schema value)))
        ((consp value) (mapcar #'tau-agent--schema value))
        ((memq value '(string number integer object array boolean))
         (symbol-name value))
        (t value)))

(defun tau-agent-tool-schema (tool)
  "Return the Responses function schema for TOOL."
  (let (properties required)
    (dolist (arg (tau-agent-tool-args tool))
      (let ((spec (copy-sequence arg)) (name (plist-get arg :name)))
        (unless (plist-get spec :optional) (push name required))
        (cl-remf spec :name)
        (cl-remf spec :optional)
        (setq properties
              (append properties (list (intern (concat ":" name))
                                       (tau-agent--schema spec))))))
    (list :type "function" :name (tau-agent-tool-name tool)
          :description (tau-agent-tool-description tool)
          :parameters (list :type "object"
                            :properties (or properties (make-hash-table))
                            :required (vconcat (nreverse required))))))

(provide 'tau-agent-core)
;;; tau-agent-core.el ends here
