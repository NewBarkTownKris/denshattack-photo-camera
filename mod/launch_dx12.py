"""Run Denshattack with its Linux photo folder picker and optional DX12/SM5 flags."""

import os
from pathlib import Path, PureWindowsPath
import subprocess
import sys


GAME_EXECUTABLES = {"denshattack_proto.exe", "denshattack_proto-win64-shipping.exe"}


def _game_index(argv):
    for index, arg in enumerate(argv):
        if not arg.startswith("-") and PureWindowsPath(arg.strip('"')).name.lower() in GAME_EXECUTABLES:
            return index
    return None


def dx12_command(argv):
    index = _game_index(argv)
    if index is None:
        return list(argv)

    # Prefix arguments belong to Steam's launcher and Proton. Keep their order and
    # preserve the original argv boundaries for game paths and values with spaces.
    result = list(argv[:index + 1])
    needed = {"-dx12", "-sm5"}
    for arg in argv[index + 1:]:
        flag = arg.lower()
        if flag in ("-dx11", "-d3d11", "-dx12", "-d3d12"):
            flag = "-dx12"
        elif flag in ("-sm5", "-sm6"):
            flag = "-sm5"
        else:
            result.append(arg)
            continue
        if flag in needed:
            result.append(flag)
            needed.remove(flag)
    result.extend(flag for flag in ("-dx12", "-sm5") if flag in needed)
    return result


def main(argv):
    keep_renderer = bool(argv) and argv[0] == "--keep-renderer"
    command = list(argv[1:] if keep_renderer else argv)
    if not command:
        sys.exit("Usage: python3 launch_dx12.py [--keep-renderer] %command% (in Steam launch options)")
    if _game_index(command) is not None:
        if not keep_renderer:
            command = dx12_command(command)
        picker = Path(__file__).resolve().with_name("photo_directory.py")
        if not picker.is_file():  # Running the wrapper directly from the source checkout.
            picker = picker.parent.parent / "tools/photo_directory.py"
        if picker.is_file():
            try:
                subprocess.Popen([sys.executable, str(picker), "--watch", "--parent-pid", str(os.getpid())],
                                 stdin=subprocess.DEVNULL, start_new_session=True)
            except OSError as exc:
                print(f"Could not start the Denshattack photo folder picker: {exc}", file=sys.stderr)
        else:
            print("Missing photo_directory.py. Reinstall the camera mod to use the in-game folder picker.",
                  file=sys.stderr)
    # Retain the PID, signals and exit status of Steam's original game command.
    os.execvp(command[0], command)


if __name__ == "__main__":
    main(sys.argv[1:])
