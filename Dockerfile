# Use .NET SDK image with side-by-side multi-SDK support on Linux
FROM mcr.microsoft.com/dotnet/sdk:8.0

# Install Java runtime (required by SonarScanner) and utilities
RUN apt-get update && \
    apt-get install -y --no-install-recommends default-jre unzip curl && \
    rm -rf /var/lib/apt/lists/*

# Install additional .NET SDKs (6.0, 7.0, 9.0) side-by-side
RUN curl -sSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh \
    && chmod +x /tmp/dotnet-install.sh \
    && /tmp/dotnet-install.sh --channel 6.0 --install-dir /usr/share/dotnet --skip-non-versioned-files \
    && /tmp/dotnet-install.sh --channel 7.0 --install-dir /usr/share/dotnet --skip-non-versioned-files \
    && /tmp/dotnet-install.sh --channel 9.0 --install-dir /usr/share/dotnet --skip-non-versioned-files \
    && rm /tmp/dotnet-install.sh

# Install SonarScanner for .NET as global tool (for .NET Core/8+ projects)
RUN dotnet tool install --global dotnet-sonarscanner --version 11.2.0

# Install generic SonarScanner CLI (for .NET Framework / non-buildable projects)
ENV SONAR_SCANNER_VERSION=6.2.1.4610
RUN curl -sSL "https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux-x64.zip" \
        -o /tmp/sonar-scanner.zip && \
    unzip /tmp/sonar-scanner.zip -d /opt && \
    mv /opt/sonar-scanner-${SONAR_SCANNER_VERSION}-linux-x64 /opt/sonar-scanner && \
    rm /tmp/sonar-scanner.zip

# Add dotnet tools and sonar-scanner to PATH
ENV PATH="/root/.dotnet/tools:/opt/sonar-scanner/bin:${PATH}"

# Set working directory
WORKDIR /workspace

# Default command
CMD ["bash"]
