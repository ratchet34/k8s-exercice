#!/bin/bash

# Validate Kubernetes Application Deployment
# This script validates that all components are properly deployed and functioning

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNING=0

# Function to record test result
record_test() {
    local status=$1
    local message=$2
    
    case $status in
        "PASS")
            print_success "$message"
            ((TESTS_PASSED++))
            ;;
        "FAIL")
            print_error "$message"
            ((TESTS_FAILED++))
            ;;
        "WARN")
            print_warning "$message"
            ((TESTS_WARNING++))
            ;;
    esac
}

# Function to check if kubectl is available
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    if command -v kubectl &> /dev/null; then
        record_test "PASS" "kubectl is available"
    else
        record_test "FAIL" "kubectl not found"
        return 1
    fi
    
    if kubectl cluster-info &> /dev/null; then
        record_test "PASS" "Kubernetes cluster is accessible"
    else
        record_test "FAIL" "Cannot connect to Kubernetes cluster"
        return 1
    fi
    
    return 0
}

# Function to validate namespaces
validate_namespaces() {
    print_status "Validating namespaces..."
    
    local namespaces=("production" "monitoring")
    for ns in "${namespaces[@]}"; do
        if kubectl get namespace "$ns" &>/dev/null; then
            record_test "PASS" "Namespace $ns exists"
        else
            record_test "FAIL" "Namespace $ns does not exist"
        fi
    done
}

# Function to validate storage
validate_storage() {
    print_status "Validating storage..."
    
    # Check PVs
    local pvs=("postgres-pv" "redis-pv" "shared-logs-pv")
    for pv in "${pvs[@]}"; do
        local status=$(kubectl get pv "$pv" -o jsonpath='{.status.phase}' 2>/dev/null)
        if [ "$status" = "Bound" ]; then
            record_test "PASS" "PV $pv is bound"
        elif [ "$status" = "Available" ]; then
            record_test "WARN" "PV $pv is available but not bound"
        else
            record_test "FAIL" "PV $pv is not available (status: $status)"
        fi
    done
    
    # Check PVCs
    local pvcs=("postgres-pvc" "redis-pvc" "shared-logs-pvc")
    for pvc in "${pvcs[@]}"; do
        local status=$(kubectl get pvc "$pvc" -n production -o jsonpath='{.status.phase}' 2>/dev/null)
        if [ "$status" = "Bound" ]; then
            record_test "PASS" "PVC $pvc is bound"
        else
            record_test "FAIL" "PVC $pvc is not bound (status: $status)"
        fi
    done
}

