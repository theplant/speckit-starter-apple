# Real Device UI Testing Workflow

This workflow guides running UI tests on real iPhone devices with AI-friendly terminal output for debugging and analysis.

## When to Use This Workflow

- Running UI tests on a physical iPhone device
- Debugging test failures with full terminal output
- Extracting screenshots and test artifacts for AI review
- Verifying app behavior on real hardware (vs simulator)

## Prerequisites

### Required Tools

```bash
# Install xcparse for extracting screenshots from .xcresult
brew install chargepoint/xcparse/xcparse

# Install xcresultparser for AI-friendly test output
brew install xcresultparser
```

### Device Setup

1. Connect iPhone via USB cable
2. Trust the computer on the device
3. Ensure device is unlocked during test execution
4. Device must be registered in Apple Developer account

## Steps

### 1. List Available Devices

Find your connected device's ID:

```bash
// turbo
xcrun xctrace list devices 2>&1 | grep -E "iPhone|iPad" | grep -v Simulator
```

Output format: `DeviceName (iOS Version) (Device-UUID)`

Example: `FMGG (26.2) (00008150-000144891A42401C)`

### 2. Verify Project Signing

Ensure `project.yml` has a valid `DEVELOPMENT_TEAM`:

```yaml
settings:
  base:
    DEVELOPMENT_TEAM: "YOUR_TEAM_ID"
    CODE_SIGN_STYLE: Automatic
```

If team ID is missing, find it:
```bash
// turbo
grep -r "DEVELOPMENT_TEAM" *.xcodeproj/project.pbxproj | grep -v '""' | head -1
```

After updating `project.yml`, regenerate the project:
```bash
xcodegen generate
```

### 3. Run UI Tests on Real Device

**Basic command structure:**

```bash
xcodebuild test \
  -project PROJECT.xcodeproj \
  -scheme SCHEME_NAME \
  -destination 'platform=iOS,id=DEVICE_UUID' \
  -only-testing:TARGET/TestClass/testMethod \
  -resultBundlePath /tmp/test-results.xcresult \
  -allowProvisioningUpdates \
  2>&1 | tee /tmp/test-output.log
```

**Key parameters:**
- `-destination 'platform=iOS,id=DEVICE_UUID'` - Target real device by UUID
- `-resultBundlePath` - Save test results to specific location for extraction
- `-allowProvisioningUpdates` - Auto-create/update provisioning profiles
- `2>&1 | tee` - Capture all output to file AND terminal

**Example for QuickAnswers project:**

```bash
# Remove old results first
rm -rf /tmp/test-results.xcresult

# Run specific test
xcodebuild test \
  -project QuickAnswers.xcodeproj \
  -scheme QuickAnswers \
  -destination 'platform=iOS,id=00008150-000144891A42401C' \
  -only-testing:QuickAnswersUITests/SettingsTests/test_Settings_CompleteFlow \
  -resultBundlePath /tmp/test-results.xcresult \
  -allowProvisioningUpdates \
  2>&1 | tee /tmp/test-output.log
```

### 4. Extract AI-Friendly Test Summary

After test completes, generate readable output:

**Colored CLI output (best for terminal review):**
```bash
// turbo
xcresultparser -o cli /tmp/test-results.xcresult
```

**Markdown output (best for AI analysis):**
```bash
// turbo
xcresultparser -o md /tmp/test-results.xcresult > /tmp/test-summary.md
```

**Text output:**
```bash
// turbo
xcresultparser -o txt /tmp/test-results.xcresult > /tmp/test-summary.txt
```

### 5. Extract Screenshots

Extract all screenshots from test run:

```bash
// turbo
xcparse screenshots /tmp/test-results.xcresult /tmp/test-screenshots --test
```

This creates a folder structure:
```
/tmp/test-screenshots/
└── TestClassName/
    └── testMethodName()/
        ├── Screenshot-DeviceName-StepName_0_UUID.png
        └── ...
```

### 6. AI Review Process

**AI MUST review all extracted artifacts:**

