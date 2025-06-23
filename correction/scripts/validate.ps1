# Validate Kubernetes Application Deployment - PowerShell Script for Windows
# This script validates that all components are properly deployed and functioning

param(
    [string]$Action = "validate"
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
    Write-Host "[✓] $Message" -ForegroundColor $colors.Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[⚠] $Message" -ForegroundColor $colors.Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[✗] $Message" -ForegroundColor $colors.Red
}

# Test results
$script:TestsPassed = 0
$script:TestsFailed = 0
$script:TestsWarning = 0

# Function to record test result
function Record-Test {
    param(
        [string]$Status,
        [string]$Message
    )
    
    switch ($Status) {
        "PASS" {
            Write-Success $Message
            $script:TestsPassed++
        }
        "FAIL" {
            Write-Error $Message
            $script:TestsFailed++
        }
        "WARN" {
            Write-Warning $Message
            $script:TestsWarning++
        }
    }
}

# Function to check prerequisites
function Test-Prerequisites {
    Write-Status "Checking prerequisites..."
    
    try {
        $null = kubectl version --client 2>$null
        Record-Test "PASS" "kubectl is available"
    }
    catch {
        Record-Test "FAIL" "kubectl not found"
        return $false
    }
    
    try {
        $null = kubectl cluster-info 2>$null
        Record-Test "PASS" "Kubernetes cluster is accessible"
    }
    catch {
        Record-Test "FAIL" "Cannot connect to Kubernetes cluster"
        return $false
    }
    
    return $true
}

# Function to validate namespaces
function Test-Namespaces {
    Write-Status "Validating namespaces..."
    
    @("production", "monitoring") | ForEach-Object {
        try {
            $null = kubectl get namespace $_ 2>$null
            Record-Test "PASS" "Namespace $_ exists"
        }
        catch {
            Record-Test "FAIL" "Namespace $_ does not exist"
        }
    }
}

# Function to validate storage
function Test-Storage {
    Write-Status "Validating storage..."
    
    # Check PVs
    @("postgres-pv", "redis-pv", "shared-logs-pv") | ForEach-Object {
        try {
            $status = kubectl get pv $_ -o jsonpath='{.status.phase}' 2>$null
            if ($status -eq "Bound") {
                Record-Test "PASS" "PV $_ is bound"
            }
            elseif ($status -eq "Available") {
                Record-Test "WARN" "PV $_ is available but not bound"
            }
            else {
                Record-Test "FAIL" "PV $_ is not available (status: $status)"
            }
        }
        catch {
            Record-Test "FAIL" "PV $_ not found"
        }
    }
    
    # Check PVCs
    @("postgres-pvc", "redis-pvc", "shared-logs-pvc") | ForEach-Object {
        try {
            $status = kubectl get pvc $_ -n production -o jsonpath='{.status.phase}' 2>$null
            if ($status -eq "Bound") {
                Record-Test "PASS" "PVC $_ is bound"
            }
            else {
                Record-Test "FAIL" "PVC $_ is not bound (status: $status)"
            }
        }
        catch {
            Record-Test "FAIL" "PVC $_ not found"
        }
    }
}

# Function to validate deployments
function Test-Deployments {
    Write-Status "Validating deployments..."
    
    @("postgres-deployment", "redis-deployment", "backend-deployment", "frontend-deployment") | ForEach-Object {
        try {
            $ready = kubectl get deployment $_ -n production -o jsonpath='{.status.readyReplicas}' 2>$null
            $desired = kubectl get deployment $_ -n production -o jsonpath='{.spec.replicas}' 2>$null
            
            if ($ready -eq $desired -and [int]$ready -gt 0) {
                Record-Test "PASS" "Deployment $_ is ready ($ready/$desired replicas)"
            }
            else {
                Record-Test "FAIL" "Deployment $_ is not ready ($ready/$desired replicas)"
            }
        }
        catch {
            Record-Test "FAIL" "Deployment $_ not found"
        }
    }
}

# Function to validate services
function Test-Services {
    Write-Status "Validating services..."
    
    @("postgres-service", "redis-service", "backend-service", "frontend-service") | ForEach-Object {
        try {
            $endpoints = kubectl get endpoints $_ -n production -o jsonpath='{.subsets[*].addresses[*].ip}' 2>$null
            $endpointCount = ($endpoints -split ' ' | Where-Object { $_ }).Count
            if ($endpointCount -gt 0) {
                Record-Test "PASS" "Service $_ has $endpointCount endpoints"
            }
            else {
                Record-Test "FAIL" "Service $_ has no endpoints"
            }
        }
        catch {
            Record-Test "FAIL" "Service $_ not found"
        }
    }
}

