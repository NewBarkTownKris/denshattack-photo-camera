"""Develop the missing companions for Denshattack scene-linear EXRs."""

import argparse
from pathlib import Path
import sys


def discover_shots(directory):
    return sorted(path for path in directory.iterdir()
                  if path.suffix.lower() == ".exr" and not path.name.startswith(".")
                  and not path.name.lower().endswith(".source.exr") and path.is_file())


def develop(source, formats, args):
    pending = {}
    for fmt in formats:
        output = (source.with_suffix(".dng") if fmt == "dng"
                  else source.with_name(f"{source.stem}_{fmt}.tiff"))
        if not output.is_file():
            pending[fmt] = output

    kept = len(formats) - len(pending)
    if not pending:
        return 0, kept, False
    try:
        from grade import read_linear_exr
        rgb = read_linear_exr(source)
    except (OSError, ValueError, RuntimeError, ImportError) as error:
        print(f"{source}: {error}", file=sys.stderr)
        return 0, kept, True

    saved = 0
    failed = False
    for fmt, path in pending.items():
        try:
            if fmt == "dng":
                from linear_dng import write_dng
                stops, negative = write_dng(rgb, path, clip_negative=args.clip_negative, integer=args.integer_dng)
                kind = "16-bit integer" if args.integer_dng else "32-bit floating point"
                detail = f"{kind}, baseline exposure +{stops} EV, {negative} negative channel samples floored"
            else:
                from grade import highlight_exposure, write_log_tiff
                ev = args.ev if args.ev is not None else highlight_exposure(rgb, fmt)
                low, high = write_log_tiff(path, rgb, fmt, exposure=ev)
                detail = (f"{ev:+g} EV encoded, {-ev:+g} EV restores the scene after log decoding, "
                          f"{low} low and {high} high channel samples clipped")
            print(f"Saved {path} ({detail})", flush=True)
            saved += 1
        except (OSError, ValueError, RuntimeError, ImportError, OverflowError) as error:
            # Another exporter may publish between our directory check and its atomic link.
            if isinstance(error, FileExistsError) and path.is_file():
                kept += 1
            else:
                print(f"{source} ({fmt}): {error}", file=sys.stderr)
                failed = True
    return saved, kept, failed


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    inputs = parser.add_mutually_exclusive_group()
    inputs.add_argument("photo", nargs="?", type=Path, help="EXR or directory (default: camera screenshot directory)")
    inputs.add_argument("--directory", type=Path, help="Scan this directory for missing companions")
    parser.add_argument("--format", choices=("all", "dng", "logc3", "flog"), default="all")
    parser.add_argument("--ev", type=float, help="Set a log TIFF exposure in stops (default: fit highlights)")
    parser.add_argument("--integer-dng", action="store_true", help="Write a 16-bit integer DNG for legacy readers")
    parser.add_argument("--clip-negative", action="store_true", help="Floor negative RGB for the DNG companion")
    args = parser.parse_args(argv)
    formats = ("logc3", "flog", "dng") if args.format == "all" else (args.format,)
    try:
        if args.photo is not None and not args.photo.is_dir():
            if args.photo.suffix.lower() != ".exr" or not args.photo.is_file():
                parser.error(f"Choose an existing scene-linear EXR or directory: {args.photo}")
            sources = [args.photo]
        else:
            directory = args.directory or args.photo
            if directory is None:
                from photo_directory import selected_directory
                directory = selected_directory()
            sources = discover_shots(directory)
            print(f"Scanning {directory}", flush=True)
    except (OSError, ValueError) as error:
        parser.exit(1, f"{error}\n")

    saved = kept = failed = 0
    for source in sources:
        written, existing, problem = develop(source, formats, args)
        saved += written
        kept += existing
        failed += int(problem)
    print(f"Checked {len(sources)} EXR(s). Saved {saved} companion(s), kept {kept} existing. "
          f"Failed shots: {failed}.")
    return int(failed > 0)


if __name__ == "__main__":
    sys.exit(main())
