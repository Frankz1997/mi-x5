"""Assemble the actual Flutter UI frames into the README animation.

Requires Pillow. Run after: flutter test tool/capture_docs.dart
"""
from pathlib import Path

from PIL import Image


def main():
    paths = [Path(f"build/docs-frames/{index:03d}.png") for index in range(72)]
    if not all(path.is_file() for path in paths):
        raise SystemExit("Missing frames. Run flutter test tool/capture_docs.dart first.")
    with Image.open(paths[48]) as source:
        palette = source.convert("RGB").quantize(colors=256)
    frames = []
    for path in paths:
        with Image.open(path) as source:
            if source.size != (500, 540):
                raise SystemExit(f"Unexpected frame size: {path.name}")
            frames.append(source.convert("RGB").quantize(palette=palette, dither=Image.Dither.NONE))
    output = Path("docs/images/demo.gif")
    output.parent.mkdir(parents=True, exist_ok=True)
    frames[0].save(
        output,
        save_all=True,
        append_images=frames[1:],
        duration=83,
        loop=0,
        disposal=1,
        optimize=True,
    )
    with Image.open(output) as animation:
        assert animation.n_frames > 60 and animation.size == (500, 540)
    print(f"Created {output}: {output.stat().st_size:,} bytes")


if __name__ == "__main__":
    main()