# Function to validate deployments
validate_deployments() {
    print_status "Validating deployments..."
    
    local deployments=("postgres-deployment" "redis-deployment" "backend-deployment" "frontend-deployment")
    for deployment in "${deployments[@]}"; do
        local ready=$(kubectl get deployment "$deployment" -n production -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
        local desired=$(kubectl get deployment "$deployment" -n production -o jsonpath='{.spec.replicas}' 2>/dev/null)
        
        if [ "$ready" = "$desired" ] && [ "$ready" -gt 0 ]; then
            record_test "PASS" "Deployment $deployment is ready ($ready/$desired replicas)"
        else
            record_test "FAIL" "Deployment $deployment is not ready ($ready/$desired replicas)"
        fi
    done
}

# Function to validate services
validate_services() {
    print_status "Validating services..."
    
    local services=("postgres-service" "redis-service" "backend-service" "frontend-service")
    for service in "${services[@]}"; do
        local endpoints=$(kubectl get endpoints "$service" -n production -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w)
        if [ "$endpoints" -gt 0 ]; then
            record_test "PASS" "Service $service has $endpoints endpoints"
        else
            record_test "FAIL" "Service $service has no endpoints"
        fi
    done
}

# Function to validate pods health
validate_pod_health() {
    print_status "Validating pod health..."
    
    local apps=("postgres" "redis" "backend" "frontend")
    for app in "${apps[@]}"; do
        local running_pods=$(kubectl get pods -n production -l app=$app --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
        local total_pods=$(kubectl get pods -n production -l app=$app --no-headers 2>/dev/null | wc -l)
        
        if [ "$running_pods" -eq "$total_pods" ] && [ "$running_pods" -gt 0 ]; then
            record_test "PASS" "All $app pods are running ($running_pods/$total_pods)"
        else
            record_test "FAIL" "$app pods not all running ($running_pods/$total_pods)"
        fi
        
        # Check pod restarts
        local restarts=$(kubectl get pods -n production -l app=$app -o jsonpath='{.items[*].status.containerStatuses[*].restartCount}' 2>/dev/null | tr ' ' '\n' | sort -n | tail -1)
        if [ -z "$restarts" ]; then
            restarts=0
        fi
        
        if [ "$restarts" -eq 0 ]; then
            record_test "PASS" "$app pods have no restarts"
        elif [ "$restarts" -lt 3 ]; then
            record_test "WARN" "$app pods have $restarts restarts (acceptable)"
        else
            record_test "FAIL" "$app pods have $restarts restarts (too many)"
        fi
    done
}

# Function to validate ingress
validate_ingress() {
    print_status "Validating ingress..."
    
    if kubectl get ingress app-ingress -n production &>/dev/null; then
        record_test "PASS" "Ingress exists"
        
        local ingress_ip=$(kubectl get ingress app-ingress -n production -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
        if [ -z "$ingress_ip" ]; then
            ingress_ip=$(kubectl get ingress app-ingress -n production -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
        fi
        
        if [ ! -z "$ingress_ip" ]; then
            record_test "PASS" "Ingress has external IP/hostname: $ingress_ip"
        else
            record_test "WARN" "Ingress external IP/hostname not yet assigned"
        fi
    else
        record_test "FAIL" "Ingress does not exist"
    fi
}

# Function to validate HPA
validate_hpa() {
    print_status "Validating HPA (Horizontal Pod Autoscaler)..."
    
    local hpas=("backend-hpa" "frontend-hpa")
    for hpa in "${hpas[@]}"; do
        if kubectl get hpa "$hpa" -n production &>/dev/null; then
            local current_replicas=$(kubectl get hpa "$hpa" -n production -o jsonpath='{.status.currentReplicas}' 2>/dev/null)
            local min_replicas=$(kubectl get hpa "$hpa" -n production -o jsonpath='{.spec.minReplicas}' 2>/dev/null)
            
            if [ "$current_replicas" -ge "$min_replicas" ]; then
                record_test "PASS" "HPA $hpa is active ($current_replicas replicas, min: $min_replicas)"
            else
                record_test "WARN" "HPA $hpa may not be fully active ($current_replicas replicas, min: $min_replicas)"
            fi
        else
            record_test "FAIL" "HPA $hpa does not exist"
        fi
    done
}

# Function to validate jobs
validate_jobs() {
    print_status "Validating jobs..."
    
    # Check migration job
    local migration_status=$(kubectl get job database-migration-job -n production -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null)
    if [ "$migration_status" = "True" ]; then
        record_test "PASS" "Database migration job completed successfully"
    else
        local failed_status=$(kubectl get job database-migration-job -n production -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null)
        if [ "$failed_status" = "True" ]; then
            record_test "FAIL" "Database migration job failed"
        else
            record_test "WARN" "Database migration job status unclear"
        fi
    fi
    
    # Check cronjob
    if kubectl get cronjob log-cleanup-cronjob -n production &>/dev/null; then
        record_test "PASS" "Log cleanup CronJob exists"
        
        local last_schedule=$(kubectl get cronjob log-cleanup-cronjob -n production -o jsonpath='{.status.lastScheduleTime}' 2>/dev/null)
        if [ ! -z "$last_schedule" ]; then
            record_test "PASS" "CronJob was last scheduled at: $last_schedule"
        else
            record_test "WARN" "CronJob has not been scheduled yet"
        fi
    else
        record_test "FAIL" "Log cleanup CronJob does not exist"
    fi
}

# Function to test application connectivity
test_application_connectivity() {
    print_status "Testing application connectivity..."
    
    # Test backend health endpoint
    if kubectl get pods -n production -l app=backend --field-selector=status.phase=Running &>/dev/null; then
        local backend_pod=$(kubectl get pods -n production -l app=backend --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [ ! -z "$backend_pod" ]; then
            if kubectl exec "$backend_pod" -n production -- wget -q -O- http://localhost:3000/health &>/dev/null; then
                record_test "PASS" "Backend health endpoint is accessible"
            else
                record_test "FAIL" "Backend health endpoint is not accessible"
            fi
        fi
    fi
    
    # Test frontend health endpoint
    if kubectl get pods -n production -l app=frontend --field-selector=status.phase=Running &>/dev/null; then
        local frontend_pod=$(kubectl get pods -n production -l app=frontend --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [ ! -z "$frontend_pod" ]; then
            if kubectl exec "$frontend_pod" -n production -- wget -q -O- http://localhost:80/health &>/dev/null; then
                record_test "PASS" "Frontend health endpoint is accessible"
            else
                record_test "FAIL" "Frontend health endpoint is not accessible"
            fi
        fi
    fi
    
    # Test database connectivity
    if kubectl get pods -n production -l app=postgres --field-selector=status.phase=Running &>/dev/null; then
        local postgres_pod=$(kubectl get pods -n production -l app=postgres --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [ ! -z "$postgres_pod" ]; then
            if kubectl exec "$postgres_pod" -n production -- pg_isready -U myuser &>/dev/null; then
                record_test "PASS" "PostgreSQL is accepting connections"
            else
                record_test "FAIL" "PostgreSQL is not accepting connections"
            fi
        fi
    fi
    
    # Test Redis connectivity
    if kubectl get pods -n production -l app=redis --field-selector=status.phase=Running &>/dev/null; then
        local redis_pod=$(kubectl get pods -n production -l app=redis --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [ ! -z "$redis_pod" ]; then
            if kubectl exec "$redis_pod" -n production -- redis-cli ping | grep -q "PONG"; then
                record_test "PASS" "Redis is accepting connections"
            else
                record_test "FAIL" "Redis is not accepting connections"
            fi
        fi
    fi
}

# Function to validate security
validate_security() {
    print_status "Validating security configurations..."
    
    # Check if network policies exist
    local network_policies=$(kubectl get networkpolicies -n production --no-headers 2>/dev/null | wc -l)
    if [ "$network_policies" -gt 0 ]; then
        record_test "PASS" "Network policies are configured ($network_policies policies)"
    else
        record_test "WARN" "No network policies found"
    fi
    
    # Check secrets
    local secrets=("postgres-secret" "backend-secret" "tls-secret")
    for secret in "${secrets[@]}"; do
        if kubectl get secret "$secret" -n production &>/dev/null; then
            record_test "PASS" "Secret $secret exists"
        else
            record_test "FAIL" "Secret $secret does not exist"
        fi
    done
    
    # Check if pods are running as non-root (where applicable)
    local non_root_apps=("backend" "frontend")
    for app in "${non_root_apps[@]}"; do
        local running_as_root=$(kubectl get pods -n production -l app=$app -o jsonpath='{.items[*].spec.securityContext.runAsUser}' 2>/dev/null | grep -c "^0$" || true)
        if [ "$running_as_root" -eq 0 ]; then
            record_test "PASS" "$app pods are not running as root"
        else
            record_test "WARN" "Some $app pods may be running as root"
        fi
    done
}

# Function to check resource usage
check_resource_usage() {
    print_status "Checking resource usage..."
    
    # Check if metrics server is available
    if kubectl top nodes &>/dev/null; then
        record_test "PASS" "Metrics server is available"
        
        # Check pod resource usage
        local high_cpu_pods=$(kubectl top pods -n production --no-headers 2>/dev/null | awk '{if ($2 > 500) print $1}' | wc -l)
        if [ "$high_cpu_pods" -eq 0 ]; then
            record_test "PASS" "No pods with excessive CPU usage"
        else
            record_test "WARN" "$high_cpu_pods pods have high CPU usage (>500m)"
        fi
        
        local high_memory_pods=$(kubectl top pods -n production --no-headers 2>/dev/null | awk '{if ($3 > 1000) print $1}' | wc -l)
        if [ "$high_memory_pods" -eq 0 ]; then
            record_test "PASS" "No pods with excessive memory usage"
        else
            record_test "WARN" "$high_memory_pods pods have high memory usage (>1000Mi)"
        fi
    else
        record_test "WARN" "Metrics server not available - cannot check resource usage"
    fi
}

# Function to generate detailed report
generate_detailed_report() {
    print_status "Generating detailed report..."
    echo ""
    echo "=================================="
    echo "DETAILED KUBERNETES CLUSTER REPORT"
    echo "=================================="
    echo "Generated at: $(date)"
    echo ""
    
    echo "📊 CLUSTER OVERVIEW:"
    echo "  Kubernetes Version: $(kubectl version --short 2>/dev/null | grep Server | cut -d' ' -f3)"
    echo "  Nodes: $(kubectl get nodes --no-headers 2>/dev/null | wc -l)"
    echo "  Namespaces: $(kubectl get namespaces --no-headers 2>/dev/null | wc -l)"
    echo ""
    
    echo "🏗️  APPLICATION COMPONENTS:"
    echo "  Deployments: $(kubectl get deployments -n production --no-headers 2>/dev/null | wc -l)"
    echo "  Services: $(kubectl get services -n production --no-headers 2>/dev/null | wc -l)"
    echo "  Pods: $(kubectl get pods -n production --no-headers 2>/dev/null | wc -l)"
    echo "  ConfigMaps: $(kubectl get configmaps -n production --no-headers 2>/dev/null | wc -l)"
    echo "  Secrets: $(kubectl get secrets -n production --no-headers 2>/dev/null | wc -l)"
    echo ""
    
    echo "💾 STORAGE:"
    echo "  PersistentVolumes: $(kubectl get pv --no-headers 2>/dev/null | wc -l)"
    echo "  PersistentVolumeClaims: $(kubectl get pvc -n production --no-headers 2>/dev/null | wc -l)"
    echo ""
    
    echo "⚡ AUTOSCALING:"
    echo "  HPA: $(kubectl get hpa -n production --no-headers 2>/dev/null | wc -l)"
    echo ""
    
    echo "🔄 JOBS & CRONJOBS:"
    echo "  Jobs: $(kubectl get jobs -n production --no-headers 2>/dev/null | wc -l)"
    echo "  CronJobs: $(kubectl get cronjobs -n production --no-headers 2>/dev/null | wc -l)"
    echo ""
    
    echo "🔒 SECURITY:"
    echo "  Network Policies: $(kubectl get networkpolicies -n production --no-headers 2>/dev/null | wc -l)"
    echo "  Service Accounts: $(kubectl get serviceaccounts -n production --no-headers 2>/dev/null | wc -l)"
    echo ""
    
    echo "🌐 NETWORKING:"
    echo "  Services:"
    kubectl get services -n production --no-headers 2>/dev/null | while read name type cluster_ip external_ip ports age; do
        echo "    - $name ($type): $cluster_ip"
    done
    echo ""
    
    echo "  Ingress:"
    kubectl get ingress -n production --no-headers 2>/dev/null | while read name class hosts address ports age; do
        echo "    - $name: $hosts -> $address"
    done
    echo ""
    
    if kubectl top nodes &>/dev/null; then
        echo "📈 RESOURCE USAGE:"
        echo "  Node Resources:"
        kubectl top nodes --no-headers 2>/dev/null | while read name cpu_usage cpu_percent memory_usage memory_percent; do
            echo "    - $name: CPU $cpu_usage ($cpu_percent), Memory $memory_usage ($memory_percent)"
        done
        echo ""
        
        echo "  Pod Resources (Top 5 CPU):"
        kubectl top pods -n production --no-headers 2>/dev/null | sort -k2 -nr | head -5 | while read name cpu memory; do
            echo "    - $name: CPU $cpu, Memory $memory"
        done
        echo ""
    fi
    
    echo "🏥 HEALTH STATUS:"
    kubectl get pods -n production --no-headers 2>/dev/null | while read name ready status restarts age; do
        echo "    - $name: $status ($ready ready, $restarts restarts)"
    done
}

# Main validation function
main_validation() {
    echo "=========================================="
    echo "Kubernetes Application Validation Script"
    echo "=========================================="
    echo ""
    
    # Run all validation tests
    check_prerequisites || exit 1
    validate_namespaces
    validate_storage
    validate_deployments
    validate_services
    validate_pod_health
    validate_ingress
    validate_hpa
    validate_jobs
    test_application_connectivity
    validate_security
    check_resource_usage
    
    echo ""
    echo "=========================================="
    echo "VALIDATION SUMMARY"
    echo "=========================================="
    echo -e "Tests Passed:  ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests Failed:  ${RED}$TESTS_FAILED${NC}"
    echo -e "Warnings:      ${YELLOW}$TESTS_WARNING${NC}"
    echo "Total Tests:   $((TESTS_PASSED + TESTS_FAILED + TESTS_WARNING))"
    echo ""
    
    if [ $TESTS_FAILED -eq 0 ]; then
        if [ $TESTS_WARNING -eq 0 ]; then
            print_success "All tests passed! Your Kubernetes deployment is healthy."
            exit 0
        else
            print_warning "All tests passed with $TESTS_WARNING warnings. Review the warnings above."
            exit 0
        fi
    else
        print_error "$TESTS_FAILED tests failed. Your deployment needs attention."
        exit 1
    fi
}

# Main execution
case "${1:-validate}" in
    "validate")
        main_validation
        ;;
    "report")
        check_prerequisites || exit 1
        generate_detailed_report
        ;;
    "quick")
        check_prerequisites || exit 1
        validate_deployments
        validate_services
        validate_pod_health
        echo ""
        echo "Quick validation completed: $TESTS_PASSED passed, $TESTS_FAILED failed, $TESTS_WARNING warnings"
        ;;
    "help")
        echo "Usage: $0 [validate|report|quick|help]"
        echo "  validate - Run full validation suite (default)"
        echo "  report   - Generate detailed cluster report"
        echo "  quick    - Run quick health check"
        echo "  help     - Show this help message"
        ;;
    *)
        print_error "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac
