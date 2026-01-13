<!--
Sync Impact Report
==================
- Version change: 5.0.0 → 5.1.0 (MINOR: Hybrid repository approach)
- Modified principles:
  - VII. OpenAPI-Unified Architecture → VII. Hybrid Repository Architecture
- Modified sections:
  - Repository Strategy: OpenAPI for sync-capable data, direct CoreData for local-only data
  - Added guidance on when to use each approach
- Templates requiring updates: ✅ reviewed (no updates needed - templates are generic)
- Follow-up TODOs: None
- Rationale: Not all data needs remote sync. Local-only data (settings, cache, drafts) should use
  direct CoreData for simplicity. Sync-capable data (notes, folders) uses OpenAPI for remote/local.
-->

# Apple Platform Clean Architecture Constitution

## Core Principles

### I. Dependency Rule (Inward Dependencies)

Source code dependencies MUST only point inward. Inner layers MUST NOT know anything about outer layers.

- **Entities** MUST NOT import Domain, Data, or Presentation code
- **Domain (Use Cases)** MUST NOT import Data or Presentation code
- **Data** MUST NOT import Presentation code
- **Presentation** MAY import all inner layers through protocols

**Rationale**: This rule ensures the core business logic remains independent of frameworks, UI, and external services, enabling the system to be testable, maintainable, and adaptable to change.

### II. Layer Separation

The application MUST be organized into four distinct layers:

- **Entities**: Enterprise-wide business objects and rules. Pure Swift structs/classes with no framework dependencies.
- **Domain (Use Cases)**: Application-specific business rules. Orchestrates data flow between entities and implements use case logic.
- **Data**: Repository implementations, network clients, database access. Converts external data formats to/from entities.
- **Presentation**: SwiftUI views, ViewModels, Coordinators. Handles UI logic and user interaction.

**Rationale**: Clear layer boundaries enable independent development, testing, and replacement of components without affecting other parts of the system.

### III. Protocol-Driven Design

All layer boundaries MUST be defined by Swift protocols (interfaces).

- Use Cases MUST define repository protocols that Data layer implements
- Presentation MUST interact with Domain through use case protocols
- Concrete implementations MUST be injected via dependency injection
- No concrete class from an outer layer MAY be referenced by an inner layer

**Rationale**: Protocol boundaries enable mocking for tests, allow swapping implementations (e.g., switching from CoreData to Realm), and enforce the dependency rule at compile time.

### IV. Testability First (ViewModel-Only Testing)

All business logic MUST be testable through ViewModel functions only. **Tests MUST NOT call repository or use case functions directly** - only Seeds are allowed to call repository functions for data setup.

- **Tests MUST only call ViewModel public methods** - this mirrors real user interactions
- **Tests MUST create ViewModels via DependencyContainer** - ensures consistent dependency wiring
- **Seeds are the ONLY place allowed to call repository functions** - for test data setup
- **Entity tests are NOT required** - entities are tested implicitly through ViewModel tests
- **Repository tests are NOT required** - repositories are tested implicitly through ViewModel tests
- **Use Case tests are NOT required** - use cases are tested implicitly through ViewModel tests
- UI tests MUST use the same seeds as integration tests for consistency

**Rationale**: Tests should mirror real app usage. Users interact with ViewModels through the UI, not with repositories directly. By testing only through ViewModels created via DependencyContainer, we ensure the entire stack works together correctly. This catches integration bugs that layer-specific tests would miss.

### V. SOLID Principles

All code MUST adhere to SOLID principles:

- **Single Responsibility**: Each class/struct has one reason to change. Use Cases handle one use case. ViewModels handle one screen.
- **Open-Closed**: Extend behavior through new conformances, not modification. Add new Use Cases rather than modifying existing ones.
- **Liskov Substitution**: Any protocol conformance MUST be substitutable. Test implementations MUST behave consistently with real ones.
- **Interface Segregation**: Protocols MUST be small and focused. Split large protocols into role-specific ones.
- **Dependency Inversion**: High-level modules MUST NOT depend on low-level modules. Both MUST depend on abstractions (protocols).

**Rationale**: SOLID principles are the foundation of Clean Architecture and ensure long-term maintainability.

### VI. Test-Driven Development (TDD)

All features MUST be developed using Test-Driven Development. **Tests MUST be written FIRST and MUST PASS before any human review.**

#### TDD Cycle (Red-Green-Refactor)

1. **RED**: Write a failing test that defines the expected behavior
2. **GREEN**: Write the minimum code to make the test pass
3. **REFACTOR**: Improve the code while keeping tests green

#### AI-Assisted Development Requirements

When AI assists with development, it MUST:

1. **Write thorough tests FIRST** before implementing any feature code
2. **Run all tests** and ensure they compile (RED phase - tests should fail initially)
3. **Implement the feature** to make tests pass
4. **Run all tests again** and verify ALL tests pass (GREEN phase)
5. **Only stop for human review** when all tests are passing

#### Test Coverage Requirements

| Layer | Test Required | Notes |
|-------|---------------|-------|
| ViewModels | YES (90%) | Integration tests via DependencyContainer |
| Entities | NO | Tested implicitly through ViewModel tests |
| Use Cases | NO | Tested implicitly through ViewModel tests |
| Repositories | NO | Tested implicitly through ViewModel tests |

#### Seeds-Based Testing

All tests MUST use a shared `Seeds/` folder. **Only Seeds can call repository functions directly.**

- `TestSeeds.swift` - Factory methods to create test data via repositories
- `TestDependencyContainer.swift` - Test-specific DependencyContainer with in-memory storage
- Seed data MUST be deterministic (fixed UUIDs, dates, content)
- Seeds MUST be usable by both unit tests and UI tests

```swift
// ✅ Correct: TestDependencyContainer for tests
@MainActor
final class TestDependencyContainer {
    let coreDataStack = InMemoryCoreDataStack()
    
    lazy var noteRepository: NoteRepositoryProtocol = NoteRepository(coreDataStack: coreDataStack)
    lazy var folderRepository: FolderRepositoryProtocol = FolderRepository(coreDataStack: coreDataStack)
    
    func makeNoteEditorViewModel(noteId: UUID? = nil, folderId: UUID? = nil) -> NoteEditorViewModel {
        NoteEditorViewModel(
            noteId: noteId,
            folderId: folderId,
            createNoteUseCase: CreateNoteUseCase(repository: noteRepository),
            updateNoteUseCase: UpdateNoteUseCase(repository: noteRepository),
            getNoteUseCase: GetNoteUseCase(repository: noteRepository),
            moveNoteToFolderUseCase: MoveNoteToFolderUseCase(repository: noteRepository),
            getFoldersUseCase: GetFoldersUseCase(repository: folderRepository)
        )
    }
}

// ✅ Correct: Seeds can call repository functions
struct TestSeeds {
    static func createTestNote(using container: TestDependencyContainer, content: String = "Test") async throws -> Note {
        try await container.noteRepository.create(content: content, folderId: nil)
    }
    
    static func createTestFolder(using container: TestDependencyContainer, name: String = "Folder") async throws -> Folder {
        try await container.folderRepository.create(name: name)
    }
}

// ✅ Correct: Test only calls ViewModel functions, creates via DependencyContainer
func testMoveNoteToFolder_MovesSuccessfully() async throws {
    // Arrange - Create via DependencyContainer
    let container = TestDependencyContainer()
    let note = try await TestSeeds.createTestNote(using: container)
    let folder = try await TestSeeds.createTestFolder(using: container)
    let viewModel = container.makeNoteEditorViewModel(noteId: note.id)
    
    // Act - Only call ViewModel functions
    await viewModel.loadNote()
    await viewModel.moveToFolder(folder.id)
    
    // Assert - Check ViewModel state, NOT repository directly
    XCTAssertEqual(viewModel.note?.folderId, folder.id)
}

// ❌ WRONG: Test calls repository directly
func testMoveNoteToFolder_WRONG() async throws {
    let viewModel = container.makeNoteEditorViewModel(noteId: note.id)
    await viewModel.moveToFolder(folder.id)
    
    // ❌ WRONG - Don't call repository in test assertions
    let movedNote = try await container.noteRepository.get(id: note.id)
    XCTAssertEqual(movedNote?.folderId, folder.id)
}
```

#### Test Quality Standards

- Each test MUST test ONE behavior (Single Assertion Principle)
- Test names MUST describe the scenario: `test[Method]_[Scenario]_[ExpectedResult]`
- Tests MUST be independent and not rely on execution order
- Tests MUST use Arrange-Act-Assert (AAA) or Given-When-Then pattern
- **Tests MUST only call ViewModel public methods** - never repository/use case directly
- **Tests MUST create ViewModels via DependencyContainer** - never construct directly
- **Tests MUST assert on ViewModel state** - not repository state
- Edge cases MUST be tested: empty inputs, nil values, error conditions, boundary values

#### Pre-Review Checklist

Before stopping for human review, AI MUST verify:

- [ ] All tests compile without errors
- [ ] All tests pass (`xcodebuild test` exits with code 0)
- [ ] No skipped or disabled tests (no `XCTSkip`, no commented tests)
- [ ] Edge cases are covered (empty, nil, error, boundary)
- [ ] All ViewModels created via DependencyContainer
- [ ] Tests only call ViewModel functions (no direct repository calls except in Seeds)
- [ ] Assertions check ViewModel state, not repository state

**Rationale**: TDD ensures code correctness from the start, provides living documentation, enables safe refactoring, and catches regressions immediately. Requiring passing tests before human review maximizes review efficiency.

### VII. Hybrid Repository Architecture

Repositories are divided into two categories based on their sync requirements:

1. **OpenAPI Repositories** - For data that MAY sync with a remote server (notes, folders)
2. **Direct CoreData Repositories** - For local-only data (settings, cache, drafts)

#### Architecture Principle

```
┌─────────────────────────────────────────────────────────────┐
│                    Presentation Layer                        │
│                      (ViewModels)                            │
├─────────────────────────────────────────────────────────────┤
│                    Domain Layer                              │
│                     (Use Cases)                              │
├─────────────────────────────────────────────────────────────┤
│              Repository Protocol Layer                       │
│    (NoteRepositoryProtocol, SettingsRepositoryProtocol)     │
├──────────────────────┬──────────────────────────────────────┤
│  OpenAPI Repositories│    Direct CoreData Repositories      │
│  (sync-capable)      │    (local-only)                      │
│  - Notes             │    - Settings                        │
│  - Folders           │    - Cache                           │
│                      │    - Drafts                          │
├──────────────────────┼──────────────────────────────────────┤
│   OpenAPI Client     │         CoreDataStack                │
├──────────────────────┼──────────────────────────────────────┤
│ Remote │ Local       │                                      │
│Transport│Transport   │         CoreData                     │
└──────────────────────┴──────────────────────────────────────┘
```

#### When to Use Each Approach

| Use OpenAPI Repository | Use Direct CoreData Repository |
|------------------------|--------------------------------|
| Data may sync to server | Data is local-only |
| Needs online/offline support | No remote equivalent |
| Part of the API contract | App-specific settings |
| Examples: Notes, Folders, Users | Examples: Settings, Cache, Drafts |

#### Key Concepts

1. **OpenAPI for sync-capable data** - Data that may need remote sync uses OpenAPI
2. **Direct CoreData for local-only** - Settings, cache, drafts use direct CoreData
3. **Transport is selected automatically** - Based on whether remote server is configured
4. **Local transport is NOT a mock** - It's a real implementation using CoreData for storage
5. **Seamless online/offline** - OpenAPI data works regardless of transport

#### Required Tools

- **Swift OpenAPI Generator** (`apple/swift-openapi-generator`) - Generates Swift client/server code
- **Swift OpenAPI Runtime** (`apple/swift-openapi-runtime`) - Runtime library
- **Swift OpenAPI URLSession** (`apple/swift-openapi-urlsession`) - Remote transport for production

#### API Configuration

Server URL and API keys are configured via `APIConfiguration`. Transport selection is automatic:

```swift
// APIConfiguration.swift - Configuration for remote server
struct APIConfiguration {
    let serverURL: URL?
    let apiKey: String?
    
    /// Returns true if remote server is configured
    var isRemoteConfigured: Bool {
        serverURL != nil
    }
    
    /// Load configuration from environment or UserDefaults
    static func load() -> APIConfiguration {
        // Check environment variables first (for CI/testing)
        if let urlString = ProcessInfo.processInfo.environment["API_SERVER_URL"],
           let url = URL(string: urlString) {
            return APIConfiguration(
                serverURL: url,
                apiKey: ProcessInfo.processInfo.environment["API_KEY"]
            )
        }
        
        // Check UserDefaults (for user configuration)
        if let urlString = UserDefaults.standard.string(forKey: "apiServerURL"),
           let url = URL(string: urlString) {
            return APIConfiguration(
                serverURL: url,
                apiKey: UserDefaults.standard.string(forKey: "apiKey")
            )
        }
        
        // No remote configured - use local
        return APIConfiguration(serverURL: nil, apiKey: nil)
    }
    
    /// Default local-only configuration
    static let local = APIConfiguration(serverURL: nil, apiKey: nil)
}
```

#### Local CoreData Transport

The local transport implements the OpenAPI interface using CoreData for storage:

```swift
// LocalCoreDataTransport.swift - Real implementation using CoreData
import OpenAPIRuntime
import HTTPTypes
import CoreData

final class LocalCoreDataTransport: ClientTransport {
    private let coreDataStack: CoreDataStack
    
    init(coreDataStack: CoreDataStack = .shared) {
        self.coreDataStack = coreDataStack
    }
    
    func send(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        // Route to appropriate handler based on operationID
        switch operationID {
        case "createNote":
            return try await handleCreateNote(body: body)
        case "getNotes":
            return try await handleGetNotes(request: request)
        // ... other operations
        default:
            throw LocalTransportError.operationNotImplemented(operationID)
        }
    }
}
```

#### Remote URLSession Transport

The remote transport uses URLSession with optional API key authentication:

```swift
// RemoteTransport.swift - URLSession transport with API key
import OpenAPIRuntime
import OpenAPIURLSession
import HTTPTypes

final class AuthenticatedTransport: ClientTransport {
    private let urlSessionTransport: URLSessionTransport
    private let apiKey: String?
    
    init(apiKey: String? = nil) {
        self.urlSessionTransport = URLSessionTransport()
        self.apiKey = apiKey
    }
    
    func send(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var modifiedRequest = request
        
        // Add API key header if configured
        if let apiKey = apiKey {
            modifiedRequest.headerFields[HTTPField.Name("X-API-Key")!] = apiKey
        }
        
        return try await urlSessionTransport.send(
            modifiedRequest,
            body: body,
            baseURL: baseURL,
            operationID: operationID
        )
    }
}
```

#### DependencyContainer with Automatic Transport Selection

DependencyContainer automatically selects transport based on configuration:

```swift
@MainActor
final class DependencyContainer: ObservableObject {
    static let shared = DependencyContainer()
    
    private var _coreDataStack: CoreDataStack?
    private var _apiConfiguration: APIConfiguration?
    private var _transport: (any ClientTransport)?
    private var _client: Client?
    
    // Builder methods
    @discardableResult
    func withCoreDataStack(_ stack: CoreDataStack) -> DependencyContainer {
        _coreDataStack = stack
        _transport = nil  // Reset to rebuild with new stack
        _client = nil
        return self
    }
    
    @discardableResult
    func withAPIConfiguration(_ config: APIConfiguration) -> DependencyContainer {
        _apiConfiguration = config
        _transport = nil  // Reset to rebuild with new config
        _client = nil
        return self
    }
    
    // Computed properties with automatic transport selection
    var coreDataStack: CoreDataStack {
        _coreDataStack ?? .shared
    }
    
    var apiConfiguration: APIConfiguration {
        _apiConfiguration ?? .load()
    }
    
    /// Transport is selected automatically based on configuration
    var transport: any ClientTransport {
        if let existing = _transport { return existing }
        
        let newTransport: any ClientTransport
        if apiConfiguration.isRemoteConfigured {
            // Remote server configured - use URLSession transport
            newTransport = AuthenticatedTransport(apiKey: apiConfiguration.apiKey)
        } else {
            // No remote - use local CoreData transport
            newTransport = LocalCoreDataTransport(coreDataStack: coreDataStack)
        }
        _transport = newTransport
        return newTransport
    }
    
    var client: Client {
        if let existing = _client { return existing }
        let serverURL = apiConfiguration.serverURL ?? URL(string: "http://localhost")!
        let newClient = Client(serverURL: serverURL, transport: transport)
        _client = newClient
        return newClient
    }
    
    /// Note repository - ALWAYS uses OpenAPI client
    var noteRepository: NoteRepositoryProtocol {
        OpenAPINoteRepository(client: client)
    }
    
    /// Folder repository - ALWAYS uses OpenAPI client
    var folderRepository: FolderRepositoryProtocol {
        OpenAPIFolderRepository(client: client)
    }
    
    static func create() -> DependencyContainer {
        DependencyContainer()
    }
}

// ✅ Production - auto-selects based on configuration
let container = DependencyContainer.shared

// ✅ Test - force local with in-memory CoreData
let testContainer = DependencyContainer.create()
    .withCoreDataStack(InMemoryCoreDataStack())
    .withAPIConfiguration(.local)

// ✅ Force remote for specific tests
let remoteContainer = DependencyContainer.create()
    .withAPIConfiguration(APIConfiguration(
        serverURL: URL(string: "https://api.example.com")!,
        apiKey: "test-key"
    ))
```

#### Testing with Builder Pattern

Tests use the same DependencyContainer with builder pattern to inject in-memory storage:

```swift
@MainActor
final class NoteEditorViewModelTests: XCTestCase {
    var container: DependencyContainer!
    
    override func setUp() {
        super.setUp()
        // Force local transport with in-memory CoreData
        container = DependencyContainer.create()
            .withCoreDataStack(InMemoryCoreDataStack())
            .withAPIConfiguration(.local)
    }
    
    func testCreateNote_SavesSuccessfully() async throws {
        let note = try await TestSeeds.createTestNote(using: container)
        let viewModel = container.makeNoteEditorViewModel(noteId: note.id)
        await viewModel.loadNote()
        XCTAssertTrue(viewModel.noteLoaded)
    }
}
```

#### Project Structure

```
[AppName]/
├── openapi.yaml                    # API specification (source of truth)
├── openapi-generator-config.yaml   # Generator configuration
├── Data/
│   ├── API/
│   │   ├── Generated/              # Generated OpenAPI code
│   │   │   ├── Types.swift
│   │   │   └── Client.swift
│   │   ├── LocalCoreDataTransport.swift   # Local CoreData transport
│   │   ├── AuthenticatedTransport.swift   # Remote URLSession transport
│   │   ├── APIConfiguration.swift         # Server URL/API key config
│   │   └── DomainMapping.swift            # API types → Domain types
│   ├── Repositories/
│   │   ├── OpenAPINoteRepository.swift    # OpenAPI - sync-capable
│   │   ├── OpenAPIFolderRepository.swift  # OpenAPI - sync-capable
│   │   └── SettingsRepository.swift       # Direct CoreData - local-only
│   └── Persistence/
│       └── CoreDataStack.swift
├── DI/
│   └── DependencyContainer.swift
└── ...
```

#### Direct CoreData Repository Example

For local-only data, use direct CoreData access:

```swift
// SettingsRepository.swift - Direct CoreData for local-only data
import CoreData

protocol SettingsRepositoryProtocol {
    func get(key: String) async throws -> String?
    func set(key: String, value: String) async throws
    func delete(key: String) async throws
}

final class SettingsRepository: SettingsRepositoryProtocol {
    private let coreDataStack: CoreDataStack
    
    init(coreDataStack: CoreDataStack = .shared) {
        self.coreDataStack = coreDataStack
    }
    
    func get(key: String) async throws -> String? {
        let context = coreDataStack.viewContext
        let request = SettingEntity.fetchRequest()
        request.predicate = NSPredicate(format: "key == %@", key)
        let results = try context.fetch(request)
        return results.first?.value
    }
    
    func set(key: String, value: String) async throws {
        let context = coreDataStack.viewContext
        // ... implementation
    }
    
    func delete(key: String) async throws {
        // ... implementation
    }
}
```

#### Regenerating OpenAPI Code

When `openapi.yaml` changes, regenerate the client code:

```bash
swift run swift-openapi-generator generate \
  --config NotesApp/openapi-generator-config.yaml \
  --output-directory NotesApp/Data/API/Generated \
  NotesApp/openapi.yaml
```

#### Benefits

- **Right tool for the job** - OpenAPI for sync, direct CoreData for local-only
- **Automatic transport selection** - Based on configuration, no code changes needed
- **Seamless online/offline** - OpenAPI data works regardless of transport
- **Simpler local-only code** - No OpenAPI overhead for settings/cache
- **Type-safe** - OpenAPI generates type-safe client code
- **Easy remote migration** - Just configure server URL to switch to remote

**Rationale**: Not all data needs the complexity of OpenAPI. Local-only data (settings, cache) benefits from simpler direct CoreData access. Sync-capable data uses OpenAPI for transparent remote/local switching.

## Architecture Layers

### Layer Structure

```
┌─────────────────────────────────────────────────────────────┐
│                    Presentation Layer                        │
│  (SwiftUI Views, ViewModels, Coordinators, UI Components)   │
├─────────────────────────────────────────────────────────────┤
│                      Data Layer                              │
│  (Repositories, Network, Database, DTOs, Mappers)           │
├─────────────────────────────────────────────────────────────┤
│                     Domain Layer                             │
│  (Use Cases, Repository Protocols, Domain Services)         │
├─────────────────────────────────────────────────────────────┤
│                    Entities Layer                            │
│  (Business Objects, Value Objects, Enterprise Rules)        │
└─────────────────────────────────────────────────────────────┘
         ↑ Dependencies point INWARD (toward Entities)
```

### Module Organization

```
[AppName]/
├── Entities/           # Pure business objects, no dependencies
│   └── Models/
├── Domain/             # Use cases and repository protocols
│   ├── UseCases/
│   └── Interfaces/     # Repository protocols
├── Data/               # Concrete implementations
│   ├── Repositories/
│   ├── Network/
│   ├── Persistence/
│   └── DTOs/
├── Presentation/       # UI layer
│   ├── Views/
│   ├── ViewModels/
│   └── Coordinators/
└── DI/                 # Dependency injection container

[AppName]Tests/
├── Seeds/              # Shared test data factories
│   └── TestSeeds.swift
├── Integration/        # ViewModel integration tests with real repositories
│   └── *IntegrationTests.swift
└── Helpers/            # Test utilities (in-memory CoreData stack, etc.)
    └── TestCoreDataStack.swift
```

> **Note**: Replace `[AppName]` with your actual app name (e.g., `NotesApp`, `TaskManager`, `PhotoEditor`).

### Data Flow

1. **User Action** → View calls ViewModel method
2. **ViewModel** → Invokes Use Case with request
3. **Use Case** → Calls Repository protocol method
4. **Repository** → Fetches/persists data, maps to Entity
5. **Response** → Flows back: Repository → Use Case → ViewModel → View update

## Tooling & Project Management

### XcodeGen (Project Generation)

The Xcode project MUST be generated from a `project.yml` specification file using XcodeGen.

- The `.xcodeproj` file MUST NOT be committed to version control
- All project configuration MUST be defined in `project.yml`
- Targets MUST be organized to reflect the layer structure (Entities, Domain, Data, Presentation)
- Schemes MUST be defined for each testable target
- Run `xcodegen generate` after any `project.yml` changes

**Rationale**: XcodeGen eliminates merge conflicts in `.xcodeproj` files, makes project structure declarative and reviewable, and ensures reproducible builds.

### Carthage (Dependency Management)

External dependencies MUST be managed using Carthage.

- All dependencies MUST be declared in `Cartfile`
- Pinned versions MUST be tracked in `Cartfile.resolved`
- Built frameworks MUST be stored in `Carthage/Build/` (gitignored)
- Dependencies MUST be linked as XCFrameworks for Apple Silicon compatibility

**Platform-specific commands**:

| Platform | Bootstrap | Update |
|----------|-----------|--------|
| iOS | `carthage bootstrap --platform iOS --use-xcframeworks` | `carthage update --platform iOS --use-xcframeworks` |
| macOS | `carthage bootstrap --platform macOS --use-xcframeworks` | `carthage update --platform macOS --use-xcframeworks` |
| Multi-platform | `carthage bootstrap --use-xcframeworks` | `carthage update --use-xcframeworks` |

**Rationale**: Carthage provides decentralized dependency management with pre-built binaries, reducing build times and avoiding CocoaPods' workspace modifications.

### Project File Structure

```
project.yml              # XcodeGen project specification
Cartfile                 # Carthage dependencies
Cartfile.resolved        # Locked dependency versions
.gitignore               # Must include: *.xcodeproj, Carthage/Build/
[AppName]/
├── Entities/
├── Domain/
├── Data/
├── Presentation/
└── DI/
[AppName]Tests/
[AppName]UITests/
```

### Build & Setup Commands

```bash
# Initial project setup (iOS)
carthage bootstrap --platform iOS --use-xcframeworks
xcodegen generate
open [AppName].xcodeproj

# Initial project setup (macOS)
carthage bootstrap --platform macOS --use-xcframeworks
xcodegen generate
open [AppName].xcodeproj

# After pulling changes
carthage bootstrap --platform [iOS|macOS] --use-xcframeworks
xcodegen generate

# Update dependencies
carthage update --platform [iOS|macOS] --use-xcframeworks
```

> **Note**: Replace `[AppName]` with your app name and `[iOS|macOS]` with your target platform.

## Platform Requirements

### Deployment Targets

Minimum deployment targets for modern SwiftUI features:

