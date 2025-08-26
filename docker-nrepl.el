;;; docker-nrepl.el --- Connect to nREPL servers in Docker containers -*- lexical-binding: t; -*-

;; Copyright (C) 2025 Andrey Subbotin

;; Author: Andrey Subbotin <andrey@subbotin.me>
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1") (cider "1.0"))
;; Keywords: docker, clojure, nrepl, tools
;; URL: https://github.com/eploko/docker-nrepl

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This package enables seamless connections to nREPL servers running inside
;; Docker containers.  It allows selecting containers interactively,
;; remembers the last container used, and can associate specific containers
;; with projects.
;;
;; Usage:
;;
;; (use-package docker-nrepl
;;   :after cider
;;   :config
;;   (docker-nrepl-setup))
;;
;; Then use `docker-nrepl-connect' (bound to C-c M-c by default) to connect
;; to an nREPL server in a Docker container.

;;; Code:

(require 'cider)
(require 'project)

;;; Customization

(defgroup docker-nrepl nil
  "Connect to nREPL servers in Docker containers."
  :prefix "docker-nrepl-"
  :group 'applications)

(defcustom docker-nrepl-internal-port 7888
  "Default internal port for nREPL servers in Docker containers."
  :type 'integer
  :group 'docker-nrepl)

(defcustom docker-nrepl-data-file
  (expand-file-name "docker-nrepl-data.el" user-emacs-directory)
  "File to store docker-nrepl data between Emacs sessions."
  :type 'file
  :group 'docker-nrepl)

(defcustom docker-nrepl-bind-keys t
  "Whether to bind the default keys for docker-nrepl commands."
  :type 'boolean
  :group 'docker-nrepl)

;;; Variables

(defvar docker-nrepl-last-container nil
  "The last Docker container selected for nREPL connection.")

(defvar docker-nrepl-container-history nil
  "History of Docker containers used for nREPL connections.")

(defvar docker-nrepl-project-containers (make-hash-table :test 'equal)
  "Hash table mapping project paths to their associated Docker containers.")

;;; Core functions

(defun docker-nrepl--get-containers ()
  "Get a list of running Docker containers as (name . id) pairs."
  (let* ((docker-output (shell-command-to-string "docker ps --format '{{.Names}}|{{.ID}}'"))
         (lines (split-string docker-output "\n" t)))
    (mapcar (lambda (line)
              (let ((parts (split-string line "|" t)))
                (cons (car parts) (cadr parts))))
            lines)))

(defun docker-nrepl--find-port-mapping (container-id port)
  "Find the host port that maps to PORT for CONTAINER-ID."
  (let ((docker-output
         (shell-command-to-string
          (format "docker port %s %d" container-id port))))
    (when (string-match "0.0.0.0:\\([0-9]+\\)" docker-output)
      (match-string 1 docker-output))))

;; Marginalia integration
(defun docker-nrepl--marginalia-annotate (cand)
  "Provide Marginalia annotation for Docker container CAND."
  (when-let* ((containers (docker-nrepl--get-containers))
              (container (assoc cand containers))
              (container-id (cdr container)))
    (let* ((image-info (shell-command-to-string 
                        (format "docker inspect --format '{{.Config.Image}}' %s" container-id)))
           (status-info (shell-command-to-string 
                         (format "docker inspect --format '{{.State.Status}}' %s" container-id)))
           (image (string-trim image-info))
           (status (string-trim status-info)))
      (marginalia--fields
       (container-id :face 'font-lock-comment-face)
       (image :face 'font-lock-string-face :truncate 1.0)
       (status :face 'success)))))

;; Create completion table with proper metadata
(defun docker-nrepl--completion-table ()
  "Create a completion table for Docker containers with proper category."
  (let ((containers (mapcar #'car (docker-nrepl--get-containers))))
    (lambda (string pred action)
      (if (eq action 'metadata)
          '(metadata (category . docker-container))
        (complete-with-action action containers string pred)))))

;;;###autoload
(defun docker-nrepl-select-container (&optional prompt)
  "Select a Docker container interactively with completion.
Return (name . id) pair. With optional PROMPT, use that instead of default."
  (let* ((prompt (or prompt "Select Docker container: "))
         (completion-table (docker-nrepl--completion-table))
         (selected-name (completing-read prompt
                                         completion-table
                                         nil t nil
                                         'docker-nrepl-container-history
                                         (when docker-nrepl-last-container
                                           (car docker-nrepl-last-container))))
         (containers (docker-nrepl--get-containers)))
    (setq docker-nrepl-last-container (assoc selected-name containers))
    docker-nrepl-last-container))

(defun docker-nrepl-connect--with-retry (force-select)
  "Helper function that implements the retry logic for docker-nrepl-connect.
FORCE-SELECT when non-nil forces container selection dialog."
  (let* ((container (if (or force-select (null docker-nrepl-last-container))
                        (docker-nrepl-select-container)
                      docker-nrepl-last-container))
         (container-id (cdr container))
         (container-name (car container))
         (host-port (docker-nrepl--find-port-mapping container-id docker-nrepl-internal-port)))
    (if host-port
        (progn
          (message "Connecting to nREPL in container %s (%s) on port %s"
		   container-name container-id host-port)
          (cider-connect-clj (list :host "localhost" :port host-port)))
      ;; Port not found - ask user if they want to try another container
      (when (yes-or-no-p
	     (format (concat "Could not find port %d mapping for container %s (%s). "
			     "Would you like to choose another container? ")
                     docker-nrepl-internal-port container-name container-id))
        ;; User wants to try again - recurse with force-select=t
        (docker-nrepl-connect--with-retry t)))))

;;;###autoload
(defun docker-nrepl-connect (&optional arg)
  "Connect to nREPL running in a Docker container.
When called with prefix argument ARG (C-u), prompt for container selection.
Otherwise, use the last selected container if available."
  (interactive "P")
  (docker-nrepl-connect--with-retry arg))

;;;###autoload
(defun docker-nrepl-set-project-container ()
  "Associate current project with a Docker container for nREPL connections."
  (interactive)
  (if-let ((project (project-current t)))
      (let* ((project-root (project-root project))
             (container (docker-nrepl-select-container 
                         (format "Select container for project %s: " 
                                 (file-name-nondirectory (directory-file-name project-root))))))
        (puthash project-root container docker-nrepl-project-containers)
        (setq docker-nrepl-last-container container)
        (message "Project %s associated with container %s" 
                 (file-name-nondirectory (directory-file-name project-root))
                 (car container)))
    (user-error "Not in a project")))

;;;###autoload
(defun docker-nrepl-connect-project (&optional arg)
  "Connect to the Docker container associated with the current project.
With prefix ARG, prompt for container selection first."
  (interactive "P")
  (if-let ((project (project-current t)))
      (let* ((project-root (project-root project))
             (container (gethash project-root docker-nrepl-project-containers)))
        (if (and container (not arg))
            (progn
              (setq docker-nrepl-last-container container)
              (docker-nrepl-connect nil))
          (docker-nrepl-connect t)))
    (user-error "Not in a project")))

;;; Persistence

(defun docker-nrepl-save-data ()
  "Save container and project associations to a file."
  (interactive)
  (let ((data `((last-container . ,docker-nrepl-last-container)
                (container-history . ,docker-nrepl-container-history)
                (project-containers . ,(let ((hash-data nil))
                                         (maphash (lambda (k v) (push (cons k v) hash-data)) 
                                                  docker-nrepl-project-containers)
                                         hash-data)))))
    (with-temp-file docker-nrepl-data-file
      (prin1 data (current-buffer)))
    (message "Saved docker-nrepl data to %s" docker-nrepl-data-file)))

