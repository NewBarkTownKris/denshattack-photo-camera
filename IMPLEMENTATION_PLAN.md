# Denshattack! photo camera implementation plan

The first playable build should let a player freeze a trick at its peak, fly around the suspended train, save the shot, and finish the trick. The full camera adds VHOLUME’s photographic controls and a scene-linear capture workflow for DaVinci Resolve, Lightroom, and darktable.

## Installed target

| Evidence | What it establishes |
| --- | --- |
| Steam app manifest | App ID `2524850`, installed build `26541226`. |
| `Denshattack_Proto-Win64-Shipping.exe` | Win64 shipping game. Its fixed file and product versions both read `5.6.1.0`, and the binary contains `Unreal Engine 5.6.1`. |
| Cooked content manifest | `BP_FreeCameraPawn`, `PlayerController_Densha`, `ReplayCameras`, and exploration widget `WBP_CameraScreenshot` are investigation leads. Their availability during an ordinary run needs a live test. |
| Local Proton prefix | Saved game settings specify 3840 × 2160 with HDR display output disabled. Start with this SDR configuration and the normal Steam launch option. |

The tested build was identified from Steam's `appmanifest_2524850.acf`, the version of `Denshattack_Proto-Win64-Shipping.exe`, and the game's packaged and saved configuration.

## 1. Prove the frozen shot under Proton

**Implemented and tested.** The installed camera freezes the train, provides six-axis framing and saves a cropped PNG. It includes the optional thirds grid, an in-game controls card, center autofocus, coarse/fine manual focus and equivalent aperture controls. Same-pose PNGs on **9-2-B To the Moon** verified the speed-line switch and the change in focus distance. [Controls and live test details](README.md)