| Platform | Minimum Version | Rationale |
|----------|-----------------|----------|
| iOS | 17.0 | `navigationDestination(item:)`, `@Observable` |
| macOS | 14.0 (Sonoma) | `navigationDestination(item:)`, `@Observable` |
| watchOS | 10.0 | Modern SwiftUI navigation |
| tvOS | 17.0 | Modern SwiftUI navigation |
| visionOS | 1.0 | All modern APIs available |

**Required for**:
- `NavigationStack` (iOS 16+ / macOS 13+)
- `navigationDestination(item:)` (iOS 17+ / macOS 14+)
- Modern SwiftUI navigation patterns
- `@Observable` macro (iOS 17+ / macOS 14+)

**Rationale**: Modern SwiftUI navigation APIs provide type-safe, declarative navigation that aligns with Clean Architecture principles. Older APIs (`NavigationView`, `NavigationLink` with `isActive`) are deprecated and harder to test.

### SwiftUI API Availability Checklist

Before using SwiftUI APIs, verify minimum platform version:

| API | iOS | macOS | Notes |
|-----|-----|-------|-------|
| `NavigationStack` | 16.0 | 13.0 | Replaces `NavigationView` |
| `navigationDestination(for:)` | 16.0 | 13.0 | Type-based navigation |
| `navigationDestination(item:)` | 17.0 | 14.0 | Optional binding navigation |
| `@Observable` | 17.0 | 14.0 | Replaces `@ObservableObject` |
| `TextEditor` | 14.0 | 11.0 | Basic text editing |
| `.searchable` | 15.0 | 12.0 | Search bar modifier |
| `Inspector` | 17.0 | 14.0 | Side panel inspector |
| `ContentUnavailableView` | 17.0 | 14.0 | Empty state views |

## Swift Concurrency Guidelines

### @MainActor Isolation

All UI-related classes MUST be marked with `@MainActor`:

- **ViewModels**: MUST be `@MainActor` (they update `@Published` properties bound to UI)
- **DependencyContainer**: MUST be `@MainActor` (creates ViewModels)
- **Use Cases**: SHOULD NOT be `@MainActor` (business logic is UI-independent)
- **Repositories**: SHOULD NOT be `@MainActor` (data access is background work)

```swift
// ✅ Correct: ViewModel is MainActor-isolated
@MainActor
final class ItemListViewModel: ObservableObject {
    @Published var items: [Item] = []
}

// ✅ Correct: DependencyContainer matches ViewModel isolation
@MainActor
final class DependencyContainer: ObservableObject {
    func makeItemListViewModel() -> ItemListViewModel { ... }
}

// ✅ Correct: Use Case is not MainActor (can run on any actor)
final class GetItemsUseCase {
    func execute() async throws -> [Item] { ... }
}
```

**Rationale**: Swift's strict concurrency checking requires consistent actor isolation. If a ViewModel is `@MainActor`, any factory that creates it must also be `@MainActor` or use `await`.

### Async/Await Patterns

- Repository methods MUST be `async throws`
- Use Case methods MUST be `async throws`
- ViewModel methods that call Use Cases MUST use `Task { }` blocks
- Never block the main thread with synchronous data access

```swift
// ✅ Correct: Async call in Task block
func loadItems() {
    Task {
        items = try await getItemsUseCase.execute()
    }
}
```

## Development Workflow

### Feature Implementation Order (TDD with Seeds)

1. **Define Entities** - Create pure business objects
2. **Write Entity Tests** - Test computed properties, initializers, edge cases
3. **Define Repository Protocol** - Specify data access interface
4. **Implement Repository** - Concrete data access with real database
5. **Define Use Case** - Specify the interface
6. **Implement Use Case** - Business logic orchestration
7. **Create Seeds** - Add test data factories to `Seeds/TestSeeds.swift`
8. **Write ViewModel Integration Tests** - Test with real Use Cases and Repositories
9. **Implement ViewModel** - Make tests pass
10. **Implement View** - SwiftUI view bound to ViewModel
11. **Wire Dependencies** - Register in DI container
12. **Run All Tests** - Verify everything passes before review

### Testing Strategy (No Mocks)

| Layer | Test Type | Dependencies | Coverage Target |
|-------|-----------|--------------|----------------|
| Entities | Unit | None | 100% |
| ViewModels | Integration | Real Use Cases + Real Repositories | 90% |
| Use Cases | N/A | Tested via ViewModel integration tests | N/A |
| Repositories | Integration | Real Database (in-memory) | 80% |
| Views | UI | Real App with Seeds | Critical paths |

