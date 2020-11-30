(setq inhibit-startup-message   t)   ; Don't want any startup message
(setq make-backup-files         nil) ; Don't want any backup files
(setq auto-save-list-file-name  nil) ; Don't want any .saves files
(setq auto-save-default         nil) ; Don't want any auto saving
(require 'package)
(add-to-list 'package-archives '("melpa" . "http://melpa.org/packages/"))
(package-initialize)
(require 'ido)
(show-paren-mode t)
(ido-mode t)

(setq auto-mode-alist
      (append
       (list
        '("\\.n3" . ttl-mode)
        '("\\.ttl" . ttl-mode))
       auto-mode-alist))

(defmacro bind-key (key function)
  `(progn
     (setq k (read-kbd-macro ,key))
     (global-unset-key k)
     (global-set-key k ,function)))

(defun bind-keys (bindings)
  (if (eq (cdr bindings) nil)
      t
    (progn
      (let ((key (car bindings))
	    (function (cadr bindings)))	 
	(bind-key key function)
	(bind-keys (cddr bindings))))))

(bind-keys
 '("<C-tab>" other-window
   "<backtab>" other-window
   "<C-return>" zoom-window
   ))

(defun zoom-window ()
  "..." (interactive) (let* ((w1 (selected-window))
			     (w2 (select-window (window-at 0 0)))
			     (b1 (window-buffer w1))
			     (b2 (window-buffer w2))
			     (s1 (window-start w1))
			     (s2 (window-start w2)))
			(set-window-buffer w1 b2)
			(set-window-buffer w2 b1)
			(set-window-start w1 s2)
			(set-window-start w2 s1)))
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(custom-safe-themes
   (quote
    ("a287cbeda5de1ef78b747a1d6decb41d99fbd2aed76026054e956f4cc48be605" "1504cef09993103524ba9dfd4f46e7f0dcddc24a59b83bf71d2f3b6153c4bf75" "fb98e662fab8dcec7e960f832bbe6edde03bdbf929187754e5238bb8c99c0e41" "684bbe04f2f4755c6411e3d7851f87075c2e38817e5f687c3021f8d79f48316e" "be496fbe7e6acac40415e02fecaaf636de2cdc18a8237898654ec328f1a97dc9" default)))
 '(menu-bar-mode nil)
 '(package-selected-packages
   (quote
    (markdown-mode auto-complete projectile-rails flycheck flymake-ruby w3 projectile))))

(load-theme 'jeff)
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(default ((t (:inherit nil :stipple nil :background "black" :foreground "white" :inverse-video nil :box nil :strike-through nil :overline nil :underline nil :slant normal :weight normal :height 70 :width normal :foundry "PfEd" :family "Terminus"))))
 '(mode-line ((t (:background "color-238")))))
