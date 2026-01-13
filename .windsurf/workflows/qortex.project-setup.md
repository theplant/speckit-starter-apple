---
description: Project initial setup for all the tools used for the folders, config files
---

# Project Setup Workflow

This workflow guides setting up a new iOS project with Clean Architecture, XcodeGen, and OpenAPI tooling.

## When to Use This Workflow

- Starting a new iOS project from scratch
- Adding Clean Architecture to an existing project
- Setting up OpenAPI code generation
- Configuring project tooling

## Prerequisites

Install required tools:

```bash
# XcodeGen - Project generation
brew install xcodegen

# Swift OpenAPI Generator (via SPM - added to Package.swift)
```

## Steps

### 1. Create Project Directory Structure

```bash
mkdir -p MyApp/{App,Entities/Models,Domain/{UseCases,Interfaces},Data/{API/Generated,Repositories,Persistence},Presentation/{Views,ViewModels},DI}
mkdir -p MyAppTests/{Seeds,Helpers,Integration}
mkdir -p MyAppUITests
mkdir -p .specify/memory
mkdir -p .windsurf/workflows
```

Expected structure:
```
MyApp/
├── App/
│   ├── MyAppApp.swift
│   └── ContentView.swift
├── Entities/
│   └── Models/
│       └── Note.swift
├── Domain/
│   ├── UseCases/
│   │   └── CreateNoteUseCase.swift
│   └── Interfaces/
│       └── NoteRepositoryProtocol.swift
├── Data/
│   ├── API/
│   │   ├── Generated/
│   │   │   ├── Types.swift
│   │   │   └── Client.swift
│   │   ├── LocalCoreDataTransport.swift
│   │   ├── AuthenticatedTransport.swift
│   │   ├── APIConfiguration.swift
│   │   └── DomainMapping.swift
│   ├── Repositories/
│   │   ├── OpenAPINoteRepository.swift
│   │   └── SettingsRepository.swift
│   └── Persistence/
│       ├── CoreDataStack.swift
│       └── MyApp.xcdatamodeld
├── Presentation/
│   ├── Views/
│   │   └── NoteEditorView.swift
│   └── ViewModels/
│       └── NoteEditorViewModel.swift
└── DI/
    └── DependencyContainer.swift

MyAppTests/
├── Seeds/
│   └── TestSeeds.swift
├── Helpers/
│   └── InMemoryCoreDataStack.swift
└── Integration/
    └── NoteEditorViewModelIntegrationTests.swift

MyAppUITests/
└── MyAppUITests.swift
```

### 2. Create project.yml (XcodeGen)

```yaml
name: MyApp
options:
  bundleIdPrefix: com.example
  deploymentTarget:
    iOS: "17.0"

packages:
  OpenAPIRuntime:
    url: https://github.com/apple/swift-openapi-runtime
    from: "1.0.0"
  OpenAPIURLSession:
    url: https://github.com/apple/swift-openapi-urlsession
    from: "1.0.0"
  HTTPTypes:
    url: https://github.com/apple/swift-http-types
    from: "1.0.0"

targets:
  MyApp:
    type: application
    platform: iOS
    sources:
      - MyApp
    dependencies:
      - package: OpenAPIRuntime
      - package: OpenAPIURLSession
      - package: HTTPTypes
        product: HTTPTypes
    settings:
      base:
        INFOPLIST_FILE: MyApp/App/Info.plist
        PRODUCT_BUNDLE_IDENTIFIER: com.example.myapp

  MyAppTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - MyAppTests
    dependencies:
      - target: MyApp

  MyAppUITests:
    type: bundle.ui-testing
    platform: iOS
    sources:
      - MyAppUITests
    dependencies:
      - target: MyApp
```

### 3. Create Package.swift (for OpenAPI Generator)

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MyAppGenerator",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "MyAppGenerator",
            dependencies: [
                .product(name: "swift-openapi-generator", package: "swift-openapi-generator"),
            ]
        ),
    ]
)
```

### 4. Create openapi.yaml

```yaml
openapi: '3.1.0'
info:
  title: MyApp API
  version: 1.0.0
servers:
  - url: https://api.example.com
    description: Production server

paths:
  /notes:
    get:
      operationId: getNotes
      summary: Get all notes
      parameters:
        - name: folderId
          in: query
          schema:
            type: string
            format: uuid
      responses:
        '200':
          description: Success
          content:
            application/json:
              schema:
                type: array
                items:
                  $ref: '#/components/schemas/Note'
    post:
      operationId: createNote
      summary: Create a note
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/CreateNoteRequest'
      responses:
        '201':
          description: Created
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Note'

components:
  schemas:
    Note:
      type: object
      required: [id, content, createdAt, modifiedAt]
      properties:
        id:
          type: string
          format: uuid
        content:
          type: string
        createdAt:
          type: string
          format: date-time
        modifiedAt:
          type: string
          format: date-time
        folderId:
          type: string
          format: uuid
    
    CreateNoteRequest:
      type: object
      required: [content]
      properties:
        content:
          type: string
        folderId:
          type: string
          format: uuid
