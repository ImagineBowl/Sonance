# Sonance

A native iOS instrument tuner built with SwiftUI. Sonance listens through the microphone, detects pitch in real time, and displays tuning feedback on a curved gauge.

## Features

- Real-time chromatic tuning (A440 reference)
- Note name with octave display (e.g. B4)
- Cent offset and frequency (Hz) readout
- Color-coded background (in tune / close / out of tune)
- Animated needle gauge with spring physics
- FFT + autocorrelation pitch detection for sub-cent accuracy
- Microphone permission handling with a clear denied state
- Start / stop control for the audio engine

## Requirements

- Xcode 16.2+
- iOS 18.2+
- iPhone or iPad with a microphone

## Getting Started

1. Clone the repository:
   ```bash
   git clone https://github.com/ImagineBowl/Sonance.git
   cd Sonance
   ```
2. Open `Sonance.xcodeproj` in Xcode.
3. Select a device or simulator target.
4. Build and run (`Cmd + R`).

Microphone access is required. The app requests permission on first launch.

## Project Structure

```
Sonance/
├── SonanceApp.swift              # App entry point
├── Utils/
│   ├── BVAudioAnalyzer.swift     # Pitch detection (AudioAnalyzer)
│   └── TunerConfig.swift         # Tuner constants and thresholds
├── Views/
│   ├── TunerView.swift           # Main tuner UI
│   ├── BVCustomTunerNeedleView.swift
│   └── ArcShape.swift            # Gauge arc shape
└── Assets.xcassets/              # Colors, app icon
```

## How It Works

1. **Capture** — `AVAudioEngine` taps the microphone input.
2. **Analyze** — A Hanning-windowed FFT finds the rough pitch.
3. **Refine** — Normalized autocorrelation fine-tunes the frequency in the time domain.
4. **Display** — The detected frequency is mapped to the nearest note and cent offset.

Tuning thresholds:

| State      | Offset     |
|------------|------------|
| In tune    | ≤ 5 cents  |
| Close      | ≤ 15 cents |
| Out of tune| > 15 cents |

## Branches

| Branch                    | Purpose                          |
|---------------------------|----------------------------------|
| `main`                    | Stable release branch            |
| `develop`                 | Active development               |
| `feature/audio-reliability` | Audio pipeline improvements  |
| `feature/tuner-improvements`  | Tuner UI and UX enhancements |

## License

This project is licensed under the MIT License — see [LICENSE](LICENSE) for details.
