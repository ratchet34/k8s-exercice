#!/bin/bash

# Cleanup Kubernetes Application - Complete Resource Removal Script
# This script removes all resources created by the Kubernetes application

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
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl not found. Please install kubectl first."
        exit 1
    fi
    print_success "kubectl is available"
}

# Function to check if cluster is accessible
check_cluster() {
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
        exit 1
    fi
    print_success "Kubernetes cluster is accessible"
}

# Function to safely delete resources
safe_delete() {
    local resource_type=$1
    local resource_name=$2
    local namespace=${3:-""}
    
    local kubectl_cmd="kubectl delete $resource_type $resource_name"
    if [ ! -z "$namespace" ]; then
        kubectl_cmd="$kubectl_cmd -n $namespace"
    fi
    
    if $kubectl_cmd --ignore-not-found=true --timeout=60s; then
        print_success "Deleted $resource_type/$resource_name"
    else
        print_warning "Failed to delete $resource_type/$resource_name or resource not found"
    fi
}

# Function to wait for resource deletion
wait_for_deletion() {
    local resource_type=$1
    local namespace=${2:-""}
    local timeout=${3:-120}
    
    local kubectl_cmd="kubectl get $resource_type"
    if [ ! -z "$namespace" ]; then
        kubectl_cmd="$kubectl_cmd -n $namespace"
    fi
    
    print_status "Waiting for $resource_type to be deleted..."
    local count=0
    while [ $count -lt $timeout ]; do
        if ! $kubectl_cmd --no-headers 2>/dev/null | grep -q .; then
            print_success "$resource_type deleted successfully"
            return 0
        fi
        sleep 5
        count=$((count + 5))
    done
    
    print_warning "$resource_type still exists after ${timeout}s timeout"
    return 1
}

# Function to force delete stuck resources
force_delete_stuck_resources() {
    print_warning "Attempting to force delete stuck resources..."
    
    # Force delete stuck pods
    kubectl get pods -n production --no-headers 2>/dev/null | while read pod rest; do
        if [ ! -z "$pod" ]; then
            kubectl delete pod "$pod" -n production --force --grace-period=0 2>/dev/null || true
        fi
    done
    
    # Patch finalizers on stuck PVCs
    kubectl get pvc -n production -o name 2>/dev/null | while read pvc; do
        kubectl patch "$pvc" -n production -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
    done
    
    # Patch finalizers on stuck PVs
    kubectl get pv -o name 2>/dev/null | grep -E "(postgres|redis|shared-logs)" | while read pv; do
        kubectl patch "$pv" -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
    done
}

# Main cleanup function
cleanup_application() {
    print_status "Starting Kubernetes application cleanup..."
    
    # Check prerequisites
    check_kubectl
    check_cluster
    
    # Get the directory where the script is located
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
    MANIFESTS_DIR="$SCRIPT_DIR/../manifests"
    
    # Ask for confirmation
    read -p "Are you sure you want to delete all application resources? This action cannot be undone. (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Cleanup cancelled."
        exit 0
    fi
    
    # 1. Delete network policies (to restore network connectivity)
    print_status "1. Removing network policies..."
    if [ -f "$MANIFESTS_DIR/09-security/network-policies.yaml" ]; then
        kubectl delete -f "$MANIFESTS_DIR/09-security/network-policies.yaml" --ignore-not-found=true
    else
        safe_delete "networkpolicies" "--all" "production"
    fi
    print_success "Network policies removed"
    
    # 2. Delete ingress
    print_status "2. Removing ingress..."
    if [ -f "$MANIFESTS_DIR/07-ingress/ingress.yaml" ]; then
        kubectl delete -f "$MANIFESTS_DIR/07-ingress/ingress.yaml" --ignore-not-found=true
    else
        safe_delete "ingress" "--all" "production"
    fi
    print_success "Ingress removed"
    
    # 3. Delete CronJobs and Jobs
    print_status "3. Removing jobs and cronjobs..."
    if [ -d "$MANIFESTS_DIR/08-jobs" ]; then
        kubectl delete -f "$MANIFESTS_DIR/08-jobs/" --ignore-not-found=true
    else
        safe_delete "cronjobs" "--all" "production"
        safe_delete "jobs" "--all" "production"
    fi
    print_success "Jobs and CronJobs removed"
    
    # 4. Delete HPA
    print_status "4. Removing HPA (Horizontal Pod Autoscalers)..."
    safe_delete "hpa" "--all" "production"
    print_success "HPA removed"
    
    # 5. Delete frontend
    print_status "5. Removing frontend..."
    if [ -d "$MANIFESTS_DIR/06-frontend" ]; then
        kubectl delete -f "$MANIFESTS_DIR/06-frontend/" --ignore-not-found=true
    else
        safe_delete "deployment" "frontend-deployment" "production"
        safe_delete "service" "frontend-service" "production"
    fi
    print_success "Frontend removed"
    
    # 6. Delete backend
    print_status "6. Removing backend..."
    if [ -d "$MANIFESTS_DIR/05-backend" ]; then
        kubectl delete -f "$MANIFESTS_DIR/05-backend/" --ignore-not-found=true
    else
        safe_delete "deployment" "backend-deployment" "production"
        safe_delete "service" "backend-service" "production"
    fi
    print_success "Backend removed"
    
    # 7. Delete cache (Redis)
    print_status "7. Removing Redis cache..."
    if [ -d "$MANIFESTS_DIR/04-cache" ]; then
        kubectl delete -f "$MANIFESTS_DIR/04-cache/" --ignore-not-found=true
    else
        safe_delete "deployment" "redis-deployment" "production"
        safe_delete "service" "redis-service" "production"
    fi
    print_success "Redis cache removed"
    
    # 8. Delete database (PostgreSQL)
    print_status "8. Removing PostgreSQL database..."
    if [ -d "$MANIFESTS_DIR/03-database" ]; then
        kubectl delete -f "$MANIFESTS_DIR/03-database/" --ignore-not-found=true
    else
        safe_delete "deployment" "postgres-deployment" "production"
        safe_delete "service" "postgres-service" "production"
    fi
    print_success "PostgreSQL database removed"
    
    # Wait for pods to be deleted
    print_status "Waiting for pods to terminate..."
    wait_for_deletion "pods" "production" 180
    
    # 9. Delete configuration
    print_status "9. Removing configuration (ConfigMaps and Secrets)..."
    if [ -d "$MANIFESTS_DIR/02-config" ]; then
        kubectl delete -f "$MANIFESTS_DIR/02-config/" --ignore-not-found=true
    else
        safe_delete "configmaps" "--all" "production"
        safe_delete "secrets" "--all" "production"
    fi
    print_success "Configuration removed"
    
    # 10. Delete storage (PVCs first, then PVs)
    print_status "10. Removing storage..."
    if [ -f "$MANIFESTS_DIR/01-storage/persistent-volume-claims.yaml" ]; then
        kubectl delete -f "$MANIFESTS_DIR/01-storage/persistent-volume-claims.yaml" --ignore-not-found=true
    else
        safe_delete "pvc" "--all" "production"
    fi
    
    # Wait for PVCs to be deleted
    print_status "Waiting for PVCs to be deleted..."
    wait_for_deletion "pvc" "production" 120
    
    # Delete PVs
    if [ -f "$MANIFESTS_DIR/01-storage/persistent-volumes.yaml" ]; then
        kubectl delete -f "$MANIFESTS_DIR/01-storage/persistent-volumes.yaml" --ignore-not-found=true
    else
        safe_delete "pv" "postgres-pv"
        safe_delete "pv" "redis-pv" 
        safe_delete "pv" "shared-logs-pv"
    fi
    print_success "Storage removed"
    
    # Check for stuck resources and force delete if necessary
    if kubectl get pods -n production --no-headers 2>/dev/null | grep -q .; then
        print_warning "Some pods are still running. Attempting force deletion..."
        force_delete_stuck_resources
        sleep 10
    fi
    
    # 11. Delete namespaces (this will delete any remaining resources)
    print_status "11. Removing namespaces..."
    if [ -f "$MANIFESTS_DIR/00-namespaces.yaml" ]; then
        kubectl delete -f "$MANIFESTS_DIR/00-namespaces.yaml" --ignore-not-found=true
    else
        safe_delete "namespace" "production"
        safe_delete "namespace" "monitoring"
    fi
    
    # Wait for namespaces to be deleted
    print_status "Waiting for namespaces to be deleted..."
    wait_for_deletion "namespace production" "" 300
    
    print_success "All application resources have been removed!"
}

# Function to show remaining resources
show_remaining_resources() {
    print_status "Checking for remaining resources..."
    
    echo ""
    print_status "Remaining namespaces:"
    kubectl get namespaces production monitoring --no-headers 2>/dev/null || echo "No target namespaces found"
    
    echo ""
    print_status "Remaining PVs:"
    kubectl get pv --no-headers 2>/dev/null | grep -E "(postgres|redis|shared-logs)" || echo "No target PVs found"
    
    echo ""
    print_status "All production resources:"
    kubectl get all -n production --no-headers 2>/dev/null || echo "Production namespace not found or empty"
    
    # Check for stuck resources
    local stuck_pods=$(kubectl get pods -n production --no-headers 2>/dev/null | wc -l)
    local stuck_pvcs=$(kubectl get pvc -n production --no-headers 2>/dev/null | wc -l)
    
    if [ $stuck_pods -gt 0 ] || [ $stuck_pvcs -gt 0 ]; then
        print_warning "Found $stuck_pods stuck pods and $stuck_pvcs stuck PVCs"
        echo "You may need to manually clean these up or run the force cleanup option."
    else
        print_success "No stuck resources detected"
    fi
}

# Function to force cleanup stuck resources
force_cleanup() {
    print_warning "Performing force cleanup of stuck resources..."
    
    read -p "This will forcefully delete stuck resources. Are you sure? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Force cleanup cancelled."
        exit 0
    fi
    
    force_delete_stuck_resources
    
    # Force delete namespace if it exists
    if kubectl get namespace production &>/dev/null; then
        print_status "Force deleting production namespace..."
        kubectl patch namespace production -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
        kubectl delete namespace production --force --grace-period=0 2>/dev/null || true
    fi
    
    if kubectl get namespace monitoring &>/dev/null; then
        print_status "Force deleting monitoring namespace..."
        kubectl patch namespace monitoring -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
        kubectl delete namespace monitoring --force --grace-period=0 2>/dev/null || true
    fi
    
    print_success "Force cleanup completed"
}

# Main execution
case "${1:-cleanup}" in
    "cleanup")
        cleanup_application
        show_remaining_resources
        ;;
    "check")
        show_remaining_resources
        ;;
    "force")
        force_cleanup
        show_remaining_resources
        ;;
    "help")
        echo "Usage: $0 [cleanup|check|force|help]"
        echo "  cleanup - Remove all application resources (default)"
        echo "  check   - Check for remaining resources"
        echo "  force   - Force delete stuck resources"
        echo "  help    - Show this help message"
        ;;
    *)
        print_error "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac
