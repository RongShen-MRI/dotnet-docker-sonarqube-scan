# ============================================================
# SonarQube Scanner Configuration
# Update these values to match your project and environment
# ============================================================

# -- Scan Mode --
# "generic" = Source-only analysis (for .NET Framework projects - no build needed)
# "dotnet"  = Full analysis with build (for .NET 6 / 7 / 8 / 9 projects)
$SCAN_MODE = "generic"

# -- .NET SDK Version (for "dotnet" scan mode only) --
# "auto"  = Auto-detect from project files / use project's global.json (recommended)
# "6.0", "7.0", "8.0", "9.0" = Pin to a specific SDK version
$DOTNET_SDK_VERSION = "auto"

# -- Workspace to scan (local path to your .NET solution/project) --
$WORKSPACE_PATH = "Path\To\Your\Project"

# -- SonarQube Server --
$SONAR_HOST_URL = "http://host.docker.internal:9000"

# -- SonarQube Authentication Token --
$SONAR_TOKEN = "Your_SonarQube_Token"

# -- SonarQube Project Key (unique identifier for your project) --
$SONAR_PROJECT_KEY = "Your_Project_Key"

# -- SonarQube Project Name (display name in SonarQube dashboard) --
$SONAR_PROJECT_NAME = "Your_Project_Name"

# -- Docker image name --
$DOCKER_IMAGE = "sonarqube-scanner:test"

# -- Container name (scanner) --
$CONTAINER_NAME = "sonarqube-scanner"

# -- SonarQube Server container name --
$SONAR_SERVER_CONTAINER = "sonarqube"

# -- SonarQube Exclusions (glob patterns, comma-separated) --
$SONAR_EXCLUSIONS = "**/bin/**,**/obj/**,**/node_modules/**,**/wwwroot/lib/**,**/packages/**,**/*.dll,**/*.exe,**/*.pdb"
