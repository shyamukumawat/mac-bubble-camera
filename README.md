# CameraBubble

> A lightweight (~1MB), zero-bloat, native macOS floating circular camera bubble designed for tech content creators, developers, and educators.

![macOS](https://img.shields.io/badge/platform-macOS%2014.0%2B-black?style=flat-square&logo=apple)
![Swift](https://img.shields.io/badge/built%20with-Swift-FA7343?style=flat-square&logo=swift)
![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)
![Size](https://img.shields.io/badge/binary%20size-~1MB-green?style=flat-square)

---

## Features

1. **Multiple Shapes (Circle, 16:9 Landscape, 9:16 Portrait Shorts/Reels, 4:3, Rounded Square):** Switch instantly between a circular bubble, standard 16:9 widescreen, 9:16 vertical portrait (for TikTok, Instagram Reels, and YouTube Shorts), 4:3 standard, or rounded square.
2. **AI Virtual Background & Custom Image Replacement:** Replace the room background behind you in real time using Apple's Neural Engine Vision person segmentation. Choose any custom image file (`.png`, `.jpg`, `.jpeg`, `.heic`), background blur, or sleek studio gradients.
3. **Interactive Edge & Corner Drag Resizing:** Hover near any edge or corner to see dynamic resize cursors. Drag left/right to adjust width, top/bottom to adjust height, or drag corners to extend both. Hold `Shift` while dragging to lock aspect ratio.
4. **Apple Continuity Camera Support:** Automatically detects and pairs with your connected **iPhone** for studio-grade 4K facecam, or defaults to your built-in Mac camera.
5. **Instant Full-Screen Toggle (Intro / Outro Mode):** Seamlessly transition between a small corner bubble and full-screen video with a simple double-click or by pressing `F` / `Space`. Designed specifically for YouTube and tutorial intros/outros.
6. **Smooth Trackpad Resizing:** Scroll up or down with two fingers over the bubble to resize dynamically from 120px up to 900px while maintaining the correct aspect ratio.
7. **Keyboard Shortcuts:** Quick presets (`1`, `2`, `3`), shape toggle (`S`), background cycle (`V`), background style toggle (`G`), full screen toggle (`F` / `Space`), white border toggle (`B`), and dismiss (`Esc`).
8. **macOS Menu Bar Quick Controls:** Status bar item in the macOS menu bar for quick switching, shape selection, background style & image selection, camera selection, and resizing.
9. **Zero Bloat & Zero CPU Overhead:** Built entirely with native AppKit, AVFoundation, and Apple Vision framework. No Electron, no web runtime, and zero battery drain.

---

## Shortcuts & Controls

| Action | Shortcut / Gesture |
| :--- | :--- |
| **Move Anywhere** | **Click & Drag** inside the bubble |
| **Adjust Width / Height** | **Drag Edges / Corners** (hover over border to see resize cursor) |
| **Lock Aspect Ratio while Dragging** | Hold **`Shift`** while dragging edge or corner |
| **Switch Shape (16:9 / 9:16 / Circle / Square)** | **`S`** or Right-click Menu / Menu Bar |
| **Cycle Background Preset** | **`V`** or Right-click Menu / Menu Bar |
| **Toggle Background Style (Backdrop Frame ⇄ AI Cutout)** | **`G`** or Right-click Menu / Menu Bar |
| **Set Custom Background Image** | Right-click Menu ➔ **Background** ➔ **Choose Custom Image...** |
| **Toggle Full Screen / Bubble** | **Double Click** or **`F`** / **`Space`** |
| **Exit Full Screen** | **`Esc`** or **Double Click** |
| **Smooth Resize** | **Trackpad Two-Finger Scroll** (Up / Down) |
| **Small Preset** | **`1`** |
| **Medium Preset** | **`2`** |
| **Large Preset** | **`3`** |
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
