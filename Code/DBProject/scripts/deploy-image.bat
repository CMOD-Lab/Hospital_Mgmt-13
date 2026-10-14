@echo off
setlocal enabledelayedexpansion

:: =============================================================
:: deploy-image.bat - Deploy DBProject to AWS EKS
:: Application: Clinic Management System (ASP.NET Web Forms)
:: Target: AWS EKS (Windows node group)
:: Usage: scripts\deploy-image.bat
:: Run from repository root directory
:: =============================================================

set APP_NAME=dbproject
set NAMESPACE=dbproject
set K8S_DIR=Code\DBProject\kubernetes
set TEMP_DIR=%TEMP%\dbproject-k8s-deploy

echo ==============================================
echo  DBProject - AWS EKS Deployment
echo ==============================================
echo.

:: ── AWS / EKS configuration ──────────────────────────────────
set /p AWS_REGION="Enter AWS Region (e.g. us-east-1): "
if "!AWS_REGION!"=="" (
    echo ERROR: AWS Region is required.
    exit /b 1
)

set /p CLUSTER_NAME="Enter EKS Cluster Name: "
if "!CLUSTER_NAME!"=="" (
    echo ERROR: EKS Cluster Name is required.
    exit /b 1
)

:: ── Docker image URI ─────────────────────────────────────────
set /p IMAGE_URI="Enter full Docker image URI (e.g. 123456789.dkr.ecr.us-east-1.amazonaws.com/dbproject:latest): "
if "!IMAGE_URI!"=="" (
    echo ERROR: Docker image URI is required.
    exit /b 1
)

echo.
echo -- Application Environment Variables --
echo Press Enter to skip any variable.
echo.

set /p DB_CONNECTION_STRING="Enter DB_CONNECTION_STRING (or press Enter to skip): "
set /p DB_HOST="Enter DB_HOST (or press Enter to skip): "
set /p DB_NAME_INPUT="Enter DB_NAME [DBProject]: "
if "!DB_NAME_INPUT!"=="" (
    set DB_NAME=DBProject
) else (
    set DB_NAME=!DB_NAME_INPUT!
)
set /p DB_USER="Enter DB_USER (or press Enter to skip): "
set /p DB_PASSWORD="Enter DB_PASSWORD (or press Enter to skip): "
set /p REDIS_HOST="Enter REDIS_HOST (or press Enter to skip): "
set /p REDIS_PORT_INPUT="Enter REDIS_PORT [6379]: "
if "!REDIS_PORT_INPUT!"=="" (
    set REDIS_PORT=6379
) else (
    set REDIS_PORT=!REDIS_PORT_INPUT!
)
set /p REDIS_ACCESS_KEY="Enter REDIS_ACCESS_KEY (or press Enter to skip): "
set /p APPINSIGHTS_INSTRUMENTATIONKEY="Enter APPINSIGHTS_INSTRUMENTATIONKEY (or press Enter to skip): "

echo.
echo -- Configuring kubectl for EKS --
aws eks update-kubeconfig --region !AWS_REGION! --name !CLUSTER_NAME!
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to configure kubectl for EKS cluster.
    exit /b 1
)

echo Verifying cluster connectivity...
kubectl cluster-info
if !ERRORLEVEL! neq 0 (
    echo ERROR: Cannot connect to EKS cluster.
    exit /b 1
)

echo.
echo -- Preparing Kubernetes manifests --

:: Copy manifests to temp directory
if exist "!TEMP_DIR!" rmdir /s /q "!TEMP_DIR!"
mkdir "!TEMP_DIR!"
xcopy /s /e /q "!K8S_DIR!\*" "!TEMP_DIR!\"

:: Replace placeholders using PowerShell
powershell -Command ^
  "(Get-Content '!TEMP_DIR!\deployment.yaml') ^
   -replace '{{IMAGE_URI}}', '!IMAGE_URI!' ^
   -replace '{{DB_CONNECTION_STRING}}', '!DB_CONNECTION_STRING!' ^
   -replace '{{DB_HOST}}', '!DB_HOST!' ^
   -replace '{{DB_NAME}}', '!DB_NAME!' ^
   -replace '{{DB_USER}}', '!DB_USER!' ^
   -replace '{{DB_PASSWORD}}', '!DB_PASSWORD!' ^
   -replace '{{REDIS_HOST}}', '!REDIS_HOST!' ^
   -replace '{{REDIS_PORT}}', '!REDIS_PORT!' ^
   -replace '{{REDIS_ACCESS_KEY}}', '!REDIS_ACCESS_KEY!' ^
   -replace '{{APPINSIGHTS_INSTRUMENTATIONKEY}}', '!APPINSIGHTS_INSTRUMENTATIONKEY!' ^
   | Set-Content '!TEMP_DIR!\deployment.yaml'"

if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to update deployment manifest.
    exit /b 1
)

echo.
echo -- Applying Kubernetes manifests --

echo 1/4 Applying namespace...
kubectl apply -f "!TEMP_DIR!\namespace.yaml"
if !ERRORLEVEL! neq 0 ( echo ERROR: Failed to apply namespace. & exit /b 1 )

echo 2/4 Applying deployment...
kubectl apply -f "!TEMP_DIR!\deployment.yaml"
if !ERRORLEVEL! neq 0 ( echo ERROR: Failed to apply deployment. & exit /b 1 )

echo 3/4 Applying service...
kubectl apply -f "!TEMP_DIR!\service.yaml"
if !ERRORLEVEL! neq 0 ( echo ERROR: Failed to apply service. & exit /b 1 )

echo 4/4 Applying ingress...
kubectl apply -f "!TEMP_DIR!\ingress.yaml"
if !ERRORLEVEL! neq 0 ( echo ERROR: Failed to apply ingress. & exit /b 1 )

echo.
echo -- Waiting for deployment rollout --
kubectl rollout status deployment/!APP_NAME! -n !NAMESPACE! --timeout=300s
if !ERRORLEVEL! neq 0 (
    echo ERROR: Deployment rollout failed or timed out.
    echo Rollback command: kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
    exit /b 1
)

echo.
echo -- Verifying deployed resources --
kubectl get pods,svc,ingress -n !NAMESPACE!

echo.
echo -- Application Access URL --
for /f "tokens=*" %%i in ('kubectl get ingress !APP_NAME!-ingress -n !NAMESPACE! -o jsonpath^="{.status.loadBalancer.ingress[0].hostname}" 2^>nul') do set INGRESS_HOST=%%i
if "!INGRESS_HOST!"=="" set INGRESS_HOST=^<pending^>
echo   Application URL: http://!INGRESS_HOST!
echo   Health Check   : http://!INGRESS_HOST!/health
echo.
echo   NOTE: If the URL shows pending, wait a few minutes for the
echo         AWS Load Balancer to be provisioned, then run:
echo         kubectl get ingress -n !NAMESPACE!

:: Cleanup temp files
rmdir /s /q "!TEMP_DIR!" 2>nul

echo.
echo ==============================================
echo  Deployment Complete!
echo  Namespace : !NAMESPACE!
echo  Image     : !IMAGE_URI!
echo ==============================================
echo.
echo Rollback command (if needed):
echo   kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!

endlocal
exit /b 0
