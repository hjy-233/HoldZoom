# HoldZoom

A lightweight screen magnifier for macOS.

HoldZoom captures the current screen and displays it in a pixelated, pannable overlay. It also includes a cursor-following flashlight effect.

## Features

- Hold **Control** to show a screen capture; release it to dismiss the overlay.
- Hold **Control** and scroll to zoom from 1× to 8× around the pointer.
- Pan with **WASD**, the arrow keys, or by dragging the image.
- Hold **Control** and press the configured annotation key (default **N**) to enter persistent annotation mode. Choose pen, circle, rectangle, line, arrow, or eraser from the on-screen tool picker. Left-click a tool to select it; right-click to open its settings for color, line width, shape fill, eraser mode, and eraser size. The selected tool is named on screen. Drag the eraser to remove part of a stroke or the whole stroke. Draw with the left mouse button, pan with the right mouse button or movement keys, and zoom with the scroll wheel. Press **Escape** to leave annotation mode, then again to dismiss the overlay.
- Undo with **Command+Z**, redo with **Command+Shift+Z**, clear marks with **Option+Delete**, and save a session with **Option+S**.
- Save screenshot-and-annotation sessions permanently from the menu bar. Restore the most recent screenshot or restore its annotations onto the currently displayed matching screenshot.
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

The default shortcuts are **Control** to show the magnifier, **Control+scroll** to zoom, **WASD** or the arrow keys to pan, **Command+R** for the flashlight, and **Control+N** to enter annotation mode. Set the annotation key in `shortcuts.annotations.enter.key` in `~/.config/holdzoom.json`; it is a single key with no extra modifier. In annotation mode, the scroll wheel zooms, **Escape** exits that mode first, and pressing it again dismisses the overlay.

HoldZoom reads its local settings from `~/.config/holdzoom.json`. On first launch, it creates that file with the default settings. The file is per-user and is not part of this repository.

Saved sessions are stored per user in `~/Library/Application Support/HoldZoom/Sessions/`.

## License

HoldZoom is licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for the full text.
