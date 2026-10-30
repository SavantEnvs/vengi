# .vengi: stack-buffer-overflow in mz_inflate via ZipReadStream

Reproducer: `stack-overflow.vengi`. ASan: `memcpy` in `mz_inflate` (`miniz.c:457`) writes past a stack
buffer, called from `io::ZipReadStream::read` (`ZipReadStream.cpp:380`) <- `ReadStream::readUInt32`
(`Stream.cpp:659`) <- `VENGIFormat::loadNodePaletteNormals`.

Cause: not triaged beyond the frames above (the output size miniz is given exceeds the caller's
stack buffer for a crafted deflate stream). This is separate from the region bug; it is the one remaining defect of
this target.
