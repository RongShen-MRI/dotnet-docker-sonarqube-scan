# SonarQube Scanner - Scanning Guide

## Prerequisites

- **Docker Desktop** installed and running
- **SonarQube Server** running and accessible (default: `http://localhost:9000`)
- **SonarQube Token** generated from your SonarQube server
- **Docker image** built: `sonarqube-scanner:test`

---

## File Overview

| File | Purpose |
|---|---|
| `Dockerfile` | Builds the scanner image (.NET 6/7/8/9 SDKs + Java + SonarScanner CLI) |
| `scan-config.ps1` | **Configuration file** - change workspace path, scan mode, and project settings |
| `run-scan.ps1` | Runs the full scan pipeline |
| `SCANNING-GUIDE.md` | This guide |

---

## Scan Modes

| Mode | Use For | How It Works |
|---|---|---|
| `generic` | .NET Framework, mixed projects, source-only | Analyzes source code directly (no build required) |
| `dotnet` | .NET 6 / 7 / 8 / 9 projects | Runs `begin` → `dotnet build` → `end` for deep analysis with SDK auto-detection |

> **Your project (`abell.root`) is .NET Framework**, so use `generic` mode (set by default).

---

## .NET SDK Version Selection

When using `dotnet` scan mode, the container includes multiple .NET SDKs. The `$DOTNET_SDK_VERSION` setting in `scan-config.ps1` controls which SDK is used:

| Value | Behavior |
|---|---|
| `"auto"` (default) | Auto-detects target frameworks from project files. Uses `global.json` if present. |
| `"6.0"` | Pins the build to .NET 6.0 SDK |
| `"7.0"` | Pins the build to .NET 7.0 SDK |
| `"8.0"` | Pins the build to .NET 8.0 SDK |
| `"9.0"` | Pins the build to .NET 9.0 SDK |

### Which mode for which .NET version?

| .NET Version | Recommended Mode | Notes |
|---|---|---|
| .NET 9 | `dotnet` | Fully supported |
| .NET 8 | `dotnet` | Fully supported (LTS) |
| .NET 7 | `dotnet` | Supported |
| .NET 6 | `dotnet` | Supported (LTS) |
| .NET Core 3.x | `generic` | SDK is EOL and not installed; source-only analysis |
| .NET Core 2.x | `generic` | SDK is EOL and not installed; source-only analysis |
| .NET Framework (4.x, 3.5, etc.) | `generic` | Cannot be built on Linux; source-only analysis |

> **Tip:** In `auto` mode, the scanner detects your project's target frameworks and warns you if it finds EOL or .NET Framework targets that can't be built.

---

## Step 1: Build the Docker Image (One-Time Setup)

```powershell
cd path\to\the\Dockerfile
docker build -t sonarqube-scanner:test .
```

> **Note:** The Docker image includes .NET SDKs 6.0, 7.0, 8.0, and 9.0 (~2-3 GB total). You can edit the `Dockerfile` to remove SDKs you don't need to reduce image size.

---

## Step 2: Configure Your Scan

Open `scan-config.ps1` and update the settings:

```powershell
# Scan mode: "generic" for .NET Framework, "dotnet" for .NET 6/7/8/9
$SCAN_MODE = "generic"

# SDK version (for dotnet mode): "auto", "6.0", "7.0", "8.0", "9.0"
$DOTNET_SDK_VERSION = "auto"

# Path to the project you want to scan
$WORKSPACE_PATH = "<Path to your project folder>"

# SonarQube server URL (use host.docker.internal for localhost from Docker)
$SONAR_HOST_URL = "<SonarQube server URL (use host.docker.internal for localhost from Docker)>"

# Your SonarQube authentication token
$SONAR_TOKEN = "<Your SonarQube Token>"

# Project key (unique ID in SonarQube - no spaces)
$SONAR_PROJECT_KEY = "<Unique project key (no spaces)>"

# Project display name in SonarQube dashboard
$SONAR_PROJECT_NAME = "<Project display name>"
```

### To scan a different project

Simply change these values in the config file:
- `$WORKSPACE_PATH` - path to the new project
- `$SONAR_PROJECT_KEY` - unique key (no spaces)
- `$SONAR_PROJECT_NAME` - display name
- `$SCAN_MODE` - `"generic"` or `"dotnet"` depending on project type
- `$DOTNET_SDK_VERSION` - `"auto"` or specific version (`"6.0"`, `"7.0"`, `"8.0"`, `"9.0"`)

---

## Step 3: Run the Scan

```powershell
cd path\to\script\
.\run-scan.ps1
```

### What happens during the scan:

