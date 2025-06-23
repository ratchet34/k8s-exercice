# Deploy Kubernetes Application - PowerShell Script for Windows
# This script deploys the complete Kubernetes application stack

param(
    [string]$Action = "deploy"
)

# Colors for output
$colors = @{
    Red = "Red"
    Green = "Green"
    Yellow = "Yellow"
    Blue = "Cyan"
}

function Write-Status {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor $colors.Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor $colors.Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor $colors.Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor $colors.Red
}

# Function to check if kubectl is available
function Test-Kubectl {
    try {
        $null = kubectl version --client 2>$null
        Write-Success "kubectl is available"
        return $true
    }
    catch {
        Write-Error "kubectl not found. Please install kubectl first."
        return $false
    }
}

# Function to check if cluster is accessible
function Test-Cluster {
    try {
        $null = kubectl cluster-info 2>$null
        Write-Success "Kubernetes cluster is accessible"
        return $true
    }
    catch {
        Write-Error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
        return $false
    }
}

# Function to wait for pods to be ready
function Wait-ForPods {
    param(
        [string]$Namespace,
        [string]$App,
        [int]$Timeout = 300
    )
    
    Write-Status "Waiting for $App pods to be ready in namespace $Namespace..."
    
    try {
        kubectl wait --for=condition=ready pod -l app=$App -n $Namespace --timeout="${Timeout}s" 2>$null
        Write-Success "$App pods are ready"
        return $true
    }
    catch {
        Write-Error "$App pods failed to become ready within $Timeout seconds"
        return $false
    }
}

# Function to check if a deployment is ready
function Test-Deployment {
    param(
        [string]$Namespace,
        [string]$Deployment
    )
    
    Write-Status "Checking deployment $Deployment in namespace $Namespace..."
    
    try {
        kubectl rollout status deployment/$Deployment -n $Namespace --timeout=300s 2>$null
        Write-Success "Deployment $Deployment is ready"
        return $true
    }
    catch {
        Write-Error "Deployment $Deployment failed to roll out"
        return $false
    }
}

# Main deployment function
function Deploy-Application {
    Write-Status "Starting Kubernetes application deployment..."
    
    # Check prerequisites
    if (-not (Test-Kubectl)) { exit 1 }
    if (-not (Test-Cluster)) { exit 1 }
    
    # Get script directory - More robust method
    $ScriptDir = if ($PSScriptRoot) {
        $PSScriptRoot
    } elseif ($MyInvocation.MyCommand.Path) {
        Split-Path -Parent $MyInvocation.MyCommand.Path
    } else {
        # Fallback: assume we're in the scripts directory
        Get-Location
    }
    
    Write-Status "Script directory: $ScriptDir"
    
    # Try different possible locations for manifests
    $PossibleManifestPaths = @(
        (Join-Path $ScriptDir "..\manifests"),
        (Join-Path (Split-Path $ScriptDir -Parent) "manifests"),
        "D:\Dev\k8s-exercice\correction\manifests",
        ".\manifests",
        "..\manifests"
    )
    
    $ManifestsDir = $null
    foreach ($Path in $PossibleManifestPaths) {
        if (Test-Path $Path) {
            $ManifestsDir = $Path
            break
        }
    }
    
    if (-not $ManifestsDir) {
        Write-Error "Manifests directory not found in any of the expected locations:"
        foreach ($Path in $PossibleManifestPaths) {
            Write-Host "  - $Path" -ForegroundColor Yellow
        }
        Write-Host ""
        Write-Host "Please ensure you're running the script from the correct directory or that the manifests exist." -ForegroundColor Yellow
        exit 1
    }
    
    Write-Status "Using manifests directory: $ManifestsDir"
    
    try {
        # 1. Deploy namespaces
        Write-Status "1. Deploying namespaces..."
        kubectl apply -f "$ManifestsDir\00-namespaces.yaml"
        Write-Success "Namespaces deployed"
        
        # 2. Deploy storage
        Write-Status "2. Deploying storage (PV and PVC)..."
        kubectl apply -f "$ManifestsDir\01-storage\"
        Write-Success "Storage deployed"
        
        # Wait for PVCs to be bound
        Write-Status "Waiting for PVCs to be bound..."
        kubectl wait --for=condition=bound pvc --all -n production --timeout=60s
        Write-Success "PVCs are bound"
        
        # 3. Deploy configuration
        Write-Status "3. Deploying configuration (ConfigMaps and Secrets)..."
        kubectl apply -f "$ManifestsDir\02-config\"
        Write-Success "Configuration deployed"
        
        # 4. Deploy database
        Write-Status "4. Deploying PostgreSQL database..."
        kubectl apply -f "$ManifestsDir\03-database\"
        Write-Success "Database deployment submitted"
        
        # Wait for database to be ready
        Wait-ForPods -Namespace "production" -App "postgres" -Timeout 300
        Test-Deployment -Namespace "production" -Deployment "postgres-deployment"
        
        # 5. Deploy cache
        Write-Status "5. Deploying Redis cache..."
        kubectl apply -f "$ManifestsDir\04-cache\"
        Write-Success "Cache deployment submitted"
        
        # Wait for Redis to be ready
        Wait-ForPods -Namespace "production" -App "redis" -Timeout 180
        Test-Deployment -Namespace "production" -Deployment "redis-deployment"
        
        # 6. Run database migration
        Write-Status "6. Running database migration..."
        kubectl apply -f "$ManifestsDir\08-jobs\migration-job.yaml"
        
        # Wait for migration job to complete
        Write-Status "Waiting for database migration to complete..."
        try {
            kubectl wait --for=condition=complete job/database-migration-job -n production --timeout=600s
            Write-Success "Database migration completed successfully"
        }
        catch {
            Write-Warning "Database migration may have failed. Check job logs:"
            kubectl logs job/database-migration-job -n production
        }
        
        # 7. Deploy backend
        Write-Status "7. Deploying backend application..."
        kubectl apply -f "$ManifestsDir\05-backend\"
        Write-Success "Backend deployment submitted"
        
        # Wait for backend to be ready
        Wait-ForPods -Namespace "production" -App "backend" -Timeout 300
        Test-Deployment -Namespace "production" -Deployment "backend-deployment"
        
        # 8. Deploy frontend
        Write-Status "8. Deploying frontend application..."
        kubectl apply -f "$ManifestsDir\06-frontend\"
        Write-Success "Frontend deployment submitted"
        
        # Wait for frontend to be ready
        Wait-ForPods -Namespace "production" -App "frontend" -Timeout 300
        Test-Deployment -Namespace "production" -Deployment "frontend-deployment"
        
        # 9. Deploy ingress
        Write-Status "9. Deploying ingress..."
        kubectl apply -f "$ManifestsDir\07-ingress\"
        Write-Success "Ingress deployed"
        
        # 10. Deploy CronJob
        Write-Status "10. Deploying log cleanup CronJob..."
        kubectl apply -f "$ManifestsDir\08-jobs\cleanup-cronjob.yaml"
        Write-Success "CronJob deployed"
        
        # 11. Deploy security policies
        Write-Status "11. Deploying network policies..."
        kubectl apply -f "$ManifestsDir\09-security\"
        Write-Success "Security policies deployed"
        
        Write-Success "All components deployed successfully!"
    }
    catch {
        Write-Error "Deployment failed: $_"
        exit 1
    }
}

