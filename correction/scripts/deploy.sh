#!/bin/bash

# Deploy Kubernetes Application - Automated Deployment Script
# This script deploys the complete Kubernetes application stack

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

# Function to wait for pods to be ready
wait_for_pods() {
    local namespace=$1
    local app=$2
    local timeout=${3:-300}
    
    print_status "Waiting for $app pods to be ready in namespace $namespace..."
    
    if kubectl wait --for=condition=ready pod -l app=$app -n $namespace --timeout=${timeout}s; then
        print_success "$app pods are ready"
        return 0
    else
        print_error "$app pods failed to become ready within ${timeout} seconds"
        return 1
    fi
}

# Function to check if a deployment is ready
check_deployment() {
    local namespace=$1
    local deployment=$2
    
    print_status "Checking deployment $deployment in namespace $namespace..."
    
    if kubectl rollout status deployment/$deployment -n $namespace --timeout=300s; then
        print_success "Deployment $deployment is ready"
        return 0
    else
        print_error "Deployment $deployment failed to roll out"
        return 1
    fi
}

# Main deployment function
deploy_application() {
    print_status "Starting Kubernetes application deployment..."
    
    # Check prerequisites
    check_kubectl
    check_cluster
    
    # Get the directory where the script is located
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
    MANIFESTS_DIR="$SCRIPT_DIR/../manifests"
    
    if [ ! -d "$MANIFESTS_DIR" ]; then
        print_error "Manifests directory not found: $MANIFESTS_DIR"
        exit 1
    fi
    
    print_status "Using manifests directory: $MANIFESTS_DIR"
    
    # 1. Deploy namespaces
    print_status "1. Deploying namespaces..."
    kubectl apply -f "$MANIFESTS_DIR/00-namespaces.yaml"
    print_success "Namespaces deployed"
    
    # 2. Deploy storage
    print_status "2. Deploying storage (PV and PVC)..."
    kubectl apply -f "$MANIFESTS_DIR/01-storage/"
    print_success "Storage deployed"
    
    # Wait for PVCs to be bound (with better error handling)
    print_status "Waiting for PVCs to be bound..."
    if kubectl wait --for=condition=bound pvc --all -n production --timeout=60s; then
        print_success "PVCs are bound"
    else
        print_warning "Some PVCs failed to bind within 60 seconds. Checking status..."
        
        # Show detailed status of PVCs
        echo ""
        print_status "PVC Status:"
        kubectl get pvc -n production
        
        echo ""
        print_status "PV Status:"
        kubectl get pv
        
        # Check for available StorageClasses
        echo ""
        print_status "Available StorageClasses:"
        kubectl get storageclass
        
        # Try to fix common issues
        print_status "Attempting to fix common PVC binding issues..."
        
        # Check if we're on minikube and use dynamic provisioning instead
        if kubectl get nodes | grep -q minikube; then
            print_status "Detected Minikube - applying Minikube-specific storage configuration..."
            kubectl apply -f "$MANIFESTS_DIR/01-storage/persistent-volume-claims-minikube.yaml" 2>/dev/null || true
        elif kubectl get storageclass standard &>/dev/null; then
            print_status "Standard StorageClass found - applying dynamic provisioning configuration..."
            kubectl apply -f "$MANIFESTS_DIR/01-storage/persistent-volume-claims-dynamic.yaml" 2>/dev/null || true
        fi
        
        # Continue deployment even if PVCs are not bound yet
        print_warning "Continuing deployment. PVCs may bind later during the process."
    fi
    
    # 3. Deploy configuration
    print_status "3. Deploying configuration (ConfigMaps and Secrets)..."
    kubectl apply -f "$MANIFESTS_DIR/02-config/"
    print_success "Configuration deployed"
    
    # 4. Deploy database
    print_status "4. Deploying PostgreSQL database..."
    kubectl apply -f "$MANIFESTS_DIR/03-database/"
    print_success "Database deployment submitted"
    
    # Wait for database to be ready
    wait_for_pods "production" "postgres" 300
    check_deployment "production" "postgres-deployment"
    
    # 5. Deploy cache
    print_status "5. Deploying Redis cache..."
    kubectl apply -f "$MANIFESTS_DIR/04-cache/"
    print_success "Cache deployment submitted"
    
    # Wait for Redis to be ready
    wait_for_pods "production" "redis" 180
    check_deployment "production" "redis-deployment"
    
    # 6. Run database migration
    print_status "6. Running database migration..."
    kubectl apply -f "$MANIFESTS_DIR/08-jobs/migration-job.yaml"
    
    # Wait for migration job to complete
    print_status "Waiting for database migration to complete..."
    if kubectl wait --for=condition=complete job/database-migration-job -n production --timeout=600s; then
        print_success "Database migration completed successfully"
    else
        print_warning "Database migration may have failed. Check job logs:"
        kubectl logs job/database-migration-job -n production
    fi
    
    # 7. Deploy backend
    print_status "7. Deploying backend application..."
    kubectl apply -f "$MANIFESTS_DIR/05-backend/"
    print_success "Backend deployment submitted"
    
    # Wait for backend to be ready
    wait_for_pods "production" "backend" 300
    check_deployment "production" "backend-deployment"
    
    # 8. Deploy frontend
    print_status "8. Deploying frontend application..."
    kubectl apply -f "$MANIFESTS_DIR/06-frontend/"
    print_success "Frontend deployment submitted"
    
    # Wait for frontend to be ready
    wait_for_pods "production" "frontend" 300
    check_deployment "production" "frontend-deployment"
    
    # 9. Deploy ingress
    print_status "9. Deploying ingress..."
    kubectl apply -f "$MANIFESTS_DIR/07-ingress/"
    print_success "Ingress deployed"
    
    # 10. Deploy CronJob
    print_status "10. Deploying log cleanup CronJob..."
    kubectl apply -f "$MANIFESTS_DIR/08-jobs/cleanup-cronjob.yaml"
    print_success "CronJob deployed"
    
    # 11. Deploy security policies
    print_status "11. Deploying network policies..."
    kubectl apply -f "$MANIFESTS_DIR/09-security/"
    print_success "Security policies deployed"
    
    print_success "All components deployed successfully!"
}