```

### 5. Create openapi-generator-config.yaml

```yaml
generate:
  - types
  - client
accessModifier: internal
```

### 6. Create .gitignore

```gitignore
# Xcode
*.xcodeproj
*.xcworkspace
xcuserdata/
DerivedData/
*.xcscmblueprint
*.xccheckout

# Carthage
Carthage/Build/
Carthage/Checkouts/

# Swift Package Manager
.build/
.swiftpm/

# CocoaPods (if used)
Pods/

# Generated files
*.generated.swift

# OS files
.DS_Store
*.swp
*~

# IDE
.idea/
*.sublime-*

# Secrets
*.xcconfig
!*.sample.xcconfig
```

### 7. Create CoreData Model

Create `MyApp.xcdatamodeld` with entities:

**NoteEntity:**
- `id`: UUID
- `content`: String
- `createdAt`: Date
- `modifiedAt`: Date
- `folder`: Relationship to FolderEntity

**FolderEntity:**
- `id`: UUID
- `name`: String
- `createdAt`: Date
- `notes`: Relationship to NoteEntity (to-many)

### 8. Create CoreDataStack

```swift
// CoreDataStack.swift
import CoreData

class CoreDataStack {
    static let shared = CoreDataStack()
    
    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "MyApp")
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Failed to load Core Data stack: \(error)")
            }
        }
        return container
    }()
    
    var viewContext: NSManagedObjectContext {
        persistentContainer.viewContext
    }
    
    func saveContext() {
        let context = viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                fatalError("Failed to save context: \(error)")
            }
        }
    }
}
```

### 9. Create APIConfiguration

```swift
// APIConfiguration.swift
import Foundation

struct APIConfiguration {
    let serverURL: URL?
    let apiKey: String?
    
    var isRemoteConfigured: Bool {
        serverURL != nil
    }
    
    static func load() -> APIConfiguration {
        if let urlString = ProcessInfo.processInfo.environment["API_SERVER_URL"],
           let url = URL(string: urlString) {
            return APIConfiguration(
                serverURL: url,
                apiKey: ProcessInfo.processInfo.environment["API_KEY"]
            )
        }
        
        if let urlString = UserDefaults.standard.string(forKey: "apiServerURL"),
           let url = URL(string: urlString) {
            return APIConfiguration(
                serverURL: url,
                apiKey: UserDefaults.standard.string(forKey: "apiKey")
            )
        }
        
        return APIConfiguration(serverURL: nil, apiKey: nil)
    }
    
    static let local = APIConfiguration(serverURL: nil, apiKey: nil)
}
```

### 10. Create DependencyContainer

```swift
// DependencyContainer.swift
import Foundation
import OpenAPIRuntime

@MainActor
final class DependencyContainer: ObservableObject {
    static let shared = DependencyContainer()
    
    private var _coreDataStack: CoreDataStack?
    private var _apiConfiguration: APIConfiguration?
    private var _transport: (any ClientTransport)?
    private var _client: Client?
    
    init() {}
    
    @discardableResult
    func withCoreDataStack(_ stack: CoreDataStack) -> DependencyContainer {
        _coreDataStack = stack
        _transport = nil
        _client = nil
        return self
    }
    
    @discardableResult
    func withAPIConfiguration(_ config: APIConfiguration) -> DependencyContainer {
        _apiConfiguration = config
        _transport = nil
        _client = nil
        return self
    }
    
    static func create() -> DependencyContainer {
        DependencyContainer()
    }
    
    var coreDataStack: CoreDataStack {
        _coreDataStack ?? .shared
    }
    
    var apiConfiguration: APIConfiguration {
        _apiConfiguration ?? .load()
    }
    
    var transport: any ClientTransport {
        if let existing = _transport { return existing }
        
        let newTransport: any ClientTransport
        if apiConfiguration.isRemoteConfigured {
            newTransport = AuthenticatedTransport(apiKey: apiConfiguration.apiKey)
        } else {
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
    
    // Add repository and ViewModel factories here
}
```

### 11. Generate OpenAPI Code

```bash
// turbo
swift run swift-openapi-generator generate \
  --config MyApp/openapi-generator-config.yaml \
  --output-directory MyApp/Data/API/Generated \
  MyApp/openapi.yaml
```

### 12. Generate Xcode Project

```bash
// turbo
xcodegen generate
```

### 13. Open and Build

```bash
open MyApp.xcodeproj
```

### 14. Verify Setup

```bash
// turbo
xcodebuild build -project MyApp.xcodeproj -scheme MyApp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.2'
```

## Configuration Files Summary

| File | Purpose |
|------|---------|
| `project.yml` | XcodeGen project specification |
| `Package.swift` | Swift Package Manager for OpenAPI generator |
| `openapi.yaml` | API specification (source of truth) |
| `openapi-generator-config.yaml` | OpenAPI generator settings |
| `.gitignore` | Git ignore patterns |
| `MyApp.xcdatamodeld` | CoreData model |

## Next Steps

After setup, use these workflows:
- `/openapi-clean-architecture` - Add new entities and repositories
- `/testing` - Add tests following TDD patterns
