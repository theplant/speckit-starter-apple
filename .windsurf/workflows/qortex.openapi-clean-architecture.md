---
description: OpenAPI and Clean Architecture patterns for iOS apps
---

# OpenAPI and Clean Architecture Workflow

This workflow guides implementing the hybrid repository architecture with OpenAPI for sync-capable data and direct CoreData for local-only data.

## When to Use This Workflow

- Adding new data entities that need remote sync capability
- Creating OpenAPI-backed repositories
- Setting up local CoreData transport for offline mode
- Configuring remote server connection

## Architecture Overview

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
├──────────────────────┼──────────────────────────────────────┤
│   OpenAPI Client     │         CoreDataStack                │
├──────────────────────┼──────────────────────────────────────┤
│ Remote │ Local       │                                      │
│Transport│Transport   │         CoreData                     │
└──────────────────────┴──────────────────────────────────────┘
```

## Steps

### 1. Determine Repository Type

Decide if your data needs OpenAPI or direct CoreData:

| Use OpenAPI Repository | Use Direct CoreData Repository |
|------------------------|--------------------------------|
| Data may sync to server | Data is local-only |
| Needs online/offline support | No remote equivalent |
| Part of the API contract | App-specific settings |
| Examples: Notes, Folders, Users | Examples: Settings, Cache, Drafts |

### 2. For OpenAPI Repository - Define API Spec

Add operations to `openapi.yaml`:

```yaml
paths:
  /notes:
    get:
      operationId: getNotes
      summary: Get all notes
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
```

### 3. Regenerate OpenAPI Code

```bash
// turbo
swift run swift-openapi-generator generate \
  --config NotesApp/openapi-generator-config.yaml \
  --output-directory NotesApp/Data/API/Generated \
  NotesApp/openapi.yaml
```

### 4. Update LocalCoreDataTransport

Add handler for new operations in `LocalCoreDataTransport.swift`:

```swift
switch operationID {
case "createNote":
    return try await handleCreateNote(body: body)
case "getNotes":
    return try await handleGetNotes(request: request)
// Add new operation handlers here
default:
    throw LocalTransportError.operationNotImplemented(operationID)
}
```

### 5. Create Domain Mapping

Add mapping extensions in `DomainMapping.swift`:

```swift
extension Components.Schemas.Note {
    func toDomain() -> Note {
        Note(
            id: UUID(uuidString: id) ?? UUID(),
            content: content,
            createdAt: // parse date,
            modifiedAt: // parse date,
            folderId: folderId.flatMap { UUID(uuidString: $0) }
        )
    }
}
```

### 6. Create OpenAPI Repository

```swift
final class OpenAPINoteRepository: NoteRepositoryProtocol {
    private let client: Client
    
    init(client: Client) {
        self.client = client
    }
    
    func getAll() async throws -> [Note] {
        let response = try await client.getNotes()
        switch response {
        case .ok(let okResponse):
            let notes = try okResponse.body.json
            return notes.map { $0.toDomain() }
        default:
            throw RepositoryError.requestFailed
        }
    }
}
```

### 7. For Direct CoreData Repository

Create repository that directly uses CoreDataStack:

```swift
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
}
```

### 8. Register in DependencyContainer

```swift
// For OpenAPI repository
var noteRepository: NoteRepositoryProtocol {
    _noteRepository ?? OpenAPINoteRepository(client: client)
}

// For direct CoreData repository
var settingsRepository: SettingsRepositoryProtocol {
    _settingsRepository ?? SettingsRepository(coreDataStack: coreDataStack)
}
```

### 9. Configure Remote Server (Optional)

Set environment variables or UserDefaults:

```swift
// Environment variables (for CI/testing)
API_SERVER_URL=https://api.example.com
API_KEY=your-api-key

// Or UserDefaults (for user configuration)
UserDefaults.standard.set("https://api.example.com", forKey: "apiServerURL")
UserDefaults.standard.set("your-api-key", forKey: "apiKey")
```

### 10. Run Tests

```bash
// turbo
xcodegen generate && xcodebuild test -project NotesApp.xcodeproj -scheme NotesApp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.2'
```

## Key Files

- `openapi.yaml` - API specification (source of truth)
- `openapi-generator-config.yaml` - Generator configuration
- `Data/API/Generated/` - Generated OpenAPI code
- `Data/API/LocalCoreDataTransport.swift` - Local CoreData transport
- `Data/API/AuthenticatedTransport.swift` - Remote URLSession transport
- `Data/API/APIConfiguration.swift` - Server URL/API key config
- `Data/Repositories/OpenAPI*Repository.swift` - OpenAPI repositories
- `Data/Repositories/*Repository.swift` - Direct CoreData repositories
- `DI/DependencyContainer.swift` - Dependency injection
