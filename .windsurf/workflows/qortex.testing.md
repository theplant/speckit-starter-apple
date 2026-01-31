---
description: Add and refactor code for testing following TDD and UI-only testing patterns with AI-friendly output
---

# Testing Workflow

This workflow guides adding tests and refactoring code for testability following the constitution's TDD and UI-only testing principles with AI-friendly output.

## When to Use This Workflow

- Adding new features with tests
- Refactoring existing code for better testability
- Setting up test infrastructure
- Creating test seeds for data setup
- Writing UI tests that provide AI with debugging context

## Core Testing Principles

1. **UI tests MUST inherit from `AIFriendlyUITestCase`** - provides screenshots, element hierarchy, structured logging
2. **Tests MUST use `step()` wrapper** - creates structured test activities for reports
3. **Seeds are the ONLY place allowed to call repository functions** - for test data setup
4. **All tests MUST pass before human review**
5. **Screenshots MUST be captured at key points** - enables AI to see exact UI state
6. **FAIL-FAST on app crashes** - Never wait for elements when app is not running; check app state before waits
7. **3-SECOND MAX WAIT** - If an element doesn't appear within 3 seconds, the selector is likely wrong. Use root-cause-tracing to fix selectors, not longer timeouts.
8. **ONE TEST PER USER STORY** - Each user story should have exactly ONE comprehensive test that covers the complete flow. This reduces test overhead and execution time while ensuring full coverage of the user journey.
9. **AI MUST REVIEW EVERY SCREENSHOT** - After extracting test artifacts, AI MUST use `read_file` to view EVERY screenshot image. Check for:
   - **Upside-down/mirrored text** - Coordinate system bugs (common in CoreGraphics/CoreText)
   - **Misalignments** - Elements not properly aligned or positioned
   - **Text cut-off** - Labels or content truncated or clipped
   - **Wrong content** - Incorrect text, values, or data displayed
   - **Layout issues** - Overlapping elements, wrong spacing, broken layouts
   - **Missing elements** - Expected UI components not visible
   - **Visual regressions** - UI looks different than expected
   - **Empty states** - Blank areas where content should appear
   - **Error states** - Unexpected error messages or warnings
   If any issue is found, AI should flag it immediately and investigate before proceeding. See **Step 11a** for detailed review process.

## Prerequisites

Before running AI-friendly UI tests, ensure these tools are installed:

```bash
# Extract artifacts (screenshots, attachments, logs) from `.xcresult`
brew install chargepoint/xcparse/xcparse

# Optional: Parse `.xcresult` into Markdown/JUnit summaries
brew install xcresultparser
```

**Why these tools?** Xcode's `.xcresult` bundles contain step logs, screenshots, attachments, and diagnostics but are not directly human/AI-friendly.

- **`xcparse`** reliably extracts screenshots, text attachments, and logs into normal folders.
- **`xcresultparser`** is useful for generating Markdown/JUnit summaries from the same `.xcresult`.

## Steps

### 1. Set Up Test Infrastructure

Ensure these files exist in your test targets:

```
[AppName]Tests/
├── Seeds/
│   └── TestSeeds.swift             # Test data factories
├── Helpers/
│   └── InMemoryCoreDataStack.swift # In-memory storage for tests
└── Integration/
    └── *IntegrationTests.swift     # ViewModel integration tests

[AppName]UITests/
├── Helpers/
│   └── AIFriendlyUITestCase.swift  # Base class for AI-friendly UI tests
└── *UITests.swift                  # UI tests inheriting from base class
```

### 2. Create AIFriendlyUITestCase Base Class

This base class provides automatic screenshot capture, element hierarchy dumps, and structured logging:

