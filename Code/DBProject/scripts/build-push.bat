@echo off
setlocal enabledelayedexpansion

:: =============================================================
:: build-push.bat - Build and push Docker image for DBProject
:: Application: Clinic Management System (ASP.NET Web Forms)
:: Usage: scripts\build-push.bat
:: Run from repository root directory
:: =============================================================

set PROJECT_NAME=dbproject
set DOCKERFILE_PATH=Code\DBProject\Dockerfile

echo ==============================================
echo  DBProject - Docker Build and Push
echo ==============================================
echo.

:: ── Prompt for image tag ─────────────────────────────────────
set /p IMAGE_TAG_INPUT="Enter image tag [latest]: "
if "!IMAGE_TAG_INPUT!"=="" (
    set IMAGE_TAG=latest
) else (
    set IMAGE_TAG=!IMAGE_TAG_INPUT!
)
echo   Image tag: !IMAGE_TAG!
echo.

:: ── Registry selection ───────────────────────────────────────
echo Select container registry:
echo   1. AWS ECR
echo   2. Docker Hub
set /p REGISTRY_CHOICE="Enter choice [1]: "
if "!REGISTRY_CHOICE!"=="" set REGISTRY_CHOICE=1

if "!REGISTRY_CHOICE!"=="1" goto :ecr_setup
if "!REGISTRY_CHOICE!"=="2" goto :dockerhub_setup
echo ERROR: Invalid registry choice. Exiting.
exit /b 1

:ecr_setup
echo.
echo -- AWS ECR Configuration --
set /p AWS_REGION="Enter AWS Region (e.g. us-east-1): "
set /p AWS_ACCOUNT_ID="Enter AWS Account ID: "
set /p ECR_REPO_INPUT="Enter ECR repository name [!PROJECT_NAME!]: "
if "!ECR_REPO_INPUT!"=="" (
    set ECR_REPO=!PROJECT_NAME!
) else (
    set ECR_REPO=!ECR_REPO_INPUT!
)

set REGISTRY_URL=!AWS_ACCOUNT_ID!.dkr.ecr.!AWS_REGION!.amazonaws.com
set FULL_IMAGE_NAME=!REGISTRY_URL!/!ECR_REPO!:!IMAGE_TAG!

echo.
echo Logging in to AWS ECR...
aws ecr get-login-password --region !AWS_REGION! | docker login --username AWS --password-stdin !REGISTRY_URL!
if !ERRORLEVEL! neq 0 (
    echo ERROR: ECR login failed.
    exit /b 1
)

echo Checking ECR repository '!ECR_REPO!'...
aws ecr describe-repositories --repository-names !ECR_REPO! --region !AWS_REGION! >nul 2>&1
if !ERRORLEVEL! neq 0 (
    echo Creating ECR repository...
    aws ecr create-repository --repository-name !ECR_REPO! --region !AWS_REGION!
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Failed to create ECR repository.
        exit /b 1
    )
)
echo ECR repository ready.
goto :build_image

:dockerhub_setup
echo.
echo -- Docker Hub Configuration --
set /p DOCKER_USERNAME="Enter Docker Hub username: "
set /p DOCKER_PASSWORD="Enter Docker Hub password/token: "
set /p DOCKERHUB_REPO_INPUT="Enter Docker Hub repository [!DOCKER_USERNAME!/!PROJECT_NAME!]: "
if "!DOCKERHUB_REPO_INPUT!"=="" (
    set DOCKERHUB_REPO=!DOCKER_USERNAME!/!PROJECT_NAME!
) else (
    set DOCKERHUB_REPO=!DOCKERHUB_REPO_INPUT!
)

set FULL_IMAGE_NAME=!DOCKERHUB_REPO!:!IMAGE_TAG!

echo.
echo Logging in to Docker Hub...
echo !DOCKER_PASSWORD! | docker login --username !DOCKER_USERNAME! --password-stdin
if !ERRORLEVEL! neq 0 (
    echo ERROR: Docker Hub login failed.
    exit /b 1
)
goto :build_image

:build_image
echo.
echo Building Docker image...
echo   Image     : !FULL_IMAGE_NAME!
echo   Context   : . (repository root)
echo   Dockerfile: !DOCKERFILE_PATH!
echo.

docker build -f !DOCKERFILE_PATH! -t !FULL_IMAGE_NAME! .
if !ERRORLEVEL! neq 0 (
    echo ERROR: Docker build failed.
    exit /b 1
)

echo.
echo Pushing image to registry...
docker push !FULL_IMAGE_NAME!
if !ERRORLEVEL! neq 0 (
    echo ERROR: Docker push failed.
    exit /b 1
)

echo.
echo ==============================================
echo  Build and Push Complete!
echo  Image: !FULL_IMAGE_NAME!
echo ==============================================

endlocal
exit /b 0
