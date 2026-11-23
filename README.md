# Denshattack! Photo Camera

Freeze the train mid-trick, fly around it, and frame a photograph with a mouse, keyboard, or controller. **F9** saves the game’s look as a PNG. **F3** also saves a scene-linear HDR EXR for grading. The mod targets the Windows Steam build of Denshattack! (`26541226`, Unreal Engine 5.6.1) and runs through UE4SS v4.0.0. Gameplay and capture have been tested on Linux with Proton Experimental.

[Download the latest release](https://github.com/NewBarkTownKris/denshattack-photo-camera/releases/latest)

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

Press **F8** during a run, move the camera, then press **F9** for a game-look PNG. Press **F3** for a PNG and a scene-linear EXR from the same frozen composition. Press **F8** again to restore the gameplay view. If you exit during a write, the camera waits for completion or timeout.

In v0.1.0, the game controls exposure and the aperture dial controls depth of field. Photographic ISO, timed shutters, exposure metering and priority modes are planned. The TIFF export exposure offset fits highlights into the selected log encoding.

| Input | Action |
| --- | --- |
| F1 | Show or hide the controls in the viewfinder |
| F2 | Open the desktop screenshot folder picker (with the camera launcher) |
| F3 / F9 | Save PNG + EXR / PNG only |
| W / S, A / D or left stick | Move forward / back and left / right |
| E / Q | Rise / descend |
| Mouse, arrow keys or right stick | Look left, right, up or down |
| Z / X, F10 | Roll either direction, reset roll |
| Hold Ctrl / Shift | Fine movement (0.2×) / fast movement (4×) |
| `[` / `]` | Narrow / widen the field of view |
| F7 | Cycle 16, 24, 35, 50, 85, 135, 200 and 600 mm lenses |
| F5 | Cycle viewport, 3:2, 4:3, 1:1, 16:9, 5:4, 21:9 and 65:24 |
| F6 | Rotate the selected frame into portrait or landscape |
| V | Switch the train’s speed lines and radial blur between clean and original |
| H / G | Toggle the viewfinder / rule-of-thirds grid |
| R | Cycle optical, square, circle and off |
| N | Focus once on the first visible collision surface at the center of the frame |
| J / K | Move the focus plane nearer / farther |
| L | Switch manual focus between 20% and 1% steps |
| B | Toggle photographic depth of field |
| U / I | Open / close the equivalent aperture from f/1 to f/16 |
| Y | Cycle 1×, 2×, 4× and 8× depth-of-field strength |

Mouse look is active as soon as you enter photo mode. Push the right stick up or move the mouse up to raise the camera's aim. Both slow down on longer lenses for fine framing. Partial stick travel gives slower movement or aiming. For analog sticks with Steam Input, use a Gamepad layout with each stick mapped to its corresponding joystick. **E/Q** controls vertical movement and **F8** enters and exits photo mode.

Photo mode hides the train’s speed lines and bypasses its speed-driven radial blur when those materials are available. **V** restores the look at the instant of the freeze for an action shot. Leaving photo mode restores the original values. The game’s saved graphics settings are preserved.

To isolate the train, choose a longer lens with **F7**, center the subject and tap **N**. Focus stays at that distance as you reframe. A missed autofocus attempt keeps the previous distance. **J** or **K** engages manual focus. Try **U** to open the aperture or **Y** for stronger blur. Aperture here changes the depth-of-field effect independently of the game’s exposure. The finder and its guides are hidden for the saved PNG.

The optical finder marks the corners of the active crop and puts a broken ring and focus brackets around its center. The square finder shows open brackets, and the circle finder shows two rings. Press **R** to cycle them. The thirds grid works with any reticle. Guides and readouts stay out of both saved images.

### Choose where to save

With the camera launcher running, press **F2** in photo mode and select a folder on your desktop. The next shutter press uses it. PNG, EXR and developed companions stay together. The choice persists between sessions.

On Windows, choose a folder on a local drive. To open the picker directly from the extracted release, run `py -3 windows/photo_camera.py choose`. On Linux, run `python3 tools/photo_directory.py`. To print the current location, run `python3 tools/photo_directory.py --show` (Windows: `py -3 tools/photo_directory.py --show`).

The default Windows directory is `%LOCALAPPDATA%\Denshattack_Proto\Saved\Screenshots\Windows`. Under Proton the equivalent is `steamapps/compatdata/2524850/pfx/drive_c/users/steamuser/AppData/Local/Denshattack_Proto/Saved/Screenshots/Windows` in the Steam library.

For the standard installation, check `Denshattack_Proto/Binaries/Win64/ue4ss/UE4SS.log` under the game directory. Search for `[DenshattackPhotoCamera]`. The `Saved` message includes the file path after the mod checks the PNG dimensions and closing chunk. A timeout or a crop mismatch is logged there too.

The 4K playtest on **9-2-B To the Moon** captured three PNGs from one frozen camera position with the speed effects hidden, restored and hidden again. The streaks along the edge of the track followed the switch, and the grid and settings panel stayed out of the PNGs. A separate 135 mm focus bracket at 10.66 m and 5.14 m showed the change in focus in the saved images.

## Develop a grading shot

The **F3** shutter saves an opaque, three-channel, half-float EXR tagged with linear Rec.709/D65 primaries. Allow about 50 MB for a 3840 × 2160 master. The separate HDR view uses the detached camera’s pose and projection. Both log TIFFs are developed from this scene color before the final tone map and display grade. Colors authored into textures, materials, lighting and emissives are already present. Bloom, outlines, photographic depth of field and some particles can look different in the companion PNG. Both files use the selected frame. The PNG remains available if the EXR write fails.

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

Each 16-bit TIFF uses the closest whole-stop reduction needed to fit its highlights. The command prints the offset and writes it into the TIFF description. To match the original exposure in Resolve, apply the inverse adjustment in scene-linear space after decoding the log curve. Pass `--ev 0` to develop at the original exposure and see how many channel samples exceed the TIFF range. Use each input transform once. [ARRI LogC3 specification](https://www.arri.com/resource/blob/31918/66f56e6abb6e5b6553929edf9aa7483e/2017-03-alexa-logc-curve-in-vfx-data.pdf) · [Fujifilm F-Log specification](https://dl.fujifilm-x.com/technical-data/F-Log_DataSheet_E_Ver.1.2.pdf)

This product includes DNG technology under license by Adobe.

On the 4K lunar-course test, the EXR reached 505 times reference white. The floating-point DNG reserves nine stops above white. This preserves faint stars and emissive detail at the same time. For readers requiring unsigned 16-bit DNG, pass `--integer-dng` when developing a fresh output. Integer DNG has less shadow precision at this range. Real shots opened in darktable 5.6.2. Lightroom and Resolve application imports still need direct verification.

## Uninstall

Close the game. On Windows, run `py -3 windows/photo_camera.py remove` from the extracted download. On Linux, remove the camera launcher from Steam’s launch options first, then run `python3 tools/install.py remove`. On either platform you can add `--remove-loader` to roll back a clean loader installed by the camera installer. On Linux also remove its DLL override from Steam. Keep overrides used by your other mods.

## Development

Run the Lua suites with `for t in tests/*.lua; do lua5.4 "$t" || exit 1; done` on Linux. With the export requirements installed, run `python3 -m unittest discover -s tests`. Build both download archives and the checksum manifest with `python3 tools/package_release.py --version 0.1.0 --output dist`.

The viewfinder and photographic controls were inspired by technicallyalex’s [VHOLUME Photo Camera](https://github.com/technicallyalex/vholume-photo-camera). This independent fan mod is distributed under the [MIT license](LICENSE).