```swift
// AIFriendlyUITestCase.swift
import XCTest

/// Wrapper to make a closure Sendable for Swift 6 concurrency.
/// This is safe because XCTContext.runActivity executes the closure synchronously
/// on the same thread before returning.
private struct SendableBlock: @unchecked Sendable {
    let block: () -> Void
    
    func callAsFunction() {
        block()
    }
}

class AIFriendlyUITestCase: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        
        // FAIL-FAST: Short timeout to detect launch failures immediately
        let launched = app.wait(for: .runningForeground, timeout: 3)
        if !launched {
            takeScreenshot(named: "AppLaunchFailed")
            dumpElementHierarchy(context: "AppLaunchFailed")
            XCTFail("FAIL-FAST: App failed to launch. State: \(app.state.rawValue)")
            return
        }
        
        takeScreenshot(named: "InitialState")
    }
    
    override func tearDownWithError() throws {
        if let failureCount = testRun?.failureCount, failureCount > 0 {
            captureFailureContext()
        }
        app = nil
    }
    
    // MARK: - Crash Detection
    
    /// FAIL-FAST: Check app state before waiting for elements
    @discardableResult
    func assertAppRunning(context: String = "Unknown") -> Bool {
        let state = app.state
        guard state == .runningForeground || state == .runningBackground else {
            takeScreenshot(named: "AppCrashed-\(context)")
            dumpElementHierarchy(context: "AppCrashed-\(context)")
            XCTFail("FAIL-FAST: App not running during '\(context)'. State: \(state.rawValue)")
            return false
        }
        return true
    }
    
    // MARK: - Structured Test Steps
    
    /// Uses SendableBlock wrapper to satisfy Swift 6 strict concurrency
    func step(_ name: String, block: @escaping () -> Void) {
        let sendableBlock = SendableBlock(block: block)
        XCTContext.runActivity(named: name) { _ in
            sendableBlock()
        }
    }
    
    // MARK: - Screenshot Capture
    
    func takeScreenshot(named name: String) {
        let fullScreenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(
            uniformTypeIdentifier: "public.png",
            name: "Screenshot-\(UIDevice.current.name)-\(name).png",
            payload: fullScreenshot.pngRepresentation,
            userInfo: nil
        )
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    
    // MARK: - Element Hierarchy Dump
    
    func dumpElementHierarchy(context: String) {
        let hierarchy = app.debugDescription
        let attachment = XCTAttachment(string: hierarchy)
        attachment.name = "ElementHierarchy-\(context).txt"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    
    // MARK: - Failure Context Capture
    
    private func captureFailureContext() {
        takeScreenshot(named: "FailureState")
        dumpElementHierarchy(context: "OnFailure")
    }
}
```

### 3. Create InMemoryCoreDataStack (if not exists)

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

### 4. Create TestSeeds

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

### 5. Write UI Tests (Using AIFriendlyUITestCase)

UI tests MUST inherit from `AIFriendlyUITestCase` and use the `step()` wrapper.

**IMPORTANT: ONE TEST PER USER STORY** - Each user story should have exactly ONE comprehensive test that covers ALL acceptance scenarios in a single flow. This approach:
- Reduces test execution time (app launches once per user story)
- Ensures the complete user journey is tested end-to-end
- Avoids redundant setup/teardown overhead
- Makes tests easier to maintain

```swift
// US1_WorksheetCreationTests.swift
import XCTest

/// US1: Worksheet Creation
/// One comprehensive test covering all acceptance scenarios
final class US1_WorksheetCreationTests: AIFriendlyUITestCase {
    
    /// Complete flow test for US1: Worksheet Creation
    /// Covers: AC1 (enter name), AC2 (preview updates), AC3 (print enabled)
    func test_US1_CompleteWorksheetCreationFlow() {
        // AC1: User can enter student name
        step("1. Wait for app to load") {
            let tabBar = app.tabBars.firstMatch
            XCTAssertTrue(tabBar.waitForExistence(timeout: 3))
            takeScreenshot(named: "US1-Step1-AppLoaded")
        }
        
        step("2. Enter student name") {
            let contentTextField = app.textFields["contentTextField"]
            XCTAssertTrue(contentTextField.waitForExistence(timeout: 3))
            contentTextField.tap()
            contentTextField.typeText("Liam")
            takeScreenshot(named: "US1-Step2-NameEntered")
        }
        
        // AC2: Preview updates when name is entered
        step("3. Verify preview updates with name") {
            let preview = app.otherElements["worksheetPreview"]
            XCTAssertTrue(preview.waitForExistence(timeout: 3))
            takeScreenshot(named: "US1-Step3-PreviewVisible")
        }
        
        // AC3: Print button becomes enabled
        step("4. Verify print button is enabled") {
            let printButton = app.buttons["printButton"]
            XCTAssertTrue(printButton.waitForExistence(timeout: 3))
            XCTAssertTrue(printButton.isEnabled, 
                "Print button should be enabled after entering text")
            takeScreenshot(named: "US1-Step4-PrintEnabled")
        }
        
        // AC4: User can tap print button
        step("5. Tap print button and verify print dialog") {
            let printButton = app.buttons["printButton"]
            printButton.tap()
            // Verify print dialog or confirmation appears
            takeScreenshot(named: "US1-Step5-PrintTapped")
        }
    }
}
```

