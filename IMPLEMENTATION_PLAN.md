# Denshattack! Photo Camera implementation plan

Denshattack! adds two constraints to a photography camera. Photo mode has to hold a moving train in its trick pose while the photographer flies the camera, and a grading master has to retain the bright scene detail that the game’s final display transform compresses.

The stable download is **v0.1.0**. The **v0.2.0-dev prerelease** adds exposure, film, timed shutters and the expanded Photo Studio. The README describes installation and controls for both. [Stable download](https://github.com/NewBarkTownKris/denshattack-photo-camera/releases/tag/v0.1.0) · [Development prerelease](https://github.com/NewBarkTownKris/denshattack-photo-camera/releases/tag/v0.2.0-dev) · [Camera guide](README.md)

## Target and capture path

| Component | Implementation |
| --- | --- |
| Game and loader | Steam app `2524850`, tested build `26541226`, Win64 Unreal Engine 5.6.1 and UE4SS v4.0.0. Windows and Linux/Proton installers reuse an existing loader or validate the pinned official archive. |
| Freeze and resume | F8 preserves the evaluated gameplay view, pauses the world and creates a detached camera. Camera input and shutter timing run on a real-time clock. Exiting restores the original view, HUD, pause state and effects. |
| Game-look photo | The instant PNG shutter crops the game view to the selected frame with finder UI hidden. The timed development shutter renders sampled poses and combines them into one image. |
| Grading master | F3 adds a matched HDR scene-color render before the final tone map and display grade. The game’s textures, lights, shading and emissives supply its colors. Game mode writes a half-float linear Rec.709/D65 EXR. Photographic modes apply the selected exposure once and write a 32-bit float master with exposure metadata. |

The Steam app manifest and shipping executable identify the tested build. Tests on Proton include DX12 with the shipped SM5 shaders at 3840 × 2160. [UE4SS release](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/v4.0.0) · [Unreal scene captures](https://dev.epicgames.com/documentation/en-us/unreal-engine/rendering-components-in-unreal-engine) · [Unreal working color space](https://dev.epicgames.com/documentation/unreal-engine/working-color-space-in-unreal-engine)

## Stable v0.1.0

- **Move and frame.** Six-axis free camera, fine/fast movement, mouse and arrow-key look, analog movement and aiming through Steam Input, and 16–600 mm prime presets.
- **Compose and focus.** Rotatable 3:2, 4:3, 1:1, 16:9, 5:4, 21:9 and 65:24 frames plus the viewport frame. Optical, square, circle and hidden reticles, independent thirds, center autofocus, coarse/fine manual focus, aperture and four DOF strengths.
- **Save and develop.** PNG or PNG + EXR, desktop folder picker, persistent destination, and batch development of missing ARRI LogC3 TIFF, Fujifilm F-Log TIFF and floating-point linear DNG companions.
- **Control motion effects.** Photo mode can suppress the train’s speed lines and radial blur. The original effects return when gameplay resumes.

Same-pose PNGs in **9-2-B To the Moon** verified changing the speed effects and shifting focus between the train and the background. Landscape, portrait and 65:24 shots confirmed the output dimensions. A 4K EXR retained scene values above 500, and a real floating-point DNG opened in darktable.

## Development branch

| Feature | Current behavior |
| --- | --- |
| Exposure and meter | Game is the initial mode. Manual, Aperture Priority and Shutter Priority use a cropped HDR meter. Settings span f/1–f/16, 8 s–1/32000 s, ISO 100–6400, Auto ISO limits, preferred minimum shutter and ±5 EV compensation. The finder shows effective settings and a ±3 EV gauge marked in thirds. |
| Creative controls | Eleven original film looks, including Neutral and monochrome. Grain strength and size follow the effective ISO. Game exposure can use a fixed Grain ISO while the game controls brightness. **C** and the Studio **Chromatic aberration** row switch between **Game** and **Off** independently of look, grain and exposure mode. |
| Slow shutters | At 1/15 s or slower in a photographic mode, the camera locks focus, focal length and exposure, records motion against real time and renders up to 64 camera poses. The train stays frozen. The finder shows time remaining and development status. Timed captures support PNG or PNG + EXR with a maximum 3840-pixel long edge. |
| Studio and persistence | F4 or left-stick click opens Studio. Arrow keys or the D-pad adjust exposure, image treatment, framing, lenses, focus and finder settings. The screenshot-folder row opens the system picker. Exposure, image treatment and composition preferences persist; the focus target belongs to the current session. |
| Focus feedback | T engages continuous center autofocus. T again locks the current distance. N or right-stick click focuses once. With photo DOF enabled, the finder reports center-target distance and near/far/aligned feedback. |
| Input | Shoulders control height. Controller face buttons fire the two shutters and View/Back resumes. Finder left-click fires the PNG shutter, middle-click focuses and the wheel adjusts focus. Modifier-wheel chords adjust aperture, shutter and manual ISO. An optional Steam Input binding of F8 on a spare button provides controller entry. |

Live Proton checks on a frozen composition yielded these results.

- At f/4 and 1/125 s, ISO 200 delivered **2×** the linear EXR signal of ISO 100, a **+1 EV** change. A separate Shutter Priority shot selected an aperture and met exposure within roughly 0.1 EV.
- The visible color fringe on a tested edge measured **36 px** with the game treatment, **0 px** with **Chromatic aberration** set to **Off**, then **38 px** after restoring **Game**.
- Timed captures at **1/15 s** and **1/2 s** produced PNG/EXR pairs with nonzero image data.
- The mouse wheel changed shutter speed from 1/125 to 1/160 s, ISO from 200 to 250, and aperture from f/4 to f/3.5 with the respective modifiers. Middle-click locked focus at 10.75 m and left-click saved a PNG.

Automated tests cover exposure stops, Auto ISO bounds, focus/DOF, cropped metering, timing, cancel/cleanup and settings restoration. [Exposure and Photo Studio](README.md#photo-studio-development-build)

## Differences from the VHOLUME reference

The comparison uses the VHOLUME Photo Camera v1.0.2 guide. Denshattack! implements its main exposure modes, focal lengths, aperture range, frames, reticles, ISO grain and slow-shutter concept. Denshattack! opens directly on the suspended train and supplies its own finder layout, control bindings, film presets and grading formats. The remaining reference features are listed here for prioritization. [VHOLUME camera guide](https://github.com/technicallyalex/vholume-photo-camera/blob/main/GUIDE.md)

| Reference feature | Remaining work or scope |
| --- | --- |
| Optical finder and Studio presentation | The reference has a segmented LCD, focus lamps, paired sidebars, rotating cards, pointer-driven Studio controls, device-aware shortcut highlights, sounds and animated shutter feedback. The development finder uses a compact readout, EV pointer, focus status and navigable settings panel. |
| Editable controls | An in-mod rebinding screen, extra wheel modifiers for lens/mode/frame/film, right-click finder toggle and the reference controller shoulder/chord layout remain open. Steam Input can customize per-game button outputs. |
| Photo folder operations | Both camera launchers support choosing a directory, and the desktop helpers support resetting to the default. In-game **Open Folder** and **Use Default** buttons remain open. |
| Subject placement | The reference places, poses, rotates and removes subjects. The Denshattack! camera photographs the train in its existing pose. Subject staging would be a separate tool if requested. |

## Verification before a development release

1. Repeat a timed run and a trick-park sequence under native Windows and Proton. Freeze in midair, move close to the train, change focus, save, resume and land the trick. Exercise restart and level travel, including cancellation during a timed capture.
2. Extend the measured scene tests to daylight, tunnel shade and neon. Check for jumps in priority modes and verify that the preferred minimum shutter yields when Auto ISO reaches its ceiling. Compare AF-C and focus feedback on the train and on a distant surface.
3. Verify the GUI, shortcuts and thumb travel with a physical controller on both platforms, including Studio changes, shutter buttons, input handoff and a custom Steam Input layout. Check narrow viewports and the widest frame before and after saving.
4. Grade a shared shot in Resolve using Rec.709 / Linear for the EXR and ARRI Wide Gamut 3 / LogC3 EI 800 for the ARRI TIFF. Match neutral levels and highlight detail after restoring the TIFF's recorded exposure offset. Check the F-Gamut / original F-Log TIFF and compare a DNG import in Lightroom and darktable. [ARRI LogC3](https://www.arri.com/resource/blob/31918/66f56e6abb6e5b6553929edf9aa7483e/2017-03-alexa-logc-curve-in-vfx-data.pdf) · [Fujifilm F-Log](https://dl.fujifilm-x.com/technical-data/F-Log_DataSheet_E_Ver.1.2.pdf) · [Adobe DNG](https://helpx.adobe.com/camera-raw/desktop/dng-and-file-formats/digital-negative.html)
5. Build the Windows and Linux/Proton ZIPs, verify checksums, and exercise fresh install, upgrade and rollback in CI. Repeat destination selection, capture to a removable drive and recovery after a failed write. Future EXR compression can reduce storage while preserving scene values.