1. **Read test summary:**
   ```
   Read /tmp/test-summary.md or /tmp/test-summary.txt
   ```

2. **List screenshots:**
   ```bash
   find /tmp/test-screenshots -name "*.png"
   ```

3. **View each screenshot** using `read_file` tool and check for:
   - Upside-down/mirrored text (coordinate system bugs)
   - Misalignments or layout issues
   - Text cut-off or truncation
   - Wrong content or values
   - Missing UI elements
   - Error states or unexpected alerts
   - Empty areas where content should appear

4. **Check test output log for errors:**
   ```bash
   grep -E "(error|Error|ERROR|failed|Failed|FAILED)" /tmp/test-output.log
   ```

## Troubleshooting

### Signing Errors

**Error:** `Signing for "TARGET" requires a development team`

**Fix:** Add `DEVELOPMENT_TEAM` to `project.yml` and regenerate:
```bash
xcodegen generate
```

**Error:** `No profiles for 'BUNDLE_ID' were found`

**Fix:** Add `-allowProvisioningUpdates` flag to xcodebuild command.

### Device Not Found

**Error:** `Unable to find a destination matching the provided destination specifier`

**Fix:** 
1. Check device is connected: `xcrun xctrace list devices`
2. Ensure device is unlocked
3. Trust computer on device if prompted
4. Use correct device UUID in `-destination`

### Keychain Access

**Error:** Password prompt during build

**Fix:** Unlock keychain before running (may require user interaction):
```bash
security unlock-keychain ~/Library/Keychains/login.keychain-db
```

### Test Timeout

**Error:** Test times out waiting for elements

**Fix:** Real devices may be slower than simulators. Check:
1. Device is not in low power mode
2. Device has sufficient battery
3. No other apps consuming resources

## Complete Example Script

```bash
#!/bin/bash
# run-device-tests.sh

DEVICE_ID="00008150-000144891A42401C"
PROJECT="QuickAnswers.xcodeproj"
SCHEME="QuickAnswers"
TEST_TARGET="QuickAnswersUITests"
RESULT_PATH="/tmp/test-results.xcresult"
SCREENSHOT_PATH="/tmp/test-screenshots"
LOG_PATH="/tmp/test-output.log"

# Clean previous results
rm -rf "$RESULT_PATH" "$SCREENSHOT_PATH"

# Run tests
echo "🧪 Running tests on device $DEVICE_ID..."
xcodebuild test \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "platform=iOS,id=$DEVICE_ID" \
  -resultBundlePath "$RESULT_PATH" \
  -allowProvisioningUpdates \
  2>&1 | tee "$LOG_PATH"

# Check exit code
if [ $? -eq 0 ]; then
  echo "✅ Tests passed!"
else
  echo "❌ Tests failed!"
fi

# Generate summary
echo "📊 Generating test summary..."
xcresultparser -o md "$RESULT_PATH" > /tmp/test-summary.md
xcresultparser -o cli "$RESULT_PATH"

# Extract screenshots
echo "📸 Extracting screenshots..."
xcparse screenshots "$RESULT_PATH" "$SCREENSHOT_PATH" --test

echo ""
echo "📁 Artifacts:"
echo "  - Summary: /tmp/test-summary.md"
echo "  - Screenshots: $SCREENSHOT_PATH"
echo "  - Full log: $LOG_PATH"
echo "  - Raw results: $RESULT_PATH"
```

## Output Formats Reference

| Format | Command | Best For |
|--------|---------|----------|
| CLI (colored) | `-o cli` | Terminal review |
| Markdown | `-o md` | AI analysis, documentation |
| Text | `-o txt` | Plain text processing |
| JUnit XML | `-o junit` | CI/CD integration |
| HTML | `-o html` | Human-readable reports |

## Notes

- Real device tests may behave differently than simulator tests
- Keychain operations work on real devices (unlike simulator)
- Network conditions on device may differ from development machine
- Always review screenshots to catch visual issues
- Keep device unlocked and plugged in during long test runs
