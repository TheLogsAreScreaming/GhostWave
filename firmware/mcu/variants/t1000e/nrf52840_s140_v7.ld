/* Linker script for nRF52840 + SoftDevice S140 7.3.0 (Seeed T1000-E
 * bootloader). The Adafruit core 1.7.0 ships this only for the nRF52833, so
 * it is ours: the S140 7.3.0 image ends at 0x27000, where the application
 * starts. The end of the application region (0xED000) and the internal
 * filesystem above it (InternalFS, 0xED000-0xF4000) are the same as the
 * core's nrf52840_s140_v6.ld, so settings survive moving between builds.
 * RAM above 0x20006000 is the application's, as in the v6 script; Bluefruit
 * checks at startup that the SoftDevice fits below it. Cross-checked with
 * meshtastic/firmware src/platform/nrf52/nrf52840_s140_v7.ld (FLASH origin
 * 0x27000). */

SEARCH_DIR(.)
GROUP(-lgcc -lc -lnosys)

MEMORY
{
  FLASH (rx)     : ORIGIN = 0x27000, LENGTH = 0xED000 - 0x27000
  RAM (rwx) :  ORIGIN = 0x20006000, LENGTH = 0x20040000 - 0x20006000
}

SECTIONS
{
  . = ALIGN(4);
  .svc_data :
  {
    PROVIDE(__start_svc_data = .);
    KEEP(*(.svc_data))
    PROVIDE(__stop_svc_data = .);
  } > RAM

  .fs_data :
  {
    PROVIDE(__start_fs_data = .);
    KEEP(*(.fs_data))
    PROVIDE(__stop_fs_data = .);
  } > RAM
} INSERT AFTER .data;

INCLUDE "nrf52_common.ld"
