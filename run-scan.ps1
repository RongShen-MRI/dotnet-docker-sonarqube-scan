# ============================================================
# SonarQube Scanner - Run Script
# Supports two scan modes:
#   "dotnet"  - For .NET Core / .NET 8+ projects (build + analyze)
#   "generic" - For .NET Framework / source-only analysis (no build required)
# ============================================================

# Load configuration
. "$PSScriptRoot\scan-config.ps1"

# ---- Setup output logging ----
$outputDir = Join-Path $PSScriptRoot "output"
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}
$logFileName = (Get-Date -Format "yyyyMMdd-HHmmss") + ".txt"
$logFilePath = Join-Path $outputDir $logFileName
Start-Transcript -Path $logFilePath -Append

Write-Host "============================================" -ForegroundColor Cyan
Write-Host " SonarQube Scanner for .NET" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Scan Mode     : $SCAN_MODE"
Write-Host "Project Key   : $SONAR_PROJECT_KEY"
Write-Host "Project Name  : $SONAR_PROJECT_NAME"
Write-Host "Workspace     : $WORKSPACE_PATH"
Write-Host "SonarQube URL : $SONAR_HOST_URL"
if ($SCAN_MODE -eq "dotnet") {
    Write-Host "SDK Version   : $DOTNET_SDK_VERSION"
}
Write-Host ""

# ---- Check SonarQube Server container ----
Write-Host "Checking SonarQube server container '$SONAR_SERVER_CONTAINER'..." -ForegroundColor Yellow

$containerExists = docker ps -a --filter "name=^${SONAR_SERVER_CONTAINER}$" --format "{{.ID}}"
if (-not $containerExists) {
    Write-Host "ERROR: SonarQube server container '$SONAR_SERVER_CONTAINER' does not exist." -ForegroundColor Red
    Write-Host "Please create the container first (e.g., docker run -d --name $SONAR_SERVER_CONTAINER -p 9000:9000 sonarqube:community)." -ForegroundColor Red
    Stop-Transcript
    exit 1
}

$containerRunning = docker ps --filter "name=^${SONAR_SERVER_CONTAINER}$" --format "{{.ID}}"
if (-not $containerRunning) {
    Write-Host "SonarQube server container is stopped. Starting it..." -ForegroundColor Yellow
    docker start $SONAR_SERVER_CONTAINER | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to start SonarQube server container '$SONAR_SERVER_CONTAINER'." -ForegroundColor Red
        Stop-Transcript
        exit 1
    }
    Write-Host "Container '$SONAR_SERVER_CONTAINER' started." -ForegroundColor Green
}
else {
    Write-Host "SonarQube server container is already running." -ForegroundColor Green
}

# Wait for SonarQube API to be ready
$healthUrl = ($SONAR_HOST_URL -replace "host\.docker\.internal", "localhost") + "/api/system/status"
Write-Host "Waiting for SonarQube server to be ready at $healthUrl ..." -ForegroundColor Yellow

$maxRetries = 12
$retryDelay = 10
$serverReady = $false