### 6. Write Integration Tests (TDD Red Phase)

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

### 7. Implement Feature (TDD Green Phase)

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

### 8. Refactor (TDD Refactor Phase)

Improve code while keeping tests green:

- Extract common patterns
- Improve naming
- Remove duplication
- Ensure all tests still pass

### 9. Run Tests Incrementally (Recommended for UI Tests)

**Why incremental?** UI tests are slow. Running all tests at once wastes time if early tests fail. Instead:

1. **Run a single test first** to verify the flow works
2. **Run tests one by one**, fixing failures before continuing
3. **Parse results after each failure** to understand context

#### Step 9a: Run a Single Test First

```bash
// turbo
xcodebuild test -project [AppName].xcodeproj -scheme [AppName] \
  -destination 'platform=iOS Simulator,id=[SIMULATOR_ID]' \
  -only-testing:[AppName]UITests/[TestClass]/[testMethodName] \
  -resultBundlePath TestResults.xcresult 2>&1 | tee xcodebuild.log
```

### 10. AI-First Observability (Live Logs + Video + Crash Evidence)

UI tests already attach screenshots and element hierarchies via `AIFriendlyUITestCase`. The missing piece for rapid AI debugging is **capturing evidence outside XCTest**:

- **Live app + system logs from the Simulator** (`log stream`)
- **Screen recording** of the entire UI run (when screenshots aren’t enough)
- **Crash reports + diagnostics** even when the **app crashes**, **test runner crashes**, or the **Simulator crashes** (`simctl diagnose`)

#### Step 10a: Boot and wait for the simulator (stable start)

```bash
# Boot and wait until it’s fully ready
xcrun simctl bootstatus [SIMULATOR_ID] -b
```

#### Step 10b: Stream Simulator logs in real time to a file

Pick the most stable predicate you can:

- **By process name** (often easiest): `process == "[AppProcessName]"`
- **By bundle identifier** (if you log with that subsystem): `subsystem == "[BundleId]"`

```bash
# Start log streaming in the background
xcrun simctl spawn booted log stream \
  --style compact \
  --level debug \
  --predicate 'process == "[AppProcessName]"' \
  > sim.log 2>&1 &
echo $! > sim.log.pid
```

#### Step 10c: Record simulator video (optional but high value)

```bash
# Record until you stop it (SIGINT). Use --force to overwrite.
xcrun simctl io booted recordVideo --codec=h264 --force ui.mp4 2> ui-video.stderr &
echo $! > ui-video.pid
```

#### Step 10d: Run tests while logs/video capture runs

```bash
// turbo
xcodebuild test -project [AppName].xcodeproj -scheme [AppName] \
  -destination 'platform=iOS Simulator,id=[SIMULATOR_ID]' \
  -only-testing:[AppName]UITests/[TestClass]/[testMethodName] \
  -resultBundlePath TestResults.xcresult \
  2>&1 | tee xcodebuild.log
```

#### Step 10e: Stop log/video capture

```bash
# Stop log stream
kill "$(cat sim.log.pid)" || true

# Stop recording (SIGINT finalizes the mp4)
kill -INT "$(cat ui-video.pid)" || true
```

**Find simulator ID:**
```bash
xcrun simctl list devices available | grep -i ipad | head -5
```

#### Step 9b: If Test Passes, Run Next Test

Continue with the next test method. If it fails, parse results and fix before continuing.

#### Step 9c: Run All Tests (After Individual Tests Pass)

