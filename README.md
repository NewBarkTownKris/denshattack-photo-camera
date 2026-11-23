# Denshattack! Photo Camera

Freeze the train mid-trick, fly around it, and frame a photograph with a mouse, keyboard, or controller. **F9** saves the game’s look as a PNG. **F3** also saves a scene-linear HDR EXR for grading. The mod targets the Windows Steam build of Denshattack! (`26541226`, Unreal Engine 5.6.1) and runs through UE4SS v4.0.0. Gameplay and capture have been tested on Linux with Proton Experimental.

**Stable v0.1.0** includes the free camera, finder, folder picker, PNG/EXR shutter and offline exporters. The **v0.2.0-dev prerelease** adds metered exposure, Photo Studio, timed captures, film looks, ISO grain and a chromatic aberration switch. Pick the Windows or Linux/Proton ZIP from the version you want and follow the same installation steps below. [Download stable v0.1.0](https://github.com/NewBarkTownKris/denshattack-photo-camera/releases/tag/v0.1.0) · [Download the v0.2.0-dev prerelease](https://github.com/NewBarkTownKris/denshattack-photo-camera/releases/tag/v0.2.0-dev)

The local **0.2.0-print.2** build adds **Spread 89:35** for a 22.25 × 8.75-inch magazine spread. It includes the 1× through 4× capture scale introduced in **0.2.0-print.1**.

## Windows installation

1. Download the **windows.zip** asset from the release and extract the entire folder. Install 64-bit Python 3.12 with the Python launcher and Tcl/Tk if you need Python. [Python for Windows](https://www.python.org/downloads/windows/)
2. Close Denshattack!, then double-click **Install-Windows.cmd** in the extracted folder. The installer finds Steam libraries or lets you locate the game. It reuses an existing UE4SS installation or downloads the pinned official loader and checks its SHA-256.
3. Double-click **windows/Launch-Camera.cmd** to start the game through Steam with the **F2** folder picker available. In a playable level, press **F8** to try the camera.

For an offline installation, supply the official loader ZIP you downloaded. From the extracted folder run:

```powershell
py -3 windows/photo_camera.py install --game "D:\SteamLibrary\steamapps\common\Denshattack" --loader-zip "C:\Downloads\UE4SS_v4.0.0.zip"
```

## Linux installation with Proton

1. Download the **linux-proton.zip** asset and extract it. You need Python 3 and either KDialog or Zenity for the desktop folder picker.
2. Close the game. Open a terminal in the extracted folder and run `sh Install-Linux.sh`. The installer locates the Steam game, reuses an existing loader, or downloads and checks UE4SS v4.0.0. To specify another library, run `sh Install-Linux.sh install --download-loader --game "/path/to/Denshattack"`.
3. Copy the launch option printed by the installer to **Steam → Denshattack! → Properties → Launch Options**. This starts the folder picker and loads the mod under Proton. If you already use custom options, merge `dwmapi=n,b` into your DLL overrides and keep the game arguments after `%command%`.
4. Launch from Steam, enter a playable level, and press **F8**.

The launch option includes `--keep-renderer`. If the Windows PC launch profile crashes in `D3D11Query.cpp` with `DXGI_ERROR_INVALID_CALL`, remove that flag from the printed command to use DX12 with the packaged SM5 shaders. That configuration passed the live Proton test.

For either platform the exact loader archive is **UE4SS_v4.0.0.zip**, SHA-256 `251ad0d1381a241750e036f5918cbf2b5d7ec58ebc608cb2dd09d459d0c81e45`. On Linux an offline install uses `sh Install-Linux.sh install --loader-zip "/path/to/UE4SS_v4.0.0.zip"`. [Official UE4SS release](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/v4.0.0)

## Take a photo

Press **F8** during a run, move the camera, then press **F9** for a PNG. Press **F3** for a PNG and a scene-linear EXR from the same frozen composition. Press **F8** again to restore the gameplay view. An instant shutter finishes its pending write or reports a timeout before gameplay resumes.

### Photo Studio development build

Press **F4** in photo mode. Use **Up/Down** to select a row and **Left/Right** to change its value, or use the controller D-pad. **F4** closes the panel and restores aiming. A fresh installation starts in **Game** exposure with **Neutral** film, **ISO grain Off** and **Chromatic aberration Game**. Studio also has controls for framing, lenses, focus, depth of field, reticle, grid and the screenshot folder. It remembers your exposure, image treatment and framing preferences between sessions. Focus distance and focus mode belong to the current shot.

| Exposure mode | What you control |
| --- | --- |
| Game | The game supplies display exposure. Set aperture for depth of field. With **ISO grain** on, the **Grain ISO** dial sets grain sensitivity from ISO 100–6400 while the game controls brightness. |
| Manual | Set aperture, exposure time and ISO. The meter shows the difference in stops from its reading. Auto ISO can take over sensitivity. |
| Aperture Priority | Set the aperture. The camera meters the composition and chooses a shutter time. With Auto ISO it also uses your preferred minimum shutter speed and ISO limits. |
| Shutter Priority | Set the shutter time. The camera chooses an aperture and can raise Auto ISO within your limits. |

The dials cover **f/1–f/16**, **8 s–1/32000 s** and **ISO 100–6400**. Exposure compensation ranges from −5 to +5 EV in thirds of a stop. With Manual exposure, ISO 200 delivers twice the linear signal of ISO 100 at the same aperture and shutter. The meter samples a small HDR rendering of the selected frame. Its virtual calibration assigns EV100 10 to linear 0.18. Once the meter has a reading, the finder shows a **±3 EV scale** above the image, marked in thirds of a stop. Positive meter error means the camera exposes brighter than its target.

At **1/15 s or slower** in a photographic mode, keep moving the camera after pressing the shutter to build a motion exposure. The finder shows the time remaining, then **Developing photo** while it renders the recorded path. The train stays frozen. Focus, focal length and exposure lock for the shot. **F8** cancels a timed exposure and resumes gameplay. The shutter uses up to 64 camera poses. Its 1× image has a maximum long edge of 3840 pixels.

**Film look** offers eleven presets, including Neutral, Chrome slide, Tungsten negative and Silver print. **ISO grain** adds grain to any look, including Neutral. The effective ISO controls its strength and size. The finder and PNG show the creative grade. F3 writes the EXR from scene color, applying the selected photographic exposure once. The TIFF exporter’s highlight-protection offset is a separate development adjustment.

Press **C**, or open **F4 → Chromatic aberration**, to switch between **Game** and **Off**. Choose **Off** to suppress the colored lens fringes along high-contrast edges in the finder and PNG. Choose **Game** to follow the game's treatment. This setting works in every exposure mode and with every film look. The scene-linear EXR is captured upstream of the display effect.

| Input | Action |
| --- | --- |
| F1 | Show or hide the controls in the viewfinder |
| F2 | Open the desktop screenshot folder picker (with the camera launcher) |
| F3 / F9 | Save PNG + EXR / PNG only |
| F4 / left stick click | Open or close Photo Studio (development build) |
| W / S, A / D or left stick | Move forward / back and left / right |
| E / Q | Rise / descend |
| Mouse, arrow keys or right stick | Look left, right, up or down |
| Z / X, F10 | Roll either direction, reset roll |
| Hold Ctrl / Shift | Fine movement (0.2×) / fast movement (4×) |
| `[` / `]` | Narrow / widen the field of view |
| F7 | Cycle 16, 24, 35, 50, 85, 135, 200 and 600 mm lenses |
| F5 | Cycle viewport, 3:2, 4:3, 1:1, 16:9, 5:4, 21:9 and 65:24. The print build also includes Spread 89:35. |
| F6 | Rotate the selected frame into portrait or landscape |
| V | Switch the train’s speed lines and radial blur between clean and original |
| C | Toggle chromatic aberration between Game and Off (development build) |
| H / G | Toggle the viewfinder / rule-of-thirds grid |
| R | Cycle optical, square, circle and off |
| N | Focus once on the first visible collision surface at the center of the frame |
| T | Toggle continuous center autofocus and focus lock (development build) |
| J / K | Move the focus plane nearer / farther |
| L | Switch manual focus between 20% and 1% steps |
| B | Toggle photographic depth of field |
| U / I | Open / close the equivalent aperture from f/1 to f/16 |
| Y | Cycle 1×, 2×, 4× and 8× depth-of-field strength |

The development build also supports **A / Cross** for PNG, **Y / Triangle** for PNG + EXR, and **right stick click** for autofocus. **RB/LB** raises/lowers the camera. Click the left stick and use the D-pad to adjust the Studio controls. Press and release **View / Back** alone to resume. To enter photo mode entirely from the controller, assign **F8** to a spare button, back grip or long press in the game’s Steam Input layout.

With Studio closed and the finder visible, **left-click** fires the PNG shutter and **middle-click** focuses once. The development build supports these wheel controls with Studio closed.

| Scroll up / down | Action |
| --- | --- |
| Wheel | Focus farther / nearer using the current **L** step |
| Shift or Ctrl + wheel | Open / close aperture |
| Alt + wheel | Faster / slower shutter |
| Ctrl + Alt + wheel | Higher / lower manual ISO |

The selected exposure mode determines which exposure dials you can turn. For example, Aperture Priority chooses shutter speed, and Auto ISO chooses sensitivity.

Mouse look is active as soon as you enter photo mode. Push the right stick up or move the mouse up to raise the camera's aim. Both slow down on longer lenses for fine framing. Partial stick travel gives slower movement or aiming. For analog sticks with Steam Input, use a Gamepad layout with each stick mapped to its corresponding joystick. **E/Q** controls vertical movement and **F8** enters and exits photo mode.

Photo mode hides the train’s speed lines and bypasses its speed-driven radial blur when those materials are available. **V** restores the look at the instant of the freeze for an action shot. Leaving photo mode restores the original values. The game’s saved graphics settings are preserved.

To isolate the train, choose a longer lens with **F7**, center the subject and tap **N**. Focus stays at that distance as you reframe. A missed autofocus attempt keeps the previous distance. **J** or **K** engages manual focus. Try **U** to open the aperture or **Y** for stronger blur. In Game exposure, aperture changes depth of field and preserves the game’s brightness. In the photographic modes it also participates in the exposure calculation.

In the development finder, **T** enables **AF-C** to keep focusing on the center target while you move. Press **T** again to lock the current distance. With photographic DOF on, the finder reports the distance to the center target and whether to focus nearer or farther. **Aligned** indicates that the target falls within the lens’s sharpness tolerance. An empty center target holds the last focus plane.

The optical finder marks the corners of the active crop and puts a broken ring and focus brackets around its center. The square finder shows open brackets, and the circle finder shows two rings. Press **R** to cycle them. The thirds grid works with any reticle. Guides and readouts stay out of both saved images.

### Capture for print

In **F4 → Capture scale**, choose **1×, 2×, 3× or 4×** with Left/Right. The row shows the output dimensions for the selected frame and shutter. The choice applies to the **F9** PNG and both files from **F3**. New and older installations start at **1×**, and the mod remembers the selection for your next session. Scaling applies when the shutter fires.

For a **22.25 × 8.75-inch** two-page magazine spread, select **F4 → Frame → Spread 89:35**, or cycle to it with **F5**. Its exact ratio is **89:35** (about **2.54:1**). At a 3840 × 2160 viewport, 2× yields **7654 × 3010 pixels**, or **344 PPI** across the spread. At 4×, **15308 × 6020 pixels** give **688 PPI**. A 300 PPI delivery at these dimensions is **6675 × 2625 pixels**.

A **65:24** composition on a **3840 × 2160** viewport gives these print sizes.

| Capture scale | Saved pixels | Inches at 300 pixels per inch |
| --- | --- | --- |
| 1× | 3835 × 1416 | 12.8 × 4.7 |
| 2× | 7670 × 2832 | 25.6 × 9.4 |
| 3× | 11505 × 4248 | 38.4 × 14.2 |
| 4× | 15340 × 5664 | 51.1 × 18.9 |

To size for a magazine layout, multiply the placed width and height in inches, including bleed, by the printer’s required pixels per inch. Choose a frame close to that aspect ratio and a scale that meets both dimensions. At 4× the capture contains sixteen times as many pixels as at 1×. A full 15360 × 8640 photographic EXR takes about **1.6 GB** before any TIFF or DNG exports.

For an instant capture, each dimension of the full viewport multiplied by the scale must fit within **16384 pixels**, including when the saved frame uses only part of the view. Timed exposures scale their 1× frame up to a **15360-pixel** long edge at 4×. Available GPU memory can limit what your system can render.

For a sharp magazine spread, use **Game** exposure or a photographic shutter faster than **1/15 s**. At 2× on a 4K viewport, each file uses one render of the whole frame. Larger instant shots use **pixel shift**. The camera renders the same view several times, shifting the sample position by a fraction of a pixel each time. Interleaving the samples gives geometry a distinct ray at each output pixel while keeping the entire scene in view for shadows. Post-processing and texture detail can still resolve at the size of each individual render.

The PNG switches to pixel shift when a 2×, 3× or 4× capture takes the full viewport above 40 megapixels. On a 3840 × 2160 viewport this happens at 3× and 4×. The PNG uses Unreal’s *FinalColorLDR* with a persistent rendering state for shadows. A plain RGBA8 render target at gamma 2.2 retains the game’s display-encoded color values. An instant EXR switches when the cropped render target, including alignment padding, exceeds 7680 × 4320 pixels in area (about 33 megapixels). After **F3** saves the PNG, the finder reports EXR progress. **F8** at that point keeps the PNG and cancels the EXR.

Large **timed exposures** render the recorded motion in overlapping horizontal bands. Directional shadows, bloom and other screen-space effects can leave visible joins in those images.

In a Proton test of the magazine spread, a 4× **F3** shot saved the **15308 × 6020** PNG after **50 seconds** and the matching EXR after **79 seconds**. Both showed finer detail than an enlarged 1× shot, with continuous shadows and clouds across the spread. The EXR matched the 1× EXR framing and retained values above scene-linear white. A shaded blue platform averaged RGB **(0, 21, 65)** in the 1× viewport PNG and **(0, 22, 67)** in the 4× PNG. The native **2× PNG** provides **344 PPI** across the same spread.

### Choose where to save

With the camera launcher running, press **F2** in photo mode and select a folder on your desktop. On the development branch you can also select **Screenshot folder** in Studio and press **Left** or **Right** to open the picker. The next shutter press uses the selected folder. PNG, EXR and developed companions stay together. The choice persists between sessions.

On Windows, choose a folder on a local drive. To open the picker directly from the extracted release, run `py -3 windows/photo_camera.py choose`. On Linux, run `python3 tools/photo_directory.py`. To print the current location, run `python3 tools/photo_directory.py --show` (Windows: `py -3 tools/photo_directory.py --show`).

The default Windows directory is `%LOCALAPPDATA%\Denshattack_Proto\Saved\Screenshots\Windows`. Under Proton the equivalent is `steamapps/compatdata/2524850/pfx/drive_c/users/steamuser/AppData/Local/Denshattack_Proto/Saved/Screenshots/Windows` in the Steam library.

For the standard installation, check `Denshattack_Proto/Binaries/Win64/ue4ss/UE4SS.log` under the game directory. Search for `[DenshattackPhotoCamera]`. The `Saved` message includes the file path after the mod checks the PNG dimensions and closing chunk. A timeout or a crop mismatch is logged there too.

The 4K playtest on **9-2-B To the Moon** captured three PNGs from one frozen camera position with the speed effects hidden, restored and hidden again. The streaks along the edge of the track followed the switch, and the grid and settings panel stayed out of the PNGs. A separate 135 mm focus bracket at 10.66 m and 5.14 m showed the change in focus in the saved images.

## Develop a grading shot

The **F3** shutter saves an opaque, three-channel EXR with linear Rec.709 primaries and a D65 white point. Game mode uses 16-bit floating point. The development build uses 32-bit floating point in photographic modes to preserve the exposure-adjusted highlights, and writes aperture, ISO and shutter metadata. Allow about 50 MB or 100 MB, respectively, for a 3840 × 2160 master. The separate HDR view uses the detached camera’s pose and projection. Both log TIFFs are developed from this scene color before the final tone map and display grade. Colors authored into textures, materials, lighting and emissives are already present. Bloom, outlines, photographic depth of field and some particles can look different in the companion PNG. Both files use the selected frame. The PNG remains available if the EXR write fails.

Wait for **PNG + EXR saved** in the finder. At 4K, the 65:24 preset produces a 3835 × 1416 pair. The camera renders a few extra columns for GPU readback and removes them before saving the EXR. If Unreal’s image writer produces no file, the camera reads the HDR pixels directly in strips.

### Optional TIFF and DNG exporter

F3 writes the EXR in-game. To develop missing LogC3 TIFFs, F-Log TIFFs and DNGs, use the exporter in the extracted download. It checks each file separately and keeps existing outputs.

**Windows** (PowerShell, from the extracted folder)

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe tools/export_photo.py
```

**Linux** (from the extracted folder)

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python tools/export_photo.py
```

Run the last command again after taking more shots. Add `--directory "/path/to/older/shots"` to backfill another folder. To develop only the Resolve TIFF for a single shot, pass the EXR filename and `--format logc3`.

| File | Import or develop |
| --- | --- |
| `.exr` | In a Resolve Color Space Transform, set **Input Color Space** to **Rec.709** and **Input Gamma** to **Linear**. The tagged white point is D65. For a DaVinci Wide Gamut timeline, set the outputs to **DaVinci Wide Gamut** and **DaVinci Intermediate**. Use one input transform if your project already manages color. |
| `_logc3.tiff` | In Resolve use **Full** data levels, **ARRI Wide Gamut 3**, and **ARRI LogC3 EI 800**. |
| `_flog.tiff` | In Resolve use **Full** data levels, **Fujifilm F-Gamut** and the original **F-Log** curve. |
| `.dng` | Import the 32-bit floating-point linear RGB negative into a raw editor. The embedded virtual camera profile describes its primaries and white balance. If darktable opens the image dark, add the baseline exposure printed by the exporter. |

When the EXR contains photographic settings, both TIFFs and the DNG carry the shutter speed, f-number, ISO and exposure mode as EXIF metadata.

Each 16-bit TIFF uses the closest whole-stop reduction needed to fit its highlights. The command prints the offset and writes it into the TIFF description. To match the original exposure in Resolve, apply the inverse adjustment in scene-linear space after decoding the log curve. Pass `--ev 0` to develop at the original exposure and see how many channel samples exceed the TIFF range. Use each input transform once. [ARRI LogC3 specification](https://www.arri.com/resource/blob/31918/66f56e6abb6e5b6553929edf9aa7483e/2017-03-alexa-logc-curve-in-vfx-data.pdf) · [Fujifilm F-Log specification](https://dl.fujifilm-x.com/technical-data/F-Log_DataSheet_E_Ver.1.2.pdf)

This product includes DNG technology under license by Adobe.

On the 4K lunar-course test, the EXR reached 505 times reference white. The floating-point DNG reserves nine stops above white. This preserves faint stars and emissive detail at the same time. For readers requiring unsigned 16-bit DNG, pass `--integer-dng` when developing a fresh output. Integer DNG has less shadow precision at this range. Real shots opened in darktable 5.6.2. Lightroom and Resolve application imports still need direct verification.

## Uninstall

Close the game. On Windows, run `py -3 windows/photo_camera.py remove` from the extracted download. On Linux, remove the camera launcher from Steam’s launch options first, then run `python3 tools/install.py remove`. On either platform you can add `--remove-loader` to roll back a clean loader installed by the camera installer. On Linux also remove its DLL override from Steam. Keep overrides used by your other mods.

## Development

Run the Lua suites with `for t in tests/*.lua; do lua5.4 "$t" || exit 1; done` on Linux. With the export requirements installed, run `python3 -m unittest discover -s tests`. Build the local Windows and Linux/Proton print archives and their checksum manifest with `python3 tools/package_release.py --version 0.2.0-print.2 --output dist/0.2.0-print.2`.

The viewfinder and photographic controls were inspired by technicallyalex’s [VHOLUME Photo Camera](https://github.com/technicallyalex/vholume-photo-camera). This independent fan mod is distributed under the [MIT license](LICENSE).