# Function to validate pod health
function Test-PodHealth {
    Write-Status "Validating pod health..."
    
    @("postgres", "redis", "backend", "frontend") | ForEach-Object {
        $app = $_
        try {
            $runningPods = kubectl get pods -n production -l app=$app --field-selector=status.phase=Running --no-headers 2>$null
            $totalPods = kubectl get pods -n production -l app=$app --no-headers 2>$null
            
            $runningCount = if ($runningPods) { ($runningPods | Measure-Object).Count } else { 0 }
            $totalCount = if ($totalPods) { ($totalPods | Measure-Object).Count } else { 0 }
            
            if ($runningCount -eq $totalCount -and $runningCount -gt 0) {
                Record-Test "PASS" "All $app pods are running ($runningCount/$totalCount)"
            }
            else {
                Record-Test "FAIL" "$app pods not all running ($runningCount/$totalCount)"
            }
            
            # Check pod restarts
            try {
                $restarts = kubectl get pods -n production -l app=$app -o jsonpath='{.items[*].status.containerStatuses[*].restartCount}' 2>$null
                if ($restarts) {
                    $maxRestarts = ($restarts -split ' ' | Measure-Object -Maximum).Maximum
                    if ($maxRestarts -eq 0) {
                        Record-Test "PASS" "$app pods have no restarts"
                    }
                    elseif ($maxRestarts -lt 3) {
                        Record-Test "WARN" "$app pods have $maxRestarts restarts (acceptable)"
                    }
                    else {
                        Record-Test "FAIL" "$app pods have $maxRestarts restarts (too many)"
                    }
                }
                else {
                    Record-Test "PASS" "$app pods have no restarts"
                }
            }
            catch {
                Record-Test "WARN" "Could not check restart count for $app pods"
            }
        }
        catch {
            Record-Test "FAIL" "Could not check $app pod status"
        }
    }
}

# Function to validate ingress
function Test-Ingress {
    Write-Status "Validating ingress..."
    
    try {
        $null = kubectl get ingress app-ingress -n production 2>$null
        Record-Test "PASS" "Ingress exists"
        
        try {
            $ingressIP = kubectl get ingress app-ingress -n production -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
            if (-not $ingressIP) {
                $ingressIP = kubectl get ingress app-ingress -n production -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>$null
            }
            
            if ($ingressIP) {
                Record-Test "PASS" "Ingress has external IP/hostname: $ingressIP"
            }
            else {
                Record-Test "WARN" "Ingress external IP/hostname not yet assigned"
            }
        }
        catch {
            Record-Test "WARN" "Could not get ingress IP/hostname"
        }
    }
    catch {
        Record-Test "FAIL" "Ingress does not exist"
    }
}

# Function to validate HPA
function Test-HPA {
    Write-Status "Validating HPA (Horizontal Pod Autoscaler)..."
    
    @("backend-hpa", "frontend-hpa") | ForEach-Object {
        try {
            $null = kubectl get hpa $_ -n production 2>$null
            $currentReplicas = kubectl get hpa $_ -n production -o jsonpath='{.status.currentReplicas}' 2>$null
            $minReplicas = kubectl get hpa $_ -n production -o jsonpath='{.spec.minReplicas}' 2>$null
            
            if ([int]$currentReplicas -ge [int]$minReplicas) {
                Record-Test "PASS" "HPA $_ is active ($currentReplicas replicas, min: $minReplicas)"
            }
            else {
                Record-Test "WARN" "HPA $_ may not be fully active ($currentReplicas replicas, min: $minReplicas)"
            }
        }
        catch {
            Record-Test "FAIL" "HPA $_ does not exist"
        }
    }
}

# Function to validate jobs
function Test-Jobs {
    Write-Status "Validating jobs..."
    
    # Check migration job
    try {
        $migrationStatus = kubectl get job database-migration-job -n production -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>$null
        if ($migrationStatus -eq "True") {
            Record-Test "PASS" "Database migration job completed successfully"
        }
        else {
            $failedStatus = kubectl get job database-migration-job -n production -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>$null
            if ($failedStatus -eq "True") {
                Record-Test "FAIL" "Database migration job failed"
            }
            else {
                Record-Test "WARN" "Database migration job status unclear"
            }
        }
    }
    catch {
        Record-Test "FAIL" "Database migration job not found"
    }
    
    # Check cronjob
    try {
        $null = kubectl get cronjob log-cleanup-cronjob -n production 2>$null
        Record-Test "PASS" "Log cleanup CronJob exists"
        
        try {
            $lastSchedule = kubectl get cronjob log-cleanup-cronjob -n production -o jsonpath='{.status.lastScheduleTime}' 2>$null
            if ($lastSchedule) {
                Record-Test "PASS" "CronJob was last scheduled at: $lastSchedule"
            }
            else {
                Record-Test "WARN" "CronJob has not been scheduled yet"
            }
        }
        catch {
            Record-Test "WARN" "Could not get CronJob schedule status"
        }
    }
    catch {
        Record-Test "FAIL" "Log cleanup CronJob does not exist"
    }
}

