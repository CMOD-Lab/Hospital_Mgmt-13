# ============================================================
# Dockerfile for Clinic Management System (ASP.NET Web Forms)
# Technology: ASP.NET Web Forms on .NET Framework 4.5.2
# Base Runtime Image: mcr.microsoft.com/dotnet/framework/aspnet:4.5.2
# Build Image: mcr.microsoft.com/dotnet/framework/sdk:4.8-windowsservercore-ltsc2019
# Target: AWS EKS Windows node group deployment
# Health Endpoint: GET /health (HealthCheckHandler.cs)
# Port: 80 (IIS)
# ============================================================

# ---- Build Stage ----
FROM mcr.microsoft.com/dotnet/framework/sdk:4.8-windowsservercore-ltsc2019 AS build

WORKDIR /src

# Copy solution and project files first for NuGet layer caching
COPY ["Code/DBProject/packages.config", "Code/DBProject/"]
COPY ["Code/DBProject/DBProject.csproj", "Code/DBProject/"]
COPY ["Code/DBProject.sln", "Code/"]

# Restore NuGet packages (cached layer if project files unchanged)
RUN nuget restore "Code/DBProject/DBProject.csproj" -PackagesDirectory "Code/packages"

# Copy the rest of the source code
COPY . .

# Build and publish the web application in Release mode
# /p:DebugType=none and /p:DebugSymbols=false ensure no PDB files
# are emitted into the publish output, keeping the image lean.
RUN msbuild "Code/DBProject/DBProject.csproj" \
    /p:Configuration=Release \
    /p:DeployOnBuild=true \
    /p:WebPublishMethod=FileSystem \
    /p:PublishUrl=C:\publish \
    /p:DeleteExistingFiles=True \
    /p:Platform=AnyCPU \
    /p:VisualStudioVersion=16.0 \
    /p:DebugType=none \
    /p:DebugSymbols=false

# Remove residual PDB, source, and temp files from the publish output
RUN powershell -Command \
    Get-ChildItem -Path C:\publish -Recurse -Include *.pdb,*.cs,*.vb,*.csproj,*.sln,*.tmp,*.log,*.cache | \
    Remove-Item -Force -ErrorAction SilentlyContinue; \
    Write-Host 'Build-stage cleanup complete.'

# ---- Runtime Stage ----
# Uses the explicit base image provided: mcr.microsoft.com/dotnet/framework/aspnet:4.5.2
# Only the compiled publish output is copied here — no source code,
# no PDB files, no NuGet packages, no build tooling.
FROM mcr.microsoft.com/dotnet/framework/aspnet:4.5.2 AS runtime

# Set working directory to IIS default web root
WORKDIR /inetpub/wwwroot

# Remove default IIS welcome page
RUN powershell -Command Remove-Item -Recurse -Force C:\inetpub\wwwroot\*

# Copy ONLY the published application output from the build stage
COPY --from=build C:\publish .

# Post-copy cleanup: remove any stray PDB / debug files
RUN powershell -Command \
    Get-ChildItem -Path C:\inetpub\wwwroot -Recurse -Include *.pdb,*.cs,*.vb,*.tmp,*.log | \
    Remove-Item -Force -ErrorAction SilentlyContinue; \
    @('obj','bin\roslyn','bin\Debug') | ForEach-Object { \
        $p = Join-Path C:\inetpub\wwwroot $_; \
        if (Test-Path $p) { Remove-Item -Recurse -Force $p } \
    }; \
    Write-Host 'Runtime-stage cleanup complete.'

# Configure the Default Application Pool to use .NET 4.0 (CLR v4)
RUN powershell -Command \
    Import-Module WebAdministration; \
    Set-ItemProperty 'IIS:\AppPools\DefaultAppPool' managedRuntimeVersion v4.0; \
    Set-ItemProperty 'IIS:\AppPools\DefaultAppPool' enable32BitAppOnWin64 False; \
    Set-WebConfigurationProperty -Filter '/system.applicationHost/applicationPools/add[@name=\"DefaultAppPool\"]' \
        -Name 'processModel.identityType' -Value 'ApplicationPoolIdentity'

# -------------------------------------------------------
# Environment variable placeholders
# Override at runtime via Kubernetes ConfigMap / Secret
# -------------------------------------------------------
# Database connection (prefer DB_CONNECTION_STRING; falls back to individual vars)
ENV DB_CONNECTION_STRING=""
ENV DB_HOST=""
ENV DB_NAME=""
ENV DB_USER=""
ENV DB_PASSWORD=""

# Redis session state (ElastiCache)
ENV REDIS_HOST=""
ENV REDIS_PORT="6379"
ENV REDIS_ACCESS_KEY=""

# Application Insights
ENV APPINSIGHTS_INSTRUMENTATIONKEY=""

# Expose HTTP port (IIS default)
EXPOSE 80

# IIS is started automatically by the base image entrypoint
# (ServiceMonitor.exe monitors the w3svc Windows service)
ENTRYPOINT ["C:\\ServiceMonitor.exe", "w3svc"]