Use a small UE4SS Lua mod as the first integration candidate. A Denshattack! mod author documents an earlier working UE4SS configuration for this title. Test a pinned loader on the installed build and record the exact working version and Proton launch settings. Target the normal boot option first, then check the low-spec option separately. [Denshattack! mod precedent](https://www.nexusmods.com/denshattack/mods/4) · [UE4SS documentation](https://docs.ue4ss.com/) · [Official game updates](https://steamcommunity.com/app/2524850/allnews/)

1. On a rebindable toggle, capture the final rendered gameplay camera pose, roll and FOV, current view target, pause state, active input mappings and HUD visibility. Create a detached camera at that pose and keep the train possessed and visible. Try the shipped free-camera pawn if it can supply the view without taking over train control. Otherwise use a dedicated camera actor.
2. Request world pause and verify it took effect. Run only camera movement, finder input and shutter timing from a real-time clock that keeps advancing during pause. Give the camera translation in three axes, yaw, pitch, roll, a level-horizon reset, and fine/fast movement. Tune close focus and slow speed beside the train. The developers describe building the world in miniature. [Unreal time sources](https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/Engine/FGameTime) · [Developer interview](https://80.lv/articles/interview-how-denshattack-blends-tony-hawk-jet-set-radio-with-trains)
3. Save a PNG from the active game view. Suppress score, combo, menu and finder layers for the captured frame. Keep train outlines and authored effects in the default shot. Check the actual file for leftover world-space text or overlays. VHOLUME’s shutter explicitly exits during pause, so the new shutter must recognize our photo session and complete the capture while it owns the freeze. [Reference shutter](https://github.com/technicallyalex/vholume-photo-camera/blob/d40bc252720da4b2fca87bf6a3d5b1c15b3d2f61/ue4ss/Mods/VHOLUMEPhotoCamera/Scripts/main.lua#L745-L799) · [Unreal screenshot API](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Runtime/Engine/FScreenshotRequest/RequestScreenshot)
4. On exit, restore the recorded view, controls and layer visibility, then release only the pause acquired by the mod. Drain held photo buttons so the shutter cannot trigger a trick on resume. Handle a second toggle, capture failure, an open pause menu, restart and level travel. Drop stale camera references when the world changes.

**Pass condition.** Freeze a midair trick for ten real seconds. Fly from behind the train to a low side angle. Confirm the rendered view changes while the train pose, combo and detailed level timer hold. Check sparks and animated materials for real-time drift. Open the saved PNG, resume, and land the trick. Repeat in a timed run and a trick park. If the view stops updating under pause, fix the camera’s paused update and input path before building the UI. If pause fails, unwind the toggle so gameplay stays usable.

## 2. Build the photographic controls

The optical, square and circle finders and independently switchable thirds grid now run in the game. F2 opens the native Linux folder picker through the Steam launcher. A 1440 × 2160 portrait test verified the chosen destination for both the PNG and EXR.

Mouse look, left-stick movement and right-stick aiming work alongside the keyboard. In-game tests used relative mouse motion and the Steam Input virtual Xbox controller on Proton. Physical controller ergonomics and camera button bindings remain to be tested.

| Feature | Planned behavior |
| --- | --- |
| Optics | 36 × 24 mm filmback with 16, 24, 35, 50, 85, 135, 200 and 600 mm primes. Support center autofocus, one-shot focus lock and coarse/fine manual focus. Test autofocus on the train itself and on the background. |
| Exposure | Game, Manual, Aperture Priority and Shutter Priority. Match f/1–f/16, 8 s–1/32000 s, ISO 100–6400, Auto ISO limits, preferred minimum shutter and EV error meter. Give Game mode the game’s exposure. Calibrate the other modes in daylight, tunnels and neon with the train included in the meter. |
| Image character | Eleven looks spanning neutral, warm, slide, instant, tungsten and monochrome. Drive grain from actual ISO. Offer DOF on/off and 1×, 2×, 4× and 8× blur strength independently of metered exposure. |
| Framing | 3:2, 4:3, 1:1, 16:9, 5:4, 21:9 and 65:24, each rotatable into portrait. Use one frame definition for the finder and saved crop. Offer optical, square, circle and hidden reticles plus a thirds grid. Test portrait, panoramic and ultrawide finder edges against saved pixels. |
| Operation | Optical finder and Photo Studio with settings persisted between sessions. Mouse wheel for focus, modifier-wheel adjustments, stick movement and aiming, shoulder/D-pad adjustments, and separate finder and shutter actions. Scope camera bindings to photo mode and test a physical controller through Steam Input. |
| Files and long exposures | Default to the game’s per-user `Saved/Screenshots/Windows` with choose/open/reset folder controls, unique filenames and a visible write result. For metered or manual shutters of 1/15 s and slower outside Game mode, lock focus/exposure and accumulate samples as the camera moves in real time. The train stays frozen. Target the reference’s 3840-pixel maximum long edge for motion shots. Cancel cleanly if the finder closes. |

Use the reference as a behavior specification. The inspected tree had no top-level license granting source or artwork reuse. An independent implementation can proceed now. Direct reuse is an option if the rights holder authorizes it. The first release frames the existing train in its trick pose. VHOLUME’s separate subject-placement tool would be a later feature if requested. [Reference camera guide](https://github.com/technicallyalex/vholume-photo-camera/blob/main/GUIDE.md) · [Lenses](https://github.com/technicallyalex/vholume-photo-camera/blob/main/ue4ss/Mods/VHOLUMEPhotoCamera/Scripts/main.lua) · [Looks and frame presets](https://github.com/technicallyalex/vholume-photo-camera/blob/main/ue4ss/Mods/VHOLUMEPhotoCamera/Scripts/film.lua)

## 3. Capture a grading master and deliver the editor formats

**Implemented.** F3 captures a game-look PNG plus a half-float, scene-linear Rec.709/D65 EXR. The offline developer produces floating-point LinearRaw DNG and full-range ARRI LogC3 and Fujifilm F-Log TIFFs. Verified landscape and portrait framing in the shipping game, scene values up to 505 in the 4K master, and zero clipped channel samples in its highlight-protected log exports. The EXR currently uses uncompressed scanlines. Direct Resolve and Lightroom import tests remain open. [Develop a grading shot](README.md#develop-a-grading-shot)

Test the render stage as soon as the frozen shot works. Start with the active view’s floating-point scene color before display tone mapping. If the loader cannot expose it, evaluate a matched HDR `SceneCapture2D` render target and a small native capture component if needed. Match projection, focus and framing. Compare train outlines, translucent sparks, emissive signs, DOF and temporal ghosting against a PNG from the same frozen pose. Establish which effects are already baked into the chosen stage. Verify the game’s working primaries and account for any Unreal pre-exposure exactly once. [Unreal working color space](https://dev.epicgames.com/documentation/unreal-engine/working-color-space-in-unreal-engine) · [Unreal exposure](https://dev.epicgames.com/documentation/unreal-engine/auto-exposure-in-unreal-engine)

| Deliverable | Encoding and acceptance test |
| --- | --- |
| **OpenEXR master** | Offer a selectable half-float scene-linear RGB file with documented primaries and white point, exposure metadata, and lossless compression. Preserve values above 1.0. Darken the same emissive detail in Resolve and darktable and verify that distinct highlights survive. [OpenEXR technical introduction](https://openexr.com/en/latest/TechnicalIntroduction.html) |
| **Resolve LogC3 TIFF** | From the same linear samples, convert primaries to ARRI Wide Gamut 3 and encode LogC3 EI 800 into a full-range 16-bit RGB TIFF. Supply the Resolve input assignment. Check full data levels, gray, saturated colors and highlight detail against the EXR under the same display transform. A 16-bit PNG can use the same encoding if desired. [ARRI LogC3 specification](https://www.arri.com/resource/blob/31918/66f56e6abb6e5b6553929edf9aa7483e/2017-03-alexa-logc-curve-in-vfx-data.pdf) · [Blackmagic color management guide](https://documents.blackmagicdesign.com/UserManuals/DaVinci-Resolve-20-Colorist-Guide.pdf) |
| **Linear DNG for Lightroom and darktable** | Encode three-channel scene-linear RGB using DNG’s LinearRaw representation. Use a documented color matrix and white point, neutral balance, black/white levels, and a scale that reserves highlight headroom. Validate with Adobe’s DNG tools, then import a real game shot in both editors. Adjust exposure and white balance and compare the recovered neutral and highlights against the EXR. Identify the source as a virtual camera. [Adobe DNG specification and SDK](https://helpx.adobe.com/camera-raw/desktop/dng-and-file-formats/digital-negative.html) · [darktable file support](https://docs.darktable.org/usermanual/5.6/en/overview/supported-file-formats/) |
| **Fuji F-Log option** | Offer an F-Gamut / original F-Log 16-bit TIFF from the same master for users who want Fuji grading. Keep the DNG pixels linear and make the Fuji rendition a selectable companion. Check a synthetic 18% neutral against the manufacturer’s published value, then round-trip a game shot in Resolve. [Fujifilm F-Log specification](https://dl.fujifilm-x.com/technical-data/F-Log_DataSheet_E_Ver.1.2.pdf) |

The decisive test is recoverable scene detail upstream of the display transform. Converting an already tone-mapped screenshot to log or changing its file extension cannot recover clipped highlights. If this build exposes only finished display pixels, ship the game-look PNG and continue renderer work before advertising the grading formats.

## Playtest and release

Package the camera as a removable mod with a pinned, tested loader and install/rollback instructions that preserve existing Steam launch options and mods. Verify the normal and low-spec launches, repeated entry/exit, map reload, keyboard/mouse and Steam Input, custom photo folders, and capture while disk writes fail. Keep the original game archives intact.

The installation and grading-editor choice are already known. The first useful player contribution is a short test in a familiar level to judge whether the free camera is slow enough for a train close-up, the controls feel natural, and the trick resumes correctly. When grading files are ready, use the same sample shot for Resolve, Lightroom and darktable. Lightroom verification can come from a Windows or macOS tester.