# Function to test application connectivity
function Test-ApplicationConnectivity {
    Write-Status "Testing application connectivity..."
    
    # Test backend health endpoint
    try {
        $backendPod = kubectl get pods -n production -l app=backend --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>$null
        if ($backendPod) {
            try {
                $null = kubectl exec $backendPod -n production -- wget -q -O- http://localhost:3000/health 2>$null
                Record-Test "PASS" "Backend health endpoint is accessible"
            }
            catch {
                Record-Test "FAIL" "Backend health endpoint is not accessible"
            }
        }
    }
    catch {
        Record-Test "WARN" "Could not test backend connectivity"
    }
    
    # Test frontend health endpoint
    try {
        $frontendPod = kubectl get pods -n production -l app=frontend --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>$null
        if ($frontendPod) {
            try {
                $null = kubectl exec $frontendPod -n production -- wget -q -O- http://localhost:80/health 2>$null
                Record-Test "PASS" "Frontend health endpoint is accessible"
            }
            catch {
                Record-Test "FAIL" "Frontend health endpoint is not accessible"
            }
        }
    }
    catch {
        Record-Test "WARN" "Could not test frontend connectivity"
    }
    
    # Test database connectivity
    try {
        $postgresPod = kubectl get pods -n production -l app=postgres --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>$null
        if ($postgresPod) {
            try {
                $null = kubectl exec $postgresPod -n production -- pg_isready -U myuser 2>$null
                Record-Test "PASS" "PostgreSQL is accepting connections"
            }
            catch {
                Record-Test "FAIL" "PostgreSQL is not accepting connections"
            }
        }
    }
    catch {
        Record-Test "WARN" "Could not test PostgreSQL connectivity"
    }
    
    # Test Redis connectivity
    try {
        $redisPod = kubectl get pods -n production -l app=redis --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>$null
        if ($redisPod) {
            try {
                $result = kubectl exec $redisPod -n production -- redis-cli ping 2>$null
                if ($result -match "PONG") {
                    Record-Test "PASS" "Redis is accepting connections"
                }
                else {
                    Record-Test "FAIL" "Redis is not accepting connections"
                }
            }
            catch {
                Record-Test "FAIL" "Redis is not accepting connections"
            }
        }
    }
    catch {
        Record-Test "WARN" "Could not test Redis connectivity"
    }
}

# Function to validate security
function Test-Security {
    Write-Status "Validating security configurations..."
    
    # Check network policies
    try {
        $networkPolicies = kubectl get networkpolicies -n production --no-headers 2>$null
        $policyCount = if ($networkPolicies) { ($networkPolicies | Measure-Object).Count } else { 0 }
        if ($policyCount -gt 0) {
            Record-Test "PASS" "Network policies are configured ($policyCount policies)"
        }
        else {
            Record-Test "WARN" "No network policies found"
        }
    }
    catch {
        Record-Test "WARN" "Could not check network policies"
    }
    
    # Check secrets
    @("postgres-secret", "backend-secret", "tls-secret") | ForEach-Object {
        try {
            $null = kubectl get secret $_ -n production 2>$null
            Record-Test "PASS" "Secret $_ exists"
        }
        catch {
            Record-Test "FAIL" "Secret $_ does not exist"
        }
    }
}

# Function to check resource usage
function Test-ResourceUsage {
    Write-Status "Checking resource usage..."
    
    try {
        $null = kubectl top nodes 2>$null
        Record-Test "PASS" "Metrics server is available"
        
        # Check pod resource usage
        try {
            $highCpuPods = kubectl top pods -n production --no-headers 2>$null | Where-Object { 
                $parts = $_ -split '\s+'
                if ($parts.Count -ge 2) {
                    $cpuStr = $parts[1]
                    $cpuValue = [int]($cpuStr -replace '[^\d]', '')
                    $cpuValue -gt 500
                }
            }
            $highCpuCount = if ($highCpuPods) { ($highCpuPods | Measure-Object).Count } else { 0 }
            
            if ($highCpuCount -eq 0) {
                Record-Test "PASS" "No pods with excessive CPU usage"
            }
            else {
                Record-Test "WARN" "$highCpuCount pods have high CPU usage (>500m)"
            }
        }
        catch {
            Record-Test "WARN" "Could not check CPU usage"
        }
    }
    catch {
        Record-Test "WARN" "Metrics server not available - cannot check resource usage"
    }
}

