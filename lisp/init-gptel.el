;;; init-gptel.el --- gptel configuration (Ollama / OpenRouter) -*- lexical-binding: t; -*-
;;; Commentary:
;;; gptel backend and model configuration.
;;; Code:

(defvar openrouter-backend
  (when-let* ((key (getenv "OPENROUTER_API_KEY")))
    (gptel-make-openai "OpenRouter"
      :host "openrouter.ai"
      :endpoint "/api/v1/chat/completions"
      :stream t
      :key key
      :models '(qwen/qwen3.6-35b-a3b
                nvidia/nemotron-3-super-120b-a12b:free
                deepseek/deepseek-v4-flash
                deepseek/deepseek-v4-pro
                google/gemini-3-flash-preview
                z-ai/glm-5.1)))
  "OpenRouter gptel backend, nil when OPENROUTER_API_KEY is unset.")

(defvar ollama-backend
  (gptel-make-ollama "Ollama"
    :host "localhost:11434"
    :stream t
    :request-params '(think "low")
    :models '(qwen3.6:35b gemma4:26b gemma4:e4b glm-5.1:cloud deepseek-v4-flash:cloud))
  "Local Ollama gptel backend.")

(setq-default
 gptel-directives '((default . "")
                    (brief . "- You provide succint answer to programming questions.
- Assume that the person asking the question is already an experienced programmer.
- Provide brief answer with an example snippet.

* Example:

** Question

How do you define type hints in Python?

** Answer

Type hints use `:` for types and `->` for return values.

*** Example
```python
def add_numbers(a: int, b: int) -> int:
    return a + b
```

-   *`a: int`*: Parameter ~a~ should be an integer.
-   *`-> int`*: The function returns an integer."))
 gptel-backend (or openrouter-backend ollama-backend)
 gptel-model (if openrouter-backend 'qwen/qwen3.6-35b-a3b 'qwen3.6:35b)
 gptel-default-mode 'org-mode)

(provide 'init-gptel)
;;; init-gptel.el ends here