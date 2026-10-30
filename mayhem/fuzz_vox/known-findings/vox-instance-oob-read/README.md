# .vox: out-of-bounds reads on file-supplied indices

Reproducer: `crash.vox`: `generate_instances_for_node` heap-buffer-overflow (`ogt_vox.h:1289`). The same
family: `MemoryReadStream::read` reading past the buffer and the `_vox_array<ogt_vox_layer>::operator[]`
layer index (`ogt_vox.h:933`).

Cause: node/layer/model indices (and, for the glm truncation, transform values) from the file are used without range checks.
The 21 defects Mayhem lists for `fuzz-vox` (run 7) reduce to five root-cause families:

- this one: OOB reads, 5 at `generate_instances_for_node`, 2 in `MemoryReadStream::read` and 1 at the
  layer `operator[]` (8);
- file-supplied indices and counts sizing an allocation, 6 of the 7 excessive-size defects
  (`../vox-index-driven-alloc/`: which are ASan, libFuzzer malloc-limit and libFuzzer rss-limit hits);
- `SIZE` chunk dimensions overflowing the 32-bit voxel count (2): the `loadModels` allocation #3544933 and
  the OOB write at `ogt_vox.h:1677` #3543522 (`../vox-size-overflow/`);
- `_vox_file_read` stack overflow (3, `../vox-file-read-stack-overflow/`);
- glm float-to-int truncation of a file transform (2).

#3503410 was recorded on 2026-10-31 under an earlier harness whose signal-handler restore was not yet in
place; it no longer reproduces (see `../vox-file-read-stack-overflow/`) and is not part of the 21.
