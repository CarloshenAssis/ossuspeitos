# Clean import failure investigation

Source: `6484f54e62dc7a28ff995d5de1e070db269e0f20`. Godot: `4.4.1.stable.official.49a5bc7b6` via explicit `$GODOT_BIN` after sourcing mission `env.sh`. Plain `godot` on this host is 4.6.3 and was not used for the reported red/green results. Runtime source unchanged by this CI-only fix.

## Cause and red evidence

Fresh `git archive HEAD` projects outside the working checkout contained no `.godot` cache. Exact `--headless --editor --quit` locally exited before completing the scan (only `Scan thread aborted` warning), so it did not expose the whole import. A separate fresh archive with `--headless --import` waited for completion and exited 0 but emitted exactly eight `ERROR: Parameter "t" is null.` messages from `servers/rendering/dummy/storage/texture_storage.h:107`, one after each character GLB save. The strict workflow gate correctly rejects these messages. There were no script/parse errors.

Godot 4.4.1 source `editor/import/3d/resource_importer_scene.cpp` calls `_generate_editor_preview_for_scene` immediately after saving every PackedScene (line 3185); that function invokes `EditorInterface::make_scene_preview` (line 2828). Headless imports use the dummy renderer, which cannot supply the texture required for this editor preview. The assets contain plain materials with no embedded images; this is not missing project dependency or application static initialization. Upstream source inspected at https://raw.githubusercontent.com/godotengine/godot/4.4.1-stable/editor/import/3d/resource_importer_scene.cpp (local copy `/tmp/resource_importer_scene.cpp`).

## Fix

Only `.github/workflows/gameplay-specs.yml` changes: install Xvfb/Xauth/Mesa drivers, then use software X11 Compatibility rendering with Dummy audio under `xvfb-run -a` for `--import`. `--import` waits for every asset. Keep the existing pipefail and SCRIPT ERROR / Parse Error / ERROR gate unchanged. All subsequent gameplay tests remain headless. No project renderer, application code, test expectations, or existing workflows changed.

## Green evidence

A third fresh archive imported with:

```sh
DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 VK_DRIVER_FILES=/workspace/.ossuspeitos-tools/vulkan/root/usr/share/vulkan/icd.d/lvp_icd.json LD_LIBRARY_PATH=/workspace/.ossuspeitos-tools/vulkan/root/usr/lib/x86_64-linux-gnu "$GODOT_BIN" --path /workspace/.ossuspeitos-state/mission-sdd/clean-import/green441 --display-driver x11 --audio-driver Dummy --rendering-method gl_compatibility --rendering-driver opengl3 --import
```

Exit 0, zero gated errors, eight imported `.scn` files; a VSync capability warning is the only warning. The host already had an Xorg dummy display on :99 but no Vulkan ICD: Compatibility editor initializes an additional rendering device. Matching Debian Mesa Vulkan drivers were downloaded and extracted under `.ossuspeitos-tools/vulkan`, without system modification. This accounts for the local environment variables above; CI installs its drivers normally. Local verification uses the existing Xorg display rather than `xvfb-run`, which is unavailable here. GitHub Ubuntu/Xvfb execution remains for CI to confirm.

Against this fresh imported project, character_appearance (142 checks), movement_config, weapon_catalog (9 checks), gunplay (6216 checks), camera_effects, graphics_profiles and network_telemetry all exited 0 with their TEST_OK marker and no gated errors. `git diff --check` passed. The existing full runtime/network verification is retained; not repeated for a workflow-only change.

## Artifacts

All logs/projects under `/workspace/.ossuspeitos-state/mission-sdd/clean-import/`:

- `red441.log`: exact short-lived headless editor quit (incomplete scan).
- `full441.log`: full fresh headless import, eight errors, process exit 0.
- `green441.log`: full fresh graphical import, zero gated errors, process exit 0.
- `character_appearance.log`, `movement_config.log`, `weapon_catalog.log`, `gunplay.log`, `camera_effects.log`, `graphics_profiles.log`, `network_telemetry.log`: fresh project affected tests.
- `graphics441.log`, `graphics441b.log`: initial graphics environment diagnostics before supplying missing local Vulkan ICD; not passing results.
