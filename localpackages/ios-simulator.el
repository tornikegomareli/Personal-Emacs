;;; Simulator --- A small package for viewing iOS simulator logs -*- lexical-binding: t -*-
;;; Commentary: This package provides some support for iOS Simulator
;;; Code:

(require 'periphery-helper)

(defgroup ios-simulator nil
  "IOS-SIMULATOR."
  :tag "ios-simulator"
  :group 'ios-simulator)

(defface ios-simulator-background-face
  '((t (:inherit default)))
  "Buffer background color."
  :group 'ios-simulator)

(defconst ios-simulator-buffer-name "*iOS Simulator*"
  "Name of the buffer.")

(defconst list-simulators-command
  "xcrun simctl list devices available -j"
  "List available simulators.")

(defconst get-booted-simulator-command
  "xcrun simctl list devices | grep -m 1 \"(Booted)\" | grep -E -o -i \"([0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12})\""
  "Get booted simulator id if any.")

(defvar current-language-selection "en-EN")
(defvar current-simulator-name nil)
(defvar current-simulator-id nil)
(defvar secondary-simulator-id nil)
(defvar current-app-identifier nil)

(defun ios-simulator:current-sdk-version ()
  "Get the current simulator sdk-version."
  (clean-up-newlines (shell-command-to-string "xcrun --sdk iphonesimulator --show-sdk-version")))

(defun ios-simulator:sdk-path ()
  "Get the current simulator sdk-path."
  (clean-up-newlines (shell-command-to-string "xcrun --show-sdk-path --sdk iphonesimulator")))

(defun ios-simulator:current-arch ()
  "Get the current arch."
  (clean-up-newlines (shell-command-to-string "clang -print-target-triple")))

(defun ios-simulator:target ()
  "Get the current simulator sdk."
  (let* ((target-components (split-string (ios-simulator:current-arch) "-"))
         (arch (nth 0 target-components))
         (vendor (nth 1 target-components))
         (version (ios-simulator:current-sdk-version)))
    (format "%s-%s-ios%s-simulator" arch vendor version)))

(cl-defun ios-simulator:install-and-run-app (&key rootfolder &key build-folder &key simulatorId &key appIdentifier)
  "Install app in simulator with ROOTFOLDER BUILD-FOLDER SIMULATORID, APPIDENTIFIER BUFFER."
  (ios-simulator:kill-buffer)

  (let* ((default-directory rootfolder)
         (simulator-id simulatorId)
         (buffer (get-buffer-create ios-simulator-buffer-name)))

    (setq applicationName (ios-simulator:app-name-from :folder build-folder))
    (setq simulatorName  (ios-simulator:fetch-simulator-name))
    
    (message-with-color
     :tag "[Installing]"
     :text (format "%s onto %s. Will launch app when done." applicationName simulatorName)
     :attributes '(:inherit success))
    (ios-simulator:terminate-app-with
     :appIdentifier appIdentifier)
    
    (ios-simulator:install-app
     :simulatorID simulator-id
     :build-folder build-folder)
      
    (inhibit-sentinel-messages #'async-shell-command
                               (ios-simulator:launch-app
                                :appIdentifier current-app-identifier
                                :applicationName applicationName
                                :simulatorName simulatorName
                                :simulatorID simulator-id)
                               buffer)

    (with-current-buffer buffer
      (setq-local mode-line-format nil)
      (read-only-mode)
      (setq left-fringe-width 0)
      (setq right-fringe-width 0)
      (setq buffer-face-mode-face 'ios-simulator-background-face)
      (buffer-face-mode 1))))

(cl-defun ios-simulator:install-app (&key simulatorID &key build-folder)
  "Install and launch app (as SIMULATORID and BUILD-FOLDER)."
  (let* ((folder build-folder)
         (install-path (shell-quote-argument folder)))
    (inhibit-sentinel-messages
     #'call-process-shell-command
     (format "xcrun simctl install %s %s%s.app\n" simulatorID install-path (ios-simulator:app-name-from :folder folder)))))

(cl-defun ios-simulator:app-name-from (&key folder)
  "Get compiled app name from (FOLDER)."
  (when-let (binary-name (directory-files folder nil "\\.app$"))
    (file-name-sans-extension (car binary-name))))

(defun ios-simulator:kill-buffer ()
  "Kill the ios-simulator buffer."
  (when (get-buffer ios-simulator-buffer-name)
    (kill-buffer ios-simulator-buffer-name)))

(defun ios-simulator:setup-simulator-dwim (id)
  "Setup simulator dwim (as ID)."
  (if (not (ios-simulator:is-simulator-app-running))
      (ios-simulator:start-simulator-with-id id)
    (ios-simulator:boot-simuator-with-id id)))

(defun ios-simulator:fetch-simulator-name ()
  "Fetches simulator name."
  (unless current-simulator-name
    (let ((simulator-name (ios-simulator:simulator-name current-simulator-id)))
      (if simulator-name
          (setq current-simulator-name (format "%s(simulator)" simulator-name))
        (setq current-simulator-name "Simulator (unknown)"))))
  current-simulator-name)

(defun ios-simulator:boot-simuator-with-id (id)
  "Simulator app is running.  Boot simulator (as ID)."
  (inhibit-sentinel-messages
   #'call-process-shell-command (format "xcrun simctl boot %s" id)))

(defun ios-simulator:start-simulator-with-id (id)
  "Launch a specific simulator with (as ID)."
  (inhibit-sentinel-messages
   #'call-process-shell-command (format "open --background -a simulator --args -CurrentDeviceUDID %s" id)))

(defun ios-simulator:is-simulator-app-running ()
  "Check if simulator is running."
  (let ((output (shell-command-to-string "ps ax | grep -v grep | grep Simulator.app")))
    (not (string= "" output))))

(defun ios-simulator:simulator-name (id)
  "Get simulator name (as ID)."
  (clean-up-newlines
   (shell-command-to-string (format "xcrun simctl list devices | grep %s | awk -F \"(\" '{ print $1 }'" id))))

(defun ios-simulator:available-simulators ()
  "List available simulators."
  (let* ((devices (ios-simulator:fetch-available-simulators))
         (items (seq-map
                 (lambda (device)
                   (cons (cdr (assoc 'name device))
                         (cdr (assoc 'udid device)))) devices)))
    items))

(cl-defun ios-simulator:build-language-menu (&key title)
  "Build language menu (as TITLE)."
  (interactive)
  (defconst languageList '(
                           ("🏴󠁧󠁢󠁥󠁮󠁧󠁿 English (UK)" "en-UK")
                           ("🇸🇪 Swedish (Sweden)" "sv-SE")
                           ("🇦🇪 Arabic (United Arab Emirates)" "ar-AE")
                           ("🇸🇦 Arabic (Saudi Arabia)" "ar-EG")
                           ("🇫🇷 French (France)" "fr-FR")
                           ("🇳🇱 Dutch (Netherlands)" "nl-NL")
                           ("🇳🇴 Norwegian (Bokmål)" "nb-NO")
                           ("🇯🇵 Japanese (Japan)" "ja-JP")
                           ("🇩🇪 German (Germany)" "de-DE")
                           ("🇪🇸 Spanish (Spain)" "es-ES")
                           ("🇮🇹 Italian (Italy)" "it-IT")
                           ("🇧🇷 Portuguese (Brazil)" "pt-BR")
                           ("🇵🇱 Polish (Poland)" "pl-PL")
                           ("🇨🇳 Chinese (Simplified)" "zh-CN")
                           ("🇷🇺 Russian (Russia)" "ru-RU")
                           ("🇹🇷 Turkish (Turkey)" "tr-TR")
                           ("🇮🇳 Hindi (India)" "hi-IN")
                           ("🇰🇷 Korean (Korea)" "ko-KR")
                           ("🇹🇼 Chinese (Traditional)" "zh-TW")
                           ))
    (progn
    (let* ((choices (seq-map (lambda (item) item) languageList))
           (choice (completing-read title choices)))
      (car (cdr (assoc choice choices))))))

(cl-defun ios-simulator:build-selection-menu (&key title &key list)
  "Builds a widget menu from (as TITLE as LIST)."
  (interactive)
  (if (<= (length list) 1)
      (elt list 0)
    (progn
      (let* ((choices (seq-map (lambda (item) item) list))
             (choice (completing-read title choices)))
        (cdr (assoc choice choices))))))

(defun ios-simulator:load-simulator-id ()
  "Get the booted simulator id or fetch a suiting one."
  (if current-simulator-id
      (ios-simulator:setup-simulator-dwim current-simulator-id)
    (progn
    (message-with-color
     :tag "[Fetching simulators]"
     :text "Please stand by.."
     :attributes '(:inherit success))
      (let ((device-id
             (or (ios-simulator:booted-simulator)
                 (ios-simulator:build-selection-menu :title "Choose a simulator:" :list (ios-simulator:available-simulators)))))
        (progn
          (ios-simulator:setup-language)
          (ios-simulator:setup-simulator-dwim current-simulator-id)
          (setq current-simulator-id device-id)))))
  current-simulator-id)

(defun ios-simulator:booted-simulator ()
  "Get booted simulator if any."
  (let ((device-id (shell-command-to-string get-booted-simulator-command)))
    (if (not (string= "" device-id))
        (clean-up-newlines device-id)
      nil)))

(defun ios-simulator:terminate-current-app ()
  "Terminate the current app running in simulator."
  (interactive)
  (if current-app-identifier
      (ios-simulator:terminate-app-with :appIdentifier current-app-identifier)))

(defun ios-simulator:change-language ()
  "Reset current language for simulator."
  (interactive)
  (setq current-language-selection (ios-simulator:build-language-menu :title "Choose simulator language")))

(defun ios-simulator:setup-language ()
  "Setup language if it isnt set."
  (interactive)
  (unless current-language-selection
    (setq current-language-selection (ios-simulator:build-language-menu :title "Choose simulator language"))))

(cl-defun ios-simulator:launch-app (&key appIdentifier &key applicationName &key simulatorName &key simulatorID)
  "Command to filter and log the simulator (as APPIDENTIFIER APPLICATIONNAME SIMULATORNAME SIMULATORID)."
  (ios-simulator:setup-language)

  (message-with-color :tag "[Running]" :text (format "%s on %s" applicationName simulatorName) :attributes 'success)
  (if-let ((simulatorID simulatorID))
      (format "xcrun simctl launch --console-pty %s %s -AppleLanguages \"\(%s\)\"" simulatorID appIdentifier current-language-selection)
    (format "xcrun simctl launch --console-pty booted %s -AppleLanguages \"\(%s\)\"" appIdentifier current-language-selection)))

(cl-defun ios-simulator:terminate-app-with (&key appIdentifier)
  "Terminate runnings apps (as APPIDENTIFIER)."
  (setq current-app-identifier appIdentifier)
  (ios-simulator:terminate-app :simulatorID current-simulator-id :appIdentifier appIdentifier)
  (ios-simulator:terminate-app :simulatorID secondary-simulator-id :appIdentifier appIdentifier))

(cl-defun ios-simulator:terminate-app (&key simulatorID &key appIdentifier)
  "Terminate app (as APPIDENTIFIER as SIMULATORID)."
  (inhibit-sentinel-messages #'call-process-shell-command
   (concat
    (if simulatorID
        (format "xcrun simctl terminate %s %s" simulatorID appIdentifier)
      (format "xcrun simctl terminate booted %s" appIdentifier)))))

(defun ios-simulator:appcontainer ()
  "Get the app container of the current app (as SIMULATORID, APPIDENTIFIER)."
  (interactive)
  (if-let ((identifier current-app-identifier)
           (id current-simulator-id)
           (command (shell-command-to-string (format "xcrun simctl get_app_container %s %s data" id identifier))))
      (async-shell-command (concat "open " command))))

(defun ios-simulator:fetch-available-simulators ()
  "List available simulators."
  (message-with-color :tag "[Fetching]" :text "available simulators..." :attributes '(:inherit warning))
  (let* ((json (call-process-to-json list-simulators-command))
         (devices (cdr (assoc 'devices json)))
         (flattened (apply 'seq-concatenate 'list (seq-map 'cdr devices)))
         (available-devices
          (seq-filter
           (lambda (device) (cdr (assoc 'isAvailable device))) flattened))
         ) available-devices))

(provide 'ios-simulator)
;;; ios-simulator.el ends here

