# Repository Guidelines

## Project Structure & Data Model
SwiftUI sources live in `RunDaddy/`. `RunDaddyApp.swift` owns scene setup and the shared SwiftData container. Define `Run` (name) and `InventoryItem` (name, count, run) models in `RunDaddy/Models/`. Keep view logic under `RunDaddy/Features/` (Import, Session, History), shared services (CSV parser, speech coordinator) in `RunDaddy/Services/`, and assets in `RunDaddy/Assets.xcassets`.

## Packing Session Workflow
Import a CSV using `FileImporter` validated with `UniformTypeIdentifiers`. The file name becomes the `Run` name; each row persists as an `InventoryItem` linked to that run. A packing session reads the current line aloud via `AVSpeechSynthesizer`, listens for “next line” with `SFSpeechRecognizer`, then advances. Provide onscreen replay/skip buttons and a progress indicator so noisy environments remain usable. All ingestion, speech, and persistence logic must rely on first-party APIs.

## Build, Test, and Development Commands
- `open RunDaddy.xcodeproj` opens the project targeting iOS 26 per requirement.
- `xcodebuild -scheme RunDaddy -destination 'platform=iOS Simulator,name=iPhone 15' build` performs CI-friendly validation.
- `xcodebuild -scheme RunDaddy -destination 'platform=iOS Simulator,name=iPhone 15' test` runs XCTest suites once the targets exist.

## Coding Style & Naming Conventions
Follow Swift API Design Guidelines: PascalCase types (`Run`, `InventoryItem`), camelCase properties, imperative method names. Use 4-space indentation, braces on the same line, and scope access control explicitly. Annotate models with `@Model` plus `@Relationship`, and keep views thin by delegating CSV parsing and speech control to dedicated service types.

## Testing Guidelines
Create `RunDaddyTests` and `RunDaddyUITests`, grouping files by feature. Cover CSV parsing (valid headers, malformed rows), SwiftData persistence (run-item linkage), and speech flow by mocking recognizer callbacks. Run `xcodebuild … test` before pushing and capture simulator logs if permissions affect outcomes.

## Commit & Pull Request Guidelines
Write imperative, component-focused commits (`SessionView: handle next line command`). Document schema updates or permission prompts in the body. Pull requests should describe the voice-driven impact, reference issues, and include clips or screenshots of the session UI; call out migration or permission steps reviewers must repeat.

## Configuration & Environment Notes
Pin `IPHONEOS_DEPLOYMENT_TARGET` and CI simulators to iOS 26 until the SDK changes. Request microphone and speech recognition permissions on launch, configure `AVAudioSession` for play-and-record, and keep `Info.plist` entitlements documented. Stay within Foundation, Speech, AVFoundation, and SwiftData to honor the first-party-only rule.