```bash
// turbo
xcodebuild test -project [AppName].xcodeproj -scheme [AppName] \
  -destination 'platform=iOS Simulator,id=[SIMULATOR_ID]' \
  -only-testing:[AppName]UITests \
  -resultBundlePath TestResults.xcresult
```

### 11. Extract Results + Artifacts for AI Analysis

```bash
# Extract screenshots and attachments
xcparse screenshots TestResults.xcresult ./artifacts/screenshots/ --test-status Failure
xcparse attachments TestResults.xcresult ./artifacts/attachments/ --uti public.plain-text public.image
xcparse logs TestResults.xcresult ./artifacts/logs/

# Optional summaries (useful for pasting into AI)
xcresultparser -o md TestResults.xcresult > ./artifacts/test-summary.md
xcresultparser -o junit TestResults.xcresult > ./artifacts/junit.xml
```

### 11a. MANDATORY: AI Must Review Every Screenshot

**CRITICAL**: After extracting screenshots, AI MUST use the `read_file` tool to view EVERY screenshot image and check for visual bugs. Do NOT skip this step even if all tests pass.

**Why?** Tests may pass but still have visual bugs that aren't caught by assertions:
- **Upside-down/mirrored text** - Coordinate system bugs in rendering code
- **Cut-off content** - Text or images clipped at boundaries
- **Wrong positioning** - Elements in wrong locations
- **Color/contrast issues** - Unreadable text, wrong colors
- **Layout breaks** - Overlapping elements, broken alignment

**How to review:**
1. List all screenshots in the artifacts folder
2. Use `read_file` on each `.png` file to view it
3. For each screenshot, check:
   - Is text readable and right-side up?
   - Are all expected elements visible?
   - Is the layout correct?
   - Are there any visual anomalies?
4. If ANY visual issue is found, investigate the rendering code before proceeding

**Example visual bug caught by screenshot review:**
```
Issue: Text "Liam" rendered as upside-down "ɯɐ!˥" in preview
Root cause: Missing coordinate system flip in renderPreview()
Fix: Added cgContext.translateBy(x: 0, y: scaledSize.height) and 
     changed scaleBy(x: scale, y: scale) to scaleBy(x: scale, y: -scale)
```

### 11b. PDF/Graphics Rendering Testing Best Practices

When testing code that generates PDFs, images, or uses CoreGraphics/CoreText, follow these practices to catch coordinate system bugs early:

#### Root Cause of Common PDF Bugs

**Upside-down/mirrored content** is almost always caused by **double coordinate flipping**:

1. **CoreGraphics** uses bottom-left origin with Y going UP
2. **UIKit** uses top-left origin with Y going DOWN
3. **UIGraphicsPDFRenderer** and **UIGraphicsImageRenderer** already provide UIKit-compatible contexts
4. **Mistake**: Manually applying `translateBy(x: 0, y: height)` + `scaleBy(x: 1, y: -1)` then using UIKit drawing methods causes DOUBLE flip

**Correct approach:**
```swift
// ❌ WRONG: Double flip when using UIKit drawing
func renderPDF() -> Data {
    let renderer = UIGraphicsPDFRenderer(bounds: rect)
    return renderer.pdfData { context in
        context.beginPage()
        let cgContext = context.cgContext
        cgContext.translateBy(x: 0, y: height)  // Manual flip
        cgContext.scaleBy(x: 1, y: -1)          // + UIKit drawing = DOUBLE FLIP
        attributedString.draw(in: rect)         // UIKit method already flips
    }
}

// ✅ CORRECT: UIGraphicsPDFRenderer already provides UIKit coordinates
func renderPDF() -> Data {
    let renderer = UIGraphicsPDFRenderer(bounds: rect)
    return renderer.pdfData { context in
        context.beginPage()
        // NO manual flip needed - just draw with UIKit methods
        UIGraphicsPushContext(context.cgContext)
        attributedString.draw(in: rect)
        UIGraphicsPopContext()
    }
}
```

#### Visual Verification Tests for PDF/Graphics

Always create tests that save generated PDFs/images to disk for visual inspection:

