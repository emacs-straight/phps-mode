;;; phps-mode-functions.el --- Mode functions for PHPs -*- lexical-binding: t -*-

;; Copyright (C) 2018-2019  Free Software Foundation, Inc.

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
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.


;;; Commentary:


;;; Code:

(require 'subr-x)
(require 'phps-mode-lexer)

(autoload 'phps-mode-runtime-debug-message "phps-mode")

(require 'phps-mode-macros)

(defvar phps-mode-functions-allow-after-change t
  "Flag to tell us whether after change detection is enabled or not.")

(defvar phps-mode-functions-buffer-changes nil
  "A stack of buffer changes.")

(defvar phps-mode-functions-idle-timer nil
  "Timer object of idle timer.")

(defvar phps-mode-functions-imenu nil
  "The Imenu alist for current buffer, nil if none.")

(defvar phps-mode-functions-lines-indent nil
  "The indentation of each line in buffer, nil if none.")

(defvar phps-mode-functions-processed-buffer nil
  "Flag whether current buffer is processed or not.")

(defun phps-mode-functions-get-processed-buffer ()
  "Get flag for whether buffer is processed or not."
  phps-mode-functions-processed-buffer)

(defun phps-mode-functions-reset-processed-buffer ()
  "Reset flag for whether buffer is processed or not."
  (setq-local phps-mode-functions-processed-buffer nil))

(defun phps-mode-functions-process-current-buffer ()
  "Process current buffer, generate indentations and Imenu, trigger incremental lexer if we have change."
  (interactive)
  (phps-mode-debug-message (message "Process current buffer"))
  (when phps-mode-functions-idle-timer
    (phps-mode-debug-message (message "Trigger incremental lexer"))
    (phps-mode-lexer-run-incremental (current-buffer))
    (setq-local phps-mode-functions-processed-buffer nil))
  (if (not phps-mode-functions-processed-buffer)
      (progn
        (phps-mode-debug-message (message "Buffer is not processed"))
        (let ((processed (phps-mode-functions--process-tokens-in-string phps-mode-lexer-tokens (buffer-substring-no-properties (point-min) (point-max)))))
          (phps-mode-debug-message (message "Processed result: %s" processed))
          (setq-local phps-mode-functions-imenu (nth 0 processed))
          (setq-local phps-mode-functions-lines-indent (nth 1 processed)))
        (setq-local phps-mode-functions-processed-buffer t))
    (phps-mode-debug-message (message "Buffer is already processed"))))

(defun phps-mode-functions-get-moved-lines-indent (old-lines-indents start-line-number diff)
  "Move OLD-LINES-INDENTS from START-LINE-NUMBER with DIFF points."
  (let ((lines-indents (make-hash-table :test 'equal))
        (line-number 1))
    (when old-lines-indents
      (let ((line-indent (gethash line-number old-lines-indents))
            (new-line-number))
        (while line-indent

          (when (< line-number start-line-number)
            ;; (message "Added new indent 3 %s from %s to %s" line-indent line-number line-number)
            (puthash line-number line-indent lines-indents))

          (when (and (> diff 0)
                     (>= line-number start-line-number)
                     (< line-number (+ start-line-number diff)))
            ;; (message "Added new indent 2 %s from %s to %s" line-indent line-number line-number)
            (puthash line-number (gethash start-line-number old-lines-indents) lines-indents))

          (when (>= line-number start-line-number)
            (setq new-line-number (+ line-number diff))
            ;; (message "Added new indent %s from %s to %s" line-indent line-number new-line-number)
            (puthash new-line-number line-indent lines-indents))

          (setq line-number (1+ line-number))
          (setq line-indent (gethash line-number old-lines-indents))))
      lines-indents)))

(defun phps-mode-functions-move-imenu-index (start diff)
  "Moved imenu from START by DIFF points."
  (when phps-mode-functions-imenu
    (setq-local phps-mode-functions-imenu (phps-mode-functions-get-moved-imenu phps-mode-functions-imenu start diff))))

(defun phps-mode-functions-move-lines-indent (start-line-number diff)
  "Move lines indent from START-LINE-NUMBER with DIFF points."
  (when phps-mode-functions-lines-indent
    ;; (message "Moving line-indent index from %s with %s" start-line-number diff)
    (setq-local phps-mode-functions-lines-indent (phps-mode-functions-get-moved-lines-indent phps-mode-functions-lines-indent start-line-number diff))))
  
(defun phps-mode-functions-get-lines-indent ()
  "Return lines indent, process buffer if not done already."
  (phps-mode-functions-process-current-buffer)
  phps-mode-functions-lines-indent)

(defun phps-mode-functions-get-imenu ()
  "Return Imenu, process buffer if not done already."
  (phps-mode-functions-process-current-buffer)
  phps-mode-functions-imenu)

(defun phps-mode-functions-get-moved-imenu (old-index start diff)
  "Move imenu-index OLD-INDEX beginning from START with DIFF."
  (let ((new-index '()))

    (when old-index
      (if (and (listp old-index)
               (listp (car old-index)))
          (dolist (item old-index)
            (let ((sub-item (phps-mode-functions-get-moved-imenu item start diff)))
              (push (car sub-item) new-index)))
        (let ((item old-index))
          (let ((item-label (car item)))
            (if (listp (cdr item))
                (let ((sub-item (phps-mode-functions-get-moved-imenu (cdr item) start diff)))
                  (push `(,item-label . ,sub-item) new-index))
              (let ((item-start (cdr item)))
                (when (>= item-start start)
                  (setq item-start (+ item-start diff)))
                (push `(,item-label . ,item-start) new-index)))))))

    (nreverse new-index)))

(defun phps-mode-functions--get-lines-in-buffer (beg end)
  "Return the number of lines in buffer between BEG and END."
  (phps-mode-functions--get-lines-in-string (buffer-substring-no-properties beg end)))

(defun phps-mode-functions--get-lines-in-string (string)
  "Return the number of lines in STRING."
  (let ((lines-in-string 0)
        (start 0))
    (while (string-match "[\n\C-m]" string start)
      (setq start (match-end 0))
      (setq lines-in-string (1+ lines-in-string)))
    lines-in-string))

(defun phps-mode-functions--get-inline-html-indentation (inline-html indent tag-level curly-bracket-level square-bracket-level round-bracket-level)
  "Generate a list of indentation for each line in INLINE-HTML, working incrementally on INDENT, TAG-LEVEL, CURLY-BRACKET-LEVEL, SQUARE-BRACKET-LEVEL and ROUND-BRACKET-LEVEL."
  (phps-mode-debug-message
   (message "Calculating HTML indent for: '%s'" inline-html))

  ;; Add trailing newline if missing
  (unless (string-match "\n$" inline-html)
    (setq inline-html (concat inline-html "\n")))

  (let ((start 0)
        (indent-start indent)
        (indent-end indent)
        (line-indents nil)
        (first-object-on-line t)
        (first-object-is-nesting-decrease nil))
    (while (string-match "\\([\n\C-m]\\)\\|\\(<[a-zA-Z]+\\)\\|\\(</[a-zA-Z]+\\)\\|\\(/>\\)\\|\\(\\[\\)\\|\\()\\)\\|\\((\\)" inline-html start)
      (let* ((end (match-end 0))
             (string (substring inline-html (match-beginning 0) end)))

        (cond

         ((string= string "\n")

          (let ((temp-indent indent))
            (when first-object-is-nesting-decrease
              (phps-mode-debug-message
               (message "Decreasing indent with one since first object was a nesting decrease"))
              (setq temp-indent (1- indent))
              (when (< temp-indent 0)
                (setq temp-indent 0)))
            (push temp-indent line-indents))

          (setq indent-end (+ tag-level curly-bracket-level square-bracket-level round-bracket-level))
          (phps-mode-debug-message "Encountered a new-line")
          (if (> indent-end indent-start)
              (progn
                (phps-mode-debug-message
                  (message "Increasing indent since %s is above %s" indent-end indent-start))
                (setq indent (1+ indent)))
            (when (< indent-end indent-start)
              (phps-mode-debug-message
                (message "Decreasing indent since %s is below %s" indent-end indent-start))
              (setq indent (1- indent))
              (when (< indent 0)
                (setq indent 0))))

          (setq indent-start indent-end)
          (setq first-object-on-line t)
          (setq first-object-is-nesting-decrease nil))

         ((string= string "(")
          (setq round-bracket-level (1+ round-bracket-level)))
         ((string= string ")")
          (setq round-bracket-level (1- round-bracket-level)))

         ((string= string "[")
          (setq square-bracket-level (1+ square-bracket-level)))
         ((string= string "]")
          (setq square-bracket-level (1- square-bracket-level)))

         ((string= string "{")
          (setq curly-bracket-level (1+ curly-bracket-level)))
         ((string= string "}")
          (setq curly-bracket-level (1- curly-bracket-level)))

         ((string-match "<[a-zA-Z]+" string)
          (setq tag-level (1+ tag-level)))

         ((string-match "\\(</[a-zA-Z]+\\)\\|\\(/>\\)" string)
          (setq tag-level (1- tag-level)))

         )

        (when first-object-on-line
          (unless (string= string "\n")
            (setq first-object-on-line nil)
            (setq indent-end (+ tag-level curly-bracket-level square-bracket-level round-bracket-level))
            (when (< indent-end indent-start)
              (phps-mode-debug-message "First object was nesting decrease")
              (setq first-object-is-nesting-decrease t))))

        (setq start end)))
    (list (nreverse line-indents) indent tag-level curly-bracket-level square-bracket-level round-bracket-level)))

(defun phps-mode-functions--process-tokens-in-string (tokens string)
  "Generate indexes for imenu and indentation for TOKENS and STRING one pass.  Complexity: O(n)."
  (if tokens
      (progn
        (phps-mode-debug-message (message "\nCalculation indentation and imenu for all lines in buffer:\n\n%s" string))
        (let ((in-heredoc nil)
              (in-heredoc-started-this-line nil)
              (in-heredoc-ended-this-line nil)
              (in-inline-control-structure nil)
              (inline-html-indent 0)
              (inline-html-indent-start 0)
              (inline-html-tag-level 0)
              (inline-html-curly-bracket-level 0)
              (inline-html-square-bracket-level 0)
              (inline-html-round-bracket-level 0)
              (inline-html-is-whitespace nil)
              (first-token-is-inline-html nil)
              (after-special-control-structure nil)
              (after-special-control-structure-token nil)
              (after-extra-special-control-structure nil)
              (after-extra-special-control-structure-first-on-line nil)
              (switch-curly-stack nil)
              (switch-alternative-stack nil)
              (switch-case-alternative-stack nil)
              (curly-bracket-level 0)
              (round-bracket-level 0)
              (square-bracket-level 0)
              (alternative-control-structure-level 0)
              (in-concatenation nil)
              (in-concatenation-round-bracket-level nil)
              (in-concatenation-square-bracket-level nil)
              (in-concatenation-level 0)
              (column-level 0)
              (column-level-start 0)
              (tuning-level 0)
              (nesting-start 0)
              (nesting-end 0)
              (last-line-number 0)
              (first-token-on-line t)
              (line-indents (make-hash-table :test 'equal))
              (first-token-is-nesting-decrease nil)
              (token-number 1)
              (allow-custom-column-increment nil)
              (allow-custom-column-decrement nil)
              (in-assignment nil)
              (in-assignment-round-bracket-level nil)
              (in-assignment-square-bracket-level nil)
              (in-assignment-level 0)
              (in-object-operator nil)
              (in-object-operator-round-bracket-level nil)
              (in-object-operator-square-bracket-level nil)
              (after-object-operator nil)
              (in-object-operator-level 0)
              (in-class-declaration nil)
              (in-class-declaration-level 0)
              (in-return nil)
              (in-return-curly-bracket-level nil)
              (in-return-level 0)
              (previous-token nil)
              (token nil)
              (token-start nil)
              (token-end nil)
              (token-start-line-number 0)
              (token-end-line-number 0)
              (tokens (nreverse (copy-sequence tokens)))
              (nesting-stack nil)
              (nesting-key nil)
              (class-declaration-started-this-line nil)
              (special-control-structure-started-this-line nil)
              (temp-pre-indent nil)
              (temp-post-indent nil)
              (imenu-index '())
              (imenu-namespace-index '())
              (imenu-class-index '())
              (imenu-in-namespace-declaration nil)
              (imenu-in-namespace-name nil)
              (imenu-in-namespace-with-brackets nil)
              (imenu-open-namespace-level nil)
              (imenu-in-class-declaration nil)
              (imenu-open-class-level nil)
              (imenu-in-class-name nil)
              (imenu-in-function-declaration nil)
              (imenu-in-function-name nil)
              (imenu-in-function-index nil)
              (imenu-nesting-level 0)
              (incremental-line-number 1))

          (push `(END_PARSE ,(length string) . ,(length string)) tokens)

          ;; Iterate through all buffer tokens from beginning to end
          (dolist (item (nreverse tokens))
            ;; (message "Items: %s %s" item phps-mode-lexer-tokens)
            (let ((next-token (car item))
                  (next-token-start (car (cdr item)))
                  (next-token-end (cdr (cdr item)))
                  (next-token-start-line-number nil)
                  (next-token-end-line-number nil))

              (when (and token
                         (< token-end next-token-start))
                ;; NOTE We use a incremental-line-number calculation because `line-at-pos' takes a lot of time
                (setq incremental-line-number (+ incremental-line-number (phps-mode-functions--get-lines-in-string (substring string (1- token-end) (1- next-token-start))))))

              ;; Handle the pseudo-token for last-line
              (if (equal next-token 'END_PARSE)
                  (progn
                    (setq next-token-start-line-number (1+ token-start-line-number))
                    (setq next-token-end-line-number (1+ token-end-line-number)))
                (setq next-token-start-line-number incremental-line-number)

                ;; NOTE We use a incremental-line-number calculation because `line-at-pos' takes a lot of time
                ;; (message "Lines for %s '%s'" next-token (substring string (1- next-token-start) (1- next-token-end)))
                (setq incremental-line-number (+ incremental-line-number (phps-mode-functions--get-lines-in-string (substring string (1- next-token-start) (1- next-token-end)))))
                (setq next-token-end-line-number incremental-line-number)
                (phps-mode-debug-message
                  (message "Token '%s' pos: %s-%s lines: %s-%s" next-token next-token-start next-token-end next-token-start-line-number next-token-end-line-number)))

              ;; Token logic - we have one-two token look-ahead at this point
              ;; `token' is previous token
              ;; `next-token' is current token
              ;; `previous-token' is maybe two tokens back
              (when token


                ;; IMENU LOGIC

                (cond

                 ((or (string= token "{")
                      (equal token 'T_CURLY_OPEN)
                      (equal token 'T_DOLLAR_OPEN_CURLY_BRACES))
                  (setq imenu-nesting-level (1+ imenu-nesting-level)))

                 ((string= token "}")

                  (when (and imenu-open-namespace-level
                             (= imenu-open-namespace-level imenu-nesting-level)
                             imenu-in-namespace-name)
                    (let ((imenu-add-list (nreverse imenu-namespace-index)))
                      (push `(,imenu-in-namespace-name . ,imenu-add-list) imenu-index))
                    (setq imenu-in-namespace-name nil))

                  (when (and imenu-open-class-level
                             (= imenu-open-class-level imenu-nesting-level)
                             imenu-in-class-name)
                    (let ((imenu-add-list (nreverse imenu-class-index)))
                      (if imenu-in-namespace-name
                          (push `(,imenu-in-class-name . ,imenu-add-list) imenu-namespace-index)
                        (push `(,imenu-in-class-name . ,imenu-add-list) imenu-index)))
                    (setq imenu-in-class-name nil))

                  (setq imenu-nesting-level (1- imenu-nesting-level))))

                (when (and (equal next-token 'END_PARSE)
                           imenu-in-namespace-name
                           (not imenu-in-namespace-with-brackets))
                  (let ((imenu-add-list (nreverse imenu-namespace-index)))
                    (push `(,imenu-in-namespace-name . ,imenu-add-list) imenu-index))
                  (setq imenu-in-namespace-name nil))
                
                (cond

                 (imenu-in-namespace-declaration
                  (cond

                   ((or (string= token "{")
                        (string= token ";"))
                    (setq imenu-in-namespace-with-brackets (string= token "{"))
                    (setq imenu-open-namespace-level imenu-nesting-level)
                    (setq imenu-namespace-index '())
                    (setq imenu-in-namespace-declaration nil))

                    ((and (or (equal token 'T_STRING)
                              (equal token 'T_NS_SEPARATOR))
                          (setq imenu-in-namespace-name (concat imenu-in-namespace-name (substring string (1- token-start) (1- token-end))))))))

                 (imenu-in-class-declaration
                  (cond

                   ((string= token "{")
                    (setq imenu-open-class-level imenu-nesting-level)
                    (setq imenu-in-class-declaration nil)
                    (setq imenu-class-index '()))

                   ((and (equal token 'T_STRING)
                         (not imenu-in-class-name))
                    (setq imenu-in-class-name (substring string (1- token-start) (1- token-end))))))

                 (imenu-in-function-declaration
                  (cond

                   ((or (string= token "{")
                        (string= token ";"))
                    (when imenu-in-function-name
                      (if imenu-in-class-name
                          (push `(,imenu-in-function-name . ,imenu-in-function-index) imenu-class-index)
                        (if imenu-in-namespace-name
                            (push `(,imenu-in-function-name . ,imenu-in-function-index) imenu-namespace-index)
                          (push `(,imenu-in-function-name . ,imenu-in-function-index) imenu-index))))
                    (setq imenu-in-function-name nil)
                    (setq imenu-in-function-declaration nil))

                   ((and (equal token 'T_STRING)
                         (not imenu-in-function-name))
                    (setq imenu-in-function-name (substring string (1- token-start) (1- token-end)))
                    (setq imenu-in-function-index token-start))))

                 (t (cond

                     ((and (not imenu-in-namespace-name)
                           (equal token 'T_NAMESPACE))
                      (setq imenu-in-namespace-name nil)
                      (setq imenu-in-namespace-declaration t))

                     ((and (not imenu-in-class-name)
                           (or (equal token 'T_CLASS)
                               (equal token 'T_INTERFACE)))
                      (setq imenu-in-class-name nil)
                      (setq imenu-in-class-declaration t))

                     ((and (not imenu-in-function-name)
                           (equal token 'T_FUNCTION))
                      (setq imenu-in-function-name nil)
                      (setq imenu-in-function-declaration t)))))


                ;; INDENTATION LOGIC

                ;; Keep track of round bracket level
                (when (string= token "(")
                  (setq round-bracket-level (1+ round-bracket-level)))
                (when (string= token ")")
                  (setq round-bracket-level (1- round-bracket-level))
                  (when first-token-on-line
                    (setq first-token-is-nesting-decrease t)))

                ;; Keep track of square bracket level
                (when (string= token "[")
                  (setq square-bracket-level (1+ square-bracket-level)))
                (when (string= token "]")
                  (setq square-bracket-level (1- square-bracket-level))
                  (when first-token-on-line
                    (setq first-token-is-nesting-decrease t)))

                ;; Handle INLINE_HTML blocks
                (when (equal token 'T_INLINE_HTML)

                  ;; Flag whether inline-html is whitespace or not
                  (setq inline-html-is-whitespace (string= (string-trim (substring string (1- token-start) (1- token-end))) ""))

                  (when first-token-on-line
                    (setq first-token-is-inline-html t))

                  (let ((inline-html-indents (phps-mode-functions--get-inline-html-indentation (substring string (1- token-start) (1- token-end)) inline-html-indent inline-html-tag-level inline-html-curly-bracket-level inline-html-square-bracket-level inline-html-round-bracket-level)))

                    (phps-mode-debug-message
                      (message "Received inline html indent: %s from inline HTML: '%s'" inline-html-indents (substring string (1- token-start) (1- token-end))))

                    ;; Update indexes
                    (setq inline-html-indent (nth 1 inline-html-indents))
                    (setq inline-html-tag-level (nth 2 inline-html-indents))
                    (setq inline-html-curly-bracket-level (nth 3 inline-html-indents))
                    (setq inline-html-square-bracket-level (nth 4 inline-html-indents))
                    (setq inline-html-round-bracket-level (nth 5 inline-html-indents))

                    (phps-mode-debug-message
                     (message "First token is inline html: %s" first-token-is-inline-html))

                    ;; Does inline html span several lines or starts a new line?
                    (when (or (> token-end-line-number token-start-line-number)
                              first-token-is-inline-html)

                      ;; Token does not only contain white-space?
                      (unless inline-html-is-whitespace
                        (let ((token-line-number-diff token-start-line-number))
                          ;; Iterate lines here and add indents
                          (dolist (item (nth 0 inline-html-indents))
                            ;; Skip first line unless first token on line was inline-html
                            (when (or (not (= token-line-number-diff token-start-line-number))
                                      first-token-is-inline-html)
                              (puthash token-line-number-diff (list item 0) line-indents)
                              (phps-mode-debug-message
                               (message "Putting indent at line %s to %s from inline HTML" token-line-number-diff item)))
                            (setq token-line-number-diff (1+ token-line-number-diff))))))))

                ;; Keep track of when we are inside a class definition
                (if in-class-declaration
                    (if (string= token "{")
                        (progn
                          (setq in-class-declaration nil)
                          (setq in-class-declaration-level 0)

                          (unless class-declaration-started-this-line
                            (setq column-level (1- column-level))
                            (pop nesting-stack))

                          (when first-token-on-line
                            (setq first-token-is-nesting-decrease t))

                          )
                      (when first-token-on-line
                        (setq in-class-declaration-level 1)))

                  ;; If ::class is used as a magical class constant it should not be considered start of a class declaration
                  (when (and (equal token 'T_CLASS)
                             (or (not previous-token)
                                 (not (equal previous-token 'T_PAAMAYIM_NEKUDOTAYIM))))
                    (setq in-class-declaration t)
                    (setq in-class-declaration-level 1)
                    (setq class-declaration-started-this-line t)))

                ;; Keep track of curly bracket level
                (when (or (equal token 'T_CURLY_OPEN)
                          (equal token 'T_DOLLAR_OPEN_CURLY_BRACES)
                          (string= token "{"))
                  (setq curly-bracket-level (1+ curly-bracket-level)))
                (when (string= token "}")
                  (setq curly-bracket-level (1- curly-bracket-level))

                  (when (and switch-curly-stack
                             (= (1+ curly-bracket-level) (car switch-curly-stack)))

                    (phps-mode-debug-message
                      (message "Ended switch curly stack at %s" curly-bracket-level))

                    (setq allow-custom-column-decrement t)
                    (pop nesting-stack)
                    (setq alternative-control-structure-level (1- alternative-control-structure-level))
                    (pop switch-curly-stack))
                  
                  (when first-token-on-line
                    (setq first-token-is-nesting-decrease t)))

                ;; Keep track of ending alternative control structure level
                (when (or (equal token 'T_ENDIF)
                          (equal token 'T_ENDWHILE)
                          (equal token 'T_ENDFOR)
                          (equal token 'T_ENDFOREACH)
                          (equal token 'T_ENDSWITCH))
                  (setq alternative-control-structure-level (1- alternative-control-structure-level))
                  ;; (message "Found ending alternative token %s %s" token alternative-control-structure-level)

                  (when (and (equal token 'T_ENDSWITCH)
                             switch-case-alternative-stack)

                    (phps-mode-debug-message
                      (message "Ended alternative switch stack at %s" alternative-control-structure-level))
                    
                    (pop switch-alternative-stack)
                    (pop switch-case-alternative-stack)
                    (setq allow-custom-column-decrement t)
                    (pop nesting-stack)
                    (setq alternative-control-structure-level (1- alternative-control-structure-level)))

                  (when first-token-on-line
                    (setq first-token-is-nesting-decrease t)))

                ;; When we encounter a token except () after a control-structure
                (when (and after-special-control-structure
                           (= after-special-control-structure round-bracket-level)
                           (not (string= token ")"))
                           (not (string= token "(")))

                  ;; Handle the else if case
                  (if (equal 'T_IF token)
                      (setq after-special-control-structure-token token)

                    ;; Is token not a curly bracket - because that is a ordinary control structure syntax
                    (if (string= token "{")

                        ;; Save curly bracket level when switch starts
                        (when (equal after-special-control-structure-token 'T_SWITCH)

                          (phps-mode-debug-message
                            (message "Started switch curly stack at %s" curly-bracket-level))

                          (push curly-bracket-level switch-curly-stack))

                      ;; Is it the start of an alternative control structure?
                      (if (string= token ":")

                          (progn

                            ;; Save alternative nesting level for switch
                            (when (equal after-special-control-structure-token 'T_SWITCH)

                              (phps-mode-debug-message
                                (message "Started switch alternative stack at %s" alternative-control-structure-level))

                              (push alternative-control-structure-level switch-alternative-stack))

                            (setq alternative-control-structure-level (1+ alternative-control-structure-level))

                            (phps-mode-debug-message
                              (message "\nIncreasing alternative-control-structure after %s %s to %s\n" after-special-control-structure-token token alternative-control-structure-level))
                            )

                        ;; Don't start inline control structures after a while ($condition); expression
                        (unless (string= token ";")
                          (phps-mode-debug-message
                            (message "\nStarted inline control-structure after %s at %s\n" after-special-control-structure-token token))

                          (setq in-inline-control-structure t)
                          (setq temp-pre-indent (1+ column-level)))))

                    (setq after-special-control-structure nil)
                    (setq after-special-control-structure-token nil)))

                ;; Support extra special control structures (CASE)
                (when (and after-extra-special-control-structure
                           (string= token ":"))
                  (setq alternative-control-structure-level (1+ alternative-control-structure-level))
                  (when after-extra-special-control-structure-first-on-line
                    (setq first-token-is-nesting-decrease t))
                  (setq after-extra-special-control-structure nil))

                ;; Keep track of concatenation
                (if in-concatenation
                    (when (or (string= token ";")
                              (and (string= token ")")
                                   (< round-bracket-level (car in-concatenation-round-bracket-level)))
                              (and (string= token ",")
                                   (= round-bracket-level (car in-concatenation-round-bracket-level))
                                   (= square-bracket-level (car in-concatenation-square-bracket-level)))
                              (and (string= token"]")
                                   (< square-bracket-level (car in-concatenation-square-bracket-level))))
                      (phps-mode-debug-message "Ended concatenation")
                      (pop in-concatenation-round-bracket-level)
                      (pop in-concatenation-square-bracket-level)
                      (unless in-concatenation-round-bracket-level
                        (setq in-concatenation nil))
                      (setq in-concatenation-level (1- in-concatenation-level)))
                  (when (and (> next-token-start-line-number token-end-line-number)
                             (or (string= token ".")
                                 (string= next-token ".")))
                    (phps-mode-debug-message "Started concatenation")
                    (setq in-concatenation t)
                    (push round-bracket-level in-concatenation-round-bracket-level)
                    (push square-bracket-level in-concatenation-square-bracket-level)
                    (setq in-concatenation-level (1+ in-concatenation-level))))

                ;; Did we reach a semicolon inside a inline block? Close the inline block
                (when (and in-inline-control-structure
                           (string= token ";")
                           (not special-control-structure-started-this-line))
                  (setq in-inline-control-structure nil))

                ;; Did we encounter a token that supports alternative and inline control structures?
                (when (or (equal token 'T_IF)
                          (equal token 'T_WHILE)
                          (equal token 'T_FOR)
                          (equal token 'T_FOREACH)
                          (equal token 'T_SWITCH)
                          (equal token 'T_ELSE)
                          (equal token 'T_ELSEIF)
                          (equal token 'T_DEFAULT))
                  (setq after-special-control-structure round-bracket-level)
                  (setq after-special-control-structure-token token)
                  (setq nesting-key token)
                  (setq special-control-structure-started-this-line t)

                  ;; ELSE and ELSEIF after a IF, ELSE, ELESIF
                  ;; and DEFAULT after a CASE
                  ;; should decrease alternative control structure level
                  (when (and nesting-stack
                             (string= (car (cdr (cdr (cdr (car nesting-stack))))) ":")
                             (or
                              (and (or (equal token 'T_ELSE)
                                       (equal token 'T_ELSEIF))
                                   (or (equal (car (cdr (cdr (car nesting-stack)))) 'T_IF)
                                       (equal (car (cdr (cdr (car nesting-stack)))) 'T_ELSEIF)
                                       (equal (car (cdr (cdr (car nesting-stack)))) 'T_ELSE)))
                              (and (equal token 'T_DEFAULT)
                                   (equal (car (cdr (cdr (car nesting-stack)))) 'T_CASE))))
                    (setq alternative-control-structure-level (1- alternative-control-structure-level))

                    (when first-token-on-line
                      (setq first-token-is-nesting-decrease t))

                    (phps-mode-debug-message
                      (message "\nDecreasing alternative control structure nesting at %s to %s\n" token alternative-control-structure-level)))

                  )

                ;; Keep track of assignments
                (when in-assignment
                  (when (or (string= token ";")
                            (and (string= token ")")
                                 (or (< round-bracket-level (car in-assignment-round-bracket-level))
                                     (and
                                      (= round-bracket-level (car in-assignment-round-bracket-level))
                                      (= square-bracket-level (car in-assignment-square-bracket-level))
                                      (or (string= next-token ")")
                                          (string= next-token "]")))))
                            (and (string= token ",")
                                 (= round-bracket-level (car in-assignment-round-bracket-level))
                                 (= square-bracket-level (car in-assignment-square-bracket-level)))
                            (and (string= token "]")
                                 (or (< square-bracket-level (car in-assignment-square-bracket-level))
                                     (and
                                      (= square-bracket-level (car in-assignment-square-bracket-level))
                                      (= round-bracket-level (car in-assignment-round-bracket-level))
                                      (or (string= next-token "]")
                                          (string= next-token ")")))))
                            (and (equal token 'T_FUNCTION)
                                 (= round-bracket-level (car in-assignment-round-bracket-level))))

                    ;; NOTE Ending an assignment because of a T_FUNCTION token is to support PSR-2 Closures
                    
                    (phps-mode-debug-message
                      (message "Ended assignment %s at %s %s" in-assignment-level token next-token))
                    (pop in-assignment-square-bracket-level)
                    (pop in-assignment-round-bracket-level)
                    (unless in-assignment-round-bracket-level
                      (setq in-assignment nil))
                    (setq in-assignment-level (1- in-assignment-level))

                    ;; Did we end two assignment at once?
                    (when (and
                           in-assignment-round-bracket-level
                           in-assignment-square-bracket-level
                           (= round-bracket-level (car in-assignment-round-bracket-level))
                           (= square-bracket-level (car in-assignment-square-bracket-level))
                           (or (string= next-token ")")
                               (string= next-token "]")))
                      (phps-mode-debug-message
                        (message "Ended another assignment %s at %s %s" in-assignment-level token next-token))
                      (pop in-assignment-square-bracket-level)
                      (pop in-assignment-round-bracket-level)
                      (unless in-assignment-round-bracket-level
                        (setq in-assignment nil))
                      (setq in-assignment-level (1- in-assignment-level)))

                    ))

                (when (and (not after-special-control-structure)
                           (or (string= token "=")
                               (equal token 'T_DOUBLE_ARROW)
                               (equal token 'T_CONCAT_EQUAL)
                               (equal token 'T_POW_EQUAL)
                               (equal token 'T_DIV_EQUAL)
                               (equal token 'T_PLUS_EQUAL)
                               (equal token 'T_MINUS_EQUAL)
                               (equal token 'T_MUL_EQUAL)
                               (equal token 'T_MOD_EQUAL)
                               (equal token 'T_SL_EQUAL)
                               (equal token 'T_SR_EQUAL)
                               (equal token 'T_AND_EQUAL)
                               (equal token 'T_OR_EQUAL)
                               (equal token 'T_XOR_EQUAL)
                               (equal token 'T_COALESCE_EQUAL)))
                  (phps-mode-debug-message "Started assignment")
                  (setq in-assignment t)
                  (push round-bracket-level in-assignment-round-bracket-level)
                  (push square-bracket-level in-assignment-square-bracket-level)
                  (setq in-assignment-level (1+ in-assignment-level)))

                ;; Second token after a object-operator
                (when (and
                       in-object-operator
                       in-object-operator-round-bracket-level
                       in-object-operator-square-bracket-level
                       (<= round-bracket-level (car in-object-operator-round-bracket-level))
                       (<= square-bracket-level (car in-object-operator-square-bracket-level))
                       (not (or
                             (equal next-token 'T_OBJECT_OPERATOR)
                             (equal next-token 'T_PAAMAYIM_NEKUDOTAYIM))))
                  (phps-mode-debug-message
                    (message "Ended object-operator at %s %s at level %s" token next-token in-object-operator-level))
                  (pop in-object-operator-round-bracket-level)
                  (pop in-object-operator-square-bracket-level)
                  (setq in-object-operator-level (1- in-object-operator-level))
                  (when (= in-object-operator-level 0)
                    (setq in-object-operator nil)))

                ;; First token after a object-operator
                (when after-object-operator
                  (when (or (equal next-token 'T_STRING)
                            (string= next-token "("))
                    (progn
                      (phps-mode-debug-message
                        (message "Started object-operator at %s %s on level %s"  token next-token in-object-operator-level))
                      (push round-bracket-level in-object-operator-round-bracket-level)
                      (push square-bracket-level in-object-operator-square-bracket-level)
                      (setq in-object-operator t)
                      (setq in-object-operator-level (1+ in-object-operator-level))))
                  (setq after-object-operator nil))

                ;; Starting object-operator?
                (when (and (or (equal token 'T_OBJECT_OPERATOR)
                               (equal token 'T_PAAMAYIM_NEKUDOTAYIM))
                           (equal next-token 'T_STRING))
                  (phps-mode-debug-message
                    (message "After object-operator at %s level %s"  token in-object-operator-level))
                  (setq after-object-operator t))

                ;; Keep track of return expressions
                (when in-return
                  (when (and (string= token ";")
                             (= curly-bracket-level (car in-return-curly-bracket-level)))

                    (phps-mode-debug-message (message "Ended return at %s" token))
                    (pop in-return-curly-bracket-level)
                    (unless in-return-curly-bracket-level
                      (setq in-return nil))
                    (setq in-return-level (1- in-return-level))))
                (when (equal token 'T_RETURN)
                  (phps-mode-debug-message "Started return")
                  (setq in-return t)
                  (push curly-bracket-level in-return-curly-bracket-level)
                  (setq in-return-level (1+ in-return-level)))

                ;; Did we encounter a token that supports extra special alternative control structures?
                (when (equal token 'T_CASE)
                  (setq after-extra-special-control-structure t)
                  (setq nesting-key token)
                  (setq after-extra-special-control-structure-first-on-line first-token-on-line)

                  (when (and switch-case-alternative-stack
                             (= (1- alternative-control-structure-level) (car switch-case-alternative-stack)))

                    (phps-mode-debug-message
                      (message "Found CASE %s vs %s" (1- alternative-control-structure-level) (car switch-case-alternative-stack)))

                    (setq alternative-control-structure-level (1- alternative-control-structure-level))
                    (when first-token-on-line
                      (setq first-token-is-nesting-decrease t))
                    (pop switch-case-alternative-stack))

                  (push alternative-control-structure-level switch-case-alternative-stack)))

              ;; Do we have one token look-ahead?
              (when token

                (phps-mode-debug-message (message "Processing token: %s" token))
                
                ;; Calculate nesting
                (setq nesting-end (+ round-bracket-level square-bracket-level curly-bracket-level alternative-control-structure-level in-assignment-level in-class-declaration-level in-concatenation-level in-return-level in-object-operator-level))

                ;; Keep track of whether we are inside a HEREDOC or NOWDOC
                (when (equal token 'T_START_HEREDOC)
                  (setq in-heredoc t)
                  (setq in-heredoc-started-this-line t))
                (when (equal token 'T_END_HEREDOC)
                  (setq in-heredoc nil)
                  (setq in-heredoc-ended-this-line t))

                ;; Has nesting increased?
                (when (and nesting-stack
                           (<= nesting-end (car (car nesting-stack))))
                  (let ((nesting-decrement 0))

                    ;; Handle case were nesting has decreased less than next as well
                    (while (and nesting-stack
                                (<= nesting-end (car (car nesting-stack))))
                      (phps-mode-debug-message
                        (message "\nPopping %s from nesting-stack since %s is lesser or equal to %s, next value is: %s\n" (car nesting-stack) nesting-end (car (car nesting-stack)) (nth 1 nesting-stack)))
                      (pop nesting-stack)
                      (setq nesting-decrement (1+ nesting-decrement)))

                    (if first-token-is-nesting-decrease

                        (progn
                          ;; Decrement column
                          (if allow-custom-column-decrement
                              (progn
                                (phps-mode-debug-message
                                  (message "Doing custom decrement 1 from %s to %s" column-level (- column-level (- nesting-start nesting-end))))
                                (setq column-level (- column-level (- nesting-start nesting-end)))
                                (setq allow-custom-column-decrement nil))
                            (phps-mode-debug-message
                              (message "Doing regular decrement 1 from %s to %s" column-level (1- column-level)))
                            (setq column-level (- column-level nesting-decrement)))

                          ;; Prevent negative column-values
                          (when (< column-level 0)
                            (setq column-level 0)))

                      (unless temp-post-indent
                        (phps-mode-debug-message
                          (message "Temporary setting post indent %s" column-level))
                        (setq temp-post-indent column-level))

                      ;; Decrement column
                      (if allow-custom-column-decrement
                          (progn
                            (phps-mode-debug-message
                              (message "Doing custom decrement 2 from %s to %s" column-level (- column-level (- nesting-start nesting-end))))
                            (setq temp-post-indent (- temp-post-indent (- nesting-start nesting-end)))
                            (setq allow-custom-column-decrement nil))
                        (setq temp-post-indent (- temp-post-indent nesting-decrement)))

                      ;; Prevent negative column-values
                      (when (< temp-post-indent 0)
                        (setq temp-post-indent 0))

                      )))

                ;; Are we on a new line or is it the last token of the buffer?
                (if (> next-token-start-line-number token-start-line-number)
                    (progn


                      ;; ;; Start indentation might differ from ending indentation in cases like } else {
                      (setq column-level-start column-level)

                      ;; Support temporarily pre-indent
                      (when temp-pre-indent
                        (setq column-level-start temp-pre-indent)
                        (setq temp-pre-indent nil))

                      ;; HEREDOC lines should have zero indent
                      (when (or (and in-heredoc
                                     (not in-heredoc-started-this-line))
                                in-heredoc-ended-this-line)
                        (setq column-level-start 0))

                      ;; Inline HTML should have zero indent
                      (when (and first-token-is-inline-html
                                 (not inline-html-is-whitespace))
                        (phps-mode-debug-message
                         (message "Setting column-level to inline HTML indent: %s" inline-html-indent-start))
                        (setq column-level-start inline-html-indent-start))

                      ;; Save line indent
                      (phps-mode-debug-message
                        (message "Process line ending.	nesting: %s-%s,	line-number: %s-%s,	indent: %s.%s,	token: %s" nesting-start nesting-end token-start-line-number token-end-line-number column-level-start tuning-level token))

                      (when (and (> token-start-line-number 0)
                                 (or
                                  (not first-token-is-inline-html)
                                  inline-html-is-whitespace))
                        (phps-mode-debug-message
                         (message "Putting indent on line %s to %s at #C" token-start-line-number column-level-start))
                        (puthash token-start-line-number `(,column-level-start ,tuning-level) line-indents))

                      ;; Support trailing indent decrements
                      (when temp-post-indent
                        (setq column-level temp-post-indent)
                        (setq temp-post-indent nil))

                      ;; Increase indentation
                      (when (and (> nesting-end 0)
                                 (or (not nesting-stack)
                                     (> nesting-end (car (cdr (car nesting-stack))))))
                        (let ((nesting-stack-end 0))
                          (when nesting-stack
                            (setq nesting-stack-end (car (cdr (car nesting-stack)))))

                          (if allow-custom-column-increment
                              (progn
                                (setq column-level (+ column-level (- nesting-end nesting-start)))
                                (setq allow-custom-column-increment nil))
                            (setq column-level (1+ column-level)))

                          (phps-mode-debug-message
                            (message "\nPushing (%s %s %s %s) to nesting-stack since %s is greater than %s or stack is empty\n" nesting-start nesting-end nesting-key token nesting-end (car (cdr (car nesting-stack))))
                            )
                          (push `(,nesting-stack-end ,nesting-end ,nesting-key ,token) nesting-stack)))


                      ;; Does token span over several lines and is it not a INLINE_HTML token?
                      (when (and (> token-end-line-number token-start-line-number)
                                 (not (equal token 'T_INLINE_HTML)))
                        (let ((column-level-end column-level))

                          ;; HEREDOC lines should have zero indent
                          (when (or (and in-heredoc
                                         (not in-heredoc-started-this-line))
                                    in-heredoc-ended-this-line)
                            (setq column-level-end 0))

                          ;; (message "Token %s starts at %s and ends at %s indent %s %s" next-token token-start-line-number token-end-line-number column-level-end tuning-level)

                          ;; Indent doc-comment lines with 1 tuning
                          (when (equal token 'T_DOC_COMMENT)
                            (setq tuning-level 1))

                          (let ((token-line-number-diff (1- (- token-end-line-number token-start-line-number))))
                            (while (>= token-line-number-diff 0)
                              (phps-mode-debug-message
                               (message "Putting indent on line %s to %s at #A" (- token-end-line-number token-line-number-diff) column-level-end))
                              (puthash (- token-end-line-number token-line-number-diff) `(,column-level-end ,tuning-level) line-indents)
                              ;; (message "Saved line %s indent %s %s" (- token-end-line-number token-line-number-diff) column-level tuning-level)
                              (setq token-line-number-diff (1- token-line-number-diff))))

                          ;; Rest tuning-level used for comments
                          (setq tuning-level 0)))

                      ;; Indent token-less lines here in between last tokens if distance is more than 1 line
                      (when (and (> next-token-start-line-number (1+ token-end-line-number))
                                 (not (equal token 'T_CLOSE_TAG)))

                        (phps-mode-debug-message
                          (message "\nDetected token-less lines between %s and %s, should have indent: %s\n" token-end-line-number next-token-start-line-number column-level))

                        (let ((token-line-number-diff (1- (- next-token-start-line-number token-end-line-number))))
                          (while (> token-line-number-diff 0)
                            (phps-mode-debug-message
                             (message "Putting indent at line %s indent %s at #B" (- next-token-start-line-number token-line-number-diff) column-level))
                            (puthash (- next-token-start-line-number token-line-number-diff) `(,column-level ,tuning-level) line-indents)
                            (setq token-line-number-diff (1- token-line-number-diff)))))


                      ;; Calculate indentation level at start of line
                      (setq nesting-start (+ round-bracket-level square-bracket-level curly-bracket-level alternative-control-structure-level in-assignment-level in-class-declaration-level in-concatenation-level in-return-level in-object-operator-level))

                      ;; Set initial values for tracking first token
                      (when (> token-start-line-number last-line-number)
                        (setq inline-html-indent-start inline-html-indent)
                        (setq first-token-on-line t)
                        (setq first-token-is-nesting-decrease nil)
                        (setq first-token-is-inline-html nil)
                        (setq in-class-declaration-level 0)
                        (setq class-declaration-started-this-line nil)
                        (setq in-heredoc-started-this-line nil)
                        (setq special-control-structure-started-this-line nil)

                        ;; When line ends with multi-line inline-html flag first token as inline-html
                        (when (and
                               (equal token 'T_INLINE_HTML)
                               (not inline-html-is-whitespace)
                               (> token-end-line-number token-start-line-number))

                          (setq inline-html-is-whitespace
                                (not (null
                                      (string-match "[\n\C-m][ \t]+$" (substring string (1- token-start) (1- token-end))))))
                          (phps-mode-debug-message
                           (message "Trailing inline html line is whitespace: %s" inline-html-is-whitespace))
                          (phps-mode-debug-message
                           (message "Setting first-token-is-inline-html to true since last token on line is inline-html and spans several lines"))
                          (setq first-token-is-inline-html t))))

                  ;; Current token is not first if it's not <?php or <?=
                  (unless (or (equal token 'T_OPEN_TAG)
                              (equal token 'T_OPEN_TAG_WITH_ECHO))
                    (setq first-token-on-line nil))

                  (when (> token-end-line-number token-start-line-number)
                    ;; (message "Token not first on line %s starts at %s and ends at %s" token token-start-line-number token-end-line-number)
                    (when (equal token 'T_DOC_COMMENT)
                      (setq tuning-level 1))

                    (let ((token-line-number-diff (1- (- token-end-line-number token-start-line-number))))
                      (while (>= token-line-number-diff 0)
                        (phps-mode-debug-message
                         (message "Putting indent on line %s to %s at #E" (- token-end-line-number token-line-number-diff) column-level))
                        (puthash (- token-end-line-number token-line-number-diff) `(,column-level ,tuning-level) line-indents)
                        (setq token-line-number-diff (1- token-line-number-diff))))
                    (setq tuning-level 0))))

              ;; Update current token
              (setq previous-token token)
              (setq token next-token)
              (setq token-start next-token-start)
              (setq token-end next-token-end)
              (setq token-start-line-number next-token-start-line-number)
              (setq token-end-line-number next-token-end-line-number)
              (setq token-number (1+ token-number))))
          (list (nreverse imenu-index) line-indents)))
    (list nil nil)))

;; TODO newline with electric mode not working
(defun phps-mode-functions-indent-line ()
  "Indent line."
  (phps-mode-runtime-debug-message "Indent line")
  (phps-mode-debug-message (message "Indent line"))
  (phps-mode-functions-process-current-buffer)
  (if phps-mode-functions-lines-indent
      (let ((line-number (line-number-at-pos (point))))
        (phps-mode-runtime-debug-message "Found lines indent index, indenting..")
        (phps-mode-debug-message (message "Found lines indent index, indenting.."))
        (let ((indent (gethash line-number phps-mode-functions-lines-indent)))
          (if indent
              (progn
                (phps-mode-runtime-debug-message (format "Found indent for line number %s = %s" line-number indent))
                (let ((indent-sum (+ (* (car indent) tab-width) (car (cdr indent))))
                      (old-indentation (current-indentation))
                      (line-start (line-beginning-position)))

                  (unless old-indentation
                    (setq old-indentation 0))

                  ;; Only continue if current indentation is wrong
                  (if (not (equal indent-sum old-indentation))
                      (progn
                        (phps-mode-runtime-debug-message (format "Indenting line since it's not already indented correctly %s vs %s" old-indentation indent-sum))

                        (setq-local phps-mode-functions-allow-after-change nil)
                        (indent-line-to indent-sum)
                        (setq-local phps-mode-functions-allow-after-change t)

                        (let ((indent-diff (- (current-indentation) old-indentation)))

                          (phps-mode-runtime-debug-message (format "Moving indexes by %s points from %s" indent-diff line-start))
                          (phps-mode-runtime-debug-message (format "Lexer tokens before move: %s" phps-mode-lexer-tokens))

                          ;; When indent is changed the trailing tokens and states just need to adjust their positions, this will improve speed of indent-region a lot
                          (phps-mode-lexer-move-tokens line-start indent-diff)
                          (phps-mode-lexer-move-states line-start indent-diff)
                          (phps-mode-functions-move-imenu-index line-start indent-diff)

                          (phps-mode-runtime-debug-message (format "Lexer tokens after move: %s" phps-mode-lexer-tokens))
                          (phps-mode-debug-message
                           (message "Lexer tokens after move: %s" phps-mode-lexer-tokens)
                           (message "Lexer states after move: %s" phps-mode-lexer-states))

                          ;; Reset change flag
                          (phps-mode-functions--reset-changes)
                          (phps-mode-functions--cancel-idle-timer)

                          ;; Update last buffer states
                          (setq-local phps-mode-lexer-buffer-length (1- (point-max)))
                          (setq-local phps-mode-lexer-buffer-contents (buffer-substring-no-properties (point-min) (point-max)))

                          (phps-mode-runtime-debug-message (format "buffer contents:\n%s" (buffer-substring-no-properties (point-min) (point-max))))
                          ))
                    (phps-mode-runtime-debug-message "Skipping indentation of line since it's already indented correctly"))))
            (phps-mode-runtime-debug-message (format "Found no indent for line number %s" line-number)))))
    (phps-mode-runtime-debug-message "Did not find lines indent index, skipping indenting..")
    (phps-mode-debug-message "Did not find lines indent index, skipping indenting..")
    (message "Did not find lines indent index, skipping indenting..")))

(defun phps-mode-functions--reset-changes ()
  "Reset change stack."
  (setq-local phps-mode-functions-buffer-changes nil))

(defun phps-mode-functions--get-changes ()
  "Get change stack."
  phps-mode-functions-buffer-changes)

(defun phps-mode-functions--cancel-idle-timer ()
  "Cancel idle timer."
  (phps-mode-runtime-debug-message "Cancelled idle timer")
  (phps-mode-debug-message (message "Cancelled idle timer"))
  (when phps-mode-functions-idle-timer
    (cancel-timer phps-mode-functions-idle-timer)
    (setq-local phps-mode-functions-idle-timer nil)))

(defun phps-mode-functions--start-idle-timer ()
  "Start idle timer."
  (phps-mode-runtime-debug-message "Enqueued idle timer")
  (phps-mode-debug-message (message "Enqueued idle timer"))
  (when (boundp 'phps-mode-idle-interval)
    (setq-local phps-mode-functions-idle-timer (run-with-idle-timer phps-mode-idle-interval nil #'phps-mode-lexer-run-incremental (current-buffer)))))

(defun phps-mode-functions-after-change (start stop length)
  "Track buffer change from START to STOP with LENGTH."
  (phps-mode-runtime-debug-message
   (format "After change %s - %s, length: %s" start stop length))
  (phps-mode-debug-message
   (message "After change %s - %s, length: %s" start stop length))

  (if phps-mode-functions-allow-after-change
      (progn
        (phps-mode-debug-message (message "After change registration is enabled"))
        (phps-mode-runtime-debug-message "After change registration is enabled")
        
        ;; If we haven't scheduled incremental lexer before - do it
        (when (and (boundp 'phps-mode-idle-interval)
                   phps-mode-idle-interval
                   (not phps-mode-functions-idle-timer))

          ;; Reset imenu
          (when (and (boundp 'imenu--index-alist)
                     imenu--index-alist)
            (setq-local imenu--index-alist nil)
            (phps-mode-debug-message (message "Cleared Imenu index")))

          (phps-mode-functions--start-idle-timer))

        ;; Save change in changes stack
        (push `(,start ,stop ,length ,(point-max) ,(buffer-substring-no-properties (point-min) (point-max))) phps-mode-functions-buffer-changes))
    (phps-mode-debug-message (message "After change registration is disabled"))
    (phps-mode-runtime-debug-message "After change registration is disabled")))

(defun phps-mode-functions-imenu-create-index ()
  "Get Imenu for current buffer."
  (phps-mode-functions-process-current-buffer)
  phps-mode-functions-imenu)

(defun phps-mode-functions-comment-region (beg end &optional _arg)
  "Comment region from BEG to END with optional ARG."
  (save-excursion
    ;; Go to start of region
    (goto-char beg)

    (let ((end-line-number (line-number-at-pos end t))
          (current-line-number (line-number-at-pos))
          (first-line t))

      ;; Does region start at beginning of line?
      (if (not (= beg (line-beginning-position)))

          ;; Use doc comment
          (progn
            (goto-char end)
            (insert " */")
            (goto-char beg)
            (insert "/* "))

        ;; Do this for every line in region
        (while (or first-line
                   (< current-line-number end-line-number))
          (move-beginning-of-line nil)

          (when first-line
            (setq first-line nil))

          ;; Does this line contain something other than white-space?
          (unless (eq (point) (line-end-position))
            (insert "// ")
            (move-end-of-line nil)
            (insert ""))

          (when (< current-line-number end-line-number)
            (line-move 1))
          (setq current-line-number (1+ current-line-number)))))))

(defun phps-mode-functions-uncomment-region (beg end &optional _arg)
  "Comment region from BEG to END with optional ARG."
  (save-excursion

    ;; Go to start of region
    (goto-char beg)

    (let ((end-line-number (line-number-at-pos end t))
          (current-line-number (line-number-at-pos))
          (first-line t))

      ;; Does region start at beginning of line?
      (if (not (= beg (line-beginning-position)))
          (progn
            (goto-char end)
            (backward-char 3)
            (when (looking-at-p " \\*/")
              (delete-char 3))

            (goto-char beg)
            (when (looking-at-p "// ")
              (delete-char 3))
            (when (looking-at-p "/\\* ")
              (delete-char 3)))

        ;; Do this for every line in region
        (while (or first-line
                   (< current-line-number end-line-number))
          (move-beginning-of-line nil)

          (when first-line
            (setq first-line nil))

          ;; Does this line contain something other than white-space?
          (unless (>= (+ (point) 3) (line-end-position))
            (when (looking-at-p "// ")
              (delete-char 3))
            (when (looking-at-p "/\\* ")
              (delete-char 3))

            (move-end-of-line nil)

            (backward-char 3)
            (when (looking-at-p " \\*/")
              (delete-char 3)))

          (when (< current-line-number end-line-number)
            (line-move 1))
          (setq current-line-number (1+ current-line-number)))))))

(provide 'phps-mode-functions)

;;; phps-mode-functions.el ends here
