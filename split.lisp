(in-package :elprep)

(defun splitter-process (mbox output) 
  (process-run "splitter" (lambda ()
                            (do ((msg (mailbox-read mbox) (mailbox-read mbox)))
                                ((eql msg :done))
                              (with-open-file (out (format nil "~s-~s" output (sam-alignment-rname msg)) :direction :output :if-exists :append)
                                (format-sam-alignment out aln))))))

(defun parse-sam-alignment-from-stream (stream)
  (when (buffered-listen stream)
    (parse-sam-alignment (buffered-read-line stream))))

(defmethod split-file-per-chromosome ((input pathname))
  (let ((nr-of-threads *nr-of-threads*))
    (with-open-file (raw-in input :direction :input)
      (let* ((in (make-buffered-stream raw-in))
             (header (parse-sam-header in)))
        ; each thread will be responsible for processing a chromosome (or a bunch of chromosomes)
        (let ((workers (make-array number-of-threads)))
          (dotimes (i nr-of-threads)
            (let ((mbox (make-mailbox)))
              (setf (aref workers i) mbox)
              (make-splitter-worker mbox input)))
          (do ((aln (parse-sam-alignment-from-stream in) (parse-sam-alignment-from-stream in)))
              ((not aln) (dotimes (i nr-of-threads) (mp:mailbox-send (aref workers i) :done)))
            (let ((mbox (aref workers (mod (sam-alignment-refid aln) nr-of-threads))))
              (mailbox-send mbox aln))))))))