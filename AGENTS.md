# Preferences
- Use `setq-default` instead of `setq` for setting variables in init.el

# Finding Documentation

## Emacs Built-in Help
- `C-h f <function>` — describe a function and its docstring
- `C-h v <variable>` — describe a variable and its current value
- `C-h k <key>` — describe what a keybinding does
- `C-h m` — describe the current major mode and its keybindings
- `M-x info` — browse Info manuals (Emacs, Elisp reference, and installed packages)

## Package Source Files
Installed packages live in `elpa/`. Each package directory contains `.el` source
files with inline docstrings and comments. Example:
- `elpa/evil-<version>/evil.el` — entry point for evil-mode
- `elpa/vertico-<version>/vertico.el` — entry point for vertico

## MELPA / Package Homepages
Most packages are installed from MELPA. To find a package's README, changelog,
or GitHub repo, search for it at https://melpa.org or look at the URL in the
package's `-pkg.el` file (`:url` field).

## Custom Lisp
Local packages live under `lisp/` and are loaded via `load-path`:
- `lisp/disasm.el` — disassembly helper
- `lisp/ttx-mode/ttx.el` — ttx major mode