# Function to generate detailed report
function Show-DetailedReport {
    Write-Status "Generating detailed report..."
    Write-Host ""
    Write-Host "==================================" -ForegroundColor $colors.Blue
    Write-Host "DETAILED KUBERNETES CLUSTER REPORT" -ForegroundColor $colors.Blue
    Write-Host "==================================" -ForegroundColor $colors.Blue
    Write-Host "Generated at: $(Get-Date)" -ForegroundColor $colors.Blue
    Write-Host ""
    
    Write-Host "📊 CLUSTER OVERVIEW:" -ForegroundColor $colors.Blue
    try {
        $k8sVersion = kubectl version --short 2>$null | Select-String "Server"
        Write-Host "  Kubernetes Version: $($k8sVersion -replace 'Server Version: ', '')"
    } catch { Write-Host "  Kubernetes Version: Unknown" }
    
    try {
        $nodeCount = (kubectl get nodes --no-headers 2>$null | Measure-Object).Count
        Write-Host "  Nodes: $nodeCount"
    } catch { Write-Host "  Nodes: Unknown" }
    
    Write-Host ""
    Write-Host "🏗️  APPLICATION COMPONENTS:" -ForegroundColor $colors.Blue
    try {
        $deploymentCount = (kubectl get deployments -n production --no-headers 2>$null | Measure-Object).Count
        Write-Host "  Deployments: $deploymentCount"
    } catch { Write-Host "  Deployments: 0" }
    
    try {
        $serviceCount = (kubectl get services -n production --no-headers 2>$null | Measure-Object).Count
        Write-Host "  Services: $serviceCount"
    } catch { Write-Host "  Services: 0" }
    
    try {
        $podCount = (kubectl get pods -n production --no-headers 2>$null | Measure-Object).Count
        Write-Host "  Pods: $podCount"
    } catch { Write-Host "  Pods: 0" }
    
    Write-Host ""
    Write-Host "🌐 NETWORKING:" -ForegroundColor $colors.Blue
    Write-Host "  Services:"
    try {
        kubectl get services -n production --no-headers 2>$null | ForEach-Object {
            $parts = $_ -split '\s+'
            Write-Host "    - $($parts[0]) ($($parts[1])): $($parts[2])"
        }
    } catch { Write-Host "    - No services found" }
}

# Main validation function
function Invoke-MainValidation {
    Write-Host "==========================================" -ForegroundColor $colors.Blue
    Write-Host "Kubernetes Application Validation Script" -ForegroundColor $colors.Blue
    Write-Host "==========================================" -ForegroundColor $colors.Blue
    Write-Host ""
    
    # Run all validation tests
    if (-not (Test-Prerequisites)) { exit 1 }
    Test-Namespaces
    Test-Storage
    Test-Deployments
    Test-Services
    Test-PodHealth
    Test-Ingress
    Test-HPA
    Test-Jobs
    Test-ApplicationConnectivity
    Test-Security
    Test-ResourceUsage
    
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor $colors.Blue
    Write-Host "VALIDATION SUMMARY" -ForegroundColor $colors.Blue
    Write-Host "==========================================" -ForegroundColor $colors.Blue
    Write-Host "Tests Passed:  " -NoNewline
    Write-Host $script:TestsPassed -ForegroundColor $colors.Green
    Write-Host "Tests Failed:  " -NoNewline
    Write-Host $script:TestsFailed -ForegroundColor $colors.Red
    Write-Host "Warnings:      " -NoNewline
    Write-Host $script:TestsWarning -ForegroundColor $colors.Yellow
    Write-Host "Total Tests:   $($script:TestsPassed + $script:TestsFailed + $script:TestsWarning)"
    Write-Host ""
    
    if ($script:TestsFailed -eq 0) {
        if ($script:TestsWarning -eq 0) {
            Write-Success "All tests passed! Your Kubernetes deployment is healthy."
            exit 0
        }
        else {
            Write-Warning "All tests passed with $($script:TestsWarning) warnings. Review the warnings above."
            exit 0
        }
    }
    else {
        Write-Error "$($script:TestsFailed) tests failed. Your deployment needs attention."
        exit 1
    }
}

# Main execution
switch ($Action.ToLower()) {
    "validate" {
        Invoke-MainValidation
    }
    "report" {
        if (-not (Test-Prerequisites)) { exit 1 }
        Show-DetailedReport
    }
    "quick" {
        if (-not (Test-Prerequisites)) { exit 1 }
        Test-Deployments
        Test-Services
        Test-PodHealth
        Write-Host ""
        Write-Host "Quick validation completed: $($script:TestsPassed) passed, $($script:TestsFailed) failed, $($script:TestsWarning) warnings"
    }
    "help" {
        Write-Host "Usage: .\validate.ps1 [validate|report|quick|help]"
        Write-Host "  validate - Run full validation suite (default)"
        Write-Host "  report   - Generate detailed cluster report"
        Write-Host "  quick    - Run quick health check"
        Write-Host "  help     - Show this help message"
    }
    default {
        Write-Error "Unknown command: $Action"
        Write-Host "Use '.\validate.ps1 help' for usage information"
        exit 1
    }
}
