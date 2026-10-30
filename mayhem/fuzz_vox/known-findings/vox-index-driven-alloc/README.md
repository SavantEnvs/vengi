# .vox: file-supplied indices and counts size an allocation

Mayhem lists seven `Memory Allocation with Excessive Size Value` defects for `fuzz-vox` (run 7). They
share a symptom but not one detector or one cause. This directory covers the first six; the seventh,
#3544933 (`loadModels`, `MagicaVoxel.cpp:604`), is a different bug and is in `../vox-size-overflow/`.

| Detector | Defects | What it is |
| --- | --- | --- |
| ASan `allocation-size-too-big` (>1 TB request) | #3525196, #3525222 | `_vox_array<_vox_scene_node_>` / `_vox_array<ogt_vox_layer>` `reserve` at `ogt_vox.h:853`, reached through `grow_to_fit_index` (`ogt_vox.h:1768` node, `ogt_vox.h:1842` layer) |
| libFuzzer malloc limit (single `malloc` > 2 GB) | #3525177, #3525265 | the same `_vox_array::reserve` call sites with a smaller index; libFuzzer prints `out-of-memory (malloc(<n>))` |
| libFuzzer rss limit (`used: N Mb; limit: 2048 Mb`) | #3525191, #3525253 | no single allocation is rejected; the loader's allocations add up past 2048 MB |

- Reproducers for the ASan family: `node-index.vox` (#3525196 shape) and `layer-index.vox` (#3525222 shape)
  (`_vox_array::reserve`, `ogt_vox.h:853`).
- `malloc-limit-layer-array.vox` is the input Mayhem saved for #3525177: libFuzzer reports
  `malloc(12933333264)` from `_vox_array<ogt_vox_layer>::reserve`. Not reproduced for #3525265 (a
  264 GB request): Mayhem's stored output elides the frames, and its parsed backtrace has none from the
  application because libFuzzer prints it from its own `HandleMalloc`.
- `rss-limit-keyframe-alloc.vox` is the input Mayhem saved for #3525253: libFuzzer's live-heap report
  names one 1.7 GB `SDL_malloc` from `_vox_suballoc_array::alloc_many<ogt_vox_keyframe_transform>`
  (`ogt_vox.h:1729`, inside `ogt_vox_read_scene_with_flags`). Mayhem's parsed backtrace for this defect
  and for #3525191 shows only `operator new` in `fuzzer::FuzzerDriver`, so the triage shows no
  application frame; the real allocation site is in the loader and is file-driven. #3525191's live heap
  is 6 allocations totalling 1.1 GB from `VoxFormat::loadGroupsPalette` (the same loader call).

Cause: node/layer indices and keyframe counts read from the file size an allocation with no upper
bound (e.g. `grow_to_fit_index` resizes to `index + 1` elements). The requested sizes come from the
file; ASan's 1 TB cap and libFuzzer's 2 GB/2048 MB limits are only what reports them.
