# .gox: file-declared sizes drive allocation, merge cost and a negative size

Reproducers: `huge-alloc.gox` (`SDL_malloc` excessive size), `negative-size.gox` (ASan
`negative-size-param` in `BufferedReadWriteStream::read`, `BufferedReadWriteStream.cpp:126`),
`slow-4s.gox` (~4.5 s on a fast machine, spent in `voxelutil::mergeVolumes` iterating a file-declared
region at `VolumeMerger.h:39`).

Cause (from the crash frames; not triaged further): sizes and regions from the file reach allocation
and the merge loop without a bound; float-to-int truncation of a file float in `GoxFormat::loadShape` (`GoxFormat.cpp:255`,
`:257`) and `int` overflow in `VolumeMerger.h:39` share the same unvalidated-extent cause. The
excessive-size allocations are sizes read from the file, not an ASan limit.

Throughput: inputs that declare a large region cost seconds each (and `mergeVolumes` also fans out
over the app's thread pool), so the target runs at ~2 exec/s in a 5-minute run. That is the loader's
per-input cost, not harness overhead.
