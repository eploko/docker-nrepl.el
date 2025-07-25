# docker-nrepl

A simple Emacs package to connect to nREPL servers running inside Docker containers.

## Features

- Interactively select Docker containers from the running containers list
- Remembers the last container selected for quick reconnection
- Associates specific containers with projects
- Integrates with `vertico` and `marginalia` if available
- Persists container selections between Emacs sessions

## Installation

### Manual installation

1. Save `docker-nrepl.el` to your Emacs load path
2. Add to your init file:

```elisp
(require 'docker-nrepl)
(docker-nrepl-setup)
```

### With use-package

```elisp
(use-package docker-nrepl
  :straight (:host github :repo "eploko/docker-nrepl.el")
  ;; or... 
  ;; :load-path "/path/to/docker-nrepl.el"
  :after cider
  :config
  (docker-nrepl-setup))
```

### With straight.el and use-package

```elisp
(use-package docker-nrepl
  :straight (:host github :repo "eploko/docker-nrepl.el")
  :after cider
  :config
  (docker-nrepl-setup))
```

## Usage

### Basic usage

1. Start your nREPL server in a Docker container (listening on port 7888 internally)
2. Press `C-c M-c` to connect (the same keybinding as `cider-connect`)
   - First time: You'll be prompted to select a container
   - Subsequent times: Automatically connects to the last container used
3. To force selection of a different container, use `C-u C-c M-c`

### Project association

You can associate specific Docker containers with projects:

1. `M-x docker-nrepl-set-project-container` to associate the current project with a container
2. Use `C-u p C-c` (via project prefix map) to connect to the project's container

## Customization

The package can be customized through the following variables:

```elisp
;; Default internal port for nREPL (default: 7888)
(setq docker-nrepl-internal-port 7888)

;; File to store docker-nrepl data between Emacs sessions
(setq docker-nrepl-data-file (expand-file-name "docker-nrepl-data.el" user-emacs-directory))

;; Whether to bind the default keys
(setq docker-nrepl-bind-keys t)
```

Customize these before calling `docker-nrepl-setup`.

## Integration with other packages

### Vertico

Works out of the box with Vertico - gives you a nice completion interface for container selection.

### Marginalia

If Marginalia is loaded, container annotations will be shown in the completion buffer, including:
- Container ID
- Image name
- Container status

## Commands

| Command | Description |
|---------|-------------|
| `docker-nrepl-connect` | Connect to nREPL in a Docker container |
| `docker-nrepl-select-container` | Select a Docker container interactively |
| `docker-nrepl-set-project-container` | Associate current project with a container |
| `docker-nrepl-connect-project` | Connect to the container for current project |
| `docker-nrepl-save-data` | Save container and project associations |
| `docker-nrepl-load-data` | Load container and project associations |

## Requirements

- Emacs 27.1 or later
- CIDER 1.0 or later
- Docker command-line tool available in your PATH
