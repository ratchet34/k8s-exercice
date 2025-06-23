# Cleanup Kubernetes Application - PowerShell Script for Windows
# This script removes all resources created by the Kubernetes application

param(
    [string]$Action = "cleanup"
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

# Function to safely delete resources
function Remove-ResourceSafely {
    param(
        [string]$ResourceType,
        [string]$ResourceName,
        [string]$Namespace = ""
    )
    
    $kubectlCmd = "kubectl delete $ResourceType $ResourceName --ignore-not-found=true --timeout=60s"
    if ($Namespace) {
        $kubectlCmd += " -n $Namespace"
    }
    
    try {
        Invoke-Expression $kubectlCmd
        Write-Success "Deleted $ResourceType/$ResourceName"
    }
    catch {
        Write-Warning "Failed to delete $ResourceType/$ResourceName or resource not found"
    }
}

# Function to wait for resource deletion
function Wait-ForDeletion {
    param(
        [string]$ResourceType,
        [string]$Namespace = "",
        [int]$Timeout = 120
    )
    
    $kubectlCmd = "kubectl get $ResourceType --no-headers"
    if ($Namespace) {
        $kubectlCmd += " -n $Namespace"
    }
    
    Write-Status "Waiting for $ResourceType to be deleted..."
    $count = 0
    while ($count -lt $Timeout) {
        try {
            $result = Invoke-Expression "$kubectlCmd 2>$null"
            if (-not $result) {
                Write-Success "$ResourceType deleted successfully"
                return $true
            }
        }
        catch {
            Write-Success "$ResourceType deleted successfully"
            return $true
        }
        Start-Sleep 5
        $count += 5
    }
    
    Write-Warning "$ResourceType still exists after ${Timeout}s timeout"
    return $false
}

# Function to force delete stuck resources
function Remove-StuckResources {
    Write-Warning "Attempting to force delete stuck resources..."
    
    # Force delete stuck pods
    try {
        $pods = kubectl get pods -n production --no-headers 2>$null
        if ($pods) {
            $pods | ForEach-Object {
                $podName = ($_ -split '\s+')[0]
                if ($podName) {
                    kubectl delete pod $podName -n production --force --grace-period=0 2>$null
                }
            }
        }
    }
    catch { }
    
    # Patch finalizers on stuck PVCs
    try {
        $pvcs = kubectl get pvc -n production -o name 2>$null
        if ($pvcs) {
            $pvcs | ForEach-Object {
                kubectl patch $_ -n production -p '{"metadata":{"finalizers":null}}' 2>$null
            }
        }
    }
    catch { }
    
    # Patch finalizers on stuck PVs
    try {
        $pvs = kubectl get pv -o name 2>$null | Where-Object { $_ -match "(postgres|redis|shared-logs)" }
        if ($pvs) {
            $pvs | ForEach-Object {
                kubectl patch $_ -p '{"metadata":{"finalizers":null}}' 2>$null
            }
        }
    }
    catch { }
}

# Main cleanup function
function Remove-Application {
    Write-Status "Starting Kubernetes application cleanup..."
    
    # Check prerequisites
    if (-not (Test-Kubectl)) { exit 1 }
    if (-not (Test-Cluster)) { exit 1 }
    
    # Get script directory
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $ManifestsDir = Join-Path $ScriptDir "..\manifests"
    
    # Ask for confirmation
    $confirmation = Read-Host "Are you sure you want to delete all application resources? This action cannot be undone. (y/N)"
    if ($confirmation -notmatch '^[Yy]$') {
        Write-Status "Cleanup cancelled."
        exit 0
    }
    
    try {
        # 1. Delete network policies
        Write-Status "1. Removing network policies..."
        if (Test-Path "$ManifestsDir\09-security\network-policies.yaml") {
            kubectl delete -f "$ManifestsDir\09-security\network-policies.yaml" --ignore-not-found=true
        } else {
            Remove-ResourceSafely -ResourceType "networkpolicies" -ResourceName "--all" -Namespace "production"
        }
        Write-Success "Network policies removed"
        
        # 2. Delete ingress
        Write-Status "2. Removing ingress..."
        if (Test-Path "$ManifestsDir\07-ingress\ingress.yaml") {
            kubectl delete -f "$ManifestsDir\07-ingress\ingress.yaml" --ignore-not-found=true
        } else {
            Remove-ResourceSafely -ResourceType "ingress" -ResourceName "--all" -Namespace "production"
        }
        Write-Success "Ingress removed"
        
        # 3. Delete CronJobs and Jobs
        Write-Status "3. Removing jobs and cronjobs..."
        if (Test-Path "$ManifestsDir\08-jobs") {
            kubectl delete -f "$ManifestsDir\08-jobs\" --ignore-not-found=true
        } else {
            Remove-ResourceSafely -ResourceType "cronjobs" -ResourceName "--all" -Namespace "production"
            Remove-ResourceSafely -ResourceType "jobs" -ResourceName "--all" -Namespace "production"
        }
        Write-Success "Jobs and CronJobs removed"
        
        # 4. Delete HPA
        Write-Status "4. Removing HPA (Horizontal Pod Autoscalers)..."
        Remove-ResourceSafely -ResourceType "hpa" -ResourceName "--all" -Namespace "production"
        Write-Success "HPA removed"
        
        # 5. Delete frontend
        Write-Status "5. Removing frontend..."
        if (Test-Path "$ManifestsDir\06-frontend") {
            kubectl delete -f "$ManifestsDir\06-frontend\" --ignore-not-found=true
        } else {
            Remove-ResourceSafely -ResourceType "deployment" -ResourceName "frontend-deployment" -Namespace "production"
            Remove-ResourceSafely -ResourceType "service" -ResourceName "frontend-service" -Namespace "production"
        }
        Write-Success "Frontend removed"
        
        # 6. Delete backend
        Write-Status "6. Removing backend..."
        if (Test-Path "$ManifestsDir\05-backend") {
            kubectl delete -f "$ManifestsDir\05-backend\" --ignore-not-found=true
        } else {
            Remove-ResourceSafely -ResourceType "deployment" -ResourceName "backend-deployment" -Namespace "production"
            Remove-ResourceSafely -ResourceType "service" -ResourceName "backend-service" -Namespace "production"
        }
        Write-Success "Backend removed"
        
        # 7. Delete cache (Redis)
        Write-Status "7. Removing Redis cache..."
        if (Test-Path "$ManifestsDir\04-cache") {
            kubectl delete -f "$ManifestsDir\04-cache\" --ignore-not-found=true
        } else {
            Remove-ResourceSafely -ResourceType "deployment" -ResourceName "redis-deployment" -Namespace "production"
            Remove-ResourceSafely -ResourceType "service" -ResourceName "redis-service" -Namespace "production"
        }
        Write-Success "Redis cache removed"
        
        # 8. Delete database (PostgreSQL)
        Write-Status "8. Removing PostgreSQL database..."
        if (Test-Path "$ManifestsDir\03-database") {
            kubectl delete -f "$ManifestsDir\03-database\" --ignore-not-found=true
        } else {
            Remove-ResourceSafely -ResourceType "deployment" -ResourceName "postgres-deployment" -Namespace "production"
            Remove-ResourceSafely -ResourceType "service" -ResourceName "postgres-service" -Namespace "production"
        }
        Write-Success "PostgreSQL database removed"
        
        # Wait for pods to be deleted
        Write-Status "Waiting for pods to terminate..."
        Wait-ForDeletion -ResourceType "pods" -Namespace "production" -Timeout 180
        
        # 9. Delete configuration
        Write-Status "9. Removing configuration (ConfigMaps and Secrets)..."
        if (Test-Path "$ManifestsDir\02-config") {
            kubectl delete -f "$ManifestsDir\02-config\" --ignore-not-found=true
        } else {
            Remove-ResourceSafely -ResourceType "configmaps" -ResourceName "--all" -Namespace "production"
            Remove-ResourceSafely -ResourceType "secrets" -ResourceName "--all" -Namespace "production"
        }
        Write-Success "Configuration removed"
        
        # 10. Delete storage
        Write-Status "10. Removing storage..."
        if (Test-Path "$ManifestsDir\01-storage\persistent-volume-claims.yaml") {
            kubectl delete -f "$ManifestsDir\01-storage\persistent-volume-claims.yaml" --ignore-not-found=true
        } else {
            Remove-ResourceSafely -ResourceType "pvc" -ResourceName "--all" -Namespace "production"
        }
        
        # Wait for PVCs to be deleted
        Write-Status "Waiting for PVCs to be deleted..."
        Wait-ForDeletion -ResourceType "pvc" -Namespace "production" -Timeout 120
        
        # Delete PVs
        if (Test-Path "$ManifestsDir\01-storage\persistent-volumes.yaml") {
            kubectl delete -f "$ManifestsDir\01-storage\persistent-volumes.yaml" --ignore-not-found=true
        } else {
            Remove-ResourceSafely -ResourceType "pv" -ResourceName "postgres-pv"
            Remove-ResourceSafely -ResourceType "pv" -ResourceName "redis-pv"
            Remove-ResourceSafely -ResourceType "pv" -ResourceName "shared-logs-pv"
        }
        Write-Success "Storage removed"
        
        # Check for stuck resources
        $stuckPods = kubectl get pods -n production --no-headers 2>$null
        if ($stuckPods) {
            Write-Warning "Some pods are still running. Attempting force deletion..."
            Remove-StuckResources
            Start-Sleep 10
        }
        
        # 11. Delete namespaces
        Write-Status "11. Removing namespaces..."
        if (Test-Path "$ManifestsDir\00-namespaces.yaml") {
            kubectl delete -f "$ManifestsDir\00-namespaces.yaml" --ignore-not-found=true
        } else {
            Remove-ResourceSafely -ResourceType "namespace" -ResourceName "production"
            Remove-ResourceSafely -ResourceType "namespace" -ResourceName "monitoring"
        }
        
        # Wait for namespaces to be deleted
        Write-Status "Waiting for namespaces to be deleted..."
        Wait-ForDeletion -ResourceType "namespace production" -Timeout 300
        
        Write-Success "All application resources have been removed!"
    }
    catch {
        Write-Error "Cleanup failed: $_"
        exit 1
    }
}

# Function to show remaining resources
function Show-RemainingResources {
    Write-Status "Checking for remaining resources..."
    
    Write-Host ""
    Write-Status "Remaining namespaces:"
    try {
        kubectl get namespaces production monitoring --no-headers 2>$null
    }
    catch {
        Write-Host "No target namespaces found"
    }
    
    Write-Host ""
    Write-Status "Remaining PVs:"
    try {
        $pvs = kubectl get pv --no-headers 2>$null | Where-Object { $_ -match "(postgres|redis|shared-logs)" }
        if ($pvs) {
            $pvs
        } else {
            Write-Host "No target PVs found"
        }
    }
    catch {
        Write-Host "No target PVs found"
    }
    
    Write-Host ""
    Write-Status "All production resources:"
    try {
        kubectl get all -n production --no-headers 2>$null
    }
    catch {
        Write-Host "Production namespace not found or empty"
    }
    
    # Check for stuck resources
    try {
        $stuckPods = kubectl get pods -n production --no-headers 2>$null | Measure-Object | Select-Object -ExpandProperty Count
        $stuckPVCs = kubectl get pvc -n production --no-headers 2>$null | Measure-Object | Select-Object -ExpandProperty Count
        
        if ($stuckPods -gt 0 -or $stuckPVCs -gt 0) {
            Write-Warning "Found $stuckPods stuck pods and $stuckPVCs stuck PVCs"
            Write-Host "You may need to manually clean these up or run the force cleanup option."
        } else {
            Write-Success "No stuck resources detected"
        }
    }
    catch {
        Write-Success "No stuck resources detected"
    }
}

# Function to force cleanup stuck resources
function Invoke-ForceCleanup {
    Write-Warning "Performing force cleanup of stuck resources..."
    
    $confirmation = Read-Host "This will forcefully delete stuck resources. Are you sure? (y/N)"
    if ($confirmation -notmatch '^[Yy]$') {
        Write-Status "Force cleanup cancelled."
        exit 0
    }
    
    Remove-StuckResources
    
    # Force delete namespace if it exists
    try {
        $null = kubectl get namespace production 2>$null
        Write-Status "Force deleting production namespace..."
        kubectl patch namespace production -p '{"metadata":{"finalizers":null}}' 2>$null
        kubectl delete namespace production --force --grace-period=0 2>$null
    }
    catch { }
    
    try {
        $null = kubectl get namespace monitoring 2>$null
        Write-Status "Force deleting monitoring namespace..."
        kubectl patch namespace monitoring -p '{"metadata":{"finalizers":null}}' 2>$null
        kubectl delete namespace monitoring --force --grace-period=0 2>$null
    }
    catch { }
    
    Write-Success "Force cleanup completed"
}

# Main execution
switch ($Action.ToLower()) {
    "cleanup" {
        Remove-Application
        Show-RemainingResources
    }
    "check" {
        Show-RemainingResources
    }
    "force" {
        Invoke-ForceCleanup
        Show-RemainingResources
    }
    "help" {
        Write-Host "Usage: .\cleanup.ps1 [cleanup|check|force|help]"
        Write-Host "  cleanup - Remove all application resources (default)"
        Write-Host "  check   - Check for remaining resources"
        Write-Host "  force   - Force delete stuck resources"
        Write-Host "  help    - Show this help message"
    }
    default {
        Write-Error "Unknown command: $Action"
        Write-Host "Use '.\cleanup.ps1 help' for usage information"
        exit 1
    }
}
