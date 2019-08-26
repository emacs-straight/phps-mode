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

(defvar phps-mode-functions-allow-after-change t
  "Flag to tell us whether after change detection is enabled or not.")

(defvar phps-mode-functions-buffer-changes-start nil
  "Start point of buffer changes, nil if none.")

(defvar phps-mode-functions-lines-indent nil
  "The indentation of each line in buffer, nil if none.")

(defvar phps-mode-functions-imenu nil
  "The Imenu alist for current buffer, nil if none.")

(defvar phps-mode-functions-processed-buffer nil
  "Flag whether current buffer is processed or not.")

(defvar phps-mode-functions-verbose nil
  "Verbose messaging, default nil.")

(defun phps-mode-functions-get-buffer-changes-start ()
  "Get buffer change start."
  phps-mode-functions-buffer-changes-start)

(defun phps-mode-functions-reset-buffer-changes-start ()
  "Reset buffer change start."
  ;; (message "Reset flag for buffer changes")
  (setq phps-mode-functions-buffer-changes-start nil))

(defun phps-mode-functions-process-current-buffer ()
  "Process current buffer, generate indentations and Imenu."
  ;; (message "(phps-mode-functions-process-current-buffer)")
  (when (phps-mode-functions-get-buffer-changes-start)
    (phps-mode-lexer-run-incremental)
    (setq phps-mode-functions-processed-buffer nil))
  (unless phps-mode-functions-processed-buffer
    (phps-mode-functions--process-current-buffer)
    (setq phps-mode-functions-processed-buffer t)))

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
    (setq phps-mode-functions-imenu (phps-mode-functions-get-moved-imenu phps-mode-functions-imenu start diff))))

(defun phps-mode-functions-move-lines-indent (start-line-number diff)
  "Move lines indent from START-LINE-NUMBER with DIFF points."
  (when phps-mode-functions-lines-indent
    ;; (message "Moving line-indent index from %s with %s" start-line-number diff)
    (setq phps-mode-functions-lines-indent (phps-mode-functions-get-moved-lines-indent phps-mode-functions-lines-indent start-line-number diff))))
  
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
                  (push `(,item-label . ,(nreverse sub-item)) new-index))
              (let ((item-start (cdr item)))
                (when (>= item-start start)
                  (setq item-start (+ item-start diff)))
                (push `(,item-label . ,item-start) new-index))))
          )))

    new-index))

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


  (when phps-mode-functions-verbose
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
              (when phps-mode-functions-verbose
                (message "Decreasing indent with one since first object was a nesting decrease"))
              (setq temp-indent (1- indent))
              (when (< temp-indent 0)
                (setq temp-indent 0)))
            (push temp-indent line-indents))

          (setq indent-end (+ tag-level curly-bracket-level square-bracket-level round-bracket-level))
          (when phps-mode-functions-verbose
            (message "Encountered a new-line"))
          (if (> indent-end indent-start)
              (progn
                (when phps-mode-functions-verbose
                  (message "Increasing indent since %s is above %s" indent-end indent-start))
                (setq indent (1+ indent)))
            (when (< indent-end indent-start)
              (when phps-mode-functions-verbose
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
              (when phps-mode-functions-verbose
                (message "First object was nesting decrease"))
              (setq first-object-is-nesting-decrease t))))

        (setq start end)))
    (list (nreverse line-indents) indent tag-level curly-bracket-level square-bracket-level round-bracket-level)))

