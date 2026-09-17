# GD32F350 firmware layouts

`REF_F350` supports two different flash layouts. They are not interchangeable.

## Standard AM32 application

Run `make REF_F350` or `make f350` to build the standard AM32 application.

- Bootloader: `0x08000000-0x08000FFF`
- Application and vector table: `0x08001000`
- Firmware name: `0x0800F7E0-0x0800F7FF`
- EEPROM: `0x0800F800-0x0800FFFF`

The BIN must be loaded at `0x08001000`. The HEX contains its addresses. Both
formats require a compatible GD32F350 bootloader at `0x08000000`; neither is a
full-chip image. Relocating the standard BIN to `0x08000000` does not work
because its vector entries contain absolute bootloader-layout addresses.

## Standalone direct-SWD application

Run `make f350-standalone` to build a full application that starts directly at
the MCU reset address. Outputs are written to `obj-standalone/`:

- `AM32_REF_F350_2.21_STANDALONE.bin`
- `AM32_REF_F350_2.21_STANDALONE.hex`

The standalone BIN must be loaded at `0x08000000`; the HEX contains that
address. This layout sets `VECT_TAB_OFFSET=0` and does not require a bootloader.
It still reserves the firmware-name and EEPROM regions shown above.

Use `Am32.sct` for a Keil bootloader-layout build. Use
`Am32_standalone.sct` and define `VECT_TAB_OFFSET=0` for a Keil standalone
build.

Always select the programmer device matching the exact MCU marking and verify
that the ESC pinout matches `REF_F350` before applying power to the motor stage.
