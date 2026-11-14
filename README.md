# KinemIQ Bridge for Godot 4

Send animations from [KinemIQ Studio](https://kinemiq.app/studio/?utm_source=github-godot) straight into your Godot project in one click.

KinemIQ Studio runs in the browser: pick real motion-capture clips (walks, runs, jumps, punches, idles), turn your own
video into an animation, or describe a motion in text, then edit it with sliders in a live 3D preview.

## Install
1. Copy `addons/kinemiq_bridge` into your project (next to `project.godot`) - or install it from the Godot Asset Library.
2. Project > Project Settings > Plugins > **KinemIQ Bridge** > Enable.

## Use
In KinemIQ Studio press **Export > Send to Godot**. The animation arrives as `res://kinemiq/<name>.glb`
(character + animation, imported by Godot like any glTF). Drag it into a scene - its AnimationPlayer plays it.
Sending the same animation again updates the same file.

## Privacy and network
- Listens on `127.0.0.1:8768` only (this computer, never the internet).
- Accepts data only from https://kinemiq.app (and a local studio).
- Sends nothing anywhere, no analytics. Turn it off by disabling the plugin.

Godot 4.x, GDScript, no dependencies.

## Licence
The add-on code is MIT (see `LICENSE`). Animations you export from KinemIQ Studio carry their own licence and credits
(shown in the Studio and in every export).
