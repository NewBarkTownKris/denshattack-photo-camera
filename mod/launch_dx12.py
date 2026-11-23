"""Run Denshattack with its Linux photo folder picker and optional DX12/SM5 flags."""

import os
from pathlib import Path, PureWindowsPath
import signal
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


def run_with_picker(command, picker):
    # Steam's reaper waits for every child. If it inherits the watcher as a
    # child, both wait forever. The launcher owns them as siblings instead.
    game = None
    watcher = None
    pending_signal = None

    def forward(signum, frame):
        nonlocal pending_signal
        if game is None:
            pending_signal = signum
        else:
            game.send_signal(signum)

    previous = {sig: signal.signal(sig, forward) for sig in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM)}
    try:
        game = subprocess.Popen(command)
        if pending_signal is not None:
            game.send_signal(pending_signal)
        try:
            watcher = subprocess.Popen(
                [sys.executable, str(picker), "--watch", "--parent-pid", str(game.pid)],
                stdin=subprocess.DEVNULL, start_new_session=True,
            )
        except OSError as exc:
            print(f"Could not start the Denshattack photo folder picker: {exc}", file=sys.stderr)
        status = game.wait()
        if watcher is not None:
            # The watcher detects game exit and closes any open native dialog.
            try:
                watcher.wait(timeout=3)
            except subprocess.TimeoutExpired:
                watcher.terminate()
                try:
                    watcher.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    watcher.kill()
                    watcher.wait()
    finally:
        for sig, handler in previous.items():
            signal.signal(sig, handler)
    if status < 0:
        sig = -status
        if sig not in (signal.SIGKILL, signal.SIGSTOP):
            signal.signal(sig, signal.SIG_DFL)
        signal.raise_signal(sig)
        return 128 + sig
    return status


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
            return run_with_picker(command, picker)
        else:
            print("Missing photo_directory.py. Reinstall the camera mod to use the in-game folder picker.",
                  file=sys.stderr)
    os.execvp(command[0], command)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
