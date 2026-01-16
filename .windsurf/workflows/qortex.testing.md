---
description: Add and refactor code for testing following TDD and ViewModel-only testing patterns
---

# Testing Workflow

This workflow guides adding tests and refactoring code for testability following the constitution's TDD and ViewModel-only testing principles.

## When to Use This Workflow

- Adding new features with tests
- Refactoring existing code for better testability
- Setting up test infrastructure
- Creating test seeds for data setup

## Core Testing Principles

1. **Tests MUST only call ViewModel public methods** - mirrors real user interactions
2. **Tests MUST create ViewModels via DependencyContainer** - ensures consistent dependency wiring
3. **Seeds are the ONLY place allowed to call repository functions** - for test data setup
4. **All tests MUST pass before human review**

## Steps

### 1. Set Up Test Infrastructure

Ensure these files exist in your test target:

```
[AppName]Tests/
├── Seeds/
│   └── TestSeeds.swift             # Test data factories
├── Helpers/
│   └── InMemoryCoreDataStack.swift # In-memory storage for tests
└── Integration/
    └── *IntegrationTests.swift     # ViewModel integration tests
```

### 2. Create InMemoryCoreDataStack (if not exists)

```swift
// InMemoryCoreDataStack.swift
import CoreData

final class InMemoryCoreDataStack: CoreDataStack {
    override init() {
        super.init()
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        persistentContainer.persistentStoreDescriptions = [description]
        persistentContainer.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Failed to load in-memory store: \(error)")
            }
        }
    }
}
```

### 3. Create TestSeeds

Seeds are the ONLY place that can call repository functions directly.

**Key principle**: Use the same `DependencyContainer` class for both production and tests. Tests inject different dependencies via builder pattern.

```swift
// TestSeeds.swift
import Foundation

@MainActor
struct TestSeeds {
    // MARK: - Note Seeds
    
    static func createTestNote(
        using container: DependencyContainer,
        content: String = "Test Note Content",
        folderId: UUID? = nil
    ) async throws -> Note {
        try await container.noteRepository.create(content: content, folderId: folderId)
    }
    
    // MARK: - Folder Seeds
    
    static func createTestFolder(
        using container: DependencyContainer,
        name: String = "Test Folder"
    ) async throws -> Folder {
        try await container.folderRepository.create(name: name)
    }
    
    // MARK: - Complex Scenarios
    
    static func createNoteInFolder(
        using container: DependencyContainer
    ) async throws -> (note: Note, folder: Folder) {
        let folder = try await createTestFolder(using: container)
        let note = try await createTestNote(using: container, folderId: folder.id)
        return (note, folder)
    }
}
```

### 4. Write Integration Tests (TDD Red Phase)

Write failing tests FIRST that define expected behavior.

**Key principle**: Same `DependencyContainer` class for production and tests. Tests use builder pattern to inject in-memory storage:

```swift
// NoteEditorViewModelIntegrationTests.swift
import XCTest
@testable import NotesApp

@MainActor
final class NoteEditorViewModelIntegrationTests: XCTestCase {
    var container: DependencyContainer!
    
    override func setUp() {
        super.setUp()
        // Same DependencyContainer, different dependencies via builder pattern
        container = DependencyContainer.create()
            .withCoreDataStack(InMemoryCoreDataStack())
            .withAPIConfiguration(.local)
    }
    
    override func tearDown() {
        container = nil
        super.tearDown()
    }
    
    // MARK: - Test Naming: test[Method]_[Scenario]_[ExpectedResult]
    
    func testLoadNote_WithValidNoteId_SetsNoteLoadedToTrue() async throws {
        // Arrange - Seeds can call repository
        let note = try await TestSeeds.createTestNote(using: container)
        let viewModel = container.makeNoteEditorViewModel(noteId: note.id)
        
        // Act - Only call ViewModel functions
        await viewModel.loadNote()
        
        // Assert - Check ViewModel state, NOT repository
        XCTAssertTrue(viewModel.noteLoaded)
        XCTAssertEqual(viewModel.content, note.content)
    }
    
    func testLoadNote_WithNonExistentNoteId_NoteLoadedStaysFalse() async throws {
        // Arrange
        let viewModel = container.makeNoteEditorViewModel(noteId: UUID())
        
        // Act
        await viewModel.loadNote()
        
        // Assert
        XCTAssertFalse(viewModel.noteLoaded)
    }
    
    func testMoveToFolder_AfterLoadingNote_UpdatesFolderId() async throws {
        // Arrange
        let note = try await TestSeeds.createTestNote(using: container)
        let folder = try await TestSeeds.createTestFolder(using: container)
        let viewModel = container.makeNoteEditorViewModel(noteId: note.id)
        await viewModel.loadNote()
        
        // Act
        await viewModel.moveToFolder(folder.id)
        
        // Assert
        XCTAssertEqual(viewModel.selectedFolderId, folder.id)
    }
}
```

