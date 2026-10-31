# Environment stability validation — 2026-10-23

## Final changes

- Shared world viewport: TAA plus 4× MSAA at every preset. Spatial post AA stays disabled.
- 16× anisotropic texture filtering.
- Native Metal is the macOS default, matching the rendered verification backend. Vulkan diagnostics repeatedly stalled before producing comparison frames; this does not establish Vulkan as the original cause.
- Disable occlusion culling in the world viewport. Comparing the same views with it on/off exposed visible-pixel changes in Airport and Blackout interiors. Frustum culling remains active.
- Ground and terrain UVs no longer move with the camera. Height remains available for layer blending, and the legacy parallax uniform remains readable by saved map materials.
- Evaluate terrain overlay texture samples before varying-weight branches so implicit mip derivatives are defined at layer boundaries.

The first attempt changed antialiasing alone and was initially not exported. Rebuilding that attempt did not resolve the user's report. These changes therefore address additional shared render paths rather than treating the earlier image metric as proof of resolution.

## Evidence

### Ground coordinate regression

`tools/ground_stability_probe.gd` tracks 35 fixed ground points from nine translated camera positions. It instruments the actual ground shader coordinate path, uses a controlled constant height texture, and accounts for viewport scaling when sampling pixels. This isolates camera-driven UV drift from ordinary perspective motion and lighting changes.

| Variant | Mean coordinate-color drift | Maximum |
| --- | ---: | ---: |
| current | 0.001493 | 0.003688 |
| baseline | 0.062870 | 0.090536 |

The current shader passes mean < 0.005 and maximum < 0.01. These diagnostic values are not a percentage reduction in the user's perceived shimmer. Raw data: `.artifacts/probes/ground-stability/report.json`.

### All-map camera turns

20 views across all ten registered maps improved in both reprojected frame-difference metrics. This compares spatial AA against the combined TAA/MSAA configuration on the revised shader: mean luminance variation is 62.4% lower, and pixels changing by more than 18/255 are 79.3% lower. It does not measure the ground-shader change against the original shader. Root viewport: 960×540, Medium environment preset, 12 camera steps of 0.12 degrees after history warmup. Animated materials remain active. Raw results: `.artifacts/probes/environment-shimmer/report.json`.

### Occlusion comparison

`.artifacts/probes/occlusion-shimmer/report.json` compares identical cameras with occlusion culling disabled/enabled while walking five positions through three views per map. Blackout's interior has 2.22% of pixels differing by more than 20/255; Airport's interior has 0.0765%. Other samples show smaller differences. Animated materials can also contribute to this comparison.

## Checks

- Content: 595 passed, 0 failed.
- Graphics: 42 passed, 0 failed, including all preset resolutions, combined AA, conservative visibility, smoke occlusion and weapon-rig reuse.
- Ground coordinate regression: passed.
- Export script check: 0 failures.
- Code signature verified.

## Performance

A 30-second airport gameplay sample after 30 seconds of warmup, 16 actors, 1920×1080, native Metal, foreground throughout: average 59.53 FPS; p95 18.828 ms; p99 21.580 ms; one frame > 50 ms. The benchmark reports **failed** because its strict average target is at least 60 FPS, although both percentile thresholds pass. This is a short sample, not a sustained thermal-performance guarantee. Raw data: `.artifacts/benchmark-airport.json`.

## Package

Exported content fingerprint: `0186e9d0df9432f53336fab59d0e48ffa0e95b9203d2a94c5e7b85c8e1dd8ddf`. The final packaged smoke test and package rendering inspection are recorded in `.artifacts/export-smoke.json` and `.artifacts/logs/packaged-stability-render.log`.

## Limits

Quantitative checks establish stable ground coordinates and better sampled edges; they do not establish that the user's full visual complaint is resolved. TAA can soften moving details. Native Metal changes the macOS rendering backend. Existing render runs can report seven texture RIDs during shutdown without test failures.

Final package verification: gameplay smoke passed all 21 steps; shipped-package rendering inspection passed 11/11 checks, including native Metal, 16× anisotropy, conservative visibility, TAA and 4× MSAA across all three presets. Source, export and smoke content fingerprints match. The rebuilt app was reopened after verification.
