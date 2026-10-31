# Frame geometry stability — 2026-10-24

The supplied 25-second Airport recording shows doorway/window trim changing as the camera moves. The user clarified that nearly all maps are affected. Earlier AA/ground-shader work is recorded separately in `ENVIRONMENT_SHIMMER_VALIDATION.md`; it is not proof that this complaint was resolved.

## Geometry defects corrected

- Airport: the inner faces of the metal jambs and headers occupied exactly the same planes as the plaster opening reveals. Trim now covers the reveals with a 3 cm lip. Jambs stop at the header instead of overlapping its front face.
- Shared modern buildings (used in Foundry, Ridgeline, Harbor, Blackout and Neon): doorway jambs now cover the reveals by 3 cm. Headers meet the shortened jambs. Trim also projects 2 cm beyond the indoor wall face, and sign lettering follows the new outdoor face. Window jambs end at their rails instead of overlapping their front faces.
- Harbor and Blackout: door surrounds cover the reveals by 3 cm; window jambs stop at the head/foot rails. Blackout window surrounds clear the wall reveal, and the transom has a different face depth from the mullions.
- Village: exterior trim and casement members meet at their joints without overlapping front faces. Casement sides clear the wall reveals, and the central transom has a separate face depth.

Overlapping, equally deep faces can alternate under camera movement (z-fighting). These changes remove specific reproducible geometry defects. They do not establish that every reported environment/shading artifact has the same cause.

## Regression evidence

`tests/suites/maps.gd` now contains 38 frame-specific checks:

- 12 actual-triangle Airport reveal checks: two orientations, floor-level/elevated openings, two jambs and one header. Before the fix: all 12 failed with exactly identical wall/trim depth (1.5000 m jamb, 1.2500 m header). After: all 12 pass at 1.4700 m / 1.2200 m.
- 12 actual-triangle door reveal checks across Harbor/Blackout and both orientations.
- 12 shared-building checks across all four facades, including indoor trim clearance (0.8300 m versus wall at 0.8500 m).
- Two checks for overlapping front faces in shared/Village window joints.

Focused result: **38 passed, 0 failed**. Raw report: `.artifacts/frame-geometry-check.json`.

Script compilation: **0 failures**. On this sandboxed host, headless Godot also prints an unrelated macOS system-certificate lookup error; it is separate from the script/test results. The dev wrapper stops on that error, so direct Godot invocations were used for the headless checks.

## Build and rendered verification

- Regenerated and rebaked Airport, Blackout, Harbor, Foundry, Ridgeline, Neon and Village. All seven lightmap rebuilds completed successfully. Known Godot editor teardown diagnostics were retained in the bake logs.
- Final content suite: **660 passed, 0 failed**, including all 38 frame checks. Raw result: `.artifacts/frame-content-check.json`. Missing-lightmap failures observed during preparation cleared after the final bakes; Glacier was being rebuilt concurrently in another chat.
- Native Metal rendered review: **27 captures across all nine multiplayer maps**, with 120 initial warmup frames per map and three translated camera positions. Captures: `.artifacts/probes/frame-review/`; contact sheet: `.artifacts/probes/frame-review/contact.png`. This is a visual sanity check, not a quantitative measurement of the original recording's flicker.
- Release app rebuilt at `builds/FPSMode.app`, script check **0 failures**, code signature verified. Export content fingerprint: `339f92b52959dff7752b29b34ba1be45fe3944dea4b769cc5a5e8bce2abe7e1a`; source matched that fingerprint immediately after export.
- Packaged gameplay smoke test: **passed, all 21 steps**, including aim toggles, firing while aimed, movement, replay, respawn and rematch. Raw result: `.artifacts/frame-package-smoke.json`; packaged content fingerprint matches the export above. Final code signature verification passed.

## Remaining limits

The geometry checks demonstrate that the corrected frame faces no longer share the wall-reveal plane or overlap at the tested joints. The visual review samples translated camera views; it does not prove that every environment artifact the user sees has been eliminated. Seven texture RIDs are reported at renderer shutdown, as in the earlier rendering checks. No runtime shader workaround or added per-frame work was introduced.
