# CameraBubble

> A lightweight (~1MB), zero-bloat, native macOS floating circular camera bubble designed for tech content creators, developers, and educators.

![macOS](https://img.shields.io/badge/platform-macOS%2014.0%2B-black?style=flat-square&logo=apple)
![Swift](https://img.shields.io/badge/built%20with-Swift-FA7343?style=flat-square&logo=swift)
![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)
![Size](https://img.shields.io/badge/binary%20size-~1MB-green?style=flat-square)

---

## Features

1. **Circular Floating Bubble:** A clean, borderless, circular webcam bubble that floats over all windows, Terminal, Chrome, code editors, and Full-screen Spaces.
2. **Apple Continuity Camera Support:** Automatically detects and pairs with your connected **iPhone** for studio-grade 4K facecam, or defaults to your built-in Mac camera.
3. **Instant Full-Screen Toggle (Intro / Outro Mode):** Seamlessly transition between a small corner bubble and full-screen video with a simple double-click or by pressing `F` / `Space`. Designed specifically for YouTube and tutorial intros/outros.
4. **Smooth Trackpad Resizing:** Scroll up or down with two fingers over the bubble to resize dynamically from 130px up to 650px.
5. **Keyboard Shortcuts:** Quick presets (`1`, `2`, `3`), full screen toggle (`F` / `Space`), and dismiss (`Esc`).
6. **macOS Menu Bar Quick Controls:** Status bar item in the macOS menu bar for quick switching, camera selection, and resizing.
7. **Zero Bloat & Zero CPU Overhead:** Built entirely with native AppKit and AVFoundation. No Electron, no web runtime, and zero battery drain.

---

## Shortcuts & Controls

| Action | Shortcut / Gesture |
| :--- | :--- |
| **Toggle Full Screen / Bubble** | **Double Click** or **`F`** / **`Space`** |
| **Exit Full Screen** | **`Esc`** or **Double Click** |
| **Smooth Resize** | **Trackpad Two-Finger Scroll** (Up / Down) |
| **Small Bubble (170px)** | **`1`** |
| **Medium Bubble (280px)** | **`2`** |
| **Large Bubble (420px)** | **`3`** |
| **Move Anywhere** | **Click & Drag** anywhere on the bubble |
| **Toggle White Border** | Right-click Menu or **`B`** |
| **Switch Camera Source** | Right-click Menu or Menu Bar icon |
| **Quit App** | **`Q`** (when focused) or Right-click Menu |

---

## Installation

### Prerequisites
**•** macOS 14.0 or later (Apple Silicon or Intel)  
**•** Xcode Command Line Tools (`xcode-select --install`)

### Build & Install from Source
Clone the repository and run the build script:

```bash
git clone https://github.com/shyamukumawat/mac-bubble-camera.git
cd mac-bubble-camera
./build.sh
```

The script compiles the Swift source into a native macOS app bundle and installs it directly into `/Applications/CameraBubble.app`.

---

## How to Launch

1. Press **`Cmd + Space`** (Spotlight).
2. Type **`CameraBubble`** and hit **Enter**.
3. The floating bubble appears on your screen instantly.

---

## Recommended Tech Creator Stack

Combine **CameraBubble** with:
**•** **Screen Recording:** macOS Native Recorder (`Cmd + Shift + 5`)  
**•** **Whiteboard / Diagrams:** [Excalidraw](https://excalidraw.com)  
**•** **Audio:** AirPods Pro or dedicated USB microphone  
**•** **Post-Editing:** CapCut Desktop (for auto-captions and noise reduction) or DaVinci Resolve  

---

## License

This project is licensed under the [MIT License](LICENSE).
