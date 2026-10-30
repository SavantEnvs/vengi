# .vengi: a file-declared region drives an unbounded voxel loop (DoS)

Reproducer: `hang.vengi` (3.3 KB). `fuzz_vengi hang.vengi` runs for more than 100 s.

Cause: `VENGIFormat::loadNodeData` (`VENGIFormat.cpp:318`) reads `mins`/`maxs` from the file, allocates
`RawVolume(Region)` for them, then runs the x/y/z loop over the whole region, calling `readBool()` on
every voxel. The stream is exhausted after a few bytes, but the loop has no `eos()`/error check, so a
~1e9-voxel region costs minutes of CPU.

Impact: denial of service by a ~3 KB file. Mayhem's accumulated corpus replays this input in every run
and it stalls libFuzzer's initial corpus pass, which is why `fuzz-vengi` reports `tests_run=0`.

Fix (one line): stop the loops when `stream.eos()`/a read fails, and validate the region size against
a maximum before allocating.

Not in `testsuite/`: seeds are replayed every run; this is a finding, not a seed.
