# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

xterm.dart is a fast and fully-featured terminal emulator for Flutter applications, designed for mobile and desktop platforms. The project follows a layered architecture with clear separation between core terminal logic and UI presentation.

## Commands

### Development
- `flutter pub get` - Install dependencies
- `flutter test --coverage` - Run all tests with coverage
- `flutter analyze --fatal-infos` - Run static analysis (used in CI)
- `dart format --set-exit-if-changed .` - Format code and fail if changes needed

### Example App
- `cd example && flutter pub get` - Set up example app
- `cd example && flutter run` - Run the example terminal application

## Architecture

### Core Structure
The codebase is organized into distinct layers:

- **Core (`lib/core.dart`)**: Terminal emulation logic independent of Flutter
  - `buffer/`: Terminal buffer management (lines, cells, segments, ranges)
  - `escape/`: ANSI escape sequence parsing and handling
  - `input/`: Keyboard input handling and keytab mappings
  - `mouse/`: Mouse input handling and reporting modes
  - `terminal.dart`: Main Terminal class that orchestrates core functionality

- **UI (`lib/ui.dart`)**: Flutter-specific presentation layer
  - `terminal_view.dart`: Main widget for displaying terminal
  - `painter.dart`: Custom painter for terminal rendering
  - `controller.dart`: UI state management
  - `shortcut/`: Keyboard shortcuts integration
  - `gesture/`: Touch and mouse gesture handling

- **Utils (`lib/utils.dart`)**: Shared utilities and data structures

### Key Components

**Terminal Core**: The `Terminal` class in `src/terminal.dart` is the main entry point that manages terminal state, buffer operations, and I/O processing. It's designed to work independently of Flutter.

**Buffer Management**: Multi-layered buffer system supporting:
- Line-based storage with segments
- Cell-based character and attribute storage
- Range selection (block and line modes)
- Reflow for terminal resizing

**Escape Sequence Processing**: Robust ANSI/VT parser that handles:
- Control sequences (CSI, OSC, ESC)
- Character set handling
- Terminal modes and features

**UI Rendering**: High-performance custom painter with:
- Paragraph-based text rendering with caching
- Selection highlighting
- Cursor rendering with multiple styles
- Theme system support

## Testing

Tests are organized by component:
- `test/src/core/` - Core terminal logic tests
- `test/src/` - General component tests
- `test/terminal/` - Integration tests
- Uses `mockito` for mocking in some tests

## Key Development Notes

- The core terminal logic is Flutter-independent and could theoretically work with other UI frameworks
- Performance is critical - the terminal renders at 60fps with custom painting
- The buffer system supports terminal reflow (resizing) which is complex
- Input handling supports both keyboard shortcuts and complex keytab mappings
- Mouse support includes various reporting modes (X10, X11, SGR, etc.)
- The package exports three main APIs: `xterm.dart` (full), `core.dart` (core only), and `ui.dart` (UI components)