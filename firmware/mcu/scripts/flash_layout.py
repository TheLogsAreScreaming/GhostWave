"""Export the ESP32 upload layout resolved by the pinned PlatformIO builder."""
import json
from pathlib import Path

Import('env')  # noqa: F821


def export_layout(source, target, env):
    images = [
        {'offset': int(str(offset), 0), 'source': str(Path(env.subst(str(path))).resolve())}
        for offset, path in env.get('FLASH_EXTRA_IMAGES', [])
    ]
    images.append({
        'offset': int(env.subst('$ESP32_APP_OFFSET'), 0),
        'source': str(Path(str(target[0])).resolve()),
    })
    board = env.BoardConfig()
    if not images or any(not Path(image['source']).is_file() for image in images):
        raise ValueError('Resolved ESP32 flash images are incomplete')
    data = {
        'schema': 1,
        'board': env.subst('$PIOENV'),
        'chip': board.get('build.mcu'),
        'flashSize': board.get('upload.flash_size'),
        # Match the pinned PlatformIO uploader rather than guessing in the browser.
        'flashMode': env.subst('${__get_board_flash_mode(__env__)}'),
        'flashFreq': env.subst('${__get_board_f_image(__env__)}'),
        'images': images,
    }
    Path(env.subst('$BUILD_DIR/flash-layout.json')).write_text(json.dumps(data, indent=2) + '\n')


env.AddPostAction('$BUILD_DIR/${PROGNAME}.bin', export_layout)  # noqa: F821