### Test Execution Commands

```bash
# Run all tests
xcodebuild test -project [AppName].xcodeproj -scheme [AppName] -destination 'platform=iOS Simulator,name=iPhone 17'

# Run tests with coverage
xcodebuild test -project [AppName].xcodeproj -scheme [AppName] -destination 'platform=iOS Simulator,name=iPhone 17' -enableCodeCoverage YES

# Run specific test class
xcodebuild test -project [AppName].xcodeproj -scheme [AppName] -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:[AppName]Tests/CreateItemUseCaseTests
```

### Debug Logging for AI-Assisted Debugging

When debugging issues (especially in UI tests), `print()` statements in application code do NOT appear in `xcodebuild` terminal output. Use these approaches instead:

#### Option 1: XCTContext.runActivity (Recommended for Tests)

Use `XCTContext.runActivity` to create structured log entries that appear in test results:

```swift
func testExample() throws {
    XCTContext.runActivity(named: "Debug: Checking note state") { _ in
        // Your debug code here
        XCTAssertTrue(condition)
    }
}
```

#### Option 2: XCTAttachment for Debug Data

Attach debug information to test results:

```swift
let attachment = XCTAttachment(string: "Debug info: noteId=\(noteId), folderId=\(folderId)")
attachment.lifetime = .keepAlways
add(attachment)
```

#### Option 3: OSLog/Logger (Recommended for App Code)

Use Apple's unified logging system instead of `print()`:

```swift
import os

extension Logger {
    static let repository = Logger(subsystem: "com.example.AppName", category: "Repository")
    static let viewModel = Logger(subsystem: "com.example.AppName", category: "ViewModel")
}

// Usage
Logger.repository.debug("Creating note with id: \(note.id)")
Logger.repository.error("Failed to save: \(error.localizedDescription)")
```

**Reading OSLog output:**
- In Xcode: View logs in Debug Console when running attached
- From Terminal: `xcrun simctl spawn booted log stream --predicate 'subsystem == "com.example.AppName"'`
- Console.app: Filter by subsystem/category

#### Option 4: Write to File (Last Resort)

For UI tests where other methods fail, write debug info to a file:

```swift
func debugLog(_ message: String) {
    let logFile = FileManager.default.temporaryDirectory.appendingPathComponent("debug.log")
    let entry = "\(Date()): \(message)\n"
    if let data = entry.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logFile.path) {
            let handle = try? FileHandle(forWritingTo: logFile)
            handle?.seekToEndOfFile()
            handle?.write(data)
            handle?.closeFile()
        } else {
            try? data.write(to: logFile)
        }
    }
}
```

#### Why print() Doesn't Work in xcodebuild

- `print()` outputs to stdout, but `xcodebuild` captures test runner output, not app stdout
- For iOS 10+, even `NSLog` is treated as a Notice-level message and filtered out
- UI tests run the app in a separate process, further isolating stdout

#### Best Practice for AI Debugging

1. **Write integration tests** that reproduce the issue in unit test context (where `print()` works)
2. **Use XCTContext.runActivity** for structured debugging in test code
3. **Use Logger/OSLog** for application code debugging
4. **Check xcresult files** for detailed test logs: found at path shown in test output

### Code Review Checklist

- [ ] Dependencies point inward only
- [ ] No framework imports in Entities or Domain
- [ ] All boundaries defined by protocols
- [ ] Use Cases are single-purpose
- [ ] ViewModels do not contain business logic
- [ ] Repository implementations are in Data layer only
- [ ] **All tests pass** (verified by CI or local run)
- [ ] **Test coverage meets targets** (90% ViewModels via integration tests)
- [ ] **Edge cases tested** (empty, nil, error, boundary)
- [ ] **No skipped or disabled tests**
- [ ] **ViewModels created via DependencyContainer** (not constructed directly)
- [ ] **Tests only call ViewModel functions** (no direct repository/use case calls)
- [ ] **Seeds used for test data** (only seeds call repository functions)

## Governance

This constitution supersedes all other architectural practices for this project.

- All pull requests MUST verify compliance with these principles
- Violations MUST be documented and justified in the PR description
- Amendments require: documentation of change, team review, migration plan for existing code
- Use this constitution as the reference for architectural decisions

**Version**: 5.1.0 | **Ratified**: 2026-01-12 | **Last Amended**: 2026-01-13
