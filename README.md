# Whisprlocal

A macOS menu bar application for real-time audio transcription using Whisper.cpp, optimized for Apple Silicon.

## Features

- 🎤 Real-time audio transcription
- 🔄 Multiple Whisper model support (tiny, base, small)
- 🌍 Support for multiple languages
- 📋 Easy copy-paste of transcriptions
- ⚡️ Optimized for Apple Silicon
- 🎯 Native macOS menu bar integration

## Requirements

- macOS 14.0 or later
- Apple Silicon Mac (M1/M2/M3)
- Xcode 15.0 or later for development

## Installation

1. Clone the repository
2. Open `whisprlocal.xcodeproj` in Xcode
3. Build and run the project

## Usage

1. Launch the app - it will appear in your menu bar
2. Open Preferences (⌘,) and download a Whisper model
3. Click the menu bar icon to start/stop recording
4. View transcriptions in real-time
5. Copy transcriptions to clipboard with optional timestamps

## Models

Available Whisper models:

- Tiny (English) - Fast, less accurate
- Base (English) - Good balance of speed and accuracy
- Small (English) - Most accurate, slower
- Tiny (Multilingual) - Support for multiple languages
- Base (Multilingual) - Better multilingual support

## Development

The project uses SwiftUI and AVFoundation for the frontend and audio capture, with SwiftWhisper for transcription. Key components:

- `TranscriptionManager`: Handles Whisper model loading and transcription
- `AudioRecorder`: Manages audio capture and processing
- `ModelManager`: Handles model downloading and management

## Project Structure 
whisprlocal/
├── Audio/
│   └── AudioRecorder.swift        # Audio capture implementation
├── Models/
│   └── ModelManager.swift         # Model management
├── Views/
│   ├── ContentView.swift          # Main UI
│   ├── PreferencesView.swift      # Settings UI
│   └── DownloadButton.swift       # Model download UI
└── TranscriptionManager.swift     # Core transcription logic


## Building from Source

1. Ensure you have Xcode 15.0+ installed
2. Clone the repository
3. Open `whisprlocal.xcodeproj`
4. Select your development team in project settings
5. Build and run (⌘R)

## Dependencies

- [SwiftWhisper](https://github.com/exPHAT/SwiftWhisper) - Swift wrapper for Whisper.cpp

## Privacy

The app processes all audio locally on your device. No data is sent to external servers. Required permissions:

- Microphone access
- Disk access (for model storage)

## License

MIT License

Copyright (c) 2024

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Acknowledgments

- [Whisper](https://github.com/openai/whisper) by OpenAI
- [Whisper.cpp](https://github.com/ggerganov/whisper.cpp) for the optimized C++ implementation
- [SwiftWhisper](https://github.com/exPHAT/SwiftWhisper) for the Swift wrapper