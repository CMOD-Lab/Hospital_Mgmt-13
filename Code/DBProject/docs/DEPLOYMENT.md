# Deployment Guide — Clinic Management System (DBProject)

## Overview

This guide covers the complete deployment of the **Clinic Management System** (ASP.NET Web Forms, .NET Framework 4.5.2) to **AWS EKS** using Windows containers.

| Property | Value |
|---|---|
| Application | Clinic Management System |
| Technology | ASP.NET Web Forms (.NET Framework 4.5.2) |
| Container Type | Windows Server Core (IIS) |
| Runtime Base Image | `mcr.microsoft.com/dotnet/framework/aspnet:4.5.2` |
| Build Base Image | `mcr.microsoft.com/dotnet/framework/sdk:4.8-windowsservercore-ltsc2019` |
| Port | 80 (HTTP / IIS) |
| Health Endpoint | `GET /health` |
| Target Platform | AWS EKS (Windows node group) |

---

## Prerequisites

### Local Development
- Docker Desktop for Windows with **Windows containers** mode enabled
- .NET Framework 4.5.2 SDK (for local builds)
- Visual Studio 2019+ or MSBuild 16+

### AWS EKS Deployment
- AWS CLI v2 (`aws --version`)
- `kubectl` v1.24+ (`kubectl version --client`)
- `eksctl` (optional, for cluster creation)
- AWS IAM permissions:
  - `eks:DescribeCluster`, `eks:UpdateKubeconfig`
  - `ecr:GetAuthorizationToken`, `ecr:CreateRepository`, `ecr:PutImage`
  - `ec2:DescribeInstances` (for node group management)

---

## 1. Local Development Setup

### 1.1 Switch Docker to Windows Containers

Right-click the Docker Desktop tray icon → **Switch to Windows containers**.

### 1.2 Configure Environment Variables

Create a `.env` file in the project root (never commit this file):

```env
DB_CONNECTION_STRING=Data Source=<sql-host>;Initial Catalog=DBProject;User ID=<user>;Password=<pass>;
DB_HOST=<sql-host>
DB_NAME=DBProject
DB_USER=<sql-user>
DB_PASSWORD=<sql-password>
REDIS_HOST=<redis-host>
REDIS_PORT=6379
REDIS_ACCESS_KEY=<redis-key>
APPINSIGHTS_INSTRUMENTATIONKEY=<ai-key>
```

### 1.3 Build and Run Locally with Docker Compose

```bash
# From repository root
docker-compose -f Code/DBProject/docker-compose.yml up --build
```

Access the application at: `http://localhost:80`  
Health check: `http://localhost:80/health`

### 1.4 Stop Local Environment

```bash
docker-compose -f Code/DBProject/docker-compose.yml down
```

---

## 2. Build and Push Docker Image

### 2.1 Using the Build Script (Linux/macOS)

```bash
chmod +x Code/DBProject/scripts/build-push.sh
./Code/DBProject/scripts/build-push.sh
```

### 2.2 Using the Build Script (Windows)

```cmd
Code\DBProject\scripts\build-push.bat
```

Both scripts will interactively prompt for:
1. Image tag (default: `latest`)
2. Registry type: **AWS ECR** or **Docker Hub**
3. Registry credentials and repository details

The scripts automatically:
- Sanitize the image name to Docker tag compliance (lowercase, hyphens)
- Authenticate to the selected registry
- Auto-create the ECR repository if it does not exist
- Build the Docker image from the repository root
- Push the image to the registry

### 2.3 Manual Build (Advanced)

```bash
# From repository root
docker build \
  -f Code/DBProject/Dockerfile \
  -t <registry>/<repo>:<tag> \
  .

docker push <registry>/<repo>:<tag>
```

---

## 3. AWS EKS Prerequisites

### 3.1 Configure AWS CLI

```bash
aws configure
# Enter: AWS Access Key ID, Secret Access Key, Region, Output format
```

### 3.2 EKS Cluster with Windows Node Group

Your EKS cluster must have a **Windows node group** to run Windows containers.

#### Create Windows Node Group (if not already present)

```bash
eksctl create nodegroup \
  --cluster <cluster-name> \
  --name windows-nodes \
  --node-type m5.xlarge \
  --nodes 2 \
  --nodes-min 1 \
  --nodes-max 4 \
  --node-ami-family WindowsServer2019FullContainer \
  --region <aws-region>
```

#### Enable Windows Support on Existing Cluster

```bash
eksctl utils install-vpc-controllers --cluster <cluster-name> --approve
```

### 3.3 Install AWS Load Balancer Controller

The ingress manifest uses the AWS Load Balancer Controller (ALB Ingress Controller).

```bash
# Install using Helm
helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=<cluster-name> \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

---

## 4. Kubernetes Deployment

### 4.1 Using the Deploy Script (Linux/macOS)

```bash
chmod +x Code/DBProject/scripts/deploy-image.sh
./Code/DBProject/scripts/deploy-image.sh
```

### 4.2 Using the Deploy Script (Windows)

```cmd
Code\DBProject\scripts\deploy-image.bat
```

Both scripts will prompt for:
- AWS Region and EKS Cluster Name
- Full Docker image URI (with registry and tag)
- Application environment variables (DB, Redis, App Insights)

The scripts automatically:
1. Configure `kubectl` for the EKS cluster
2. Verify cluster connectivity
3. Substitute all `{{PLACEHOLDER}}` values in manifests
4. Apply manifests in order: namespace → deployment → service → ingress
5. Wait for deployment rollout completion
6. Display the application URL

### 4.3 Manual Deployment

```bash
# 1. Configure kubectl
aws eks update-kubeconfig --region <region> --name <cluster-name>

# 2. Edit deployment.yaml — replace all {{PLACEHOLDER}} values
#    Required: {{IMAGE_URI}}, {{DB_CONNECTION_STRING}} or {{DB_HOST}}/{{DB_NAME}}/{{DB_USER}}/{{DB_PASSWORD}}
#    Optional: {{REDIS_HOST}}, {{REDIS_PORT}}, {{REDIS_ACCESS_KEY}}, {{APPINSIGHTS_INSTRUMENTATIONKEY}}

# 3. Apply manifests
kubectl apply -f Code/DBProject/kubernetes/namespace.yaml
kubectl apply -f Code/DBProject/kubernetes/deployment.yaml
kubectl apply -f Code/DBProject/kubernetes/service.yaml
kubectl apply -f Code/DBProject/kubernetes/ingress.yaml

# 4. Monitor rollout
kubectl rollout status deployment/dbproject -n dbproject

# 5. Verify resources
kubectl get pods,svc,ingress -n dbproject
```

---

## 5. Kubernetes Manifest Reference

| File | Kind | Description |
|---|---|---|
| `namespace.yaml` | Namespace | Creates the `dbproject` namespace |
| `deployment.yaml` | Deployment | 2 replicas, Windows node selector, health probes |
| `service.yaml` | Service | ClusterIP on port 80, routes to pods |
| `ingress.yaml` | Ingress | AWS ALB, internet-facing, routes to service |

### Environment Variable Placeholders in deployment.yaml

| Placeholder | Description | Required |
|---|---|---|
| `{{IMAGE_URI}}` | Full Docker image URI with tag | ✅ Yes |
| `{{DB_CONNECTION_STRING}}` | Full SQL Server connection string | ✅ (or individual vars) |
| `{{DB_HOST}}` | SQL Server hostname | ✅ (if no full conn string) |
| `{{DB_NAME}}` | Database name | ✅ (default: DBProject) |
| `{{DB_USER}}` | Database username | ✅ (if SQL auth) |
| `{{DB_PASSWORD}}` | Database password | ✅ (if SQL auth) |
| `{{REDIS_HOST}}` | Redis/ElastiCache hostname | ✅ (required for sessions) |
| `{{REDIS_PORT}}` | Redis port | ⬜ (default: 6379) |
| `{{REDIS_ACCESS_KEY}}` | Redis authentication key | ⬜ (if auth enabled) |
| `{{APPINSIGHTS_INSTRUMENTATIONKEY}}` | Application Insights key | ⬜ Optional |

---

## 6. Health Check Endpoint

The application exposes a health check endpoint at `GET /health` implemented by `HealthCheckHandler.cs`.

**Response (HTTP 200):**
```json
{
  "status": "healthy",
  "application": "HospitalManagement",
  "timestamp": "2024-01-15T10:30:00.0000000Z"
}
```

Kubernetes liveness and readiness probes are configured to use this endpoint:
- **Readiness probe**: starts after 60s, checks every 15s
- **Liveness probe**: starts after 90s, checks every 30s

---

## 7. Scaling and Management

### Scale Deployment

```bash
kubectl scale deployment dbproject --replicas=3 -n dbproject
```

### Rolling Update (new image)

```bash
kubectl set image deployment/dbproject \
  dbproject=<new-image-uri> \
  -n dbproject

