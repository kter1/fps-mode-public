# Effects art

Original, generated art (CC0, no external assets). Regenerate the PNGs with
`godot --headless --script res://tools/generate_effect_textures.gd`.

- `smoke_flipbook.png` / `fire_flipbook.png`: 4x4 flipbooks of 128 px cells for the soft billboarded
  smoke, dust and fire sprites (`fx_smoke.gdshader`, `fx_fire.gdshader`). Smoke stores a sprite-space
  normal in RG, detail in B and density in A; fire stores heat in R, soot in G and density in A.
- `fx_flash.gdshader`: additive blast flash.
- `scorch.png`: blast scorch decal.
- `fx_drum.gdshader` + `label_flammable.png` / `hazard_diamond.png`: the weathered hazard-red steel
  drum (recolours the scanned Poly Haven drum paint, adds rust, scratches and signage).