for ($i = 1; $i -le $maxRetries; $i++) {
    try {
        $response = Invoke-RestMethod -Uri $healthUrl -Method Get -TimeoutSec 10 -ErrorAction Stop
        if ($response.status -eq "UP") {
            Write-Host "SonarQube server is UP." -ForegroundColor Green
            $serverReady = $true
            break
        }
        else {
            Write-Host "SonarQube server status: $($response.status). Waiting ${retryDelay}s... ($i/$maxRetries)" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "SonarQube server not ready yet. Waiting ${retryDelay}s... ($i/$maxRetries)" -ForegroundColor Yellow
    }
    Start-Sleep -Seconds $retryDelay
}

if (-not $serverReady) {
    Write-Host "ERROR: SonarQube server did not become ready after $($maxRetries * $retryDelay) seconds." -ForegroundColor Red
    Stop-Transcript
    exit 1
}

# Validate workspace path
if (-not (Test-Path $WORKSPACE_PATH)) {
    Write-Host "ERROR: Workspace path does not exist: $WORKSPACE_PATH" -ForegroundColor Red
    Stop-Transcript
    exit 1
}

# Remove existing container if it exists
$existing = docker ps -a --filter "name=^${CONTAINER_NAME}$" --format "{{.ID}}"
if ($existing) {
    Write-Host "Removing existing container '$CONTAINER_NAME'..." -ForegroundColor Yellow
    docker rm -f $CONTAINER_NAME | Out-Null
}

if ($SCAN_MODE -eq "dotnet") {
    # ---- .NET Core / .NET 8+ mode: begin → build → end ----
    $scanCommand = @"
set -e

echo '=========================================='
echo 'Installed .NET SDKs:'
echo '=========================================='
dotnet --list-sdks
echo ''

DOTNET_SDK_VERSION="$DOTNET_SDK_VERSION"

if [ "`$DOTNET_SDK_VERSION" = "auto" ]; then
    echo '=========================================='
    echo 'Auto-detecting target frameworks...'
    echo '=========================================='
    TFMS=`$(grep -roh --include='*.csproj' --include='*.fsproj' --include='*.vbproj' \
        '<TargetFramework[s]*>[^<]*</TargetFramework[s]*>' /workspace 2>/dev/null \
        | sed 's/<[^>]*>//g' | tr ';' '\n' | sort -u || true)

    if [ -n "`$TFMS" ]; then
        echo "Detected target frameworks:"
        echo "`$TFMS" | while read -r tf; do echo "  - `$tf"; done
    else
        echo "(No target frameworks detected from project files)"
    fi
    echo ''

    if echo "`$TFMS" | grep -qE 'netcoreapp[23]\.'; then
        echo 'WARNING: .NET Core 2.x/3.x target(s) detected. These SDKs are EOL and not installed.' >&2
        echo '         Consider using SCAN_MODE="generic" for source-only analysis.' >&2
        echo ''
    fi

    if echo "`$TFMS" | grep -qE '^net[0-9]{2,3}$'; then
        echo 'WARNING: .NET Framework target(s) detected (e.g., net48). These cannot be built on Linux.' >&2
        echo '         Consider using SCAN_MODE="generic" for source-only analysis.' >&2
        echo ''
    fi

    if [ -f /workspace/global.json ]; then
        echo 'Note: Using existing global.json from workspace.'
        echo ''
    fi
else
    echo '=========================================='
    echo "Pinning to .NET SDK `$DOTNET_SDK_VERSION..."
    echo '=========================================='

    SDK_LINE=`$(dotnet --list-sdks | grep "^`$DOTNET_SDK_VERSION" | head -1 || true)
    EXACT_SDK=`$(echo "`$SDK_LINE" | awk '{print `$1}')

    if [ -z "`$EXACT_SDK" ]; then
        echo "ERROR: No SDK matching version `$DOTNET_SDK_VERSION found in container." >&2
        echo "Available SDKs:" >&2
        dotnet --list-sdks >&2
        exit 1
    fi

    echo "Using SDK: `$EXACT_SDK"

    if [ -f /workspace/global.json ]; then
        echo 'Note: Existing global.json found in workspace - it will be respected.'
    else
        echo "Creating temporary global.json to pin SDK `$EXACT_SDK..."
        echo "{\"sdk\":{\"version\":\"`$EXACT_SDK\",\"rollForward\":\"latestFeature\"}}" > /workspace/global.json
        trap 'rm -f /workspace/global.json' EXIT
    fi
    echo ''
fi

echo '=========================================='
echo '[Step 1/3] SonarScanner BEGIN...'
echo '=========================================='
dotnet sonarscanner begin \
    /k:"$SONAR_PROJECT_KEY" \
    /n:"$SONAR_PROJECT_NAME" \
    /d:sonar.host.url="$SONAR_HOST_URL" \
    /d:sonar.token="$SONAR_TOKEN" \
    /d:sonar.cs.opencover.reportsPaths="/workspace/**/coverage.opencover.xml" \
    /d:sonar.exclusions="**/bin/**,**/obj/**,**/node_modules/**,**/wwwroot/lib/**"

echo ''
echo '=========================================='
echo '[Step 2/3] Building the project...'
echo '=========================================='
dotnet build /workspace --no-incremental

echo ''
echo '=========================================='
echo '[Step 3/3] SonarScanner END (uploading)...'
echo '=========================================='
dotnet sonarscanner end \
    /d:sonar.token="$SONAR_TOKEN"

echo ''
echo '=========================================='
echo 'Scan Complete!'
echo '=========================================='
"@
}
else {
    # ---- Generic mode: source-only analysis (for .NET Framework) ----
    $scanCommand = @"
set -e

echo '=========================================='
echo '[Step 1/1] Running SonarScanner analysis...'
echo '=========================================='
sonar-scanner \
    -Dsonar.projectKey="$SONAR_PROJECT_KEY" \
    -Dsonar.projectName="$SONAR_PROJECT_NAME" \
    -Dsonar.sources="/workspace" \
    -Dsonar.host.url="$SONAR_HOST_URL" \
    -Dsonar.token="$SONAR_TOKEN" \
    -Dsonar.sourceEncoding="UTF-8" \
    -Dsonar.exclusions="**/bin/**,**/obj/**,**/node_modules/**,**/wwwroot/lib/**,**/packages/**,**/*.dll,**/*.exe,**/*.pdb"

echo ''
echo '=========================================='
echo 'Scan Complete!'
echo '=========================================='
"@
}

# Convert Windows CRLF to Unix LF (required for bash inside Linux container)
$scanCommand = $scanCommand -replace "`r`n", "`n"

Write-Host "Running scan inside container..." -ForegroundColor Green

# Stop transcript temporarily - Start-Transcript does not reliably capture native command output
Stop-Transcript | Out-Null

docker run --rm `
    --name $CONTAINER_NAME `
    -v "${WORKSPACE_PATH}:/workspace" `
    $DOCKER_IMAGE `
    bash -c $scanCommand 2>&1 | ForEach-Object {
        $line = $_.ToString()
        Write-Host $line
        Add-Content -Path $logFilePath -Value $line -Encoding UTF8
    }

$scanExitCode = $LASTEXITCODE

# Resume transcript
Start-Transcript -Path $logFilePath -Append | Out-Null

if ($scanExitCode -ne 0) {
    Write-Host ""
    Write-Host "ERROR: Scan failed. Check the output above for details." -ForegroundColor Red
    Stop-Transcript
    exit 1
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host " Scan Complete!" -ForegroundColor Green
Write-Host " View results at:" -ForegroundColor Green
Write-Host " $SONAR_HOST_URL/dashboard?id=$SONAR_PROJECT_KEY" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Green
Write-Host "Log saved to: $logFilePath" -ForegroundColor Gray

Stop-Transcript
