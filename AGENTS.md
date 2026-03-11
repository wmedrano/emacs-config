# Preferences
- Use `setq-default` instead of `setq` for setting variables in init.el

# Finding Documentation

## Package Source Files
Installed packages live in `elpa/`. Each package directory contains `.el` source
files with inline docstrings and comments. Example:
- `elpa/evil-<version>/evil.el` — entry point for evil-mode
- `elpa/vertico-<version>/vertico.el` — entry point for vertico


## Custom Lisp
Local packages live under `lisp/` and are loaded via `load-path`:
- `lisp/disasm.el` — disassembly helper
- `lisp/consult-agent-shell.el` — Consult interface for agent-shell
- `lisp/ttx-mode/ttx.el` — ttx major mode