**Generic mode** (for .NET Framework):
1. SonarScanner CLI analyzes all source files in the workspace
2. Results are uploaded to SonarQube server

**Dotnet mode** (for .NET 6/7/8/9):
1. **SDK DETECTION** - Detect/pin the target SDK version
2. **BEGIN** - Initialize SonarScanner analysis and configure rules
3. **BUILD** - Compile the .NET project (`dotnet build`)
4. **END** - Collect analysis results and upload to SonarQube server

---

## Step 4: Verify the Results

### 4.1 Check the Terminal Output

After the scan completes, you should see:

```
==========================================
Scan Complete!
==========================================
```

If any step fails, the script will stop and show an error message.

### 4.2 View Results in SonarQube Dashboard

1. Open your browser and navigate to:
   ```
   http://localhost:9000/dashboard?id=<sonar-project-key>
   ```
   *(Replace `<sonar-project-key>` with your `$SONAR_PROJECT_KEY`)*

2. Log in with your credentials

### 4.3 What to Look For in the Dashboard

| Metric | Description | Where to Find |
|---|---|---|
| **Quality Gate** | Overall pass/fail status | Top of project dashboard |
| **Bugs** | Reliability issues found | Overview tab |
| **Vulnerabilities** | Security issues found | Overview tab |
| **Code Smells** | Maintainability issues | Overview tab |
| **Coverage** | Test coverage percentage | Overview tab |
| **Duplications** | Duplicated code percentage | Overview tab |

### 4.4 Drill Into Issues

1. Click **"Issues"** tab in your project
2. Filter by:
   - **Type**: Bug, Vulnerability, Code Smell
   - **Severity**: Blocker, Critical, Major, Minor, Info
   - **Status**: Open, Confirmed, Resolved
3. Click any issue to see the exact file and line number

### 4.5 Verify via SonarQube API (Optional)

Check project status via API:

```powershell
# Check Quality Gate status
Invoke-RestMethod -Uri "http://localhost:9000/api/qualitygates/project_status?projectKey=<sonar-project-key>" `
    -Headers @{ Authorization = "Bearer <Your SonarQube Token>" }

# List issues
Invoke-RestMethod -Uri "http://localhost:9000/api/issues/search?projectKeys=abell-root&ps=10" `
    -Headers @{ Authorization = "Bearer <Your SonarQube Token>" }
```

---

## Troubleshooting

### "Connection refused" to SonarQube

- Ensure SonarQube server is running on `localhost:9000`
- The Docker container uses `host.docker.internal` to reach your host machine
- Check: `docker run --rm sonarqube-scanner:test curl -s http://host.docker.internal:9000/api/system/status`

### "dotnet build" fails (dotnet mode only)

- Ensure your solution/project file (`.sln` or `.csproj`) is in the workspace root
- If the solution has NuGet dependencies, they will be restored automatically during build
- The container has .NET SDKs 6.0, 7.0, 8.0, and 9.0 — check that your project targets one of these
- Try setting `$DOTNET_SDK_VERSION` to match your project's target framework
- If your project has a `global.json`, ensure it specifies an installed SDK version
- For .NET Framework projects, switch to `generic` mode instead

### .NET Core 2.x / 3.x projects

- These SDKs are end-of-life and not included in the Docker image
- Use `$SCAN_MODE = "generic"` for source-only analysis (no build)
- The scanner will warn you in `auto` mode if it detects these targets

### Wrong SDK version used

- Set `$DOTNET_SDK_VERSION` to the specific version you need (e.g., `"8.0"`)
- If your project has a `global.json`, it takes precedence over the config setting
- Run `docker run --rm sonarqube-scanner:test dotnet --list-sdks` to see installed versions

### SonarScanner fails

- Verify your token is valid and not expired
- Verify the project key does not contain spaces or special characters
- Check that SonarQube server is accessible from inside the container

### "Permission denied" on mounted volume

- On Windows with Docker Desktop, ensure the drive is shared in Docker settings
- Go to Docker Desktop → Settings → Resources → File Sharing

---

## Quick Reference - Scanning Another Project

```powershell
# 1. Edit the config
notepad <path-to-scan-config>\scan-config.ps1

# 2. Change these values:
#    $SCAN_MODE          = "generic"  (or "dotnet" for .NET 6/7/8/9)
#    $DOTNET_SDK_VERSION = "auto"     (or "6.0", "7.0", "8.0", "9.0")
#    $WORKSPACE_PATH     = "C:\path\to\your\other\project"
#    $SONAR_PROJECT_KEY = "other-project-key"
#    $SONAR_PROJECT_NAME = "Other Project Name"

# 3. Run the scan
.\run-scan.ps1
```
