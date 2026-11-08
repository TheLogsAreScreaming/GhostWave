# PlatformIO post-build step for the nRF52 envs: firmware.hex -> firmware.uf2
# with the Adafruit core's uf2conv.py, for drag-and-drop flashing through the
# Adafruit nRF52 UF2 bootloader (family 0xADA52840). The UF2 carries the
# addresses from the hex: 0x26000 after S140 6.1.1 (RAK4631), 0x27000 after
# S140 7.3.0 (T1000-E).
import os

Import("env")  # noqa: F821  (PlatformIO SCons global)

FAMILY = "0xADA52840"


def make_uf2(source, target, env):
    hex_path = str(target[0])
    uf2_path = os.path.splitext(hex_path)[0] + ".uf2"
    fw = env.PioPlatform().get_package_dir("framework-arduinoadafruitnrf52")
    conv = os.path.join(fw, "tools", "uf2conv", "uf2conv.py")
    cmd = '"%s" "%s" "%s" -c -f %s -o "%s"' % (env.subst("$PYTHONEXE"), conv, hex_path, FAMILY, uf2_path)
    if env.Execute(cmd):
        env.Exit(1)
    print("UF2: %s" % uf2_path)


env.AddPostAction("$BUILD_DIR/${PROGNAME}.hex", make_uf2)  # noqa: F821
