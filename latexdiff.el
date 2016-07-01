;;; latexdiff.el --- Latexdiff integration in Emacs

;; Copyright (C) 2016 Launay Gaby

;; Author: Launay Gaby <gaby.launay@gmail.com>
;; Maintainer: Launay Gaby <gaby.launay@gmail.com>
;; Version: 0.1.0
;; Keywords: latex, diff
;; URL: http://github.com/muahah/emacs-latexdiff

;; This file is NOT part of GNU Emacs.

;;; License:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:

;; latexdiff is a minor mode to interact with Latexdiff-vc
;; [https://github.com/ftilmann/latexdiff] for git repository
;; and using Helm.

;; To use latexdiff, make sure that this file is in Emacs load-path
;; (add-to-list 'load-path "/path/to/directory/or/file")
;;
;; Then require latexdiff
;; (require 'latexdiff)

;; To start latexdiff
;; (latexdiff-mode t) or M-x latexdiff-mode
;;
;; latexdiff is buffer local, so hook it up
;; (add-hook 'latex-mode-hook 'latexdiff-mode)
;; or
;; (add-hook 'LaTeX-mode-hook 'latexdiff-mode)
;; for use with Auctex
;;
;; latexdiff do not define default keybinding, so add them
;;
;; (define-key latexdiff-mode-map (kbd "C-c l d") 'helm-latexdiff)
;; or with Evil
;; (evil-leader/set-key-for-mode 'latex-mode "ld" 'helm-latexdiff)
;;
;; The main function to use is `helm-latexdiff' which show you the
;; commits of your current git repository and ask you to choose
;; the two commits to use latexdiff on

;;; Todo:

;; add check to test if latexdiff is installed
;; add nice colors
;; add ergonomy !

;;; Code:

(require 'helm)

(defvar latexdiff-mode-map (make-sparse-keymap)
  "Keymap for `latexdiff-mode'.")

(defface latexdiff-date-face
  '((t (:inherit helm-prefarg)))
  "Face for the date"
  :group 'latexdiff)

(defface latexdiff-author-face
  '((t (:inherit helm-ff-file)))
  "Face for the author"
  :group 'latexdiff)

(defface latexdiff-message-face
  '((t (:inherit default :foreground "white")))
  "Face for the message"
  :group 'latexdiff)

(defface latexdiff-ref-labels-face
  '((t (:inherit helm-grep-match)))
  "Face for the ref-labels"
  :group 'latexdiff)

(defgroup latexdiff nil
  "latexdiff integration in Emacs"
  :prefix "latexdiff-"
  :link `(url-link :tag "latexdiff homepage" "https://github.com/muahah/emacs-latexdiff"))

;;;###autoload
(define-minor-mode latexdiff-mode
  "Latexdiff integration"
  :init-value nil
  :lighter " Latexdiff"
  :keymap latexdiff-mode-map
  )

(defun latexdiff--compile-diff (&optional REV1 REV2)
  "Use latexdiff to compile a pdf file of the
difference between REV1 and REV2"
  (let ((file (TeX-master-file nil nil t))
	(diff-file (format "%s-diff%s-%s" (TeX-master-file nil nil t) REV1 REV2)))
    (message "[%s.tex] Generating latex diff between %s and %s" file REV1 REV2)
    (call-process "/bin/bash" nil 0 nil "-c"
		  (format "yes X | latexdiff-vc --force -r %s -r %s %s.tex --pdf > latexdiff.log ;
                           GLOBIGNORE='*.pdf' ;
                           rm -r %s* ;
                           rm -r %s-oldtmp* ;
                           GLOBIGNORE='' ;
                           okular %s.pdf "
			  REV1 REV2 file diff-file file diff-file))))

(defun latexdiff--compile-diff-with-current (REV)
  "Use latexdiff to compile a pdf file of the
difference between the current state and REV"
  (let ((file (TeX-master-file nil nil t))
	(diff-file (format "%s-diff%s" (TeX-master-file nil nil t) REV)))
    (message "[%s.tex] Generating latex diff with %s" file REV)
    (call-process "/bin/bash" nil 0 nil "-c"
		  (format "yes X | latexdiff-vc --force -r %s %s.tex --pdf > latexdiff.log ;
                           GLOBIGNORE='*.pdf' ;
                           rm -r %s* ;
                           rm -r %s-oldtmp* ;
                           GLOBIGNORE='' ;
                           okular %s.pdf "
			  REV file diff-file file diff-file))))

(defun latexdiff--clean ()
  "Remove all file generated by latexdiff"
  (interactive)
  (let ((file (TeX-master-file nil nil t)))
    (call-process "/bin/bash" nil 0 nil "-c"
		  (format "rm -f %s-diff* ;
                           rm -f %s-oldtmp* ;
                           rm -f latexdiff.log"
			  file file))))

(defun latexdiff--get-commits-infos ()
  "Return a list with all commits informations"
  (interactive)
  (let ((infos nil))
    (with-temp-buffer
      (vc-git-command t nil nil "log" "--format=%h---%cr---%cn---%s---%d" "--abbrev-commit" "--date=short")
      (goto-char (point-min))
      (while (re-search-forward "^.+$" nil t)
	(push (split-string (match-string 0) "---") infos)))
    infos))

(defun latexdiff--get-commits-description ()
  "Return a list of commits description strings
to use with helm"
  (interactive)
  (let ((descriptions ())
	(infos (latexdiff--get-commits-infos))
	(tmp-desc nil)
	(lengths '((l1 . 0) (l2 . 0) (l3 . 0) (l4 . 0))))
    ;; Get lengths
    (dolist (tmp-desc infos)
      (pop tmp-desc)
      (when (> (length (nth 0 tmp-desc)) (cdr (assoc 'l1 lengths)))
	  (add-to-list 'lengths `(l1 . ,(length (nth 1 tmp-desc)))))
      (when (> (length (nth 1 tmp-desc)) (cdr (assoc 'l2 lengths)))
	  (add-to-list 'lengths `(l2 . ,(length (nth 2 tmp-desc)))))
      (when (> (length (nth 2 tmp-desc)) (cdr (assoc 'l3 lengths)))
	  (add-to-list 'lengths `(l3 . ,(length (nth 3 tmp-desc)))))
      (when (> (length (nth 3 tmp-desc)) (cdr (assoc 'l4 lengths)))
	  (add-to-list 'lengths `(l4 . ,(length (nth 4 tmp-desc)))))
      )
    (print lengths)
    ;; Get infos
    (dolist (tmp-desc infos)
      (pop tmp-desc)
      (push (string-join
	     (list
	      (propertize (format
			   (format "%%-%ds "
				   (cdr (assoc 'l1 lengths)))
			   (nth 1 tmp-desc)) 'face 'latexdiff-author-face)
	      (propertize (format
			   (format "%%-%ds "
				   (cdr (assoc 'l2 lengths)))
			   (nth 0 tmp-desc)) 'face 'latexdiff-date-face)
	      (propertize (format
			   (format "%%-%ds"
				   (cdr (assoc 'l3 lengths)))
			   (nth 2 tmp-desc)) 'face 'latexdiff-message-face)
	      (propertize (format "%s"
			   (nth 3 tmp-desc)) 'face 'latexdiff-ref-labels-face))
	     " ")
	    descriptions)
      )
    descriptions))

(defun latexdiff--get-commits-hashes ()
  "Return the list of commits hashes"
  (interactive)
  (let ((hashes ())
	(infos (latexdiff--get-commits-infos))
	(tmp-desc nil))
    (setq infos (cdr infos))
    (dolist (tmp-desc infos)
      (push (pop tmp-desc) hashes))
      hashes))

(defun latexdiff--update-commits ()
  "Update the list of commits
to use with helm"
  (interactive)
  (let ((descr (latexdiff--get-commits-description))
	(hash (latexdiff--get-commits-hashes))
	(list ()))
      (print descr)
      (print hash)
    (while (not (equal (length descr) 0))
      (setq list (cons (cons (pop descr) (pop hash)) list)))
    (reverse list)))

(defvar helm-source-latexdiff-choose-commit
  (helm-build-sync-source "Latexdiff choose commit"
    ;; :init (lambda () (latexdiff--update-commits))
    :candidates 'latexdiff--update-commits
    :fuzzy-match helm-projectile-fuzzy-match
    ;; :keymap helm-latexdiff-commit-map
    :mode-line helm-read-file-name-mode-line-string
    :action '(("Choose this commit" . latexdiff--compile-diff-with-current))
    )
  "Helm source for modified projectile projects.")

(defvar helm-source-latexdiff-choose-commit-range
  (helm-build-sync-source "Latexdiff choose commit"
    :candidates 'latexdiff--update-commits
    :fuzzy-match helm-projectile-fuzzy-match
    :mode-line helm-read-file-name-mode-line-string
    :action '(("Choose these commits" . latexdiff--compile-diff))
    )
  "Helm source for modified projectile projects.")

(defun helm-latexdiff ()
  (interactive)
  (helm :sources 'helm-source-latexdiff-choose-commit
	:buffer "*helm-latexdiff*"
	:nomark t
	:prompt "Choose a commit: "))

(defun helm-latexdiff-range ()
  (interactive)
  (let ((commits (latexdiff--update-commits)))
    (let ((rev1 (helm-comp-read "First commit: " commits))
	  (rev2 (helm-comp-read "Second commit: " commits)))
    (latexdiff--compile-diff rev1 rev2)
  )))


(provide 'latexdiff)