(defun docker-nrepl-load-data ()
  "Load container and project associations from a file."
  (interactive)
  (when (file-exists-p docker-nrepl-data-file)
    (with-temp-buffer
      (insert-file-contents docker-nrepl-data-file)
      (goto-char (point-min))
      (let ((data (read (current-buffer))))
        ;; Load last container
        (when-let ((last-container (alist-get 'last-container data)))
          (setq docker-nrepl-last-container last-container))
        
        ;; Load container history
        (when-let ((history (alist-get 'container-history data)))
          (setq docker-nrepl-container-history history))
        
        ;; Load project containers
        (when-let ((projects (alist-get 'project-containers data)))
          (setq docker-nrepl-project-containers (make-hash-table :test 'equal))
          (dolist (pair projects)
            (puthash (car pair) (cdr pair) docker-nrepl-project-containers)))
        
        (message "Loaded docker-nrepl data from %s" docker-nrepl-data-file)))
    t))

;;; Hooks and setup

(defun docker-nrepl--kill-emacs-hook ()
  "Save docker-nrepl data when Emacs is killed."
  (docker-nrepl-save-data))

;; Register with Marginalia if available
(defun docker-nrepl--setup-marginalia ()
  "Set up Marginalia integration for Docker containers."
  (when (and (boundp 'marginalia-annotators)
             (fboundp 'marginalia-mode))
    ;; Add our annotator to the marginalia annotators list
    (unless (assq 'docker-container marginalia-annotators)
      (push '(docker-container docker-nrepl--marginalia-annotate builtin none)
            marginalia-annotators))))

;;;###autoload
(defun docker-nrepl-setup ()
  "Set up docker-nrepl.
This loads saved data and sets up hooks and keybindings."
  (interactive)
  ;; Load saved data
  (docker-nrepl-load-data)
  
  ;; Set up hooks
  (add-hook 'kill-emacs-hook #'docker-nrepl--kill-emacs-hook)
  
  ;; Set up Marginalia integration
  (docker-nrepl--setup-marginalia)
  
  ;; Set up keybindings if enabled
  (when docker-nrepl-bind-keys
    ;; Replace the default cider-connect binding
    (define-key clojure-mode-map (kbd "C-c M-c") #'docker-nrepl-connect)
    (define-key cider-mode-map (kbd "C-c M-c") #'docker-nrepl-connect)
    
    ;; Add project-specific binding
    (when (boundp 'project-prefix-map)
      (define-key project-prefix-map (kbd "C-c") #'docker-nrepl-connect-project))))

(provide 'docker-nrepl)
;;; docker-nrepl.el ends here
