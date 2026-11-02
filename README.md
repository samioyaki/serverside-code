# Fish A Baddie

Fish A Baddie is a server-authoritative Roblox collection/tycoon game. Players cast a rod, release inside the timing zone, collect rarity- and trait-rolled baddies, place them on a personal plot for passive income, and progress through rods, upgrades, crates, fusion, and rebirths.

## Play loop

1. Spawn on the fishing dock facing the open water.
2. Equip the generated rod and hold/release, or press `F`/use the on-screen `CAST` and `REEL` button.
3. Release while the timing marker is inside the green zone.
4. Open **Baddies**, choose **Go To Plot**, hold a catch, and tap/click an unlocked cell to place it.
5. Click a placed baddie to upgrade it, fuse three duplicates, modify traits, convert Secrets, or go on a date. Chemistry adds up to a 50% income bonus, and fusion shards buy trait credits at the Trait Lab.
6. Claim generated coins, travel back to the dock, and spend them at the island shops on rods and upgrades.

The supplied baddie models are stored as sanitized `.rbxm` files under `roblox/assets/Baddies` and baked into `st.rbxl`. To replace a baddie, use a model filename matching its `TemplateId` (for example `Foam.rbxm`, `Lagoon.rbxm`, or `Siren.rbxm`). Catch reveals, held tools, and plot displays automatically use the real model. All 25 configured baddies currently have matching real models.

Rods use the free [Fishing Rod Creator Store model](https://create.roblox.com/store/asset/11316383656/Fishing-Rod) by `@mamaJukerson`. To display that third-party model, enable **Game Settings → Security → Allow Loading Third Party Assets** before publishing. The model is loaded through Roblox's public-asset API, stripped of every script, normalized for Tool use, and recolored for each rod tier. If the setting is disabled or Roblox cannot load the model, the polished local procedural rod is used automatically, so fishing remains fully playable.

Core UI and fishing sounds use Roblox-bundled audio so the published place has immediate feedback. The supplied high-quality source sounds remain under `Audios/`; upload them to the experience and paste their IDs into `AudioConfig.lua` to replace the bundled fallbacks.

Premium buttons remain visibly unavailable until non-zero game pass and developer-product IDs are entered in `ProductConfig.lua`. This prevents accidental broken purchase prompts while keeping the full coin, collection, plot, dating, fusion, upgrade, crate-ticket, and rebirth loops playable.

The placeholder catalog, colors, rarity assignments, and replacement IDs are defined in `roblox/src/ReplicatedStorage/Shared/Config/BaddieConfig.lua`.

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
cargo run --locked --manifest-path tools/rojo-place-merge/Cargo.toml --target-dir /tmp/rojo-place-merge-target -- st.rbxl /tmp/FishABaddie.rojo-source.rbxl st.rbxl roblox/assets/Baddies
```

The merge tool removes all `Script`, `LocalScript`, and `ModuleScript` instances from imported baddie models before inserting them into the place.

`Workspace` and `ReplicatedStorage` are configured to keep unknown Studio instances during sync, so the existing binary map and imported asset instances in `st.rbxl` are not removed just because they are not represented as source files yet.

The older `roblox/default.project.json` still works from inside the `roblox/` directory.