kubectl rollout status deployment/dbproject -n dbproject
```

### Rollback

```bash
kubectl rollout undo deployment/dbproject -n dbproject
# Rollback to specific revision:
kubectl rollout undo deployment/dbproject --to-revision=2 -n dbproject
```

### Horizontal Pod Autoscaler (HPA)

```bash
kubectl autoscale deployment dbproject \
  --cpu-percent=70 \
  --min=2 \
  --max=6 \
  -n dbproject
```

---

## 8. Troubleshooting

### Pod Not Starting

```bash
# Check pod status
kubectl get pods -n dbproject

# Describe pod for events
kubectl describe pod <pod-name> -n dbproject

# View container logs
kubectl logs <pod-name> -n dbproject
kubectl logs <pod-name> -n dbproject --previous  # crashed container
```

### Common Issues

| Issue | Cause | Resolution |
|---|---|---|
| `ImagePullBackOff` | Cannot pull image from ECR | Verify ECR permissions and image URI |
| `CrashLoopBackOff` | Application startup failure | Check logs; verify DB_CONNECTION_STRING |
| `Pending` pods | No Windows nodes available | Verify Windows node group is running |
| Health probe failing | App not responding on `/health` | Check IIS startup; verify Web.config handler |
| Session errors | Redis not reachable | Verify REDIS_HOST and REDIS_PORT env vars |

### Windows Container Specific

```bash
# Exec into Windows container (PowerShell)
kubectl exec -it <pod-name> -n dbproject -- powershell

# Check IIS status inside container
kubectl exec -it <pod-name> -n dbproject -- powershell -Command "Get-Service W3SVC"

# Check application event log
kubectl exec -it <pod-name> -n dbproject -- powershell -Command "Get-EventLog -LogName Application -Newest 20"
```

### Ingress / Load Balancer Issues

```bash
# Check ingress status
kubectl describe ingress dbproject-ingress -n dbproject

# Check ALB controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

---

## 9. Security Considerations

1. **Secrets Management**: Store `DB_PASSWORD`, `REDIS_ACCESS_KEY`, and `APPINSIGHTS_INSTRUMENTATIONKEY` in Kubernetes Secrets or AWS Secrets Manager — never in plain ConfigMaps.

   ```bash
   kubectl create secret generic dbproject-secrets \
     --from-literal=DB_PASSWORD=<password> \
     --from-literal=REDIS_ACCESS_KEY=<key> \
     -n dbproject
   ```

2. **Network Policies**: Restrict pod-to-pod communication using Kubernetes NetworkPolicies.

3. **ECR Image Scanning**: Enable ECR image scanning on push to detect vulnerabilities.

4. **IAM Roles for Service Accounts (IRSA)**: Use IRSA instead of static AWS credentials for pods that need AWS API access.

5. **TLS/HTTPS**: Configure HTTPS on the ALB ingress using ACM certificates:
   ```yaml
   annotations:
     alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS": 443}]'
     alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:<region>:<account>:certificate/<id>
   ```

6. **SQL Server**: Use SQL Server authentication (not Integrated Security) in containers. Prefer Azure SQL or Amazon RDS for managed database services.

---

## 10. .NET Framework Specific Notes

- **Windows Containers Only**: .NET Framework 4.5.2 requires Windows containers. Linux containers are not supported.
- **IIS Hosting**: The application runs under IIS managed by `ServiceMonitor.exe` in the base image.
- **Application Pool**: Configured for .NET CLR v4.0, AnyCPU, ApplicationPoolIdentity.
- **Session State**: Uses Redis session state provider (`Microsoft.Web.RedisSessionStateProvider`) for distributed sessions across pods. Ensure `REDIS_HOST` is set.
- **Connection Strings**: The DAL layer reads `DB_CONNECTION_STRING` environment variable first, then falls back to individual `DB_HOST`/`DB_NAME`/`DB_USER`/`DB_PASSWORD` variables.
- **Application Insights**: Set `APPINSIGHTS_INSTRUMENTATIONKEY` to enable telemetry collection.
- **EKS Windows Nodes**: Ensure your EKS cluster has Windows node groups with `kubernetes.io/os: windows` label. The deployment manifest includes the required `nodeSelector` and `tolerations`.
