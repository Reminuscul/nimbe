# Nimbe

**An original shader pack for [Horizon](https://github.com/ludovic111/horizon)**, the Rust rewrite of Minecraft: Java Edition.
Nimbe is written in Horizon's native WGSL shader format (`horizon-shaders.toml`, shader API 0.1).

![Sunset over the lake](docs/screenshots/sunset.png)

## Features

- **Painted sky**: the gradient changes through the day, with a pink band at sunrise and sunset and a halo around the sun.
- **Clouds**: sunlit cumulus with self-shadowing, glowing edges against the light and darker bases. There are also high cirrus and a full overcast during storms.
- **Night**: twinkling stars that turn with the sky, a faint nebula, and auroras in cold biomes.
- **Shadows**: crisp, stable shadows from the sun and moon. They take the tint of the water and stained glass they pass through, and clouds cast shadows on the ground.
- **Water**:
  - turquoise (emerald in the shallows, deep teal further out) or biome colors;
  - a living swell with irregular three-scale ripples that never repeat, rougher where wind gusts drift across;
  - micro-facet sun glitter;
  - reflections of the world that ripple with the surface.
- **Under the water**:
  - light loses its red, then its green, as it goes deeper;
  - it draws a moving web of caustics on the bed, sharp in one place and soft in another.
- **Lighting**: warm torches, colored soul fire, redstone, amethyst and sea lanterns, and fireflies that cast light.
- **Materials**:
  - relief derived from textures, plus LabPBR resource pack support;
  - shiny metals and polished blocks, light shining through foliage;
  - wet ground and puddles in the rain.
- **Wind**: grass, flowers, leaves and vines sway smoothly. Underwater, a current rocks the seagrass and ripples the kelp along its whole height.
- **Atmosphere**: light shafts, haze that matches the sky color, and ambient occlusion.
- **Image**: bloom, adaptive exposure, color grading, vignette and anti-aliasing.

Every effect can be tuned from the pack's menu.

| | |
|---|---|
| ![Day](docs/screenshots/day.png) | ![Shallow water](docs/screenshots/shallows.png) |
| ![Reflections](docs/screenshots/reflections.png) | ![Night sky](docs/screenshots/night.png) |

## Install

1. Download `nimbe.hshader` from the [latest release](../../releases/latest).
2. Put it in the game's `shaderpacks` folder, next to `options.txt`. The **Open Pack Folder** button opens that folder.
3. In game, open **Options > Video Settings > Shaders > Shader Packs...** and click **Nimbe**. Click it again to turn it off.

If the game rejects the pack, it shows the reason in chat.

## Performance

These are the most expensive settings, in order:

1. **Shadows** and their resolution
2. **Water reflections**
3. **Light shafts**
4. **Cloud quality**

On a small GPU, start by lowering the shadow resolution to 1024 and the light shaft quality to Low.

## Multiplayer note

A server re-sends the time of day every second. If the server runs below 20 ticks per second, the game steps the sun back slightly each time, and block shadows follow it. The engine places the shadow map, so a pack cannot hold it still. Cloud shadows are projected straight down and do not move.

## Build from source

The pack is the repository itself. To build the `.hshader` file (a zip archive):

```sh
./scripts/package.sh        # writes dist/nimbe.hshader
```

Pushing a tag such as `v1.0.0` builds the file and attaches it to a GitHub release automatically.

## License

MIT, see [LICENSE](LICENSE). All the code in this pack is original and is not taken from any other shader pack.