# Function to show deployment status
function Show-Status {
    Write-Status "Deployment Status Summary:"
    Write-Host "==================================" -ForegroundColor $colors.Blue
    
    Write-Host ""
    Write-Status "Namespaces:"
    kubectl get namespaces production monitoring --no-headers 2>$null
    
    Write-Host ""
    Write-Status "Persistent Volumes:"
    kubectl get pv --no-headers 2>$null
    
    Write-Host ""
    Write-Status "Persistent Volume Claims:"
    kubectl get pvc -n production --no-headers 2>$null
    
    Write-Host ""
    Write-Status "Deployments:"
    kubectl get deployments -n production --no-headers 2>$null
    
    Write-Host ""
    Write-Status "Services:"
    kubectl get services -n production --no-headers 2>$null
    
    Write-Host ""
    Write-Status "Ingress:"
    kubectl get ingress -n production --no-headers 2>$null
    
    Write-Host ""
    Write-Status "HPA (Horizontal Pod Autoscaler):"
    kubectl get hpa -n production --no-headers 2>$null
    
    Write-Host ""
    Write-Status "Jobs:"
    kubectl get jobs -n production --no-headers 2>$null
    
    Write-Host ""
    Write-Status "CronJobs:"
    kubectl get cronjobs -n production --no-headers 2>$null
    
    Write-Host ""
    Write-Status "Pods:"
    kubectl get pods -n production --no-headers 2>$null
    
    Write-Host ""
    Write-Status "Network Policies:"
    kubectl get networkpolicies -n production --no-headers 2>$null
}

# Function to get access information
function Show-AccessInfo {
    Write-Host ""
    Write-Status "Access Information:"
    Write-Host "===================" -ForegroundColor $colors.Blue
    
    # Get ingress IP
    $IngressIP = kubectl get ingress app-ingress -n production -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
    if (-not $IngressIP) {
        $IngressIP = kubectl get ingress app-ingress -n production -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>$null
    }
    
    if ($IngressIP) {
        Write-Host "🌐 Application URL: https://myapp.local" -ForegroundColor $colors.Green
        Write-Host "   (Add '$IngressIP myapp.local' to your C:\Windows\System32\drivers\etc\hosts file)" -ForegroundColor $colors.Yellow
    } else {
        Write-Warning "Ingress IP not yet available. You may need to wait a few minutes."
    }
    
    # Get LoadBalancer service
    $LB_IP = kubectl get service frontend-service -n production -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
    if ($LB_IP) {
        Write-Host "🌐 Direct Frontend Access: http://$LB_IP" -ForegroundColor $colors.Green
    }
    
    Write-Host ""
    # Write-Host "📊 Useful commands:" -ForegroundColor $colors.Blue
    Write-Host "  kubectl get pods -n production"
    Write-Host "  kubectl get services -n production"
    Write-Host "  kubectl get ingress -n production"
    Write-Host "  kubectl logs -f deployment/backend-deployment -n production"
    Write-Host "  kubectl logs -f deployment/frontend-deployment -n production"
}

# Main execution
switch ($Action.ToLower()) {
    "deploy" {
        Deploy-Application
        Show-Status
        Show-AccessInfo
    }
    "status" {
        Show-Status
        Show-AccessInfo    }
    "help" {
        Write-Host "Usage: .\deploy.ps1 [deploy|status|help]"
        Write-Host "  deploy  - Deploy the entire application stack (default)"
        Write-Host "  status  - Show current deployment status"
        Write-Host "  help    - Show this help message"
    }
    default {
        Write-Error "Unknown command: $Action"
        Write-Host "Use '.\deploy.ps1 help' for usage information"
        exit 1
    }
}