```swift
final class PDFVisualVerificationTests: XCTestCase {
    let artifactsPath = "/tmp/[app-name]-test-artifacts"
    
    override func setUp() {
        try? FileManager.default.createDirectory(
            atPath: artifactsPath,
            withIntermediateDirectories: true
        )
    }
    
    func testPDF_SaveForVisualInspection() async throws {
        let pdfData = try await renderer.renderPDF(content: "Test")
        
        // Save PDF for manual inspection
        let pdfPath = "\(artifactsPath)/output.pdf"
        try pdfData.write(to: URL(fileURLWithPath: pdfPath))
        print("✅ PDF saved to: \(pdfPath)")
        
        // Also save as PNG for AI review
        if let pdfDocument = PDFDocument(data: pdfData),
           let page = pdfDocument.page(at: 0) {
            let pageImage = page.thumbnail(of: page.bounds(for: .mediaBox).size, for: .mediaBox)
            if let pngData = pageImage.pngData() {
                let imagePath = "\(artifactsPath)/output.png"
                try pngData.write(to: URL(fileURLWithPath: imagePath))
                print("✅ PDF page image saved to: \(imagePath)")
            }
        }
    }
}
```

#### AI Must Review Generated PDFs

After running PDF visual verification tests:
1. Use `read_file` on the generated PNG to view the rendered output
2. Check for:
   - **Upside-down text** - Coordinate system bug
   - **Mirrored text** - Wrong scale direction
   - **Text not aligned with lines** - Baseline calculation error
   - **Content at wrong position** - Margin/offset calculation error
3. If issues found, trace through the coordinate transforms in the rendering code

### 12. Collect Crash + Simulator Diagnostics (when things crash/hang)

If the **app crashes**, **UI test runner crashes**, **simulator crashes**, or the run hangs with little information, collect diagnostics immediately after reproduction:

```bash
# Collect diagnostics for the affected simulator
xcrun simctl diagnose --udid [SIMULATOR_ID] --no-archive --output ./artifacts/simctl-diagnose/
```

Note: Prefer leaving the affected simulator **booted** when running `simctl diagnose` so it can collect more information.

If you’re debugging a flake or deep simulator issue, enable verbose simulator logging before reproducing:

```bash
xcrun simctl logverbose [SIMULATOR_ID] enable
```

### 13. What to hand to AI when a UI test fails

Provide the following files/folders so AI has immediate context:

- **`TestResults.xcresult`**
- **`xcodebuild.log`**
- **`sim.log`** (if you ran log streaming)
- **`ui.mp4`** (if you recorded video)
- **`./artifacts/screenshots/`**
- **`./artifacts/attachments/`**
- **`./artifacts/logs/`**
- **`./artifacts/simctl-diagnose/`** (if crash/simulator issue)

### 14. Pre-Review Checklist

Before stopping for human review, verify:

- [ ] All tests compile without errors
- [ ] All tests pass (`xcodebuild test` exits with code 0)
- [ ] No skipped or disabled tests (no `XCTSkip`, no commented tests)
- [ ] Edge cases are covered (empty, nil, error, boundary)
- [ ] UI tests inherit from `AIFriendlyUITestCase`
- [ ] UI tests use `step()` wrapper for structured logging
- [ ] Screenshots captured at key points via `takeScreenshot(named:)`
- [ ] Accessibility identifiers follow naming conventions
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
| UI | YES (100% Critical Paths) | E2E journeys via XCUITest with AIFriendlyUITestCase |
| ViewModels | NO | Tested implicitly through UI tests |
| Entities | NO | Tested implicitly through UI tests |
| Use Cases | NO | Tested implicitly through UI tests |
| Repositories | NO | Tested implicitly through UI tests |

## Accessibility Identifier Conventions

| Element Type | Pattern | Example |
|--------------|---------|---------|
| Text Fields | `{purpose}TextField` | `contentTextField`, `studentNameField` |
| Buttons | `{action}Button` | `printButton`, `saveStudentButton` |
| Toggles/Switches | `{feature}Toggle` | `traceableToggle` |
| Pickers | `{setting}Picker` | `gradeLevelPicker` |
| Preview Areas | `{content}Preview` | `worksheetPreview` |
| Lists/Tables | `{items}List` | `studentsList` |
