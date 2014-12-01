(in-package :elprep)
(in-simple-base-string-syntax)

;;; input streams

#+lispworks
(defmacro with-buffer-dispatch (buffer &body body)
  (error "with-buffer-dispatch is not available in LispWorks: ~S."
         `(with-buffer-dispatch ,buffer ,@body)))

#+lispworks
(defmacro with-ascii-stream-input-buffer (buffer stream &body body)
  (error "with-ascii-stream-input-buffer is not available in LispWorks: ~S."
         `(with-ascii-stream-input-buffer ,buffer ,stream ,@body)))

#+sbcl
(progn
  (defconstant +ascii-stream-buffer-size+ (expt 2 13))

  (declaim (inline make-buffered-ascii-input-stream))

  (defstruct (buffered-ascii-input-stream
              (:constructor make-buffered-ascii-input-stream
               (stream &optional (element-type 'base-char) &aux
                       (buffer (ecase element-type
                                 (base-char (make-array +ascii-stream-buffer-size+ :element-type 'octet))
                                 (character (make-array +ascii-stream-buffer-size+ :element-type 'character))))
                       (limit  (read-sequence buffer stream)))))
    (index 0 :type fixnum)
    (limit 0 :type fixnum)
    buffer
    (secondary-buffer nil)
    (element-type 'base-char :type symbol :read-only t)
    (stream nil :type (or null stream)))

  (defmethod input-stream-p ((stream buffered-ascii-input-stream)) t)

  (declaim (inline stream-fill-buffer))

  (defun stream-fill-buffer (stream)
    (declare (buffered-ascii-input-stream stream) #.*optimization*)
    (let ((position (read-sequence (buffered-ascii-input-stream-buffer stream)
                                   (buffered-ascii-input-stream-stream stream))))
      (declare (fixnum position))
      (when (> position 0)
        (setf (buffered-ascii-input-stream-index stream) 0
              (buffered-ascii-input-stream-limit stream) position)
        t)))

  (defmacro with-buffer-dispatch (buffer &body body)
    `(etypecase ,buffer
       ((simple-array octet (*))
        (let ((,buffer ,buffer))
          (declare ((simple-array octet (*)) ,buffer))
          (flet ((bchar (buffer index)
                   (declare ((simple-array octet (*)) buffer) (fixnum index))
                   (code-char (the octet (aref buffer index))))
                 ((setf bchar) (new-value buffer index)
                   (declare (base-char new-value) ((simple-array octet (*)) buffer) (fixnum index))
                   (setf (aref buffer index) (char-code new-value))
                   new-value))
            (declare (inline bchar (setf bchar)) (ignorable #'bchar #'(setf bchar)))
            ,@body)))
       ((simple-array character (*))
        (let ((,buffer ,buffer))
          (declare ((simple-array character (*)) ,buffer))
          (flet ((bchar (buffer index)
                   (declare ((simple-array character (*)) buffer) (fixnum index))
                   (aref buffer index))
                 ((setf bchar) (new-value buffer index)
                   (declare (character new-value) ((simple-array character (*)) buffer) (fixnum index))
                   (setf (aref buffer index) new-value)))
            (declare (inline bchar (setf bchar)) (ignorable #'bchar #'(setf bchar)))
            ,@body)))))

  (defmacro with-ascii-stream-input-buffer (buffer stream &body body)
    `(let ((,buffer (buffered-ascii-input-stream-buffer ,stream)))
       (with-buffer-dispatch ,buffer ,@body)))

  (defmethod stream-element-type ((stream buffered-ascii-input-stream))
    (buffered-ascii-input-stream-element-type stream))

  (defmethod close ((stream buffered-ascii-input-stream) &key abort)
    (declare (ignore abort))
    (setf (buffered-ascii-input-stream-stream stream) nil
          (buffered-ascii-input-stream-buffer stream) nil
          (buffered-ascii-input-stream-secondary-buffer stream) nil))

  (defmethod stream-file-position ((stream buffered-ascii-input-stream) &optional position)
    (declare #.*optimization*)
    (if position
      (when (file-position (buffered-ascii-input-stream-stream stream) position)
        (stream-fill-buffer stream) t)
      (+ (file-position (buffered-ascii-input-stream-stream stream))
         (the fixnum (- (the fixnum (buffered-ascii-input-stream-index stream))
                        (the fixnum (buffered-ascii-input-stream-limit stream)))))))

  (defmethod stream-clear-input ((stream buffered-ascii-input-stream)))

  (defmethod stream-read-sequence ((stream buffered-ascii-input-stream) sequence &optional (start 0) end)
    (declare #.*optimization*)
    (assert (typep start 'fixnum))
    (if end (assert (typep end 'fixnum))
      (setq end (length sequence)))
    (let ((start start) (end end))
      (declare (fixnum start end))
      (when (> end start)
        (with-ascii-stream-input-buffer buffer stream
          (loop (let* ((index (buffered-ascii-input-stream-index stream))
                       (limit (buffered-ascii-input-stream-limit stream))
                       (size  (min (the fixnum (- end start))
                                   (the fixnum (- limit index)))))
                  (declare (fixnum index limit size))
                  (setf (subseq sequence start end)
                        (subseq buffer index limit))
                  (setf (buffered-ascii-input-stream-index stream) (the fixnum (+ index size)))
                  (setq start (the fixnum (+ start size))))
                (unless (stream-fill-buffer stream)
                  (return-from stream-read-sequence start)))))))

  (defmethod stream-peek-char ((stream buffered-ascii-input-stream))
    (declare #.*optimization*)
    (with-ascii-stream-input-buffer buffer stream
      (loop (let ((index (buffered-ascii-input-stream-index stream))
                  (limit (buffered-ascii-input-stream-limit stream)))
              (declare (fixnum index limit))
              (when (< index limit)
                (return-from stream-peek-char (bchar buffer index))))
            (unless (stream-fill-buffer stream)
              (return-from stream-peek-char :eof)))))

  (defmethod stream-read-char-no-hang ((stream buffered-ascii-input-stream))
    (declare #.*optimization*)
    (with-ascii-stream-input-buffer buffer stream
      (loop (let ((index (buffered-ascii-input-stream-index stream))
                  (limit (buffered-ascii-input-stream-limit stream)))
              (declare (fixnum index limit))
              (when (< index limit)
                (let ((char (bchar buffer index)))
                  (setf (buffered-ascii-input-stream-index stream) (the fixnum (1+ index)))
                  (return-from stream-read-char-no-hang char))))
            (unless (stream-fill-buffer stream)
              (return-from stream-read-char-no-hang :eof)))))

  (defmethod stream-read-char ((stream buffered-ascii-input-stream))
    (declare #.*optimization*)
    (with-ascii-stream-input-buffer buffer stream
      (loop (let ((index (buffered-ascii-input-stream-index stream))
                  (limit (buffered-ascii-input-stream-limit stream)))
              (declare (fixnum index limit))
              (when (< index limit)
                (let ((char (bchar buffer index)))
                  (setf (buffered-ascii-input-stream-index stream) (the fixnum (1+ index)))
                  (return-from stream-read-char char))))
            (unless (stream-fill-buffer stream)
              (return-from stream-read-char :eof)))))

  (defmethod stream-read-line ((stream buffered-ascii-input-stream))
    (declare #.*optimization*)
    (let ((strings '()))
      (declare (list strings))
      (with-ascii-stream-input-buffer buffer stream
        (loop (let ((index (buffered-ascii-input-stream-index stream))
                    (limit (buffered-ascii-input-stream-limit stream)))
                (declare (fixnum index limit))
                (loop for end of-type fixnum from index below limit
                      for flag of-type boolean = (char= (bchar buffer end) #\Newline)
                      until flag finally
                      (let ((string (make-array (the fixnum (- end index)) :element-type 'base-char)))
                        (declare (simple-base-string string))
                        (loop for j of-type fixnum from index below end
                              for i of-type fixnum from 0
                              do (setf (schar string i) (bchar buffer j)))
                        (cond (flag (setf (buffered-ascii-input-stream-index stream) (the fixnum (1+ end)))
                                    (cond (strings (push string strings)
                                                   (return-from stream-read-line
                                                     (values (apply #'concatenate 'simple-base-string (nreverse strings)) nil)))
                                          (t       (return-from stream-read-line
                                                     (values string nil)))))
                              (t   (setf (buffered-ascii-input-stream-index stream) limit)
                                   (push string strings))))))
              (unless (stream-fill-buffer stream)
                (if strings
                  (if (cdr strings)
                    (return-from stream-read-line (values (apply #'concatenate 'simple-base-string (nreverse strings)) t))
                    (return-from stream-read-line (values (car strings) t)))
                  (return-from stream-read-line (values :eof t))))))))

  (defun skip-line (stream)
    "Skip characters from stream until a newline is reached."
    (declare (buffered-ascii-input-stream stream) #.*optimization*)
    (with-ascii-stream-input-buffer buffer stream
      (loop (let ((index (buffered-ascii-input-stream-index stream))
                  (limit (buffered-ascii-input-stream-limit stream)))
              (declare (fixnum index limit))
              (loop for pos of-type fixnum from index below limit do
                    (when (char= (bchar buffer pos) #\Newline)
                      (setf (buffered-ascii-input-stream-index stream) (the fixnum (1+ pos)))
                      (return-from skip-line))
                    finally (setf (buffered-ascii-input-stream-index stream) pos)))
            (unless (stream-fill-buffer stream)
              (return-from skip-line)))))

  (defmethod stream-listen ((stream buffered-ascii-input-stream))
    (declare #.*optimization*)
    (or (let ((index (buffered-ascii-input-stream-index stream))
              (limit (buffered-ascii-input-stream-limit stream)))
          (declare (fixnum index limit))
          (< index limit))
        (listen (buffered-ascii-input-stream-stream stream))))

  (defmethod stream-unread-char ((stream buffered-ascii-input-stream) character)
    (declare (ignore character) #.*optimization*)
    (setf (buffered-ascii-input-stream-index stream)
          (the fixnum (1- (the fixnum (buffered-ascii-input-stream-index stream)))))
    nil)

  (defun copy-stream (input output)
    "Efficient copying of the contents of an input stream to an output stream."
    (declare (buffered-ascii-input-stream input) (stream output) #.*optimization*)
    (ecase (buffered-ascii-input-stream-element-type input)
      (base-char (let ((buffer (buffered-ascii-input-stream-buffer input))
                       (second (or (buffered-ascii-input-stream-secondary-buffer input)
                                   (setf (buffered-ascii-input-stream-secondary-buffer input)
                                         (make-array +ascii-stream-buffer-size+ :element-type 'base-char)))))
                   (declare ((simple-array octet (*)) buffer) (simple-base-string second))
                   (loop (let ((index (buffered-ascii-input-stream-index input))
                               (limit (buffered-ascii-input-stream-limit input)))
                           (declare (fixnum index limit))
                           (when (< index limit)
                             (loop for i of-type fixnum from index below limit do
                                   (setf (schar second i) (code-char (the octet (aref buffer i)))))
                             (write-string second output :start index :end limit)
                             (setf (buffered-ascii-input-stream-index input) limit)))
                         (unless (stream-fill-buffer input)
                           (return-from copy-stream (values))))))
      (character (let ((buffer (buffered-ascii-input-stream-buffer input)))
                   (declare ((simple-array character (*)) buffer))
                   (loop (let ((index (buffered-ascii-input-stream-index input))
                               (limit (buffered-ascii-input-stream-limit input)))
                           (declare (fixnum index limit))
                           (when (< index limit)
                             (write-string buffer output :start index :end limit)
                             (setf (buffered-ascii-input-stream-index input) limit)))
                         (unless (stream-fill-buffer input)
                           (return-from copy-stream (values)))))))))

#+lispworks
(progn
  (defun skip-line (stream)
    "Skip characters from stream until a newline is reached."
    (declare (buffered-stream stream) #.*fixnum-optimization*)
    (loop (with-stream-input-buffer (source index limit) stream
            (declare (simple-base-string source) (fixnum index limit))
            (loop for pos of-type fixnum from index below limit do
                  (when (char= (lw:sbchar source pos) #\Newline)
                    (setq index (1+ pos))
                    (return-from skip-line))
                  finally (setq index pos)))
          (unless (stream-fill-buffer stream)
            (return-from skip-line))))

  (defun copy-stream (input output)
    "Efficient copying of the contents of an input stream to an output stream."
    (declare (buffered-stream input) (stream output) #.*optimization*)
    (loop (with-stream-input-buffer (buffer index limit) input
            (declare (simple-base-string buffer) (fixnum index limit))
            (when (< index limit)
              (stream-write-string output buffer index limit)
              (setq index limit)))
          (unless (stream-fill-buffer input)
            (return-from copy-stream (values))))))


;;; output streams

(declaim (inline writec write-newline write-tab))

#+sbcl
(defun writec (out c)
  "Write a character to output stream."
  (write-char c out))

#+lispworks
(defun writec (out c)
  (declare (buffered-stream out) (base-char c) #.*optimization*)
  (loop (with-stream-output-buffer (buffer index limit) out
          (declare (simple-base-string buffer) (fixnum index limit))
          (when (< index limit)
            (setf (lw:sbchar buffer index) c)
            (setq index (the fixnum (1+ index)))
            (return-from writec c)))
        (stream-flush-buffer out)))

(defun write-newline (out)
  "Write a newline to output stream."
  (writec out #\Newline))

(defun write-tab (out)
  "Write a tabulator to output stream."
  (writec out #\Tab))

#+sbcl
(progn
  (declaim (inline writestr))
  
  (defun writestr (out string)
    (write-string string out)))

#+lispworks
(defun writestr (out string)
  (declare (buffered-stream out) (simple-base-string string) #.*optimization*)
  (let ((start 0) (end (length string)))
    (declare (fixnum start end))
    (loop (with-stream-output-buffer (buffer index limit) out
            (declare (simple-base-string buffer) (fixnum index limit))
            (loop for i of-type fixnum from index below limit do
                  (setf (lw:sbchar buffer i) (lw:sbchar string start))
                  (when (= (setq start (the fixnum (1+ start))) end)
                    (setq index (the fixnum (1+ i)))
                    (return-from writestr string))
                  finally (setq index limit)))
          (stream-flush-buffer out))))

#+lispworks
(progn
  (defstruct process
    (stream nil :read-only t)
    (error nil :read-only t)
    (pid nil :read-only t))

  (declaim (inline process-input process-output))

  (defun process-input (process)
    (declare (process process) #.*optimization*)
    (process-stream process))

  (defun process-output (process)
    (declare (process process) #.*optimization*)
    (process-stream process))

  (defun run-program (command command-args &key
                              (input nil)
                              (output nil)
                              (error nil)
                              (wait t)
                              (if-input-does-not-exist nil)
                              (if-output-exists :error)
                              (if-error-exists :error)
                              (external-format :latin-1))
    (declare (ignore external-format))
    (multiple-value-bind
        (stream error-stream pid)
        (sys:run-shell-command (cons command command-args)
                               :input input :output output :error-output error :wait wait
                               :if-input-does-not-exist if-input-does-not-exist
                               :if-output-exists if-output-exists
                               :if-error-output-exists if-error-exists
                               :save-exit-status t)
      (if wait stream
        (make-process :stream stream
                      :error error-stream
                      :pid pid))))

  (defun process-close (program &key (wait t))
    (let ((stream (process-stream program)))
      (when stream (close stream)))
    (let ((error (process-error program)))
      (when error (close error)))
    (sys:pid-exit-status (process-pid program) :wait wait)))

#+sbcl
(progn
  (defglobal *working-directory-name* "" "Cached working directory name.")
  (defglobal *working-directory* nil "Cached working directory.")

  (defun get-working-directory ()
    "Similar to LispWorks's hcl:get-working-directory."
    (let ((cwd (sb-posix:getcwd)))
      (if (string= cwd *working-directory-name*)
        *working-directory*
        (setq *working-directory-name* cwd
              *working-directory*
              (parse-namestring (concatenate 'string (sb-posix:getcwd) "/")))))))

(declaim (inline command-line-arguments))

(defun command-line-arguments ()
  #+lispworks sys:*line-arguments-list*
  #+sbcl sb-ext:*posix-argv*)
