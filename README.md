# Speckit Starter for Apple Platforms

A starter template for building iOS/macOS applications using **Clean Architecture** principles with AI-assisted development workflows powered by [spec-kit](https://github.com/github/spec-kit).

## What's Included

- **Constitution** (`.specify/memory/constitution.md`) - Clean Architecture principles tailored for Apple platforms:
  - Dependency Rule (inward dependencies)
  - Layer Separation (Entities, Domain, Data, Presentation)
  - Protocol-Driven Design
  - ViewModel-Only Testing with TDD
  - Hybrid Repository Architecture (OpenAPI + CoreData)
  - XcodeGen & Carthage tooling

- **Workflows** (`.windsurf/workflows/`) - AI-assisted development workflows:
  - `qortex.project-setup` - Initial project setup
  - `qortex.testing` - TDD and ViewModel testing patterns
  - `qortex.openapi-clean-architecture` - OpenAPI integration patterns

## Quick Start

### Installation

Run this command in your existing Apple project directory:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/theplant/speckit-starter-apple/HEAD/install.sh)"
```


### Prerequisites

- **Xcode** 15.0+ (for iOS 17 / macOS 14 deployment targets)
- **Homebrew** (for installing dependencies)
- **uv** (Python package manager, installed automatically by `install.sh`)

### Recommended Tools

```bash
# Install XcodeGen for project generation
brew install xcodegen

# Install Carthage for dependency management
brew install carthage
```

## Usage with Windsurf

Once installed, use the workflows in Windsurf:

1. **Start a new feature**: `/speckit.specify` - Describe your feature and generate a spec
2. **Plan implementation**: `/speckit.plan` - Create a design and implementation plan
3. **Generate tasks**: `/speckit.tasks` - Break down into actionable tasks
4. **Implement**: `/speckit.implement` - Execute tasks with TDD

### Example Workflow

```
You: /speckit.specify Create a notes app with folders and tags

AI: [Creates .specify/features/notes-app/spec.md]

You: /speckit.plan

AI: [Creates .specify/features/notes-app/plan.md]

You: /speckit.tasks

AI: [Creates .specify/features/notes-app/tasks.md]

You: /speckit.implement

AI: [Implements with TDD - tests first, then code]
```

## Architecture Overview

```
[AppName]/
├── Entities/           # Pure business objects
│   └── Models/
├── Domain/             # Use cases and protocols
│   ├── UseCases/
│   └── Interfaces/
├── Data/               # Implementations
│   ├── Repositories/
│   ├── API/            # OpenAPI generated code
│   └── Persistence/    # CoreData
├── Presentation/       # UI layer
│   ├── Views/
│   ├── ViewModels/
│   └── Coordinators/
└── DI/                 # Dependency injection

[AppName]Tests/
├── Seeds/              # Shared test data
├── Integration/        # ViewModel tests
└── Helpers/            # Test utilities
```

## Key Principles

### ViewModel-Only Testing

Tests only call ViewModel methods, never repositories directly:

```swift
// ✅ Correct
func testCreateNote() async throws {
    let container = TestDependencyContainer()
    let viewModel = container.makeNoteEditorViewModel()
    
    await viewModel.createNote(content: "Test")
    
    XCTAssertNotNil(viewModel.note)
}

// ❌ Wrong - don't call repository in tests
let note = try await repository.create(content: "Test")
```

### Hybrid Repository Architecture

- **OpenAPI Repositories** - For sync-capable data (notes, folders)
- **Direct CoreData Repositories** - For local-only data (settings, cache)

## Platform Requirements

| Platform | Minimum Version |
|----------|-----------------|
| iOS | 17.0 |
| macOS | 14.0 (Sonoma) |
| watchOS | 10.0 |
| tvOS | 17.0 |
| visionOS | 1.0 |

## License

MIT License - see [LICENSE](LICENSE) for details.
