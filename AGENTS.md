# Preferences
- Use `setq-default` instead of `setq` for setting variables in init.el

# Finding Documentation

## Package Source Files
Installed packages live in `elpa/`.
- Each package directory contains `.el` source files with inline docstrings and comments. Example:
  - `elpa/evil-<version>/evil.el` — entry point for evil-mode
  - `elpa/vertico-<version>/vertico.el` — entry point for vertico
- `elpa` is technically in .gitignore so tools like `rg` may skip these files.
  - Can be overcome with (cd elpa/ && rg '<thing>')


## Custom Lisp
Local packages live under `lisp/` and are loaded via `load-path`:
- `lisp/disasm.el` — disassembly helper
- `lisp/consult-agent-shell.el` — Consult interface for agent-shell
- `lisp/project-monorepo.el` — monorepo-aware project detection
- `lisp/ttx-mode/ttx-mode.el` — ttx major mode
