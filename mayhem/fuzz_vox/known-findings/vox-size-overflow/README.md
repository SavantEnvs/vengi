# .vox: SIZE chunk dimensions overflow the 32-bit voxel count (OOB write + huge `RawVolume`)

Reproducers (run them with `/mayhem/fuzz_vox -runs=1 <file>`, the libFuzzer build; the `-standalone`
binary reaches the same overflow but its heap layout makes it die at the write instead, see below):

- `loadmodels-alloc.vox`: Mayhem #3544933, `Memory Allocation with Excessive Size Value`. ASan reports
  `allocation-size-too-big` (requested `0x600003c00000`) in `voxelformat::loadModels` at
  `MagicaVoxel.cpp:604` (`new voxel::RawVolume(region)`).
- `xyzi-oob-write.vox`: Mayhem #3543522, `Out-of-bounds Write`. ASan reports `SEGV` at
  `ogt_vox.h:1677` in `ogt_vox_read_scene_with_flags` (the `voxel_data[...] = color_index` store).

Cause: one `SIZE` chunk in these files declares `16777226 x 262144 x 6`. `ogt_vox.h:1646`
computes `uint32_t voxel_count = size_x * size_y * size_z`, which wraps to `0xf00000`, and allocates
only that much for `voxel_data`. The `XYZI` loop then checks each coordinate against the individual
dimensions (`x < size_x && y < size_y && z < size_z`, which passes) and stores at
`x + y * size_x + z * size_x * size_y`, far beyond the wrapped buffer: that is the out-of-bounds write.
When the stray store happens to land in mapped memory the loader goes on, and `loadModels` builds a
`voxel::Region` from the same unwrapped dimensions and asks for a ~105 TB volume. Which of the two
fires first depends on heap layout, so the same file can report either one (`loadmodels-alloc.vox` gives
the allocation error under `fuzz_vox` and a `heap-use-after-free` at `ogt_vox.h:1677` under
`fuzz_vox-standalone`). They are one root cause: dimensions are not bounded or checked for overflow.
