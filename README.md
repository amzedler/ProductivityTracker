# ProductivityTracker

A macOS menu bar application that intelligently tracks your productivity using AI-powered analysis.

## Overview

ProductivityTracker is a native macOS app that lives in your menu bar and automatically tracks your work sessions. Unlike traditional time trackers, it uses Claude AI to provide intelligent, adaptive insights about your work patterns and productivity.

## Key Features

### Real-Time Activity Tracking
- **Automatic window and app monitoring** - Tracks what you're working on without manual input
- **Session management** - Groups related work into meaningful sessions
- **Context detection** - Identifies concurrent contexts and work patterns
- **Menu bar widget** - Shows current tracking status and today's total time at a glance

### Claude-Powered AI Analysis
- **Dynamic work segmentation** - Claude discovers natural work patterns instead of forcing predefined categories
- **Conversational insights** - Ask follow-up questions about your productivity data
- **Adaptive learning** - Provide feedback to improve future analyses
- **Smart caching** - Efficient analysis with automatic once-per-day updates

### Productivity Insights
- **Work segment analysis** - Identify periods of deep focus vs. fragmented work
- **Context switching detection** - Understand how often you switch between tasks
- **Focus quality assessment** - Claude evaluates the quality of your work sessions
- **Actionable recommendations** - Get specific suggestions to improve productivity

### Privacy & Data
- **Local-first** - All session data stored in local SQLite database
- **Optional AI processing** - Analysis only happens when you request it
- **Your data, your control** - Complete ownership of all tracking data

## Menu Bar Features

The menu bar widget provides quick access to:

- **Live tracking indicator**
  - Red recording icon when tracking is active
  - Clock icon when idle
  - Current session duration displayed

- **Today's tracking time** - See total tracked time without opening the full app

- **Quick actions**
  - Start/Stop tracking with one click
  - Open full dashboard
  - Review AI suggestions
  - Access settings

- **Enhanced buttons** - Large, clear Settings and Quit buttons for easy access

## Visual Design

ProductivityTracker features a custom 3D app icon with a beautiful blue→purple→teal gradient, incorporating clock, charts, and data visualization elements that represent the app's purpose.

The icon appears throughout macOS:
- Application Dock
- Finder windows
- Launchpad
- App Switcher (Cmd+Tab)

The menu bar uses SF Symbols for optimal rendering at small sizes and automatic light/dark mode adaptation.

## Technical Stack

- **Platform**: macOS 14.0+
- **Language**: Swift 5.9+ with SwiftUI
- **Database**: SQLite with GRDB
- **AI Integration**: Claude API (Anthropic)
- **Architecture**: MVVM with service layer

## Documentation

- **[CHANGELOG.md](./CHANGELOG.md)** - Recent changes and improvements
- **[IMPLEMENTATION_SUMMARY.md](./IMPLEMENTATION_SUMMARY.md)** - Detailed technical implementation of AI features
- **[QUICK_START.md](./QUICK_START.md)** - Quick start guide for building and testing
- **[ADD_FILES_TO_XCODE.md](./ADD_FILES_TO_XCODE.md)** - Instructions for adding files to Xcode project

## Getting Started

### Prerequisites

- macOS 14.0 or later
- Xcode 15.0 or later
- Claude API key (from Anthropic)

### Building the Project

1. Clone the repository
2. Open `ProductivityTracker.xcodeproj` in Xcode
3. Add your Claude API key to the app settings
4. Build and run (Cmd+R)

See [QUICK_START.md](./QUICK_START.md) for detailed build instructions.

## Usage

1. **Start Tracking**
   - Click the menu bar icon
   - Click "Start Tracking"
   - Work normally - the app monitors your active windows

2. **View Live Status**
   - Check menu bar for current session and duration
   - Duration updates every 10 seconds while tracking

3. **Analyze Your Day**
   - Open the Dashboard
   - Click "Analyze My Day"
   - Claude provides structured insights about your work patterns

4. **Ask Questions**
   - Use the question input to drill deeper
   - "What was my longest focus period?"
   - "How can I reduce context switching?"

5. **Provide Feedback**
   - Click "Give Feedback" on any analysis
   - Tell Claude what could be improved
   - Future analyses incorporate your feedback

## Project Structure

