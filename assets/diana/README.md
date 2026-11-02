# Diana character assets

The app loads six self-contained USDZ clips from
`Sources/DianaApp/Resources/Models/`. Each contains the model, textures, skeleton,
and one animation. No Blender installation is needed to build or run the app.

| Clip | Duration | Playback |
| --- | --- | --- |
| `Diana-idle.usdz` | 3.2 seconds | Loop |
| `Diana-run.usdz` | 0.8 seconds | Loop |
| `Diana-wave.usdz` | 3 seconds | Once |
| `Diana-kiss.usdz` | 2.2 seconds | Once |
| `Diana-portrait.usdz` | 5 seconds | Once |
| `Diana-hip.usdz` | 5 seconds | Once |

The model has 47,347 triangles, eight meshes, eight materials, and 55 bones.
Textures are capped at 2K, with normal maps capped at 1K. Motion is authored in
place; the app moves the desktop window for travel. The rig does not include
facial morphs or hair and cloth simulation.

The original `Diana.blend`, editable optimized model, texture working files, and
preparation outputs remain local and are excluded from Git. `animations.json`
records clip timing and looping behavior.
