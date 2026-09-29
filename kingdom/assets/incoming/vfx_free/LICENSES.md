# Licence verification for vfx_free (checked 2026-09-29)

Policy: only CC0 / MIT / BSD / Apache / zlib / CC-BY are imported. Quotes below are copied from the real licence files or licence field, not from summaries.

## Imported

### Kenney Particle Pack 1.1 (subset of 31 of 96 textures, 512 px)
- Source: https://github.com/Calinou/kenney-particle-pack commit ab70866 (mirror of https://kenney.nl/assets/particle-pack)
- File: `kenney_particle_pack/LICENSE.txt`. Quote: "License (Creative Commons Zero, CC0) ... You may use these assets in personal and commercial projects. Credit (Kenney or www.kenney.nl) would be nice but is not mandatory."
- Credit given anyway: Kenney (www.kenney.nl).

### RPicster Godot-particle-and-vfx-textures (7 of the 256 px alpha textures)
- Source: https://github.com/RPicster/Godot-particle-and-vfx-textures (cloned 2026-09-29)
- File: `rpicster_vfx_textures/LICENSE` is the CC0 1.0 Universal legal code. README quote: "The whole project is licensed as CC0, so use the information and textures how ever you please. No attribution is required!"
- Credit given anyway: Raffaele Picca, raffaelepicca.com.

### SimplestGodRay3D (script + shader)
- Source: https://github.com/AguaMineral/SimplestGodRay3D commit 5eaa554 (Godot Asset Library #4146)
- File: `simplest_godray/LICENSE`. Quote: "MIT License  Copyright (c) 2025 Re_Lo  Permission is hereby granted, free of charge, to any person obtaining a copy of this software ..." Copyright and permission notice kept in that folder. Shader is `shaders/free/god_ray_mesh.gdshader` (unmodified, header comment added); the script has one path change (shader path).

### Original code (no third-party licence)
`shaders/free/kuwahara_post.gdshader`, `fluffy_leaves.gdshader`, `stylized_grass.gdshader`, `stylized_water.gdshader`, `storybook_sky.gdshader` were written from scratch for this project (well-known techniques only). They stand in for the godotshaders.com candidates below.

## Checked, licence confirmed, NOT downloaded

### Binbun3D Flame FX (free version)
- URL: https://binbun3d.itch.io/flame-fx (read 2026-09-29). Licence field: "Creative Commons Zero v1.0 Universal", "personal, educational, and commercial projects with no attribution required". Free version 964 kB, name-your-own-price.
- Not downloaded: itch.io downloads go through an interactive page/session that cannot be fetched with curl. Licence is fine; a human can download the zip and drop it in `flame_fx/`. The campfire in the gallery uses Kenney flame textures instead.

## Skipped (licence NOT verified)

All godotshaders.com items: Stylized Fluffy Tree Leaves, Stylized Multimesh Grass, Stylized Sky With Clouds, Water Shader 3D (Godot 4.3), Kuwahara (innerdev / Firerabbit).
- Reason: the godotshaders.com firewall answered automated requests with "455 Security Incident Detected ... Your request was blocked. Do not retry." I did not work around the block, so the licence field and code could not be read from the source page. Research-file licence lines (CC0/MIT) stay unverified. To use them: open each page in a normal browser, copy the licence line here, paste the code into `shaders/free/`.
