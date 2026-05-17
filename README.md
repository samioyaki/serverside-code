# Fish A Baddie

## Rojo

The root `default.project.json` is the primary Rojo project. Source files live under `roblox/src`.

To sync into Studio:

```sh
rojo serve default.project.json
```

Then open `st.rbxl` or a new place in Roblox Studio, open the Rojo plugin, and connect to `localhost:34872`.

To build a place file from source:

```sh
mkdir -p build
rojo build default.project.json --output build/FishABaddie.rbxlx
```

To bake the current Rojo source into the existing `st.rbxl` place file:

```sh
rojo build default.project.json --output /tmp/FishABaddie.rojo-source.rbxl
cargo run --locked --manifest-path tools/rojo-place-merge/Cargo.toml --target-dir /tmp/rojo-place-merge-target -- st.rbxl /tmp/FishABaddie.rojo-source.rbxl st.rbxl
```

`Workspace` and `ReplicatedStorage` are configured to keep unknown Studio instances during sync, so the existing binary map and imported asset instances in `st.rbxl` are not removed just because they are not represented as source files yet.

The older `roblox/default.project.json` still works from inside the `roblox/` directory.
