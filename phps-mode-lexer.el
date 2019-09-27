;;; phps-mode-lexer.el -- Lexer for PHPs -*- lexical-binding: t -*-

;; Copyright (C) 2018-2019  Free Software Foundation, Inc.

;; This file is not part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.


;;; Commentary:

;; Based on the Zend PHP Lexer and Parser https://github.com/php/php-src/blob/master/Zend/zend_language_scanner.l
;; which is using re2c.
;;
;; NOTE Files of interest:
;; - zend_language_scanner.l


;;; Code:

;; NOTE We use autoload here to circumvent recursive require
(autoload 'phps-mode-functions--reset-changes "phps-mode-functions")
(autoload 'phps-mode-functions--cancel-idle-timer "phps-mode-functions")
(autoload 'phps-mode-functions--get-changes "phps-mode-functions")
(autoload 'phps-mode-get-syntax-table "phps-mode")
(autoload 'phps-mode-functions-processed-buffer "phps-mode-functions")
(autoload 'phps-mode-functions-reset-processed-buffer "phps-mode-functions")
(autoload 'phps-mode-runtime-debug-message "phps-mode")

(require 'semantic)
(require 'semantic/lex)

;; NOTE This line is required to pass byte-compilation
(require 'semantic/wisent)

(require 'phps-mode-macros)


;; Fix for byte-compilation warnings


;; Define the lexer for this grammar

;; Make sure `semantic-lex-syntax-modifications' is correct since lexer is dependent on Emacs syntax-table


(defvar phps-mode-lexer-tokens nil
  "Last lexer tokens.")

(defvar phps-mode-lexer-states nil
  "A list of lists containing start, state and state stack.")

(defvar phps-mode-lexer-buffer-length nil
  "Length of lexed buffer.")

(defvar phps-mode-lexer-buffer-contents nil
  "Contents of lexed buffer.")


;; SETTINGS


;; @see https://secure.php.net/manual/en/language.types.integer.php
(defvar phps-mode-lexer-long-limit 2147483648
  "Limit for 32-bit integer.")

(defvar phps-mode-lexer-PARSER_MODE t
  "Flag whether we is using parser-mode or not.")

(defvar phps-mode-lexer-SHORT_TAGS t
  "Flag whether we support short-tags or not.")


;; FLAGS/SIGNALS


(defvar phps-mode-lexer-declaring_namespace nil
  "Flag whether we are declaring namespace.")

(defvar phps-mode-lexer-prepend_trailing_brace nil
  "Flag whether we should prepend trailing brace.")

(defvar phps-mode-lexer-STATE nil
  "Current state.")

(defvar phps-mode-lexer-state_stack nil
  "Stack of states.")

(defvar phps-mode-lexer-EXPECTED nil
  "Flag whether something is expected or not.")

(defvar phps-mode-lexer-heredoc_label_stack (list)
  "The current heredoc_label.")

(defconst phps-mode-lexer-ST_INITIAL 0
  "Flag for initial state.")

(defconst phps-mode-lexer-ST_IN_SCRIPTING 1
  "Flag whether we are in script or not.")

(defconst phps-mode-lexer-ST_BACKQUOTE 2
  "Flag whether we are inside backquote or not.")

(defconst phps-mode-lexer-ST_DOUBLE_QUOTES 3
  "Flag whether we are inside double quotes or not.")

(defconst phps-mode-lexer-ST_END_HEREDOC 4
  "Flag whether we are inside end heredoc or not.")

(defconst phps-mode-lexer-ST_HEREDOC 5
  "Flag whether we are inside heredoc or not.")

(defconst phps-mode-lexer-ST_LOOKING_FOR_PROPERTY 6
  "Flag whether we are looking for property or not.")

(defconst phps-mode-lexer-ST_LOOKING_FOR_VARNAME 7
  "Flag whether we are looking for variable name or not.")

(defconst phps-mode-lexer-ST_NOWDOC 8
  "Flag whether we are inside nowdoc or not.")

(defconst phps-mode-lexer-ST_VAR_OFFSET 9
  "Flag whether we are looking for variable offset or not.")


;; REGULAR EXPRESSIONS


(defvar phps-mode-lexer-BNUM "0b[01]+"
  "Boolean number.")

(defvar phps-mode-lexer-HNUM "0x[0-9a-fA-F]+"
  "Hexadecimal number.")

(defvar phps-mode-lexer-LNUM "[0-9]+"
  "Long number.")

(defvar phps-mode-lexer-DNUM "\\([0-9]*\\.[0-9]+\\)\\|\\([0-9]+\\.[0-9]*\\)"
  "Double number.")

(defvar phps-mode-lexer-EXPONENT_DNUM
  (format "\\(\\(%s\\|%s\\)[eE][\\+-]?%s\\)"
          phps-mode-lexer-LNUM
          phps-mode-lexer-DNUM
          phps-mode-lexer-LNUM)
  "Exponent double number.")

(defvar phps-mode-lexer-LABEL
  "[A-Za-z_[:nonascii:]][0-9A-Za-z_[:nonascii:]]*"
  "Labels are used for names.")
;; NOTE original is [a-zA-Z_\x80-\xff][a-zA-Z0-9_\x80-\xff]*
;; NOTE Rebuilt for comparability with emacs-lisp

(defvar phps-mode-lexer-WHITESPACE "[ \n\r\t]+"
  "White-space.")

(defvar phps-mode-lexer-TABS_AND_SPACES "[ \t]*"
  "Tabs and white-spaces.")

(defvar phps-mode-lexer-TOKENS "[][;:,.()|^&+/*=%!~$<>?@-]"
  "Tokens.")
;; NOTE Original is [;:,.\[\]()|^&+-/*=%!~$<>?@]
;; NOTE The hyphen moved last since it has special meaning and to avoid it being interpreted as a range.

(defvar phps-mode-lexer-ANY_CHAR ".\\|\n"
  "Any character.  The Zend equivalent is [^] but is not possible in Emacs Lisp.")

(defvar phps-mode-lexer-NEWLINE "\\(\r\\|\n\\|\r\n\\)"
  "Newline characters.")


;; FUNCTIONS


(defun phps-mode-lexer-BEGIN (state)
  "Begin STATE."
  ;; (message "Begun state %s" state)
  (setq-local phps-mode-lexer-STATE state))

;; _yy_push_state
(defun phps-mode-lexer-yy_push_state (new-state)
  "Add NEW-STATE to stack and then begin state."
  (push phps-mode-lexer-STATE phps-mode-lexer-state_stack)
  ;; (message "Added state %s to stack begun state %s" phps-mode-lexer-STATE new-state)
  (phps-mode-lexer-BEGIN new-state))

(defun phps-mode-lexer-yy_pop_state ()
  "Pop current state from stack."
  (let ((old-state (pop phps-mode-lexer-state_stack)))
    ;; (message "Going back to poppped state %s" old-state)
    (if old-state
        (phps-mode-lexer-BEGIN old-state)
      (display-warning 'phps-mode "PHPs Lexer Error - Going back to nil?"))))

(defun phps-mode-lexer-MOVE_FORWARD (position)
  "Move forward to POSITION."
  (when (boundp 'semantic-lex-end-point)
    (setq semantic-lex-end-point position)))

(defun phps-mode-lexer-set-region-syntax-color (start end properties)
  "Do syntax coloring for region START to END with PROPERTIES."
  (with-silent-modifications (set-text-properties start end properties)))

(defun phps-mode-lexer-clear-region-syntax-color (start end)
  "Clear region of syntax coloring from START to END."
  (with-silent-modifications (set-text-properties start end nil)))

(defun phps-mode-lexer-get-token-syntax-color (token)
  "Return syntax color for TOKEN."
  ;; Syntax coloring
  ;; see https://www.gnu.org/software/emacs/manual/html_node/elisp/Faces-for-Font-Lock.html#Faces-for-Font-Lock
  ;; (message "Color token %s %s %s" token start end)
  (cond

   ((or
     (string= token 'T_VARIABLE)
     (string= token 'T_STRING_VARNAME))
    (list 'font-lock-face 'font-lock-variable-name-face))

   ((string= token 'T_COMMENT)
    (list 'font-lock-face 'font-lock-comment-face))

   ((string= token 'T_DOC_COMMENT)
    (list 'font-lock-face 'font-lock-doc-face))

   ((string= token 'T_INLINE_HTML)
    ;; NOTE T_INLINE_HTML is missing by purpose here to distinguish those areas from other entities
    nil)

   ((or
     (string= token 'T_STRING)
     (string= token 'T_CONSTANT_ENCAPSED_STRING)
     (string= token 'T_ENCAPSED_AND_WHITESPACE)
     (string= token 'T_NUM_STRING)
     (string= token 'T_DNUMBER)
     (string= token 'T_LNUMBER))
    (list 'font-lock-face 'font-lock-string-face))

   ((or
     (string= token 'T_DOLLAR_OPEN_CURLY_BRACES)
     (string= token 'T_CURLY_OPEN)
     (string= token 'T_OBJECT_OPERATOR)
     (string= token 'T_PAAMAYIM_NEKUDOTAYIM)
     (string= token 'T_NS_SEPARATOR)
     (string= token 'T_EXIT)
     (string= token 'T_DIE)
     (string= token 'T_RETURN)
     (string= token 'T_YIELD_FROM)
     (string= token 'T_YIELD)
     (string= token 'T_TRY)
     (string= token 'T_CATCH)
     (string= token 'T_FINALLY)
     (string= token 'T_THROW)
     (string= token 'T_IF)
     (string= token 'T_ELSEIF)
     (string= token 'T_ENDIF)
     (string= token 'T_ELSE)
     (string= token 'T_WHILE)
     (string= token 'T_ENDWHILE)
     (string= token 'T_DO)
     (string= token 'T_FUNCTION)
     (string= token 'T_CONST)
     (string= token 'T_FOREACH)
     (string= token 'T_ENDFOREACH)
     (string= token 'T_FOR)
     (string= token 'T_ENDFOR)
     (string= token 'T_DECLARE)
     (string= token 'T_ENDDECLARE)
     (string= token 'T_INSTANCEOF)
     (string= token 'T_AS)
     (string= token 'T_SWITCH)
     (string= token 'T_ENDSWITCH)
     (string= token 'T_CASE)
     (string= token 'T_DEFAULT)
     (string= token 'T_BREAK)
     (string= token 'T_CONTINUE)
     (string= token 'T_GOTO)
     (string= token 'T_ECHO)
     (string= token 'T_PRINT)
     (string= token 'T_CLASS)
     (string= token 'T_INTERFACE)
     (string= token 'T_TRAIT)
     (string= token 'T_EXTENDS)
     (string= token 'T_IMPLEMENTS)
     (string= token 'T_NEW)
     (string= token 'T_CLONE)
     (string= token 'T_VAR)
     (string= token 'T_EVAL)
     (string= token 'T_INCLUDE_ONCE)
     (string= token 'T_INCLUDE)
     (string= token 'T_REQUIRE_ONCE)
     (string= token 'T_REQUIRE)
     (string= token 'T_NAMESPACE)
     (string= token 'T_USE)
     (string= token 'T_INSTEADOF)
     (string= token 'T_GLOBAL)
     (string= token 'T_ISSET)
     (string= token 'T_EMPTY)
     (string= token 'T_HALT_COMPILER)
     (string= token 'T_STATIC)
     (string= token 'T_ABSTRACT)
     (string= token 'T_FINAL)
     (string= token 'T_PRIVATE)
     (string= token 'T_PROTECTED)
     (string= token 'T_PUBLIC)
     (string= token 'T_UNSET)
     (string= token 'T_LIST)
     (string= token 'T_ARRAY)
     (string= token 'T_CALLABLE)
     )
    (list 'font-lock-face 'font-lock-keyword-face))

   ((or
     (string= token 'T_OPEN_TAG)
     (string= token 'T_OPEN_TAG_WITH_ECHO)
     (string= token 'T_CLOSE_TAG)
     (string= token 'T_START_HEREDOC)
     (string= token 'T_END_HEREDOC)
     (string= token 'T_ELLIPSIS)
     (string= token 'T_COALESCE)
     (string= token 'T_DOUBLE_ARROW)
     (string= token 'T_INC)
     (string= token 'T_DEC)
     (string= token 'T_IS_IDENTICAL)
     (string= token 'T_IS_NOT_IDENTICAL)
     (string= token 'T_IS_EQUAL)
     (string= token 'T_IS_NOT_EQUAL)
     (string= token 'T_SPACESHIP)
     (string= token 'T_IS_SMALLER_OR_EQUAL)
     (string= token 'T_IS_GREATER_OR_EQUAL)
     (string= token 'T_PLUS_EQUAL)
     (string= token 'T_MINUS_EQUAL)
     (string= token 'T_MUL_EQUAL)
     (string= token 'T_POW_EQUAL)
     (string= token 'T_POW)
     (string= token 'T_DIV_EQUAL)
     (string= token 'T_CONCAT_EQUAL)
     (string= token 'T_MOD_EQUAL)
     (string= token 'T_SL_EQUAL)
     (string= token 'T_SR_EQUAL)
     (string= token 'T_AND_EQUAL)
     (string= token 'T_OR_EQUAL)
     (string= token 'T_XOR_EQUAL)
     (string= token 'T_COALESCE_EQUAL)
     (string= token 'T_BOOLEAN_OR)
     (string= token 'T_BOOLEAN_AND)
     (string= token 'T_BOOLEAN_XOR)
     (string= token 'T_LOGICAL_XOR)
     (string= token 'T_LOGICAL_OR)
     (string= token 'T_LOGICAL_AND)
     (string= token 'T_SL)
     (string= token 'T_SR)
     (string= token 'T_CLASS_C)
     (string= token 'T_TRAIT_C)
     (string= token 'T_FUNC_C)
     (string= token 'T_METHOD_C)
     (string= token 'T_LINE)
     (string= token 'T_FILE)
     (string= token 'T_DIR)
     (string= token 'T_NS_C)
     (string= token 'T_INT_CAST)
     (string= token 'T_DOUBLE_CAST)
     (string= token 'T_STRING_CAST)
     (string= token 'T_ARRAY_CAST)
     (string= token 'T_OBJECT_CAST)
     (string= token 'T_BOOL_CAST)
     (string= token 'T_UNSET_CAST)
     )
    (list 'font-lock-face 'font-lock-constant-face))

   (t (list 'font-lock-face 'font-lock-constant-face))))

(defun phps-mode-lexer-RETURN_TOKEN (token start end)
  "Push TOKEN to list with START and END."

  ;; Colourize token
  (when-let (token-syntax-color (phps-mode-lexer-get-token-syntax-color token))
    (phps-mode-lexer-set-region-syntax-color start end token-syntax-color))

  ;; Push token start, end, lexer state and state stack to variable
  (push
   (list start end phps-mode-lexer-STATE phps-mode-lexer-state_stack) phps-mode-lexer-states)

  (semantic-lex-push-token (semantic-lex-token token start end)))

;; TODO Figure out what this does
(defun phps-mode-lexer-SKIP_TOKEN (_token _start _end)
  "Skip TOKEN to list with START and END.")

(defvar phps-mode-lexer-re2c-matching-body nil
  "Lambda-expression for longest matching condition.")

(defvar phps-mode-lexer-re2c-matching-length nil
  "Length of longest matching condition.")

(defvar phps-mode-lexer-re2c-matching-data nil
  "Match data for longest matching condition.")

(defun phps-mode-lexer-re2c-rule (condition body)
  "Process rule with CONDITION and BODY."
  (when condition
    (let ((match-end (match-end 0))
          (match-beginning (match-beginning 0)))
      (let ((matching-length (- match-end match-beginning)))
        (when (> matching-length 0)
          (when (or (not phps-mode-lexer-re2c-matching-length)
                    (> matching-length phps-mode-lexer-re2c-matching-length))
            (setq phps-mode-lexer-re2c-matching-length matching-length)
            (setq phps-mode-lexer-re2c-matching-data (match-data))
            (setq phps-mode-lexer-re2c-matching-body body)))))))

(defun phps-mode-lexer-re2c-execute ()
  "Execute matching body (if any)."
  (if phps-mode-lexer-re2c-matching-body
      (progn
        
        ;; (message "Executing body: %s" phps-mode-lexer-re2c-matching-body)
        ;; (message "Found match %s" phps-mode-lexer-re2c-matching-data)
        (set-match-data phps-mode-lexer-re2c-matching-data)
        (funcall phps-mode-lexer-re2c-matching-body))
    (error "Failed to lex input")))


;; LEXERS

;; If multiple rules match, re2c prefers the longest match. If rules match the same string, the earlier rule has priority.
;; @see http://re2c.org/manual/syntax/syntax.html
(define-lex-analyzer phps-mode-lexer-lex-analyzer
  "Elisp port of original Zend re2c lexer."
  t

  (let ((old-start (point)))
    (if phps-mode-lexer-tokens
        (progn
          ;; Add all updated tokens to semantic
          (phps-mode-debug-message (message "Updating semantic lexer tokens from point %s, tokens: %s, point-max: %s" old-start phps-mode-lexer-tokens (point-max)))
          (dolist (token phps-mode-lexer-tokens)
            (let ((start (car (cdr token)))
                  (end (cdr (cdr token)))
                  (token-name (car token)))
              (phps-mode-lexer-set-region-syntax-color
               start end  (phps-mode-lexer-get-token-syntax-color token-name))
              (semantic-lex-push-token (semantic-lex-token token-name start end))))

          (phps-mode-lexer-MOVE_FORWARD (point-max)))

      (phps-mode-debug-message (message "Running lexer from %s" old-start))
      
      (let ((heredoc_label (car phps-mode-lexer-heredoc_label_stack))
            (ST_IN_SCRIPTING (= phps-mode-lexer-STATE phps-mode-lexer-ST_IN_SCRIPTING))
            (ST_INITIAL (= phps-mode-lexer-STATE phps-mode-lexer-ST_INITIAL))
            (ST_LOOKING_FOR_PROPERTY (= phps-mode-lexer-STATE phps-mode-lexer-ST_LOOKING_FOR_PROPERTY))
            (ST_DOUBLE_QUOTES (= phps-mode-lexer-STATE phps-mode-lexer-ST_DOUBLE_QUOTES))
            (ST_BACKQUOTE (= phps-mode-lexer-STATE phps-mode-lexer-ST_BACKQUOTE))
            (ST_HEREDOC (= phps-mode-lexer-STATE phps-mode-lexer-ST_HEREDOC))
            (ST_NOWDOC (= phps-mode-lexer-STATE phps-mode-lexer-ST_NOWDOC))
            (ST_LOOKING_FOR_VARNAME (= phps-mode-lexer-STATE phps-mode-lexer-ST_LOOKING_FOR_VARNAME))
            (ST_END_HEREDOC (= phps-mode-lexer-STATE phps-mode-lexer-ST_END_HEREDOC))
            (ST_VAR_OFFSET (= phps-mode-lexer-STATE phps-mode-lexer-ST_VAR_OFFSET)))

        ;; Reset re2c flags
        (setq phps-mode-lexer-re2c-matching-body nil)
        (setq phps-mode-lexer-re2c-matching-length nil)

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "exit"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_EXIT (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "die" ))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_DIE (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "function"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_FUNCTION (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "const"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_CONST (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "return"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_RETURN (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at (concat "yield" phps-mode-lexer-WHITESPACE "from" "[^a-zA-Z0-9_\x80-\xff]")))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_YIELD_FROM (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "yield"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_YIELD (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "try"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_TRY (match-beginning 0) (match-end 0))))0

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "catch"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_CATCH (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "finally"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_FINALLY (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "throw"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_THROW (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "if"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_IF (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "elseif"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_ELSEIF (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "endif"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_ENDIF (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "else"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_ELSE (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "while"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_WHILE (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "endwhile"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_ENDWHILE (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "do"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_DO (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "for"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_FOR (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "endfor"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_ENDFOR (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "foreach"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_FOREACH (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "endforeach"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_ENDFOREACH (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "declare"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_DECLARE (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "enddeclare"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_ENDDECLARE (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "instanceof"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_INSTANCEOF (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "as"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_AS (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "switch"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_SWITCH (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "endswitch"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_ENDSWITCH (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "case"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_CASE (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "default"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_DEFAULT (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "break"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_BREAK (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "continue"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_CONTINUE (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "goto"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_GOTO (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "echo"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_ECHO (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "print"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_PRINT (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "class"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_CLASS (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "interface"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_INTERFACE (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "trait"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_TRAIT (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "extends"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_EXTENDS (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "implements"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_IMPLEMENTS (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "->"))
         (lambda()
           (phps-mode-lexer-yy_push_state phps-mode-lexer-ST_LOOKING_FOR_PROPERTY)
           (phps-mode-lexer-RETURN_TOKEN 'T_OBJECT_OPERATOR (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and (or ST_IN_SCRIPTING ST_LOOKING_FOR_PROPERTY)
              (looking-at phps-mode-lexer-WHITESPACE))
         (lambda()
           (let* ((start (match-beginning 0))
                  (end (match-end 0))
                  (data (buffer-substring-no-properties start end)))
             (if phps-mode-lexer-PARSER_MODE
                 (phps-mode-lexer-MOVE_FORWARD end)
               (phps-mode-lexer-RETURN_TOKEN data start end)))))

        (phps-mode-lexer-re2c-rule
         (and ST_LOOKING_FOR_PROPERTY (looking-at "->"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_OBJECT_OPERATOR (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_LOOKING_FOR_PROPERTY (looking-at phps-mode-lexer-LABEL))
         (lambda()
           (let ((start (match-beginning 0))
                 (end (match-end 0)))
             (phps-mode-lexer-yy_pop_state)
             (phps-mode-lexer-RETURN_TOKEN 'T_STRING start end))))

        (phps-mode-lexer-re2c-rule
         (and ST_LOOKING_FOR_PROPERTY (looking-at phps-mode-lexer-ANY_CHAR))
         (lambda()
           (let ((_start (match-beginning 0))
                 (end (match-end 0)))
             (phps-mode-lexer-yy_pop_state)
             ;; TODO goto restart here?
             ;; (message "Restart here")
             (phps-mode-lexer-MOVE_FORWARD end))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "::"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_PAAMAYIM_NEKUDOTAYIM (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "\\\\"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_NS_SEPARATOR (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "\\.\\.\\."))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_ELLIPSIS (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "\\?\\?"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_COALESCE (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "new"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_NEW (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "clone"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_CLONE (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "var"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_VAR (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at (concat "(" phps-mode-lexer-TABS_AND_SPACES "\\(int\\|integer\\)" phps-mode-lexer-TABS_AND_SPACES ")")))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_INT_CAST (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at (concat "(" phps-mode-lexer-TABS_AND_SPACES "\\(real\\|double\\|float\\)" phps-mode-lexer-TABS_AND_SPACES ")")))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_DOUBLE_CAST (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at (concat "(" phps-mode-lexer-TABS_AND_SPACES "\\(string\\|binary\\)" phps-mode-lexer-TABS_AND_SPACES ")")))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_STRING_CAST (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at (concat "(" phps-mode-lexer-TABS_AND_SPACES "array" phps-mode-lexer-TABS_AND_SPACES ")")))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_ARRAY_CAST (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at (concat "(" phps-mode-lexer-TABS_AND_SPACES "object" phps-mode-lexer-TABS_AND_SPACES ")")))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_OBJECT_CAST (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at (concat "(" phps-mode-lexer-TABS_AND_SPACES "\\(bool\\|boolean\\)" phps-mode-lexer-TABS_AND_SPACES ")")))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_BOOL_CAST (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at (concat "(" phps-mode-lexer-TABS_AND_SPACES "unset" phps-mode-lexer-TABS_AND_SPACES ")")))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_UNSET_CAST (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "eval"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_EVAL (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "include"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_INCLUDE (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "include_once"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_INCLUDE_ONCE (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "require"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_REQUIRE (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "require_once"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_REQUIRE_ONCE (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "namespace"))
         (lambda()
           (setq phps-mode-lexer-declaring_namespace t)
           (phps-mode-lexer-RETURN_TOKEN 'T_NAMESPACE (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "use"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_USE (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "insteadof"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_INSTEADOF (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "global"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_GLOBAL (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "isset"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_ISSET (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "empty"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_EMPTY (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "__halt_compiler"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_HALT_COMPILER (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "static"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_STATIC (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "abstract"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_ABSTRACT (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "final"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_FINAL (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "private"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_PRIVATE (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "protected"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_PROTECTED (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "public"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_PUBLIC (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "unset"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_UNSET (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "=>"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_DOUBLE_ARROW (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "list"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_LIST (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "array"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_ARRAY (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "callable"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_CALLABLE (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "\\+\\+"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_INC (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "--"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_DEC (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "==="))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_IS_IDENTICAL (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "!=="))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_IS_NOT_IDENTICAL (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "=="))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_IS_EQUAL (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "\\(!=\\|<>\\)"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_IS_NOT_EQUAL (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "<=>"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_SPACESHIP (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "<="))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_IS_SMALLER_OR_EQUAL (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at ">="))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_IS_GREATER_OR_EQUAL (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "\\+="))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_PLUS_EQUAL (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "-="))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_MINUS_EQUAL (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "\\*="))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_MUL_EQUAL (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "\\*\\\\\\*="))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_POW_EQUAL (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "\\*\\\\\\*"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_POW (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "/="))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_DIV_EQUAL (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "\\.="))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_CONCAT_EQUAL (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "%="))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_MOD_EQUAL (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "<<="))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_SL_EQUAL (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at ">>="))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_SR_EQUAL (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "&="))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_AND_EQUAL (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "|="))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_OR_EQUAL (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "\\^="))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_XOR_EQUAL (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "\\?\\?="))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_COALESCE_EQUAL (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "||"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_BOOLEAN_OR (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "&&"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_BOOLEAN_AND (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "OR"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_LOGICAL_OR (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "AND"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_LOGICAL_AND (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "XOR"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_LOGICAL_XOR (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "<<"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_SL (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at ">>"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_SR (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at phps-mode-lexer-TOKENS))
         (lambda()
           (let* ((start (match-beginning 0))
                  (end (match-end 0))
                  (data (buffer-substring-no-properties start end))
                  (use-brace nil))
             ;; (message "Found token '%s'" data)
             (when phps-mode-lexer-declaring_namespace
               (when (string= data ";")
                 (setq phps-mode-lexer-prepend_trailing_brace t)
                 ;; (message "Set flag prepend trailing brace")
                 ;; (setq use-brace t)
                 )
               (setq phps-mode-lexer-declaring_namespace nil))
             (if use-brace
                 (phps-mode-lexer-RETURN_TOKEN "{" start end)
               (phps-mode-lexer-RETURN_TOKEN data start end)))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "{"))
         (lambda()
           (phps-mode-lexer-yy_push_state phps-mode-lexer-ST_IN_SCRIPTING)
           (when phps-mode-lexer-declaring_namespace
             (setq phps-mode-lexer-declaring_namespace nil))
           (phps-mode-lexer-RETURN_TOKEN "{" (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and (or ST_DOUBLE_QUOTES ST_BACKQUOTE ST_HEREDOC) (looking-at "\\${"))
         (lambda()
           (phps-mode-lexer-yy_push_state phps-mode-lexer-ST_LOOKING_FOR_VARNAME)
           (phps-mode-lexer-RETURN_TOKEN 'T_DOLLAR_OPEN_CURLY_BRACES (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "}"))
         (lambda()
           (when phps-mode-lexer-state_stack
             ;; (message "State stack %s" phps-mode-lexer-state_stack)
             ;; (message "popping state from } %s at %s-%s" (length phps-mode-lexer-state_stack) (match-beginning 0) (match-end 0))
             (phps-mode-lexer-yy_pop_state)
             ;; (message "New state: %s" phps-mode-lexer-STATE)
             )
           (phps-mode-lexer-RETURN_TOKEN "}" (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_LOOKING_FOR_VARNAME (looking-at (concat phps-mode-lexer-LABEL "[\\[}]")))
         (lambda()
           (let ((start (match-beginning 0))
                 (end (- (match-end 0) 1)))
             ;; (message "Stopped here")
             (phps-mode-lexer-yy_pop_state)
             (phps-mode-lexer-yy_push_state phps-mode-lexer-ST_IN_SCRIPTING)
             (phps-mode-lexer-RETURN_TOKEN 'T_STRING_VARNAME start end))))

        (phps-mode-lexer-re2c-rule
         (and ST_LOOKING_FOR_VARNAME (looking-at phps-mode-lexer-ANY_CHAR))
         (lambda()
           (phps-mode-lexer-yy_pop_state)
           (phps-mode-lexer-yy_push_state phps-mode-lexer-ST_IN_SCRIPTING)))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at phps-mode-lexer-BNUM))
         (lambda()
           (let* ((start (match-beginning 0))
                  (end (match-end 0))
                  (data (buffer-substring-no-properties (+ start 2) end))
                  (long-number (string-to-number data 2)))
             ;; (message "Binary number %s from %s" long-number data)
             (if (> long-number phps-mode-lexer-long-limit)
                 (phps-mode-lexer-RETURN_TOKEN 'T_DNUMBER start end)
               (phps-mode-lexer-RETURN_TOKEN 'T_LNUMBER start end)))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at phps-mode-lexer-LNUM))
         (lambda()
           (let* ((start (match-beginning 0))
                  (end (match-end 0))
                  (data (string-to-number (buffer-substring-no-properties start end))))
             ;; (message "Long number: %d" data)
             (if (> data phps-mode-lexer-long-limit)
                 (phps-mode-lexer-RETURN_TOKEN 'T_DNUMBER start end)
               (phps-mode-lexer-RETURN_TOKEN 'T_LNUMBER start end)))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at phps-mode-lexer-HNUM))
         (lambda()
           (let* ((start (match-beginning 0))
                  (end (match-end 0))
                  (data (buffer-substring-no-properties (+ start 2) end))
                  (long-number (string-to-number data 16)))
             ;; (message "Hexadecimal number %s from %s" long-number data)
             (if (> long-number phps-mode-lexer-long-limit)
                 (phps-mode-lexer-RETURN_TOKEN 'T_DNUMBER start end)
               (phps-mode-lexer-RETURN_TOKEN 'T_LNUMBER start end)))))

        (phps-mode-lexer-re2c-rule
         (and ST_VAR_OFFSET (looking-at "\\([0]\\|[1-9][0-9]*\\)"))
         (lambda()
           (let ((start (match-beginning 0))
                 (end (match-end 0)))
             (phps-mode-lexer-RETURN_TOKEN 'T_NUM_STRING start end))))

        (phps-mode-lexer-re2c-rule
         (and ST_VAR_OFFSET (looking-at (concat "\\("
                                                phps-mode-lexer-LNUM "\\|"
                                                phps-mode-lexer-HNUM "\\|"
                                                phps-mode-lexer-BNUM "\\)")))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_NUM_STRING (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (or (looking-at phps-mode-lexer-EXPONENT_DNUM)
                                  (looking-at phps-mode-lexer-DNUM)))
         (lambda()
           (let* ((start (match-beginning 0))
                  (end (match-end 0))
                  (_data (buffer-substring-no-properties start end)))
             ;; (message "Exponent/double at: %s" _data)
             (phps-mode-lexer-RETURN_TOKEN 'T_DNUMBER start end))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "__CLASS__"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_CLASS_C (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "__TRAIT__"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_TRAIT_C (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "__FUNCTION__"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_FUNC_C (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "__METHOD__"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_METHOD_C (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "__LINE__"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_LINE (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "__FILE__"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_FILE (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "__DIR__"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_DIR (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "__NAMESPACE__"))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_NS_C (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_INITIAL (looking-at "<\\?="))
         (lambda()
           (let ((start (match-beginning 0))
                 (end (match-end 0)))
             (phps-mode-lexer-BEGIN phps-mode-lexer-ST_IN_SCRIPTING)
             ;; (message "Starting scripting after <?=")
             (when phps-mode-lexer-PARSER_MODE
               (phps-mode-lexer-RETURN_TOKEN 'T_ECHO start end))
             (phps-mode-lexer-RETURN_TOKEN 'T_OPEN_TAG_WITH_ECHO start end))))

        (phps-mode-lexer-re2c-rule
         (and ST_INITIAL (looking-at "<\\?php\\([ \t]\\|\n\\)"))
         (lambda()
           (let ((start (match-beginning 0))
                 (end (match-end 0)))
             (phps-mode-lexer-BEGIN phps-mode-lexer-ST_IN_SCRIPTING)
             ;; (message "Starting scripting after <?php")
             (when phps-mode-lexer-EXPECTED
               (phps-mode-lexer-SKIP_TOKEN 'T_OPEN_TAG start end))
             (phps-mode-lexer-RETURN_TOKEN 'T_OPEN_TAG start end))))

        (phps-mode-lexer-re2c-rule
         (and ST_INITIAL (looking-at "<\\?"))
         (lambda()
           (when phps-mode-lexer-SHORT_TAGS
             (let ((start (match-beginning 0))
                   (end (match-end 0)))
               (phps-mode-lexer-BEGIN phps-mode-lexer-ST_IN_SCRIPTING)
               (when phps-mode-lexer-EXPECTED
                 (phps-mode-lexer-SKIP_TOKEN 'T_OPEN_TAG start end))
               ;; (message "Starting scripting after <?")
               (phps-mode-lexer-RETURN_TOKEN 'T_OPEN_TAG start end)))))

        ;; NOTE: mimics inline_char_handler
        (phps-mode-lexer-re2c-rule
         (and ST_INITIAL (looking-at phps-mode-lexer-ANY_CHAR))
         (lambda()
           (let ((start (match-beginning 0)))
             (let ((string-start (search-forward "<?" nil t)))
               (if string-start
                   (phps-mode-lexer-RETURN_TOKEN 'T_INLINE_HTML start (- string-start 2))
                 (phps-mode-lexer-RETURN_TOKEN 'T_INLINE_HTML start (point-max)))))))

        (phps-mode-lexer-re2c-rule
         (and (or ST_DOUBLE_QUOTES ST_HEREDOC ST_BACKQUOTE) (looking-at (concat "\\$" phps-mode-lexer-LABEL "->" "[a-zA-Z_\x80-\xff]")))
         (lambda()
           (phps-mode-lexer-yy_push_state phps-mode-lexer-ST_LOOKING_FOR_PROPERTY)
           (forward-char -3)
           (phps-mode-lexer-RETURN_TOKEN 'T_VARIABLE (match-beginning 0) (- (match-end 0) 3))))

        (phps-mode-lexer-re2c-rule
         (and (or ST_DOUBLE_QUOTES ST_HEREDOC ST_BACKQUOTE) (looking-at (concat "\\$" phps-mode-lexer-LABEL "\\[")))
         (lambda()
           (phps-mode-lexer-yy_push_state phps-mode-lexer-ST_VAR_OFFSET)
           (phps-mode-lexer-RETURN_TOKEN 'T_VARIABLE (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and (or ST_IN_SCRIPTING ST_DOUBLE_QUOTES ST_HEREDOC ST_BACKQUOTE ST_VAR_OFFSET) (looking-at (concat "\\$" phps-mode-lexer-LABEL)))
         (lambda()
           (phps-mode-lexer-RETURN_TOKEN 'T_VARIABLE (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_VAR_OFFSET (looking-at "\\]"))
         (lambda()
           (phps-mode-lexer-yy_pop_state)
           (phps-mode-lexer-RETURN_TOKEN "]" (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_VAR_OFFSET (looking-at (concat "\\(" phps-mode-lexer-TOKENS
                                                "\\|[{}\"`]\\)")))
         (lambda()
           (let* ((start (match-beginning 0))
                  (end (match-end 0))
                  (data (buffer-substring-no-properties start end)))
             (phps-mode-lexer-RETURN_TOKEN data start end))))

        (phps-mode-lexer-re2c-rule
         (and ST_VAR_OFFSET (looking-at (concat "[ \n\r\t'#]")))
         (lambda()
           (let* ((start (match-beginning 0))
                  (end (- (match-end 0) 1)))
             (phps-mode-lexer-yy_pop_state)
             (phps-mode-lexer-RETURN_TOKEN 'T_ENCAPSED_AND_WHITESPACE start end))))

        (phps-mode-lexer-re2c-rule
         (and (or ST_IN_SCRIPTING ST_VAR_OFFSET) (looking-at phps-mode-lexer-LABEL))
         (lambda()
           ;; (message "Adding T_STRING from %s to %s" (match-beginning 0) (match-end 0))
           (phps-mode-lexer-RETURN_TOKEN 'T_STRING (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "\\(#\\|//\\)"))
         (lambda()
           (let* ((start (match-beginning 0))
                  (end (match-end 0))
                  (_data (buffer-substring-no-properties start end))
                  (line (buffer-substring-no-properties end (line-end-position))))
             (if (string-match "\\?>" line)
                 (progn
                   ;; (message "Found comment 1 from %s to %s %s in %s" end (+ end (match-beginning 0)) (match-beginning 0) line)
                   (phps-mode-lexer-RETURN_TOKEN 'T_COMMENT start (+ end (match-beginning 0)))
                   )
               (progn
                 ;; TODO Handle expecting values here
                 ;; (message "Found comment 2 from %s to %s" start (line-end-position))
                 (phps-mode-lexer-RETURN_TOKEN 'T_COMMENT start (line-end-position)))))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at (concat "\\(/\\*\\|/\\*\\*" phps-mode-lexer-WHITESPACE "\\)")))
         (lambda()
           (let* ((start (match-beginning 0))
                  (end (match-end 0))
                  (_data (buffer-substring-no-properties start end))
                  (doc-com (looking-at-p (concat "/\\*\\*" phps-mode-lexer-WHITESPACE))))
             (let ((string-start (search-forward "*/" nil t)))
               (if string-start
                   (if doc-com
                       (phps-mode-lexer-RETURN_TOKEN 'T_DOC_COMMENT start (match-end 0))
                     (phps-mode-lexer-RETURN_TOKEN 'T_COMMENT start (match-end 0)))
                 (progn
                   (display-warning 'phps-mode (format "PHPs Lexer Error - Unterminated comment starting at %s" (point)))
                   (phps-mode-lexer-MOVE_FORWARD (point-max))))))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "\\?>\n?"))
         (lambda()
           (let ((start (match-beginning 0))
                 (end (match-end 0)))
             (when (= (- end start) 3)
               (setq end (1- end)))
             (phps-mode-lexer-BEGIN phps-mode-lexer-ST_INITIAL)
             (when phps-mode-lexer-PARSER_MODE
               (phps-mode-lexer-RETURN_TOKEN ";" start end))
             (phps-mode-lexer-RETURN_TOKEN 'T_CLOSE_TAG start end))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "'"))
         (lambda()
           (let* ((start (match-beginning 0))
                  (end (match-end 0))
                  (_data (buffer-substring-no-properties start end))
                  (un-escaped-end (phps-mode-lexer--get-next-unescaped "'")))
             (if un-escaped-end
                 (progn
                   ;; (message "Single quoted string %s" (buffer-substring-no-properties start un-escaped-end))
                   (phps-mode-lexer-RETURN_TOKEN 'T_CONSTANT_ENCAPSED_STRING start un-escaped-end))
               (progn
                 ;; Unclosed single quotes
                 ;; (message "Single quoted string never ends..")
                 (phps-mode-lexer-RETURN_TOKEN 'T_ENCAPSED_AND_WHITESPACE start (point-max))
                 (phps-mode-lexer-MOVE_FORWARD (point-max)))))))

        ;; Double quoted string
        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "\""))
         (lambda()
           (let* ((start (match-beginning 0))
                  (end (match-end 0))
                  (_data (buffer-substring-no-properties start end))
                  (open-quote t))

             ;; Move forward from the double-quote
             (forward-char)

             (while open-quote
               (let ((string-start (search-forward-regexp (concat
                                                           "\\(\""
                                                           "\\|\\$" phps-mode-lexer-LABEL
                                                           "\\|\\${" phps-mode-lexer-LABEL
                                                           "\\|{\\$" phps-mode-lexer-LABEL "\\)")
                                                          nil t)))

                 ;; Do we find a ending double quote or starting variable?
                 (if string-start
                     (let ((string-start (match-beginning 0))
                           (is-escaped nil))

                       ;; Go to character before match start
                       (goto-char (1- string-start))

                       ;; Store whether character is escaped or not
                       (setq is-escaped (looking-at-p "\\\\"))

                       ;; Do we find variable inside quote?
                       (goto-char string-start)

                       ;; Process character if it's not escaped
                       (if is-escaped
                           (forward-char 2)
                         (setq open-quote nil)
                         (if (looking-at "\"")
                             (let ((_double-quoted-string (buffer-substring-no-properties start (+ string-start 1))))
                               ;; (message "Double quoted string: %s" _double-quoted-string)
                               (phps-mode-lexer-RETURN_TOKEN 'T_CONSTANT_ENCAPSED_STRING start (+ string-start 1)))
                           ;; (message "Found variable after '%s'" (buffer-substring-no-properties start string-start))
                           (phps-mode-lexer-BEGIN phps-mode-lexer-ST_DOUBLE_QUOTES)
                           (phps-mode-lexer-RETURN_TOKEN "\"" start (1+ start))
                           (phps-mode-lexer-RETURN_TOKEN 'T_ENCAPSED_AND_WHITESPACE (1+ start) string-start))))
                   (progn
                     (display-warning 'phps-mode (format "Found no ending of quote at %s" (point)))
                     (phps-mode-lexer-MOVE_FORWARD (point-max))
                     (setq open-quote nil))))))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at (concat "<<<" phps-mode-lexer-TABS_AND_SPACES "\\(" phps-mode-lexer-LABEL "\\|'" phps-mode-lexer-LABEL "'\\|\"" phps-mode-lexer-LABEL "\"\\)" phps-mode-lexer-NEWLINE)))
         (lambda()
           (let* ((start (match-beginning 0))
                  (end (match-end 0))
                  (data (buffer-substring-no-properties (match-beginning 1) (match-end 1)))
                  (heredoc_label))

             ;; Determine if it's HEREDOC or NOWDOC and extract label here
             (if (string= (substring data 0 1) "'")
                 (progn
                   (setq heredoc_label (substring data 1 (- (length data) 1)))
                   (phps-mode-lexer-BEGIN phps-mode-lexer-ST_NOWDOC))
               (progn
                 (if (string= (substring data 0 1) "\"")
                     (setq heredoc_label (substring data 1 (- (length data) 1)))
                   (setq heredoc_label data))
                 (phps-mode-lexer-BEGIN phps-mode-lexer-ST_HEREDOC)))

             ;; Check for ending label on the next line
             (when (string= (buffer-substring-no-properties end (+ end (length heredoc_label))) heredoc_label)
               (phps-mode-lexer-BEGIN phps-mode-lexer-ST_END_HEREDOC))

             (push heredoc_label phps-mode-lexer-heredoc_label_stack)
             ;; (message "Found heredoc or nowdoc at %s with label %s" data heredoc_label)

             (phps-mode-lexer-RETURN_TOKEN 'T_START_HEREDOC start end))))

        (phps-mode-lexer-re2c-rule
         (and ST_IN_SCRIPTING (looking-at "[`]"))
         (lambda()
           ;; (message "Begun backquote at %s-%s" (match-beginning 0) (match-end 0))
           (phps-mode-lexer-BEGIN phps-mode-lexer-ST_BACKQUOTE)
           (phps-mode-lexer-RETURN_TOKEN "`" (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_END_HEREDOC (looking-at (concat phps-mode-lexer-ANY_CHAR)))
         (lambda()
           (let* ((start (match-beginning 0))
                  (end (+ start (length heredoc_label) 1))
                  (_data (buffer-substring-no-properties start end)))
             ;; (message "Found ending heredoc at %s, %s of %s" _data (thing-at-point 'line) heredoc_label)
             (pop phps-mode-lexer-heredoc_label_stack)
             (phps-mode-lexer-BEGIN phps-mode-lexer-ST_IN_SCRIPTING)
             (phps-mode-lexer-RETURN_TOKEN 'T_END_HEREDOC start end))))

        (phps-mode-lexer-re2c-rule
         (and (or ST_DOUBLE_QUOTES ST_BACKQUOTE ST_HEREDOC) (looking-at (concat "{\\$")))
         (lambda()
           (phps-mode-lexer-yy_push_state phps-mode-lexer-ST_IN_SCRIPTING)
           (phps-mode-lexer-RETURN_TOKEN 'T_CURLY_OPEN (match-beginning 0) (- (match-end 0) 1))))

        (phps-mode-lexer-re2c-rule
         (and ST_DOUBLE_QUOTES (looking-at "[\"]"))
         (lambda()
           (phps-mode-lexer-BEGIN phps-mode-lexer-ST_IN_SCRIPTING)
           ;; (message "Ended double-quote at %s" (match-beginning 0))
           (phps-mode-lexer-RETURN_TOKEN "\"" (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_BACKQUOTE (looking-at "[`]"))
         (lambda()
           (phps-mode-lexer-BEGIN phps-mode-lexer-ST_IN_SCRIPTING)
           (phps-mode-lexer-RETURN_TOKEN "`" (match-beginning 0) (match-end 0))))

        (phps-mode-lexer-re2c-rule
         (and ST_DOUBLE_QUOTES (looking-at phps-mode-lexer-ANY_CHAR))
         (lambda()
           (let ((start (point)))
             (let ((string-start (search-forward-regexp "[^\\\\]\"" nil t)))
               (if string-start
                   (let* ((end (- (match-end 0) 1))
                          (double-quoted-string (buffer-substring-no-properties start end)))
                     ;; Do we find variable inside quote?
                     (if (or (string-match (concat "\\${" phps-mode-lexer-LABEL) double-quoted-string)
                             (string-match (concat "{\\$" phps-mode-lexer-LABEL) double-quoted-string)
                             (string-match (concat "\\$" phps-mode-lexer-LABEL) double-quoted-string))
                         (progn
                           (let ((variable-start (+ start (match-beginning 0))))

                             ;; (message "Found starting expression inside double-quoted string at: %s %s" start variable-start)
                             (phps-mode-lexer-RETURN_TOKEN 'T_CONSTANT_ENCAPSED_STRING start variable-start)
                             ))
                       (progn
                         (phps-mode-lexer-RETURN_TOKEN 'T_CONSTANT_ENCAPSED_STRING start end)
                         ;; (message "Found end of quote at %s-%s, moving ahead after '%s'" start end (buffer-substring-no-properties start end))
                         )))
                 (progn
                   (display-warning 'phps-mode (format "Found no ending of double quoted region starting at %s" start))
                   (phps-mode-lexer-MOVE_FORWARD (point-max))))))))

        (phps-mode-lexer-re2c-rule
         (and ST_BACKQUOTE (looking-at phps-mode-lexer-ANY_CHAR))
         (lambda()
           (let ((string-start (search-forward-regexp "\\([^\\\\]`\\|\\$\\|{\\)" nil t)))
             (if string-start
                 (let ((start (- (match-end 0) 1)))
                   ;; (message "Skipping backquote forward over %s" (buffer-substring-no-properties old-start start))
                   (phps-mode-lexer-RETURN_TOKEN 'T_CONSTANT_ENCAPSED_STRING old-start start)
                   )
               (progn
                 (display-warning 'phps-mode (format "Found no ending of backquoted string starting at %s" (point)))
                 (phps-mode-lexer-MOVE_FORWARD (point-max)))))))

        (phps-mode-lexer-re2c-rule
         (and ST_HEREDOC (looking-at phps-mode-lexer-ANY_CHAR))
         (lambda()
           ;; (message "Found nothing useful at '%s' looking at {$ %s" (buffer-substring-no-properties (point) (point-max)) (looking-at "{\\$"))
           ;; Check for $, ${ and {$ forward
           (let ((string-start (search-forward-regexp (concat "\\(\n" heredoc_label ";?\n\\|\\$" phps-mode-lexer-LABEL "\\|{\\$" phps-mode-lexer-LABEL "\\|\\${" phps-mode-lexer-LABEL "\\)") nil t)))
             (if string-start
                 (let* ((start (match-beginning 0))
                        (end (match-end 0))
                        (data (buffer-substring-no-properties start end)))
                   ;; (message "Found something ending at %s" data)

                   (cond

                    ((string-match (concat "\n" heredoc_label ";?\n") data)
                                        ;, (message "Found heredoc end at %s-%s" start end)
                     (phps-mode-lexer-BEGIN phps-mode-lexer-ST_END_HEREDOC)
                     (phps-mode-lexer-RETURN_TOKEN 'T_ENCAPSED_AND_WHITESPACE old-start start))

                    (t
                     ;; (message "Found variable at '%s'.. Skipping forward to %s" data start)
                     (phps-mode-lexer-RETURN_TOKEN 'T_ENCAPSED_AND_WHITESPACE old-start start)
                     )

                    ))
               (progn
                 (display-warning 'phps-mode (format "Found no ending of heredoc at %s" (point)))
                 (phps-mode-lexer-MOVE_FORWARD (point-max)))))))

        (phps-mode-lexer-re2c-rule
         (and ST_NOWDOC (looking-at phps-mode-lexer-ANY_CHAR))
         (lambda()
           (let ((string-start (search-forward-regexp (concat "\n" heredoc_label ";?\n") nil t)))
             (if string-start
                 (let* ((start (match-beginning 0))
                        (end (match-end 0))
                        (_data (buffer-substring-no-properties start end)))
                   ;; (message "Found something ending at %s" _data)
                   ;; (message "Found nowdoc end at %s-%s" start end)
                   (phps-mode-lexer-BEGIN phps-mode-lexer-ST_END_HEREDOC)
                   (phps-mode-lexer-RETURN_TOKEN 'T_ENCAPSED_AND_WHITESPACE old-start start)
                   )
               (progn
                 (display-warning 'phps-mode (format "Found no ending of newdoc starting at %s" (point)))
                 (phps-mode-lexer-MOVE_FORWARD (point-max)))))))

        (phps-mode-lexer-re2c-rule
         (and (or ST_IN_SCRIPTING ST_VAR_OFFSET) (looking-at phps-mode-lexer-ANY_CHAR))
         (lambda()
           (display-warning 'phps-mode (format "Unexpected character at %s" (point)))
           (phps-mode-lexer-MOVE_FORWARD (point-max))))

        (phps-mode-lexer-re2c-execute)))))

(defun phps-mode-lexer-get-tokens ()
  "Get lexer tokens."
  phps-mode-lexer-tokens)

(defun phps-mode-lexer-get-states ()
  "Get lexer states."
  phps-mode-lexer-states)

(defun phps-mode-lexer--get-next-unescaped (character)
  "Find where next un-escaped CHARACTER comes, if none is found return nil."
  ;; (message "phps-mode-lexer--get-next-unescaped(%s)" character)
  (let ((escaped nil)
        (pos nil))
    (while (and (not pos)
                (< (point) (point-max)))
      (progn
        ;; (message "Setting forward one %s vs %s" (point) (point-max))
        (forward-char)
        (if (and (not escaped)
                 (looking-at-p character))
            (setq pos (1+ (point)))
          (if (looking-at-p "\\\\")
              (setq escaped (not escaped))
            (setq escaped nil)))))
    pos))

(defun phps-mode-lexer-setup (start end)
  "Just prepare other lexers for lexing region START to END."
  (phps-mode-debug-message (message "Lexer setup %s - %s" start end))
  (phps-mode-lexer-BEGIN phps-mode-lexer-ST_INITIAL))

(defun phps-mode-lexer-run ()
  "Run lexer."
  (interactive)
  (phps-mode-debug-message (message "Lexer run"))
  (setq-local phps-mode-lexer-buffer-length (1- (point-max)))
  (setq-local phps-mode-lexer-buffer-contents (buffer-substring-no-properties (point-min) (point-max)))
  (setq-local phps-mode-lexer-STATE nil)
  (setq-local phps-mode-lexer-state_stack nil)
  (setq-local phps-mode-lexer-states nil)
  (setq-local phps-mode-lexer-tokens (semantic-lex-buffer)))

(defun phps-mode-lexer-move-states (start diff)
  "Move lexer states after (or equal to) START with modification DIFF."
  (when phps-mode-lexer-states
    (setq-local phps-mode-lexer-states (phps-mode-lexer-get-moved-states phps-mode-lexer-states start diff))))

(defun phps-mode-lexer-get-moved-states (states start diff)
  "Return moved lexer STATES after (or equal to) START with modification DIFF."
  (let ((old-states states)
        (new-states '()))
    (when old-states

      ;; Iterate through states add states before start start unchanged and the others modified with diff
      (dolist (state-object (nreverse old-states))
        (let ((state-start (nth 0 state-object))
              (state-end (nth 1 state-object))
              (state-symbol (nth 2 state-object))
              (state-stack (nth 3 state-object)))
          (if (>= state-start start)
              (let ((new-state-start (+ state-start diff))
                    (new-state-end (+ state-end diff)))
                (push (list new-state-start new-state-end state-symbol state-stack) new-states))
            (if (> state-end start)
                (let ((new-state-end (+ state-end diff)))
                  (push (list state-start new-state-end state-symbol state-stack) new-states))
              (push state-object new-states))))))

    new-states))

(defun phps-mode-lexer-move-tokens (start diff)
  "Update tokens with moved lexer tokens after or equal to START with modification DIFF."
  (when phps-mode-lexer-tokens
    (setq-local phps-mode-lexer-tokens (phps-mode-lexer-get-moved-tokens phps-mode-lexer-tokens start diff))))

(defun phps-mode-lexer-get-moved-tokens (old-tokens start diff)
  "Return moved lexer OLD-TOKENS positions after (or equal to) START with DIFF points."
  (let ((new-tokens '()))
    (when old-tokens

      ;; Iterate over all tokens, add those that are to be left unchanged and add modified ones that should be changed.
      (dolist (token (nreverse old-tokens))
        (let ((token-symbol (car token))
              (token-start (car (cdr token)))
              (token-end (cdr (cdr token))))
          (if (>= token-start start)
              (let ((new-token-start (+ token-start diff))
                    (new-token-end (+ token-end diff)))
                (push `(,token-symbol ,new-token-start . ,new-token-end) new-tokens))
            (if (> token-end start)
                (let ((new-token-end (+ token-end diff)))
                  (push `(,token-symbol ,token-start . ,new-token-end) new-tokens))
              (push token new-tokens))))))
    new-tokens))

(defun phps-mode-lexer-run-incremental (buffer)
  "Run incremental lexer on BUFFER."
  (phps-mode-debug-message (message "Run incremental lexer on buffer '%s'" buffer))
  (phps-mode-runtime-debug-message (format "Run incremental lexer on buffer '%s'" buffer))
  (with-current-buffer buffer
    (let ((changes (phps-mode-functions--get-changes))
          (run-full-lexer nil)
          (old-tokens phps-mode-lexer-tokens)
          (old-states phps-mode-lexer-states)
          (buffer-length-old phps-mode-lexer-buffer-length)
          (buffer-contents-old phps-mode-lexer-buffer-contents))

      (if (and changes
               buffer-length-old
               buffer-contents-old)
          (progn

            ;; Reset processed buffer flag
            (phps-mode-functions-reset-processed-buffer)

            ;; Reset idle timer
            (phps-mode-functions--cancel-idle-timer)

            ;; Reset buffer changes index
            (phps-mode-functions--reset-changes)

            ;; Reset tokens and states here
            (setq-local phps-mode-lexer-tokens nil)
            (setq-local phps-mode-lexer-states nil)
            (setq-local phps-mode-lexer-STATE nil)
            (setq-local phps-mode-lexer-state_stack nil)

            (phps-mode-runtime-debug-message "Processing incremental changes")
            (phps-mode-debug-message (message "Processing incremental changes: %s" changes))
            (setq run-full-lexer t)

            (dolist (change (nreverse changes))
              (let ((change-start (nth 0 change))
                    (change-stop (nth 1 change))
                    (buffer-length-new (1- (nth 3 change)))
                    (buffer-contents-new (nth 4 change)))
                (phps-mode-runtime-debug-message
                 (format "Running incremental lexer %s - %s" change-start change-stop))
                (phps-mode-debug-message
                 (message "Running incremental lexer %s - %s" change-start change-stop))

                (when (and change-start
                           change-stop)
                  (if (and (> change-start 1)
                           phps-mode-lexer-states
                           phps-mode-lexer-tokens)
                      (let ((incremental-state nil)
                            (incremental-state-stack nil)
                            (incremental-states nil)
                            (incremental-tokens nil)
                            (head-states '())
                            (tail-states '())
                            (head-tokens '())
                            (tail-tokens '())
                            (buffer-length-delta nil)
                            (incremental-start 0)
                            (incremental-stop change-stop)
                            (change-length (- change-stop change-start))
                            (appended-tokens nil))

                        (phps-mode-debug-message
                         (message "Change length: %s" change-length)
                         (message "Old tokens: %s" old-tokens)
                         (message "Old states: %s" old-states))

                        ;; (phps-mode-debug-message
                        ;;  (message "Buffer length old: %s" buffer-length-old))

                        ;; 1. Determine incremental start (incremental-start), that is at the start of previous token
                        ;; 2. Build list of tokens before incremental start (head-tokens)
                        ;; 3. Build list of tokens after incremental region (tail-tokens)
                        (dolist (token old-tokens)
                          (let ((start (car (cdr token)))
                                (end (cdr (cdr token))))
                            (cond
                             ((< end change-start)
                              (push token head-tokens)
                              (setq incremental-start start))
                             ((= end change-start)
                              (setq incremental-start start))
                             ((> start change-stop)
                              (setq incremental-stop end)))))
                        (setq head-tokens (nreverse head-tokens))
                        (phps-mode-debug-message
                         (message "Head tokens: %s" head-tokens)
                         (message "Incremental start: %s" incremental-start)
                         (message "Incremental stop: %s" incremental-stop)
                         (message "Buffer length old: %s" buffer-length-old)
                         (message "Buffer contents old: %s" buffer-contents-old))

                        ;; Calculate change of buffer length
                        (setq buffer-length-delta (- buffer-length-new buffer-length-old))

                        (cond
                         ((= change-length buffer-length-delta)
                          (phps-mode-debug-message (message "Flag change as insert"))
                          (setq incremental-stop (+ incremental-stop (1- buffer-length-delta))))
                         ((and (= change-length 0)
                               (< buffer-length-delta 0))
                          (phps-mode-debug-message (message "Flag change as deletion"))
                          (setq incremental-stop (+ incremental-stop (abs buffer-length-delta))))
                         (t
                          (phps-mode-debug-message (message "Do not flag change as insert or deletion"))))

                        (dolist (token old-tokens)
                          (let ((start (car (cdr token))))
                            (when (>= start incremental-stop)
                              (push token tail-tokens))))
                        (setq tail-tokens (nreverse tail-tokens))

                        (phps-mode-debug-message
                         (message "Incremental start: %s" incremental-start)
                         (message "Incremental stop: %s" incremental-stop)
                         (message "Buffer length new: %s" buffer-length-new)
                         (message "Buffer length old: %s" buffer-length-old)
                         (message "Buffer length delta: %s" buffer-length-delta)
                         (message "Buffer contents new: %s" buffer-contents-new)
                         (message "Tail tokens: %s" tail-tokens)
                         (message "From region: %s - %s" incremental-start incremental-stop))

                        ;; Did we find a start for the incremental process?
                        (if (and
                             (> incremental-start 0)
                             head-tokens)
                            (progn

                              (phps-mode-debug-message (message "Found positive incremental-start and head tokens"))

                              ;; 1. Determine state (incremental-state) and state-stack (incremental-state-stack) at incremental start
                              ;; 2. Build list of states before incremental start (head-states)
                              ;; 3. Build list of states after incremental start (tail-states)
                              (dolist (state-object (nreverse old-states))
                                (let ((start (nth 0 state-object))
                                      (end (nth 1 state-object)))
                                  (when (< end change-start)
                                    (setq incremental-state (nth 2 state-object))
                                    (setq incremental-state-stack (nth 3 state-object))
                                    (push state-object head-states))
                                  (when (>= start incremental-stop)
                                    (push state-object tail-states))))

                              (phps-mode-debug-message
                               (message "Incremental-state: %s" incremental-state)
                               (message "Incremental-state-stack: %s" incremental-state-stack)
                               (message "Head states: %s" head-states)
                               (message "Tail states: %s" tail-states))

                              ;; Rewind lexer state here
                              (setq-local phps-mode-lexer-states head-states)
                              (setq-local phps-mode-lexer-STATE incremental-state)
                              (setq-local phps-mode-lexer-state_stack incremental-state-stack)

                              (if head-states
                                  (progn
                                    (phps-mode-runtime-debug-message "Found head states")
                                    (phps-mode-debug-message (message "Found head states"))

                                    ;; Flag that we should not run ful lexer
                                    (setq run-full-lexer nil)

                                    ;; Delete all syntax coloring from incremental-start to end of incremental-region
                                    ;; (phps-mode-lexer-clear-region-syntax-color incremental-start change-stop)

                                    ;; Do partial lex from previous-token-end to change-stop
                                    (let ((incremental-buffer (generate-new-buffer "*PHPs Incremental Buffer*")))
                                      (save-excursion
                                        (switch-to-buffer incremental-buffer)
                                        (delete-region (point-min) (point-max))
                                        (goto-char (point-max))
                                        (insert-char 10 (- incremental-start 2))
                                        (goto-char (point-max))
                                        (insert (substring buffer-contents-new (- incremental-start 2) incremental-stop))

                                        ;; Rewind lexer state here
                                        (setq-local phps-mode-lexer-states head-states)
                                        (setq-local phps-mode-lexer-STATE incremental-state)
                                        (setq-local phps-mode-lexer-state_stack incremental-state-stack)

                                        ;; Setup lexer
                                        (setq-local semantic-lex-analyzer #'phps-mode-lexer-lex)
                                        (setq-local semantic-lex-syntax-table (phps-mode-get-syntax-table))

                                        (phps-mode-debug-message
                                         (message "Incremental buffer contents: \n%s" (buffer-substring-no-properties (point-min) (point-max)))
                                         (message "Incremental buffer lexer region (%s-%s): \n%s" (1- incremental-start) (1+ incremental-stop) (buffer-substring-no-properties (1- incremental-start) (1+ incremental-stop))))

                                        (setq incremental-tokens (semantic-lex (1- incremental-start) (1+ incremental-stop)))
                                        (setq appended-tokens (append head-tokens incremental-tokens))
                                        (setq incremental-states phps-mode-lexer-states)

                                        (phps-mode-debug-message (message "Incremental tokens: %s" incremental-tokens))

                                        (kill-buffer)))

                                    (if (and (= phps-mode-lexer-STATE incremental-state)
                                             (equal phps-mode-lexer-state_stack incremental-state-stack))
                                        (progn

                                          (phps-mode-runtime-debug-message "Found matching state and state-stack, copying old state and tokens")
                                          (phps-mode-debug-message (message "Found matching state and state-stack, copying old state and tokens"))

                                          (unless (= buffer-length-delta 0)
                                            (when tail-tokens
                                              (setq tail-tokens (phps-mode-lexer-get-moved-tokens tail-tokens 0 buffer-length-delta)))

                                            (when tail-states
                                              (setq tail-states (phps-mode-lexer-get-moved-states tail-states 0 buffer-length-delta))))

                                          (phps-mode-debug-message
                                           (message "State and state stack at stop equals state at stop: %s %s" phps-mode-lexer-STATE phps-mode-lexer-state_stack))

                                          ;; TODO re-use rest of indexes here? (indentation and imenu)

                                          ;; Apply syntax coloring
                                          (dolist (token-object incremental-tokens)
                                            (let ((token (car token-object))
                                                  (start (car (cdr token-object)))
                                                  (end (cdr (cdr token-object))))
                                              (when (<= end (point-max))
                                                (phps-mode-lexer-set-region-syntax-color
                                                 start end (phps-mode-lexer-get-token-syntax-color token)))))

                                          (setq-local phps-mode-lexer-states (append tail-states incremental-states))
                                          (phps-mode-debug-message (message "New states from incremental lex are: %s" phps-mode-lexer-states))
                                          
                                          (setq appended-tokens (append appended-tokens tail-tokens))
                                          (phps-mode-debug-message (message "New tokens from incremental lex are: %s" appended-tokens)))

                                      (phps-mode-runtime-debug-message "Did not find matching state and state-stack, lexing rest of buffer")
                                      (phps-mode-debug-message (message "Did not find matching state and state-stack, lexing rest of buffer"))

                                      (phps-mode-debug-message
                                       (message "State at stop %s or state stack %s does not equals state at stop: %s %s" phps-mode-lexer-STATE phps-mode-lexer-state_stack incremental-state incremental-state-stack))

                                      ;; Clear syntax colouring of rest of buffer
                                      ;; (phps-mode-lexer-clear-region-syntax-color incremental-start (point-max))

                                      ;; Lex rest of buffer
                                      (setq head-tokens appended-tokens)
                                      (setq incremental-tokens (semantic-lex incremental-stop (point-max)))
                                      (setq appended-tokens (append head-tokens incremental-tokens))
                                      (phps-mode-debug-message (message "New states from full lex are: %s" phps-mode-lexer-states))
                                      (phps-mode-debug-message (message "New tokens from full lex are: %s" appended-tokens)))

                                    (phps-mode-runtime-debug-message (format "Final tokens: %s" appended-tokens))
                                    (phps-mode-debug-message (message "Final tokens: %s" appended-tokens))
                                    (setq-local phps-mode-lexer-tokens appended-tokens))
                                (phps-mode-runtime-debug-message "Did not find head states")
                                (phps-mode-debug-message (message "Did not find head states"))))
                          (phps-mode-debug-message (message "Did not find positive incremental-start or head-tokens"))))
                    (phps-mode-debug-message (message "Change start not above one or lacking tokens or states"))))
                (setq buffer-length-old buffer-length-new)
                (setq buffer-contents-old buffer-contents-new)))

            (setq-local phps-mode-lexer-buffer-length (1- (point-max)))
            (setq-local phps-mode-lexer-buffer-contents (buffer-substring-no-properties (point-min) (point-max))))
        (phps-mode-runtime-debug-message "Found no changes")
        (phps-mode-debug-message (message "Found no changes")))

      (when run-full-lexer
        (phps-mode-runtime-debug-message "Running full lexer")
        (phps-mode-debug-message (message "Running full lexer"))
        (phps-mode-lexer-run)))))

(define-lex phps-mode-lexer-lex
  "Call lexer analyzer action."
  phps-mode-lexer-lex-analyzer
  semantic-lex-default-action)

(provide 'phps-mode-lexer)

;;; phps-mode-lexer.el ends here
