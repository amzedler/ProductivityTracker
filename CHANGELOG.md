# Changelog

All notable changes to ProductivityTracker will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added - 2026-02-26

#### Menu Bar Enhancements
- **Real-time tracking duration display in menu bar toolbar** - Duration now displays directly next to the menu bar icon, not just in the popup menu
- **Live duration updates** - Tracking duration updates every 10 seconds while capturing
- **Status indicator** - Red recording icon when tracking is active, clock icon when idle
- **Formatted duration display** - Shows duration as "Xh Ym" in monospaced font for stable display

#### UI/UX Improvements
- **Redesigned Settings and Quit buttons** - Replaced small buttons with larger, more prominent styled buttons
  - Settings button: Large gray background with gear icon + "Settings" label
  - Quit button: Large red-tinted background with power icon + "Quit" label
  - Increased touch targets for better accessibility
- **Enhanced popup menu header** - Shows tracking status with visual indicators:
  - Green dot + "Tracking: Xh Ym" when active
  - "Tracked today: Xh Ym" when inactive (if duration > 0)
  - "Not tracking" when idle with no time tracked

#### Visual Identity
- **Custom 3D app icon** - Beautiful gradient logo (blue→purple→teal) featuring clock, charts, and data visualization elements
- **Multi-resolution icon set** - Complete icon set for all macOS sizes:
  - 16x16, 32x32, 64x64, 128x128, 256x256, 512x512, 1024x1024
  - 1x and 2x variants for Retina displays
- **Icon appears throughout macOS**:
  - Application Dock
  - Finder
  - Launchpad
  - App Switcher (Cmd+Tab)
  - "About" window

### Changed - 2026-02-26

#### Core State Management
- Extended `AppState` with tracking duration functionality:
  - New `todayTrackingDuration` property (TimeInterval)
  - Timer-based duration updates (every 10 seconds during tracking)
  - Automatic duration calculation from daily sessions
  - Duration persists across app restarts (calculated from database)

#### Menu Bar Widget
- Transformed MenuBarExtra label from static icon to dynamic HStack:
  - Icon (changes based on tracking state)
  - Duration text (appears when duration > 0)
- Improved visual hierarchy in popup menu
- Better spacing and alignment throughout menu bar UI

### Technical Details

#### Files Modified
- `ProductivityTracker/ProductivityTrackerApp.swift`
  - Added `todayTrackingDuration: TimeInterval` to AppState
  - Added `durationUpdateTimer: Timer?` for periodic updates
  - Modified `startCapturing()` to start duration timer
  - Modified `stopCapturing()` to stop duration timer and refresh
  - Added `updateTodayTrackingDuration()` async method
  - Added `formatToolbarDuration()` helper for toolbar display
  - Modified MenuBarExtra label to show duration dynamically

- `ProductivityTracker/UI/MenuBarView.swift`
  - Updated `headerSection` to show tracking status with indicators
  - Redesigned `footerSection` with larger, styled buttons
  - Added `formatDuration()` helper method
  - Improved visual consistency across all menu sections

#### Assets Added
- `ProductivityTracker/Assets.xcassets/AppIcon.appiconset/`
  - Contents.json (icon configuration)
  - icon_16x16.png through icon_512x512@2x.png
  - icon-original.png (1024x1024 source)

#### Build Configuration
- Asset catalog properly configured with `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`
- All icon files added to Resources build phase
- Assets.xcassets integrated into project structure

### Design Rationale

#### Menu Bar Duration Display
The duration display in the menu bar toolbar (not just popup) was added because:
- Users need at-a-glance visibility of tracking time without clicking
- Helps users stay aware of productivity time throughout the day
- Common pattern in time-tracking and productivity apps
- Minimal space usage with compact formatting

#### Larger Action Buttons
Settings and Quit buttons were enlarged because:
- Original buttons were too small for easy interaction
- Improved accessibility for users with motor control challenges
- Better visual hierarchy (primary actions more prominent)
- Follows macOS Human Interface Guidelines for touch targets

#### SF Symbols in Menu Bar
Custom icon not used in menu bar because:
- SF Symbols are optimized for small sizes (16x16, 32x32)
- Automatic adaptation to light/dark mode
- Better rendering at menu bar scale
- System consistency with other macOS apps

Custom 3D icon appears everywhere else (Dock, Finder, etc.) where larger sizes allow the gradient and details to shine.

---

## Previous Features

For documentation of earlier features including Claude-powered dynamic reporting, see:
- [IMPLEMENTATION_SUMMARY.md](./IMPLEMENTATION_SUMMARY.md) - Claude AI integration details
- [QUICK_START.md](./QUICK_START.md) - Quick start guide for main features
