;;; lan.el --- List devices on the local network -*- lexical-binding: t; -*-

;;; Commentary:
;; Use `lan-list' to display devices reported by the neighbor table and Avahi.

;;; Code:

(require 'tabulated-list)
(require 'subr-x)
(require 'cl-lib)

(defvar lan-list-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "g") #'lan-list)
    map)
  "Keymap for `lan-list-mode'.")

(define-derived-mode lan-list-mode tabulated-list-mode "LAN"
  "Major mode for displaying devices found on the local network."
  (setq tabulated-list-format
        [("IP address" 16 t)
         ("Name" 32 t)
         ("MAC address" 20 t)
         ("Source" 24 t)]
        tabulated-list-padding 2)
  (tabulated-list-init-header))

(defun lan--run (program &rest arguments)
  "Run PROGRAM with ARGUMENTS and return its standard output, or nil."
  (when (executable-find program)
    (with-temp-buffer
      (when (zerop (apply #'process-file program nil t nil arguments))
        (buffer-string)))))

(defun lan--merge-device (devices ip &optional name mac source)
  "Merge a device with IP, NAME, MAC, and SOURCE into DEVICES."
  (when ip
    (let ((device (or (gethash ip devices)
                      (let ((new (list :ip ip)))
                        (puthash ip new devices)
                        new))))
      (when (and name (not (string-empty-p name)))
        (plist-put device :name name))
      (when (and mac (not (string-empty-p mac)))
        (plist-put device :mac mac))
      (when source
        (plist-put device :sources
                   (cons source (delete source (plist-get device :sources)))))
      (puthash ip device devices))))

(defun lan--read-neighbors (devices)
  "Add neighbor-table entries to DEVICES."
  (when-let ((output (lan--run "ip" "neigh" "show")))
    (dolist (line (split-string output "\n" t))
      (when (string-match
             "\\`\\([0-9.]+\\) +dev +\\([^ ]+\\)\\(?: +lladdr +\\([^ ]+\\)\\)?\\(?: +\\(.*\\)\\)?"
             line)
        (lan--merge-device devices (match-string 1 line) nil
                           (match-string 3 line) "neighbor table")))))

(defun lan--read-avahi (devices)
  "Add IPv4 Avahi service announcements to DEVICES."
  (when-let ((output (lan--run "avahi-browse" "--resolve" "--all" "--terminate")))
    (let (record)
      (cl-labels ((finish-record ()
                    (when record
                      (let* ((text (string-join (nreverse (plist-get record :lines)) "\n"))
                             (ip (and (string-match "address = \\[\\([0-9.]+\\)\\]" text)
                                      (match-string 1 text)))
                             (hostname (and (string-match "hostname = \\[\\([^]]+\\)\\]" text)
                                            (match-string 1 text)))
                             (advertised (or (and (string-match "\\bfn=\\([^\"]+\\)" text)
                                                  (match-string 1 text))
                                             (and (string-match "\\bname=\\([^\"]+\\)" text)
                                                  (match-string 1 text))))
                             (name (or advertised
                                       (and hostname (string-remove-suffix ".local" hostname))
                                       (plist-get record :name))))
                        (lan--merge-device devices ip name nil "Avahi")))))
        (dolist (line (split-string output "\n" t))
          (when (string-prefix-p "= " line)
            (finish-record)
            (setq record nil)
            (when (string-match "\\`= +[^ ]+ +IPv4 +\\(.+?\\) +_[^ ]+" line)
              (setq record (list :name (match-string 1 line) :lines nil))))
          (when record
            (push line (plist-get record :lines))))
        (finish-record)))))

(defun lan--discover-devices ()
  "Return devices currently reported by the neighbor table or Avahi."
  (let ((devices (make-hash-table :test #'equal)))
    (lan--read-neighbors devices)
    (lan--read-avahi devices)
    devices))

(defun lan--read-address ()
  "Read a host address, suggesting IPs discovered on the local network."
  (let* ((devices (lan--discover-devices))
         (addresses (sort (hash-table-keys devices) #'string-lessp)))
    (completing-read "SSH address: " addresses nil nil)))

;;;###autoload
(defun lan-ssh-tunnel (username address port)
  "Start an SSH tunnel for USERNAME on ADDRESS forwarding PORT locally.
The remote service is reached at 127.0.0.1:PORT.  The SSH process runs in
the background in the `*lan-ssh-tunnel*' buffer."
  (interactive (list (read-string "SSH username: ")
                     (lan--read-address)
                     (read-number "Forward port: ")))
  (unless (and (integerp port) (<= 1 port 65535))
    (user-error "Port must be an integer between 1 and 65535"))
  (unless (executable-find "ssh")
    (user-error "Could not find ssh in `exec-path'"))
  (let* ((port-string (number-to-string port))
         (forward (format "%s:127.0.0.1:%s" port-string port-string))
         (target (format "%s@%s" username address))
         (buffer (get-buffer-create "*lan-ssh-tunnel*"))
         (process (make-process
                   :name (format "lan-ssh-tunnel-%s" port)
                   :buffer buffer
                   :command (list "ssh" "-L" forward target "-N")
                   :noquery t
                   :connection-type 'pipe)))
    (with-current-buffer buffer
      (goto-char (point-max))
      (insert (format "Starting localhost:%s -> %s:127.0.0.1:%s\n"
                      port-string address port-string)))
    (message "SSH tunnel starting: localhost:%s -> %s" port-string target)
    process))

;;;###autoload
(defun lan-list ()
  "List devices discovered on the local network in a buffer.
Refresh the list each time the command is invoked."
  (interactive)
  (let ((devices (lan--discover-devices))
        (buffer (get-buffer-create "*LAN Devices*")))
    (with-current-buffer buffer
      (lan-list-mode)
      (setq tabulated-list-entries
            (mapcar
             (lambda (device)
               (let ((ip (plist-get device :ip)))
                 (list ip
                       (vector ip
                               (or (plist-get device :name) "")
                               (or (plist-get device :mac) "")
                               (string-join (delete-dups (plist-get device :sources)) ", ")))))
             (sort (hash-table-values devices)
                   (lambda (left right)
                     (string-lessp (plist-get left :ip) (plist-get right :ip))))))
      (tabulated-list-print t)
      (goto-char (point-min)))
    (pop-to-buffer buffer)))

(provide 'lan)
;;; lan.el ends here
