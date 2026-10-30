# .vox: stack-buffer-overflow in ogt_vox `_vox_file_read`

Reproducer: `crash.vox`. ASan reports `stack-buffer-overflow` at `ogt_vox.h:716`
(`memcpy(data, &fp->buffer[fp->offset], data_to_read)`) in the ASan-handled path, not in a backward
signal handler (the harness restores the signal handlers and sigaltstack the app object replaced).

Cause: `data_to_read` is bounded by the chunk size from the file, not by the destination size of the
fixed-size stack struct the caller passes. The three Mayhem defects at this frame are one root cause.
