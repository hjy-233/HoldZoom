# HoldZoom

A lightweight screen magnifier for macOS.

HoldZoom captures the current screen and displays it in a pixelated, pannable overlay. It also includes a cursor-following flashlight effect.

## Features

- Hold **Control** to show a screen capture; release it to dismiss the overlay.
- Hold **Control** and scroll to zoom from 1× to 8× around the pointer.
- Pan with **WASD**, the arrow keys, or by dragging the image.
- Press **Command+R** to toggle the flashlight, which follows the pointer.
- Click the menu bar icon to open a small panel for capture, flashlight, and quit actions.
- The magnifier displays a static capture; it does not mirror screen changes in real time.

## Requirements

- macOS 15.4 or later
- Screen Recording permission, to capture the display
- Accessibility permission, for global keyboard and pointer input while the overlay is visible

## Build

Open `HoldZoom.xcodeproj` in Xcode, select the **HoldZoom** scheme, and run it.

## Shortcuts and configuration

The default shortcuts are **Control** to show the magnifier, **Control+scroll** to zoom, **WASD** or the arrow keys to pan, **Command+R** for the flashlight, and **Escape** to dismiss an overlay.

HoldZoom reads its local settings from `~/.config/holdzoom.json`. On first launch, it creates that file with the default settings. The file is per-user and is not part of this repository.

## License

HoldZoom is licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for the full text.
