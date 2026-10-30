# .vengi: unvalidated region -> int overflow and giant allocation

Reproducers: `int-overflow.vengi` (UBSan: `std::minus<int>` signed overflow computing the region
extent from file `mins`/`maxs`), `huge-alloc.vengi` (ASan: `SDL_malloc` of 0x1cc4cd3125190 bytes from
`RawVolume(Region)` at `VENGIFormat.cpp:325`).

Both come from the same cause as `../region-hang/`: the region read in `loadNodeData` is used
unchecked. The three `std::minus<int>` defects and the two excessive-size `SDL_malloc` defects Mayhem
reports for this target are this one root cause (`loadNodeData` region), seen at different values.
The size is read from the file; no ASan or libFuzzer limit is involved in the ASan "requested
allocation size" reports (the sizes exceed ASan's 1 TB cap).

Fix: reject a region whose width*height*depth overflows or exceeds a sane maximum before allocating.