;; TODO Make this function support incremental process
(defun phps-mode-functions--process-current-buffer ()
  "Generate indexes for indentation and imenu for current buffer in one pass.  Complexity: O(n)."
  (if (boundp 'phps-mode-lexer-tokens)
      (save-excursion
        ;; (message "Processing current buffer")
        (goto-char (point-min))
        (when phps-mode-functions-verbose
          (message "\nCalculation indentation for all lines in buffer:\n\n%s" (buffer-substring-no-properties (point-min) (point-max))))
        (let ((in-heredoc nil)
              (in-heredoc-started-this-line nil)
              (in-heredoc-ended-this-line nil)
              (in-inline-control-structure nil)
              (inline-html-indent 0)
              (inline-html-tag-level 0)
              (inline-html-curly-bracket-level 0)
              (inline-html-square-bracket-level 0)
              (inline-html-round-bracket-level 0)
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
              (first-token-on-line nil)
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
              (tokens (nreverse (copy-sequence phps-mode-lexer-tokens)))
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

          (push `(END_PARSE ,(point-max) . ,(point-max)) tokens)

          ;; Iterate through all buffer tokens from beginning to end
          (dolist (item (nreverse tokens))
            ;; (message "Items: %s %s" item phps-mode-lexer-tokens)
            (let ((next-token (car item))
                  (next-token-start (car (cdr item)))
                  (next-token-end (cdr (cdr item)))
                  (next-token-start-line-number nil)
                  (next-token-end-line-number nil))

              (when token
                ;; NOTE We use a incremental-line-number calculation because `line-at-pos' takes a lot of time
                (setq incremental-line-number (+ incremental-line-number (phps-mode-functions--get-lines-in-buffer token-end next-token-start))))

              ;; Handle the pseudo-token for last-line
              (if (equal next-token 'END_PARSE)
                  (progn
                    (setq next-token-start-line-number (1+ token-start-line-number))
                    (setq next-token-end-line-number (1+ token-end-line-number)))
                (setq next-token-start-line-number incremental-line-number)

                ;; NOTE We use a incremental-line-number calculation because `line-at-pos' takes a lot of time
                (setq incremental-line-number (+ incremental-line-number (phps-mode-functions--get-lines-in-buffer next-token-start next-token-end)))
                (setq next-token-end-line-number incremental-line-number)
                (when phps-mode-functions-verbose
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
                          (setq imenu-in-namespace-name (concat imenu-in-namespace-name (buffer-substring-no-properties token-start token-end)))))))

                 (imenu-in-class-declaration
                  (cond

                   ((string= token "{")
                    (setq imenu-open-class-level imenu-nesting-level)
                    (setq imenu-in-class-declaration nil)
                    (setq imenu-class-index '()))

                   ((and (equal token 'T_STRING)
                         (not imenu-in-class-name))
                    (setq imenu-in-class-name (buffer-substring-no-properties token-start token-end)))))

                 (imenu-in-function-declaration
                  (cond

                   ((or (string= token "{")
                        (string= token ";"))
                    (if imenu-in-class-name
                        (push `(,imenu-in-function-name . ,imenu-in-function-index) imenu-class-index)
                      (if imenu-in-namespace-name
                          (push `(,imenu-in-function-name . ,imenu-in-function-index) imenu-namespace-index)
                        (push `(,imenu-in-function-name . ,imenu-in-function-index) imenu-index)))
                    (setq imenu-in-function-name nil)
                    (setq imenu-in-function-declaration nil))

                   ((and (equal token 'T_STRING)
                         (not imenu-in-function-name))
                    (setq imenu-in-function-name (buffer-substring-no-properties token-start token-end))
                    (setq imenu-in-function-index token-start))))

                 (t (cond

                     ((and (not imenu-in-namespace-name)
                           (equal token 'T_NAMESPACE))
                      (setq imenu-in-namespace-name nil)
                      (setq imenu-in-namespace-declaration t))

                     ((and (not imenu-in-class-name)
                           (equal token 'T_CLASS))
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

                  (when first-token-on-line
                    (setq first-token-is-inline-html t))

                  (let ((inline-html-indents (phps-mode-functions--get-inline-html-indentation (buffer-substring-no-properties token-start token-end) inline-html-indent inline-html-tag-level inline-html-curly-bracket-level inline-html-square-bracket-level inline-html-round-bracket-level)))

                    (when phps-mode-functions-verbose
                      (message "Received inline html indent: %s from inline HTML: '%s'" inline-html-indents (buffer-substring-no-properties token-start token-end)))

                    ;; Update indexes
                    (setq inline-html-indent (nth 1 inline-html-indents))
                    (setq inline-html-tag-level (nth 2 inline-html-indents))
                    (setq inline-html-curly-bracket-level (nth 3 inline-html-indents))
                    (setq inline-html-square-bracket-level (nth 4 inline-html-indents))
                    (setq inline-html-round-bracket-level (nth 5 inline-html-indents))

                    ;; Does token span several lines and is it not only white-space?
                    (when (> token-end-line-number token-start-line-number)
                      (unless (string= (string-trim (buffer-substring-no-properties token-start token-end)) "")
                        (let ((token-line-number-diff token-start-line-number))
                          ;; Iterate lines here and add indents
                          (dolist (item (nth 0 inline-html-indents))
                            ;; Skip first line unless first token on line was inline-html
                            (when (or (not (= token-line-number-diff token-start-line-number))
                                      first-token-is-inline-html)
                              (puthash token-line-number-diff (list item 0) line-indents)
                              (when phps-mode-functions-verbose
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

                    (when phps-mode-functions-verbose
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

                    (when phps-mode-functions-verbose
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

                          (when phps-mode-functions-verbose
                            (message "Started switch curly stack at %s" curly-bracket-level))

                          (push curly-bracket-level switch-curly-stack))

                      ;; Is it the start of an alternative control structure?
                      (if (string= token ":")

                          (progn

                            ;; Save alternative nesting level for switch
                            (when (equal after-special-control-structure-token 'T_SWITCH)

                              (when phps-mode-functions-verbose
                                (message "Started switch alternative stack at %s" alternative-control-structure-level))

                              (push alternative-control-structure-level switch-alternative-stack))

                            (setq alternative-control-structure-level (1+ alternative-control-structure-level))

                            (when phps-mode-functions-verbose
                              (message "\nIncreasing alternative-control-structure after %s %s to %s\n" after-special-control-structure-token token alternative-control-structure-level))
                            )

                        ;; Don't start inline control structures after a while ($condition); expression
                        (unless (string= token ";")
                          (when phps-mode-functions-verbose
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
                      (when phps-mode-functions-verbose
                        (message "Ended concatenation"))
                      (pop in-concatenation-round-bracket-level)
                      (pop in-concatenation-square-bracket-level)
                      (unless in-concatenation-round-bracket-level
                        (setq in-concatenation nil))
                      (setq in-concatenation-level (1- in-concatenation-level)))
                  (when (and (> next-token-start-line-number token-end-line-number)
                             (or (string= token ".")
                                 (string= next-token ".")))
                    (when phps-mode-functions-verbose
                      (message "Started concatenation"))
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

                    (when phps-mode-functions-verbose
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
                    
                    (when phps-mode-functions-verbose
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
                      (when phps-mode-functions-verbose
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
                  (when phps-mode-functions-verbose
                    (message "Started assignment"))
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
                  (when phps-mode-functions-verbose
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
                      (when phps-mode-functions-verbose
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
                  (when phps-mode-functions-verbose
                    (message "After object-operator at %s level %s"  token in-object-operator-level))
                  (setq after-object-operator t))

                ;; Keep track of return expressions
                (when in-return
                  (when (and (string= token ";")
                             (= curly-bracket-level (car in-return-curly-bracket-level)))

                    (when phps-mode-functions-verbose
                      (message "Ended return at %s" token))
                    (pop in-return-curly-bracket-level)
                    (unless in-return-curly-bracket-level
                      (setq in-return nil))
                    (setq in-return-level (1- in-return-level))))
                (when (equal token 'T_RETURN)
                  (when phps-mode-functions-verbose
                    (message "Started return"))
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

                    (when phps-mode-functions-verbose
                      (message "Found CASE %s vs %s" (1- alternative-control-structure-level) (car switch-case-alternative-stack)))

                    (setq alternative-control-structure-level (1- alternative-control-structure-level))
                    (when first-token-on-line
                      (setq first-token-is-nesting-decrease t))
                    (pop switch-case-alternative-stack))

                  (push alternative-control-structure-level switch-case-alternative-stack)))

              (when token

                (when phps-mode-functions-verbose
                  (message "Processing token: %s" token))
                
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
                      (when phps-mode-functions-verbose
                        (message "\nPopping %s from nesting-stack since %s is lesser or equal to %s, next value is: %s\n" (car nesting-stack) nesting-end (car (car nesting-stack)) (nth 1 nesting-stack)))
                      (pop nesting-stack)
                      (setq nesting-decrement (1+ nesting-decrement)))

                    (if first-token-is-nesting-decrease

                        (progn
                          ;; Decrement column
                          (if allow-custom-column-decrement
                              (progn
                                (when phps-mode-functions-verbose
                                  (message "Doing custom decrement 1 from %s to %s" column-level (- column-level (- nesting-start nesting-end))))
                                (setq column-level (- column-level (- nesting-start nesting-end)))
                                (setq allow-custom-column-decrement nil))
                            (when phps-mode-functions-verbose
                              (message "Doing regular decrement 1 from %s to %s" column-level (1- column-level)))
                            (setq column-level (- column-level nesting-decrement)))

                          ;; Prevent negative column-values
                          (when (< column-level 0)
                            (setq column-level 0)))

                      (unless temp-post-indent
                        (when phps-mode-functions-verbose
                          (message "Temporary setting post indent %s" column-level))
                        (setq temp-post-indent column-level))

                      ;; Decrement column
                      (if allow-custom-column-decrement
                          (progn
                            (when phps-mode-functions-verbose
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

                    ;; Line logic
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
                      (when first-token-is-inline-html
                        (setq column-level-start inline-html-indent))

                      ;; Save line indent
                      (when phps-mode-functions-verbose
                        (message "Process line ending.	nesting: %s-%s,	line-number: %s-%s,	indent: %s.%s,	token: %s" nesting-start nesting-end token-start-line-number token-end-line-number column-level-start tuning-level token))

                      (when (> token-start-line-number 0)
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

                          (when phps-mode-functions-verbose
                            (message "\nPushing (%s %s %s %s) to nesting-stack since %s is greater than %s or stack is empty\n" nesting-start nesting-end nesting-key token nesting-end (car (cdr (car nesting-stack))))
                            )
                          (push `(,nesting-stack-end ,nesting-end ,nesting-key ,token) nesting-stack)
                          (when phps-mode-functions-verbose
                            ;; (message "New stack %s, start: %s end: %s\n" nesting-stack (car (car nesting-stack)) (car (cdr (car nesting-stack))))
                            )))


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
                              (puthash (- token-end-line-number token-line-number-diff) `(,column-level-end ,tuning-level) line-indents)
                              ;; (message "Saved line %s indent %s %s" (- token-end-line-number token-line-number-diff) column-level tuning-level)
                              (setq token-line-number-diff (1- token-line-number-diff))))

                          ;; Rest tuning-level used for comments
                          (setq tuning-level 0)))

                      ;; Indent token-less lines here in between last tokens if distance is more than 1 line
                      (when (and (> next-token-start-line-number (1+ token-end-line-number))
                                 (not (equal token 'T_CLOSE_TAG)))

                        (when phps-mode-functions-verbose
                          (message "\nDetected token-less lines between %s and %s, should have indent: %s\n" token-end-line-number next-token-start-line-number column-level))

                        (let ((token-line-number-diff (1- (- next-token-start-line-number token-end-line-number))))
                          (while (>= token-line-number-diff 0)
                            (puthash (- next-token-start-line-number token-line-number-diff) `(,column-level ,tuning-level) line-indents)
                            ;; (message "Saved line %s indent %s %s" (- token-end-line-number token-line-number-diff) column-level tuning-level)
                            (setq token-line-number-diff (1- token-line-number-diff)))))


                      ;; Calculate indentation level at start of line
                      (setq nesting-start (+ round-bracket-level square-bracket-level curly-bracket-level alternative-control-structure-level in-assignment-level in-class-declaration-level in-concatenation-level in-return-level in-object-operator-level))

                      ;; Set initial values for tracking first token
                      (when (> token-start-line-number last-line-number)
                        (setq first-token-on-line t)
                        (setq first-token-is-nesting-decrease nil)
                        (setq first-token-is-inline-html nil)
                        (setq in-class-declaration-level 0)
                        (setq class-declaration-started-this-line nil)
                        (setq in-heredoc-started-this-line nil)
                        (setq special-control-structure-started-this-line nil)))

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
          (setq phps-mode-functions-imenu (nreverse imenu-index))
          (setq phps-mode-functions-lines-indent line-indents)))
    (setq phps-mode-functions-imenu nil)
    (setq phps-mode-functions-lines-indent nil)))

(defun phps-mode-functions-around-newline (old-function &rest arguments)
  "Call OLD-FUNCTION with ARGUMENTS and then shift indexes if the rest of the line is just white-space."
  (if (string= major-mode "phps-mode")
      (progn
        ;; (message "Running advice")
        (let ((old-pos (point))
              (looking-at-whitespace (looking-at-p "[\ \n\t\r]*\n"))
              (old-line-number (line-number-at-pos)))

          (if looking-at-whitespace
              (progn
                ;; (message "Looking at white-space")

                ;; Temporarily disable change detection to not trigger incremental lexer

                ;; We move indexes before calling old-function
                ;; because old-function could be `newline-and-indent'
                ;; and this would trigger `indent-line'
                ;; which will trigger processing buffer
                (phps-mode-lexer-move-tokens old-pos 1)
                (phps-mode-lexer-move-states old-pos 1)
                (phps-mode-functions-move-imenu-index old-pos 1)
                (phps-mode-functions-move-lines-indent old-line-number 1)

                (setq phps-mode-functions-allow-after-change nil)
                (apply old-function arguments)
                (setq phps-mode-functions-allow-after-change t))

            (apply old-function arguments)
            ;; (message "Not looking at white-space")
            )))
    (apply old-function arguments)))

(defun phps-mode-functions-indent-line ()
  "Indent line."
  (phps-mode-functions-process-current-buffer)
  (when phps-mode-functions-lines-indent
    (let ((indent (gethash (line-number-at-pos (point)) phps-mode-functions-lines-indent)))
      (when indent
        ;; (message "indent: %s %s %s" indent (car indent) (car (cdr indent)))
        (let ((indent-sum (+ (* (car indent) tab-width) (car (cdr indent))))
              (current-indentation (current-indentation))
              (line-start (line-beginning-position)))

          (unless current-indentation
            (setq current-indentation 0))

          ;; Only continue if current indentation is wrong
          (unless (equal indent-sum current-indentation)
            (let ((indent-diff (- indent-sum current-indentation)))
              ;; (message "Indenting to %s current column %s" indent-sum (current-indentation))
              ;; (message "inside scripting, start: %s, end: %s, indenting to column %s " start end indent-level)

              (indent-line-to indent-sum)


              ;; When indent is changed the trailing tokens and states just need to adjust their positions, this will improve speed of indent-region a lot
              (phps-mode-lexer-move-tokens line-start indent-diff)
              (phps-mode-lexer-move-states line-start indent-diff)
              (phps-mode-functions-move-imenu-index line-start indent-diff)

              ;; (message "Diff after indent at %s is %s" line-start indent-diff)

              ;; Reset change flag
              (phps-mode-functions-reset-buffer-changes-start)

              )))))))

;; TODO Consider how indentation and imenu-index should be affected by this
(defun phps-mode-functions-after-change (start _stop _length)
  "Track buffer change from START to STOP with length LENGTH."
  (when phps-mode-functions-allow-after-change

    ;; If we haven't scheduled incremental lexer before - do it
    (when (and (not phps-mode-functions-buffer-changes-start)
               (boundp 'phps-mode-idle-interval)
               phps-mode-idle-interval)
      ;; (message "Enqueued incremental lexer")
      (run-with-idle-timer phps-mode-idle-interval nil #'phps-mode-lexer-run-incremental))

    ;; When point of change is not set or when start of new changes precedes old change - update the point
    (when (or (not phps-mode-functions-buffer-changes-start)
              (< start phps-mode-functions-buffer-changes-start))
      (setq phps-mode-functions-buffer-changes-start start)
      ;; (message "Setting start of changes to: %s-%s" phps-mode-functions-buffer-changes-start stop))

      ;; (message "phps-mode-functions-after-change %s %s %s" start stop length)
      )))

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
