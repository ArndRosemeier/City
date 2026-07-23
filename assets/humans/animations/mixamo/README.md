Mixamo animations for the City walker (Adobe Mixamo Additional Terms).

Download from https://www.mixamo.com/ (free Adobe account):
  1. Pick any Mixamo character (Y Bot is fine).
  2. Search and download: Kick, Stomp (and any other actions you want).
  3. Export settings: FBX Binary, With Skin, In Place = ON, 30 fps.
  4. Rename files to Kick.fbx / Stomp.fbx (or keep Mixamo names).
  5. Place them in this folder: assets/humans/animations/mixamo/raw/

Then either:
  - Open the project once in the Godot editor (imports FBX + BoneMap), OR
  - Run: tools/bake_mixamo.ps1

Baked clips land in mixamo_actions.tres and appear in the action bar as Name_m.

Do not redistribute raw Mixamo FBX as a standalone pack.
