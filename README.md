# Palabras Escondidas

A Spanish word game for Android, built with Godot 4. Link neighbouring letters on a
4x4 board (diagonals included) and find as many words as you can in three minutes.

- 598,680-word Spanish dictionary, accents ignored, `ñ` is its own letter, `Qu` is a single tile
- Three switchable skins: paper and wood, colorful, dark
- Offline, no ads, no tracking. The only permission is vibration
- UI text is in Spanish

Package id: `com.palabrasescondidas.game`

## Requirements

- [Godot](https://godotengine.org) 4.7.2 (standard build) and its export templates
- JDK 17 and the Android SDK (platform 36, build-tools 36.1.0)
- Python 3 (only to regenerate the dictionary)

## Run the tests

They run headless and print a summary:

```
godot --headless --path . --import --quit
godot --headless --path . --quit-after 600 -s tools/test_board.gd
godot --headless --path . --quit-after 600 -s tools/test_sound.gd
godot --headless --path . --quit-after 900 -s tools/test_room.gd
godot --headless --path . --quit-after 3000 -s tools/test_net.gd
```

## Build for Android

Debug APK (preset `Android`, signed with Godot's debug keystore):

```
godot --headless --path . --export-debug "Android" build/palabras-escondidas-debug.apk
```

Release bundle for Google Play (preset `Android Release`):

1. Install the Gradle build template once: extract `android_source.zip` from the export
   templates folder into `android/build/`, write `4.7.2.stable` into `android/.build_version`
   and add an empty `android/build/.gdignore`. The `android/` folder is not tracked.
2. Create an upload keystore and keep it, and its password, outside the repository.
3. Export it. The signing key is read from environment variables, never from the preset:

```
GODOT_ANDROID_KEYSTORE_RELEASE_PATH=<path to .jks>
GODOT_ANDROID_KEYSTORE_RELEASE_USER=<key alias>
GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=<password>
godot --headless --path . --export-release "Android Release" build/palabras-escondidas-release.aab
```

## Dictionary

`data/words_es.txt` is generated from the Hunspell `es_ES` and `es_AR` dictionaries:

```
python tools/build_dictionary.py <folder with es_ES/es_AR .dic and .aff> data/words_es.txt
```

## Project layout

| Path | Contents |
|---|---|
| `scripts/` | game code: board generator and solver, dictionary lookup, UI, skins, audio |
| `skins/` | the three `GameSkin` resources |
| `data/` | the word list and its licence notice |
| `tools/` | dictionary builder, headless tests, store graphics renderer |
| `store/` | Google Play listing text, screenshots and graphics |
| `docs/` | static pages (privacy policy) |

## Licences

- The word list in `data/` is derived from the RLA-ES Spanish Hunspell dictionaries and is
  distributed under the Mozilla Public License 1.1. See `data/DICTIONARY_LICENSE.md`.
- The game is made with Godot Engine (MIT). Its licence and those of its components are
  shown inside the app under "Créditos y licencias".
- The game's own code, graphics and name are all rights reserved. See `LICENSE`.
