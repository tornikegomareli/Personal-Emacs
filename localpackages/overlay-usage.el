;;; overlay-usage.el --- ;; -*- lexical-binding: t; -*-
;;; Commentary:
;;; Package for showing usage of function.

;;; Code:

(require 'rect)
(require 'project)

(defvar overlay-usage-mode nil)

(defvar-local functions-overlays-list nil
  "List of overlays for functions.")

(defvar-local variables-overlays-list nil
  "List of overlays for variables.")

(defvar-local classes-overlays-list nil
  "List of overlays for structs and classes.")

(defconst commented-lines-regex "^\\s-*/\\|;"
  "Comment-line regex.")

(defconst private-variable-regex-swift "\s+\\b\\(?:let\\|var\\|case\\)\\b\s+\\(\\w+\\)"
  "Match variables in swift.")

(defconst variable-regex-elisp "\\(?:defvar\\|defvar-local\\|defface\\|defconst\\|defgroup\\)\s+\\([a-zA-Z0-9_-\(]+\\)"
  "Match variables in elisp.")

(defgroup overlay-usage nil
  "Plugin shows complexity information."
  :prefix "overlay-usage-"
  :group 'comm)

(defface overlay-usage-default-face
  '((t :inherit font-lock-comment-face :foreground "#999999" :height 0.7 :italic nil))
  "Face added to code-usage display."
  :group 'overlay-usage)

(defface overlay-usage-function-symbol-face
  '((t :inherit font-lock-function-name-face :height 0.8 :weight semi-bold))
  "Face added to code-usage display."
  :group 'overlay-usage)

(defface overlay-usage-function-symbol-face-public
  '((t :inherit font-lock-type-face :height 0.8 :weight semi-bold))
  "Face added to code-usage display."
  :group 'overlay-usage)

(defface overlay-usage-class-symbol-face
  '((t :inherit font-lock-constant-face :height 0.8 :weight semi-bold))
  "Face added to code-usage display."
  :group 'overlay-usage)

(defface overlay-usage-variable-symbol-face
  '((t :inherit font-lock-keyword-face :height 0.7 :weight semi-bold))
  "Face added to code-usage display."
  :group 'overlay-usage)

(defface overlay-usage-count-symbol-face
  '((t :inherit default :height 0.7 :weight semi-bold))
  "Face added to code-usage display."
  :group 'overlay-usage)

;;;###autoload
(define-minor-mode overlay-usage-mode
  "Toggle 'overlay-usage-mode'."
  :group overlay-usage
  :init-value nil
  :lighter "OverlayUsage"
  (if overlay-usage-mode
      (overlay-usage-enable)
    (overlay-usage-disable)))

(defun overlay-usage:project-root-dir ()
  "Get the root directory of the current project."
  (when-let ((project (project-current)))
    (project-root project)))

(defun overlay-usage-enable ()
  "Enable overlay-usage."
  `(add-hook 'after-save-hook (lambda () (overlay-usage:update-all-buffer)) nil t)
  `(add-hook 'after-revert-hook (lambda () (overlay-usage:update-all-buffer)) nil t)
  (overlay-usage:add-all-overlays))

(defun overlay-usage-disable ()
  "Disable 'overlay-usage-mode'."
  `(remove-hook 'after-save-hook (lambda () (overlay-usage:remove-all-overlays) t))
  `(remove-hook 'after-revert-hook (lambda () (overlay-usage:remove-all-overlays) t))
  (overlay-usage:remove-all-overlays))

(defun overlay-usage:buffer-visible-p (buffer)
  "Return non-nil if BUFFER is visible in any window."
  (not (eq (get-buffer-window buffer 'visible) nil)))

(defun overlay-usage:update-all-buffer ()
  "Update all buffers."
  (dolist (buf (buffer-list))
    (when (overlay-usage:buffer-visible-p buf)
      (with-current-buffer buf
        (overlay-usage:add-all-overlays)))))

(defun overlay-usage:add-all-overlays ()
  "Add all overlays."
  (overlay-usage:remove-all-overlays)

  (let ((default-directory (overlay-usage:project-root-dir))
        (extension (overlay-usage:extension-from-file)))

    (cond ((string-match-p (regexp-quote "swift") extension)
      (overlay-usage:setup-functions :extension extension :private t)
      (overlay-usage:setup-classes-and-structs)))

      (overlay-usage:setup-functions :extension extension :private nil)
      (overlay-usage:setup-variables)))

(defun overlay-usage:remove-all-overlays ()
  "Remove all overlays."
  (overlay-usage:remove-overlays-for-functions)
  (overlay-usage:remove-overlays-for-variables)
  (overlay-usage:remove-overlays-for-classes))

(defun overlay-usage:remove-overlays-for-functions ()
  "Clean up all overlays for functions."
  (mapc #'delete-overlay functions-overlays-list))

(defun overlay-usage:remove-overlays-for-variables ()
  "Clean up all overlays for variables."
  (mapc #'delete-overlay variables-overlays-list))

(defun overlay-usage:remove-overlays-for-classes ()
  "Clean up all overlays for classes."
  (mapc #'delete-overlay classes-overlays-list))


(cl-defun add-overlays-for-functions (&key position spaces filename extension private)
  "Add overlay (as POSITION with SPACES FILENAME and search EXTENSION PRIVATE)."
  (goto-char position)
  (let* ((function-name (thing-at-point 'symbol))
         (count (string-to-number
                 (shell-command-to-string
                  (overlay-usage:shell-command-functions-from
                   :filename filename
                   :extension extension
                   :function (regexp-quote function-name)
                   :private private))))
         (ov (make-overlay
              (line-end-position 0)
              (line-end-position 0))))
    
    (overlay-put ov 'after-string
                 (concat spaces
                         (overlay-usage:propertize-with-symbol (- count 1) "λ︎" (if private
                                                                     'overlay-usage-function-symbol-face
                                                                   'overlay-usage-function-symbol-face-public
                                                                  ))))
    (push ov functions-overlays-list)))

(cl-defun add-overlays-for-variables (&key position filename)
  "Add overlay (as POSITION and FILENAME) for variables."
  (goto-char position)
  (let* ((variable-name (thing-at-point 'symbol))
         (command (shell-command-variable-from
                   :filename filename
                   :variable variable-name))
         (count (string-to-number (shell-command-to-string command)))
         (ov (make-overlay
              (line-end-position)
              (line-end-position))))

    (overlay-put ov 'after-string
                 (concat " " (overlay-usage:propertize-with-symbol count "⇠" 'overlay-usage-variable-symbol-face)))
    (overlay-put ov 'invisible t)
    (overlay-put ov 'priority 900)
    (push ov variables-overlays-list)))


(cl-defun add-overlays-for-classes (&key position spaces extension)
  "Add overlay for classes (as POSITION with SPACES and search EXTENSION)."
  (goto-char position)
  (let* ((class-name (thing-at-point 'symbol))
         (command (overlay-usage:shell-command-classes-from
                   :extension extension
                   :name class-name))
         (count (string-to-number (shell-command-to-string command)))
         (ov (make-overlay
              (line-end-position 0)
              (line-end-position 0))))

    (overlay-put ov 'after-string
                 (concat spaces
                         (overlay-usage:propertize-with-symbol (- count 1) "✦︎" 'overlay-usage-class-symbol-face)))
    (push ov classes-overlays-list)))


(defun overlay-usage:propertize-with-symbol (count symbol font)
  "Propertize with symbol (as COUNT as SYMBOL as FONT)."
  (cond
   ((< count 1)
    (concat (propertize (format "%s︎ " symbol) 'face font)
            (propertize "No references found" 'face 'overlay-usage-default-face)))
   ((= count 1)
    (concat (propertize (format "%s︎ " symbol) 'face font)
            (propertize "1" 'face 'overlay-usage-count-symbol-face)
            (propertize " reference" 'face 'overlay-usage-default-face)))
   ((> count 1)
    (concat (propertize (format "%s " symbol) 'face font)
            (propertize (number-to-string count) 'face 'overlay-usage-count-symbol-face)
            (propertize " references" 'face 'overlay-usage-default-face)))))

(defun overlay-usage:extension-from-file ()
  "Get file extension."
  (file-name-extension buffer-file-name))

(cl-defun overlay-usage:shell-command-functions-from (&key filename extension function private)
  "Shell command from EXTENSION and FUNCTION.  Can be PRIVATE and then we check the FILENAME."
  (cond
   ((string-suffix-p "swift" extension t)
    (if private
        (format "rg -t swift %s -ce '^[^\/\n\"]*\\b%s\\('" filename function)
      (format "rg -t swift -e '^[^\/\n\"]*\\b%s\\(' | wc -l" function)))
   ((string-suffix-p "el" extension t)
    (format "rg -t elisp -e '\\b%s\\b' | wc -l" function))
   (t nil)))

(cl-defun overlay-usage:shell-command-classes-from (&key extension name)
  "Shell command from EXTENSION and NAME."
  (cond
   ((string-suffix-p "swift" extension t)
    (format "rg -t swift -e '^[^\/\n\"]*\\b%s\\b' | wc -l" name))
   (t nil)))

(cl-defun shell-command-variable-from (&key filename variable)
  "Shell command from FILENAME and VARIABLE."
  (cond
   ((string-suffix-p "swift" (file-name-extension filename) t)
    (format "rg -t swift %s -ce '^[^/\n\"]*(?<!\\.)\\b%s\\b(?!\s*[:=])' --pcre2" filename variable))
   ((string-suffix-p "el" (file-name-extension filename) t)
    (format "rg -t elisp %s -ce '^(?!.*\\(def\\w+).*\\b%s\\b(?!:)' --pcre2" filename variable))
   (t nil)))

(cl-defun overlay-usage:find-classes-regex-for-file-type (&key extension)
  "Get the regex for finding classes/structs for and (as EXTENSION)."
  (let ((case-fold-search nil))
    (cond
     ((string-match-p (regexp-quote "swift") extension) "\\b\\(?:\\bstruct\\b\\|\\bclass\\b\\)\s+\\(\\w+\\)")
     (t nil))))

(cl-defun overlay-usage:find-variable-regex-for-file-type (&key extension)
  "Get the regex for finding variables for an (EXTENSION)."
  (cond
   ((string-match-p (regexp-quote "swift") extension) private-variable-regex-swift)
   ((string-match-p (regexp-quote "el") extension) variable-regex-elisp)
   (t nil)))

(cl-defun overlay-usage:find-function-regex-for-file-type (&key extension private)
  "Detect what the function start with from the (EXTENSION PRIVATE)."
  (let ((case-fold-search nil))
    (cond
     ((string-match-p (regexp-quote "swift") extension) "^[^/\n]*\\_<func\\_>")
     ((string-match-p (regexp-quote "el") extension) "^[^;\n]*\\bdef\\w+\\_>")
     (t nil))))

(defun overlay-usage:setup-classes-and-structs ()
  "Add overlays for structs and classes."
  (save-excursion
    (let* ((extension (overlay-usage:extension-from-file))
                (classes-regex (overlay-usage:find-classes-regex-for-file-type :extension extension)))
      (goto-char (point-min))
      (while (search-forward-regexp classes-regex nil t)
        (let ((position (match-beginning 1))
              (column (save-excursion
                        (back-to-indentation)
                        (current-column))))
          (beginning-of-line)
          (when (not (looking-at commented-lines-regex))
            (add-overlays-for-classes
             :position position
             :spaces (spaces-string column)
             :extension extension)))
        (forward-line)))))

(defun overlay-usage:boolean-eq (a b)
  "Check if (as A B) are equal."
  (equal a b))


(cl-defun overlay-usage:setup-functions (&key extension private)
  "Add overlay to functions with EXTENSION as PRIVATE."
  (save-excursion
    (let ((func-regex (overlay-usage:find-function-regex-for-file-type :extension extension :private private)))
      (goto-char (point-min))
      (while (search-forward-regexp (concat func-regex " \\([^(=]+\\)\(") nil t)
        (let ((position (match-beginning 1))
              (column (save-excursion
                        (back-to-indentation)
                        (current-column))))
          (beginning-of-line)
          (when (overlay-usage:boolean-eq private (looking-at "^\\s-*\\b\\(private\\|fileprivate\\)\\b"))
          (when (not (looking-at commented-lines-regex))
              (add-overlays-for-functions
               :position position
               :spaces (spaces-string column)
               :filename (buffer-file-name)
               :extension (format "%s" extension)
               :private private))))
        (forward-line)))))

(defun overlay-usage:setup-variables ()
  "Add overlays to variables."
  (save-excursion
    (let* ((extension (overlay-usage:extension-from-file))
           (variable-regex (overlay-usage:find-variable-regex-for-file-type :extension extension)))
      (goto-char (point-min))
    (while (search-forward-regexp variable-regex nil t)
      (let ((position (match-beginning 1)))
        (beginning-of-line)
          (when (not (looking-at commented-lines-regex))
          (add-overlays-for-variables
           :position position
           :filename (buffer-file-name))))
      (forward-line)))))

(provide 'overlay-usage)
;;; overlay-usage.el ends here