# Function to show deployment status
show_status() {
    print_status "Deployment Status Summary:"
    echo "=================================="
    
    echo ""
    print_status "Namespaces:"
    kubectl get namespaces production monitoring --no-headers 2>/dev/null || print_warning "Some namespaces not found"
    
    echo ""
    print_status "Persistent Volumes:"
    kubectl get pv --no-headers 2>/dev/null || print_warning "No PVs found"
    
    echo ""
    print_status "Persistent Volume Claims:"
    kubectl get pvc -n production --no-headers 2>/dev/null || print_warning "No PVCs found"
    
    echo ""
    print_status "Deployments:"
    kubectl get deployments -n production --no-headers 2>/dev/null || print_warning "No deployments found"
    
    echo ""
    print_status "Services:"
    kubectl get services -n production --no-headers 2>/dev/null || print_warning "No services found"
    
    echo ""
    print_status "Ingress:"
    kubectl get ingress -n production --no-headers 2>/dev/null || print_warning "No ingress found"
    
    echo ""
    print_status "HPA (Horizontal Pod Autoscaler):"
    kubectl get hpa -n production --no-headers 2>/dev/null || print_warning "No HPA found"
    
    echo ""
    print_status "Jobs:"
    kubectl get jobs -n production --no-headers 2>/dev/null || print_warning "No jobs found"
    
    echo ""
    print_status "CronJobs:"
    kubectl get cronjobs -n production --no-headers 2>/dev/null || print_warning "No cronjobs found"
    
    echo ""
    print_status "Pods:"
    kubectl get pods -n production --no-headers 2>/dev/null || print_warning "No pods found"
    
    echo ""
    print_status "Network Policies:"
    kubectl get networkpolicies -n production --no-headers 2>/dev/null || print_warning "No network policies found"
}

# Function to get access information
show_access_info() {
    echo ""
    print_status "Access Information:"
    echo "==================="
    
    # Get ingress IP
    INGRESS_IP=$(kubectl get ingress app-ingress -n production -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    if [ -z "$INGRESS_IP" ]; then
        INGRESS_IP=$(kubectl get ingress app-ingress -n production -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
    fi
    
    if [ ! -z "$INGRESS_IP" ]; then
        echo "🌐 Application URL: https://myapp.local"
        echo "   (Add '$INGRESS_IP myapp.local' to your /etc/hosts file)"
    else
        print_warning "Ingress IP not yet available. You may need to wait a few minutes."
    fi
    
    # Get LoadBalancer service
    LB_IP=$(kubectl get service frontend-service -n production -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    if [ ! -z "$LB_IP" ]; then
        echo "🌐 Direct Frontend Access: http://$LB_IP"
    fi
    
    echo ""
    echo "📊 Useful commands:"
    echo "  kubectl get pods -n production"
    echo "  kubectl get services -n production"
    echo "  kubectl get ingress -n production"
    echo "  kubectl logs -f deployment/backend-deployment -n production"
    echo "  kubectl logs -f deployment/frontend-deployment -n production"
}

# Main execution
case "${1:-deploy}" in
    "deploy")
        deploy_application
        show_status
        show_access_info
        ;;
    "status")
        show_status
        show_access_info
        ;;
    "help")
        echo "Usage: $0 [deploy|status|help]"
        echo "  deploy  - Deploy the entire application stack (default)"
        echo "  status  - Show current deployment status"
        echo "  help    - Show this help message"
        ;;
    *)
        print_error "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac
