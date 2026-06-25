# project-monorepo.el

A `project.el` backend for monorepos where `project-try-vc` is too slow.

## Setup

Require the package in your init file:

```elisp
(require 'project-monorepo)
```

Add a `.dir-locals.el` at the root of your monorepo:

```lisp
((nil . ((monorepo-project-root    . "~/src/monorepo")
         (monorepo-project-subdirs . ("services/foo" "services/bar"))
         (vc-handled-backends      . nil))))
```

Disabling `vc-handled-backends` avoids expensive VCS probing across the tree.

- `monorepo-project-root` — path to the root directory. Use an absolute path (e.g., `"~/src/monorepo"`).
- `monorepo-project-subdirs` — list of subdirectory paths (relative to the root) to track files under.

The backend is wired into `project-find-functions` on load; no extra setup is required.

## Customizations

### File Caching

By default, `project-find-file` reuses a cached file list — files are discovered
once per session.  Call `M-x monorepo-project-clear-cache` to force a re-scan.

To disable the cache entirely:

```elisp
(setopt monorepo-project-use-cached-files nil)
```

### `monorepo-project-enter-hook` (hook, default `nil`)

Run when a monorepo is first entered.  Functions receive no arguments — call
`project-current` if you need the project struct.  Does **not** fire on cache
hits.

```elisp
(add-hook 'monorepo-project-enter-hook
          (lambda ()
            (message "Entered monorepo: %s" (project-root (project-current)))))
```
