;;; phps-mode.el --- Major mode for PHP with Semantic integration -*- lexical-binding: t -*-

;; Copyright (C) 2018-2019  Free Software Foundation, Inc.

;; Author: Christian Johansson <christian@cvj.se>
;; Maintainer: Christian Johansson <christian@cvj.se>
;; Created: 3 Mar 2018
;; Modified: 26 Sep 2019
;; Version: 0.3.2
;; Keywords: tools, convenience
;; URL: https://github.com/cjohansson/emacs-phps-mode

;; Package-Requires: ((emacs "26"))

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2, or (at
;; your option) any later version.

;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.


;;; Commentary:

;; A major-mode that uses original PHP lexer tokens for syntax coloring and indentation making it easier to spot errors in syntax.  Also includes full support for PSR-1 and PSR-2 indentation, imenu.  Improved syntax table in comparison with old PHP major-mode.

;; Please see README.md from the same repository for extended documentation.



;;; Code:

;; NOTE use wisent-parse-toggle-verbose-flag and (semantic-debug) to debug parsing

(require 'phps-mode-flymake)
(require 'phps-mode-functions)
(require 'phps-mode-lexer)
(require 'phps-mode-semantic)
(require 'phps-mode-syntax-table)
(require 'phps-mode-tags)
(require 'semantic)

(defvar phps-mode-use-electric-pair-mode t
  "Whether or not we want to use electric pair mode.")

(defvar phps-mode-use-transient-mark-mode t
  "Whether or not we want to use transient mark mode.")

(defvar phps-mode-use-psr-2 t
  "Whether to use PSR-2 guidelines for white-space or not.")

(defvar phps-mode-idle-interval 1
  "Idle seconds before running the incremental lexer.")

(defvar phps-mode-flycheck-applied nil
  "Boolean flag whether flycheck configuration has been applied or not.")

(defvar phps-mode-inline-mmm-submode nil
  "Symbol declaring what mmm-mode to use as submode in inline areas.")

(defvar phps-mode-runtime-debug nil
  "Whether or not to use runtime debugging.")

(defun phps-mode-runtime-debug-message (message)
  "Output MESSAGE if flag is on."
  (when phps-mode-runtime-debug
    (let ((buffer (get-buffer-create "*PHPs Debug Messages*")))
      (with-current-buffer buffer
        (save-excursion
          (goto-char (point-max))
          (insert message)
          (insert "\n"))))))

(defun phps-mode-get-syntax-table ()
  "Get syntax table."
  phps-mode-syntax-table)

(defvar phps-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c /") #'comment-region)
    (define-key map (kbd "C-c DEL") #'uncomment-region)
    (define-key map (kbd "C-c C-r") #'phps-mode-lexer-run)
    (define-key map (kbd "C-c C-f") #'phps-mode-format-buffer)
    (define-key map (kbd "C-c C-p") #'phps-mode-functions-process-current-buffer)
    map)
  "Keymap for `phps-mode'.")

;;;###autoload
(defun phps-mode-format-buffer ()
  "Format current buffer according to PHPs mode."
  (interactive)
  (let ((old-buffer-contents (buffer-substring-no-properties (point-min) (point-max)))
        (old-buffer (current-buffer))
        (temp-buffer (generate-new-buffer "*PHPs Formatting*"))
        (new-buffer-contents ""))
    (save-excursion
      (switch-to-buffer temp-buffer)
      (insert old-buffer-contents)
      (phps-mode)
      (indent-region (point-min) (point-max))
      (setq new-buffer-contents (buffer-substring-no-properties (point-min) (point-max)))
      (kill-buffer)
      (switch-to-buffer old-buffer)
      (delete-region (point-min) (point-max))
      (insert new-buffer-contents))))

(define-derived-mode phps-mode prog-mode "PHPs"
  "Major mode for PHP with Semantic integration."

  ;; Skip comments when navigating via syntax-table
  (setq-local parse-sexp-ignore-comments t)

  ;; Key-map
  (use-local-map phps-mode-map)

  ;; Syntax table
  (set-syntax-table phps-mode-syntax-table)

  (when phps-mode-use-transient-mark-mode
    ;; NOTE: These are required for wrapping region functionality
    (transient-mark-mode))

  ;; TODO Add this as a menu setting similar to php-mode?
  (when phps-mode-use-electric-pair-mode
    (electric-pair-local-mode))

  ;; Font lock
  ;; This makes it possible to have full control over syntax coloring from the lexer
  (setq-local font-lock-keywords-only nil)
  (setq-local font-lock-defaults '(nil t))

  ;; Flymake TODO
  ;; (phps-mode-flymake-init)

  ;; Flycheck
  ;; Add support for flycheck PHP checkers: PHP, PHPMD and PHPCS here
  ;; Do it once but only if flycheck is available
  (when (and (fboundp 'flycheck-add-mode)
             (not phps-mode-flycheck-applied))
    (flycheck-add-mode 'php 'phps-mode)
    (flycheck-add-mode 'php-phpmd 'phps-mode)
    (flycheck-add-mode 'php-phpcs 'phps-mode)
    (setq phps-mode-flycheck-applied t))

  ;; Custom indentation
  ;; Indent-region will call this on each line of selected region
  (setq-local indent-line-function #'phps-mode-functions-indent-line)

  ;; Custom Imenu
  (setq-local imenu-create-index-function #'phps-mode-functions-imenu-create-index)

  ;; Should we follow PSR-2?
  (when phps-mode-use-psr-2

    ;; Code MUST use an indent of 4 spaces
    (setq-local tab-width 4)

    ;; MUST NOT use tabs for indenting
    (setq-local indent-tabs-mode nil))

  ;; Reset flags
  (setq-local phps-mode-functions-allow-after-change t)
  (setq-local phps-mode-functions-buffer-changes nil)
  (setq-local phps-mode-functions-buffer-changes nil)
  (setq-local phps-mode-functions-idle-timer nil)
  (setq-local phps-mode-functions-lines-indent nil)
  (setq-local phps-mode-functions-imenu nil)
  (setq-local phps-mode-functions-processed-buffer nil)
  (setq-local phps-mode-lexer-buffer-length nil)
  (setq-local phps-mode-lexer-buffer-contents nil)
  (setq-local phps-mode-lexer-tokens nil)
  (setq-local phps-mode-lexer-states nil)
  (setq-local phps-mode-functions-allow-after-change t)

  ;; Make (comment-region) and (uncomment-region) work
  (setq-local comment-region-function #'phps-mode-functions-comment-region)
  (setq-local uncomment-region-function #'phps-mode-functions-uncomment-region)
  (setq-local comment-start "// ")
  (setq-local comment-end "")

  ;; Support for change detection
  (add-hook 'after-change-functions #'phps-mode-functions-after-change 0 t)

  ;; Lexer
  (setq-local semantic-lex-syntax-table phps-mode-syntax-table)

  ;; Semantic
  (setq-local semantic-lex-analyzer #'phps-mode-lexer-lex)

  ;; Set semantic-lex initializer function
  (add-hook 'semantic-lex-reset-functions #'phps-mode-lexer-setup 0 t)

  ;; Initial run of lexer
  (phps-mode-lexer-run)

  ;; Run semantic functions for new buffer
  (semantic-new-buffer-fcn)

  ;; Disable idle scheduler since we have customized this feature
  (when (boundp 'semantic-idle-scheduler-mode)
    (setq semantic-idle-scheduler-mode nil))

  ;; Wisent LALR parser TODO
  ;; (phps-mode-tags-init)
  )

(provide 'phps-mode)
;;; phps-mode.el ends here