### 5. Implement Feature (TDD Green Phase)

Write minimum code to make tests pass:

```swift
// In ViewModel
func loadNote() async {
    guard let noteId = noteId else { return }
    do {
        if let note = try await getNoteUseCase.execute(id: noteId) {
            self.content = note.content
            self.noteLoaded = true
        }
    } catch {
        // Handle error
    }
}
```

### 6. Refactor (TDD Refactor Phase)

Improve code while keeping tests green:

- Extract common patterns
- Improve naming
- Remove duplication
- Ensure all tests still pass

### 7. Run All Tests

```bash
// turbo
xcodebuild test -project NotesApp.xcodeproj -scheme NotesApp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.2' -only-testing:NotesAppTests
```

### 8. Pre-Review Checklist

Before stopping for human review, verify:

- [ ] All tests compile without errors
- [ ] All tests pass (`xcodebuild test` exits with code 0)
- [ ] No skipped or disabled tests (no `XCTSkip`, no commented tests)
- [ ] Edge cases are covered (empty, nil, error, boundary)
- [ ] All ViewModels created via DependencyContainer
- [ ] Tests only call ViewModel functions (no direct repository calls except in Seeds)
- [ ] Assertions check ViewModel state, not repository state

## Anti-Patterns to Avoid

```swift
// ❌ WRONG: Test calls repository directly
func testMoveNote_WRONG() async throws {
    let viewModel = container.makeNoteEditorViewModel(noteId: note.id)
    await viewModel.moveToFolder(folder.id)
    
    // ❌ Don't call repository in test assertions
    let movedNote = try await container.noteRepository.get(id: note.id)
    XCTAssertEqual(movedNote?.folderId, folder.id)
}

// ❌ WRONG: Creating ViewModel directly without DependencyContainer
func testCreateNote_WRONG() async throws {
    let viewModel = NoteEditorViewModel(
        noteId: nil,
        createNoteUseCase: CreateNoteUseCase(repository: someRepo)
        // ... manually wiring dependencies
    )
}

// ❌ WRONG: Testing repository directly
func testRepository_WRONG() async throws {
    let note = try await container.noteRepository.create(content: "Test")
    let fetched = try await container.noteRepository.get(id: note.id)
    XCTAssertEqual(fetched?.content, "Test")
}
```

## Correct Patterns

```swift
// ✅ CORRECT: Seeds call repository, tests call ViewModel
func testCreateNote_CORRECT() async throws {
    // Arrange - Seeds can call repository
    let folder = try await TestSeeds.createTestFolder(using: container)
    let viewModel = container.makeNoteEditorViewModel(folderId: folder.id)
    
    // Act - Only call ViewModel functions
    viewModel.content = "New Note"
    await viewModel.saveNote()
    
    // Assert - Check ViewModel state
    XCTAssertNotNil(viewModel.noteId)
    XCTAssertTrue(viewModel.noteLoaded)
}
```

## Test Coverage Requirements

| Layer | Test Required | Notes |
|-------|---------------|-------|
| ViewModels | YES (90%) | Integration tests via DependencyContainer |
| Entities | NO | Tested implicitly through ViewModel tests |
| Use Cases | NO | Tested implicitly through ViewModel tests |
| Repositories | NO | Tested implicitly through ViewModel tests |
