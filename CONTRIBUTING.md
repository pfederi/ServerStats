# Contributing to ServerStats

Thanks for your interest in contributing!

## Getting Started

1. Fork the repository
2. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
3. Generate the project: `xcodegen generate`
4. Open `ServerStats.xcodeproj` in Xcode
5. Build and run (`Cmd+R`)

## Development

- **Project config** is managed via `project.yml` — don't edit `.xcodeproj` directly
- After changing `project.yml` or adding/removing source files, run `xcodegen generate`
- The `.xcodeproj` is gitignored since it's generated

## Code Style

- Follow existing patterns in the codebase
- SwiftUI for all views
- Keep files focused — one responsibility per file
- Use meaningful names

## Testing

```bash
xcodebuild test -scheme ServerStats -destination 'platform=macOS'
```

## Pull Requests

- Keep PRs focused on a single change
- Include screenshots for UI changes
- Make sure tests pass
- Fill out the PR template

## Reporting Issues

Use the [issue templates](https://github.com/pfederi/ServerStats/issues/new/choose) — they help us understand and fix problems faster.