```
ProductivityTracker/
├── ProductivityTracker/
│   ├── Models/              # Data models
│   │   ├── ActivitySession.swift
│   │   ├── ComprehensiveAnalysis.swift
│   │   └── ...
│   ├── Services/            # Business logic
│   │   ├── CaptureService.swift
│   │   ├── StorageManager.swift
│   │   ├── ClaudeAPIClient.swift
│   │   ├── ComprehensiveAnalyzer.swift
│   │   └── ...
│   ├── UI/                  # SwiftUI views
│   │   ├── MenuBarView.swift
│   │   ├── DashboardView.swift
│   │   ├── AIAnalysisView.swift
│   │   └── ...
│   └── Assets.xcassets/     # Images and icons
└── Documentation/
    ├── README.md
    ├── CHANGELOG.md
    ├── IMPLEMENTATION_SUMMARY.md
    └── QUICK_START.md
```

## Key Components

### AppState
Global application state manager that coordinates:
- Capture service (window monitoring)
- Storage manager (database)
- Window focus monitor
- AI categorization
- UI state (tracking status, duration, etc.)

### CaptureService
Handles automatic activity tracking:
- Monitor active applications
- Track window titles and durations
- Create and manage sessions
- Capture input statistics

### ComprehensiveAnalyzer
Orchestrates AI-powered analysis:
- Sends session data to Claude
- Processes structured analysis responses
- Handles follow-up questions
- Manages feedback loop

### StorageManager
SQLite database interface with GRDB:
- Session storage and retrieval
- Analysis caching
- Feedback persistence
- Efficient querying with indexes

## Recent Updates (2026-02-26)

### Menu Bar Enhancements
- Duration now shows in toolbar (not just popup)
- Live updates every 10 seconds
- Red recording indicator when tracking
- Formatted duration display (Xh Ym)

### UI Improvements
- Larger, more prominent Settings and Quit buttons
- Better visual hierarchy in popup menu
- Enhanced tracking status indicators
- Improved spacing and layout

### Visual Identity
- Custom 3D gradient app icon
- Complete multi-resolution icon set
- Professional branding throughout macOS

See [CHANGELOG.md](./CHANGELOG.md) for complete details.

## Development

### Adding New Features

1. Create models in `Models/` folder
2. Implement business logic in `Services/`
3. Build UI in `UI/` folder
4. Update database schema in `StorageManager` if needed
5. Add to Xcode project (see [ADD_FILES_TO_XCODE.md](./ADD_FILES_TO_XCODE.md))

### Testing

Run the app in Xcode and:
- Generate test sessions by working normally
- Use the Dashboard to verify data capture
- Test AI analysis with "Analyze My Day"
- Verify all menu bar interactions work

### Database Schema

The app uses SQLite with these main tables:
- `activity_sessions` - Individual work sessions
- `comprehensive_analyses` - Cached AI analyses
- `ai_feedback` - User feedback for learning
- `ai_suggestions` - Categorization suggestions

See [IMPLEMENTATION_SUMMARY.md](./IMPLEMENTATION_SUMMARY.md) for schema details.

## AI Integration

ProductivityTracker uses Claude (Anthropic) for intelligent analysis:

### What Claude Does
- Analyzes session data to identify natural work segments
- Assesses focus quality for each segment
- Identifies context switching patterns
- Generates specific, actionable insights
- Provides personalized recommendations
- Answers follow-up questions about your data

### Cost Considerations
- One cached analysis per day (~$0.015)
- Follow-up questions are optional
- Estimated ~$0.45/month for daily use
- All data locally stored

### Privacy
- Session data only sent to Claude when you request analysis
- No automatic background uploads
- Analysis results cached locally
- You control when and what to analyze

## Benefits

### vs Traditional Time Trackers
- **No manual input** - Automatic tracking
- **Intelligent segmentation** - AI discovers patterns
- **Conversational** - Ask questions naturally
- **Adaptive** - Learns from your feedback

### vs Generic Analytics
- **Personalized** - Adapts to YOUR work patterns
- **Specific** - Concrete insights, not generic platitudes
- **Actionable** - Clear recommendations you can implement
- **Contextual** - Understands your actual work, not just app names

## Roadmap

Potential future enhancements:
- Export analyses as PDF/Markdown
- Historical comparisons ("Compare to last week")
- Goal tracking and progress monitoring
- Proactive analysis suggestions
- Team collaboration features
- Voice feedback input
- Custom AI prompts and analysis templates

## Contributing

This is a personal project, but suggestions and feedback are welcome!

## License

[Add your license here]

## Acknowledgments

- Built with [Claude](https://claude.ai) by Anthropic
- Uses [GRDB](https://github.com/groue/GRDB.swift) for SQLite
- Icon designed with AI assistance
- SwiftUI for modern macOS UI

---

**ProductivityTracker** - Know your work. Improve your focus.
