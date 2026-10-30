# .kv6: header-declared voxel count makes inputs cost seconds

Reproducer: `slow-4s.kv6` (944 B, ~4 s). `KV6Format::loadRawVolume` appends one `KenSpriteVox` record
per declared voxel through `core::Buffer::push_back`, which reallocates (and under ASan memsets the
freed chunk in quarantine) as it grows; dimensions and counts come from the header.

Impact: a 1 KB file can cost seconds, so the target runs at ~0.6-1 exec/s while staying healthy
(1347 edges). The cost is in the loader, not the harness; fix: reserve/validate against the bytes
actually available before looping.
