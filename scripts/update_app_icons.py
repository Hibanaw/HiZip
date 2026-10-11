"""Generate platform icons from the approved SVG (requires Node sharp and Pillow)."""

import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import xml.etree.ElementTree as ET

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/branding/hizip-app-icon.svg'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sharp-module', default='sharp')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory() as temp:
        temp = Path(temp)
        # Let mobile operating systems apply their own icon masks.
        ET.register_namespace('', 'http://www.w3.org/2000/svg')
        tree = ET.parse(SOURCE)
        ns = '{http://www.w3.org/2000/svg}'
        group = tree.getroot().find(f'{ns}g/{ns}g')
        background = group[0]
        background.tag = f'{ns}rect'
        background.attrib.pop('d')
        background.attrib.update(x='999', y='36', width='2401', height='2402')
        square_svg = temp / 'square.svg'
        tree.write(square_svg)
        for source, name in [(SOURCE, 'rounded'), (square_svg, 'square')]:
            subprocess.run([
                'node', '-e',
                "const sharp=require(process.argv[1]);"
                "sharp(process.argv[2]).resize(2048,2048).png()"
                ".toFile(process.argv[3]).catch(e=>{console.error(e);process.exit(1)});",
                args.sharp_module, str(source), str(temp / f'{name}.png'),
            ], check=True)
        rounded = Image.open(temp / 'rounded.png').convert('RGBA')
        square = Image.open(temp / 'square.png').convert('RGB')
        outputs = []

        def save(image, path, size):
            path = ROOT / path
            path.parent.mkdir(parents=True, exist_ok=True)
            image.resize((size, size), Image.Resampling.LANCZOS).save(path)
            outputs.append(path)

        save(rounded, 'assets/branding/hizip-app-icon.png', 1024)
        save(square, 'assets/branding/hizip-app-icon-square.png', 1024)
        for platform in ['ios', 'macos']:
            folder = Path(platform) / 'Runner/Assets.xcassets/AppIcon.appiconset'
            entries = json.loads((ROOT / folder / 'Contents.json').read_text())['images']
            for entry in entries:
                size = round(float(entry['size'].split('x')[0]) * float(entry['scale'][:-1]))
                save(square if platform == 'ios' else rounded, folder / entry['filename'], size)
        for density, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
            save(square, f'android/app/src/main/res/mipmap-{density}/ic_launcher.png', size)
        ico = ROOT / 'windows/runner/resources/app_icon.ico'
        rounded.resize((256, 256), Image.Resampling.LANCZOS).save(
            ico, sizes=[(s, s) for s in [16, 24, 32, 48, 64, 128, 256]])
        outputs.append(ico)
        for size in [16, 24, 32, 48, 64, 128, 256, 512]:
            save(rounded, f'linux/icons/hicolor/{size}x{size}/apps/com.hibanaw.hizip.png', size)
        # The OHOS directory currently lacks an AppScope/module configuration.
        save(square, 'ohos/entry/src/main/resources/base/media/app_icon.png', 1024)
        for path in set(outputs):
            with Image.open(path) as image:
                image.load()
        print(f'Generated and decoded {len(set(outputs))} icon files.')


if __name__ == '__main__':
    main()
