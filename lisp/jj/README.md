# jj.el

Emacs integration for the [Jujutsu](https://github.com/martinvonz/jj) version control system.

## Requirements

- Emacs 29.1 or later
- [Jujutsu](https://github.com/martinvonz/jj) installed and available on `PATH`
- `markdown-mode` (for description editing)

## Installation

Clone or download the repository and add it to your load path:

```emacs-lisp
(add-to-list 'load-path "/path/to/jj-el")
(require 'jj)
```

## Usage

| Command         | Description                                              |
|-----------------|----------------------------------------------------------|
| `jj-status`     | Show repository status                                   |
| `jj-log`        | Show commit log                                          |
| `jj-diff`       | Show current diff                                        |
| `jj-edit`       | Set a revision as the working-copy (`jj edit`)           |
| `jj-new`        | Create a new change on a given parent (`jj new`)         |
| `jj-describe`   | Edit the description of a revision                       |

## Modes

**`jj-status-mode`** — Read-only buffer for `jj status` output. Press `g` to refresh.

**`jj-log-mode`** — Read-only buffer for `jj log` output. Press `g` to refresh.

**`jj-describe-mode`** — Edit a change description (based on `markdown-mode`).

| Key       | Action                        |
|-----------|-------------------------------|
| `C-c C-c` | Accept and apply description  |
| `C-c C-d` | Show diff for the revision    |
| `C-c C-k` | Abort                         |

## Customization

**`jj-edit-show-log`** (default: `t`) — Show the log in a side window when running `jj-edit`.

**`jj-describe-diff-on-exit`** (default: `bury`) — What to do with the diff buffer after accepting or rejecting a describe edit. Options: `nil` (keep open), `bury`, `kill`.
