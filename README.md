# File Converter

A small Mac app for converting worship files: multitrack WAVs to MP3 practice
tracks, PDF charts to JPGs, and a few other formats.

## Using it

Drop files or folders on the window or on the Dock icon, pick a format, press
Convert.

- **A folder** gets a new folder inside it named for the format (`MP3s`,
  `JPGs`, …) holding the converted files. Only the files directly in the folder
  are converted, not subfolders. Files already in the chosen format are left
  alone.
- **One file** opens a save dialog, so you choose where it goes and what it's
  called.
- **Several loose files** ask once for a folder to save them all in.
- Converting again replaces files with the same name in the output folder.

| From | To |
| --- | --- |
| WAV, AIFF, FLAC, M4A, MP3 | MP3, M4A (AAC 256 kbps), WAV, AIFF |
| PDF, PNG, JPG, HEIC, TIFF and other images | JPG, PNG |

**MP3s** are constant bitrate (320, 256 or 192 kbps; 320 is the default) so
every stem of a multitrack stays the same length and in sync. Files with more
than two channels are mixed down to stereo.

**PDFs** are rendered at 300 DPI. A one-page PDF keeps the name you choose; a
longer one is saved as `Name-1.jpg`, `Name-2.jpg` and so on. JPGs get a white
background where the original was transparent.

Several files convert at once, one per processor core.

## Building

Needs Xcode and `brew install lame`.

```bash
./scripts/build-app.sh            # builds dist/File Converter.app
./scripts/build-app.sh --install  # and copies it to /Applications
```

The build copies LAME (the MP3 encoder) and the one Homebrew library it links
into the app, so the app itself doesn't need Homebrew. Other audio goes through
macOS's own `afconvert`; images and PDFs through ImageIO and Core Graphics.

The app is signed ad hoc, which is fine on the Mac that built it. To hand it to
someone else it would need a Developer ID signature and notarization.

`scripts/make-icon.swift` redraws `Resources/AppIcon.icns`.

## Code

- `Sources/FileConverter/Formats.swift` — file kinds, output formats, MP3 bitrates
- `Sources/FileConverter/Engine.swift` — the conversions (LAME, afconvert, ImageIO, PDF rendering)
- `Sources/FileConverter/ConverterModel.swift` — what was dropped, where outputs go, the job queue
- `Sources/FileConverter/ContentView.swift` — the window
