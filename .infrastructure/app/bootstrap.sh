#!/bin/bash

set -e

echo " Starting Kubernetes ToDo App with MySQL deployment..."

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN} $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ  $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}  $1${NC}"
}

print_error() {
    echo -e "${RED} $1${NC}"
}

if ! kind get clusters | grep -q "todo-mysql-cluster"; then
    print_error "Cluster 'todo-mysql-cluster' not found. Please create it first:"
    echo "kind create cluster --config=cluster.yml"
    exit 1
fi

print_info "Using existing cluster: todo-mysql-cluster"

kubectl config use-context kind-todo-mysql-cluster

print_info "Step 1: Inspecting nodes for labels and taints..."
echo "==================== NODES BEFORE TAINTING ===================="
kubectl get nodes --show-labels
echo ""
kubectl describe nodes | grep -E "Name:|Labels:|Taints:" || true
echo "================================================================"

print_info "Step 2: Tainting nodes labeled with app=mysql..."
MYSQL_NODES=$(kubectl get nodes -l app=mysql -o jsonpath='{.items[*].metadata.name}')

if [ -z "$MYSQL_NODES" ]; then
    print_warning "No nodes found with label app=mysql"
else
    for node in $MYSQL_NODES; do
        print_info "Tainting node: $node with app=mysql:NoSchedule"
        kubectl taint node $node app=mysql:NoSchedule --overwrite
    done
fi

print_info "Step 3: Deploying MySQL StatefulSet with tolerations and affinity rules..."
kubectl apply -f infrastructure/mysql/mysql-statefulset.yml
print_status "MySQL StatefulSet deployed"

print_info "Step 4: Deploying ToDo App with node affinity and pod anti-affinity..."
kubectl apply -f infrastructure/todoapp/todoapp-deployment.yml
print_status "ToDo App Deployment deployed"

print_info "Step 5: Waiting for MySQL StatefulSet to be ready..."
kubectl wait --for=condition=ready pod -l app=mysql -n todo-mysql --timeout=300s

print_status "MySQL pods are ready"

print_info "Step 6: Waiting for ToDo App Deployment to be ready..."
kubectl wait --for=condition=ready pod -l app=todoapp -n todoapp --timeout=120s

print_status "ToDo App pods are ready"

echo ""
echo "==================== DEPLOYMENT SUMMARY ===================="
print_status "All resources deployed successfully!"
echo ""

print_info "Namespaces created:"
kubectl get namespaces | grep -E "(todo-mysql|todoapp)"
echo ""

print_info "Nodes after tainting:"
kubectl get nodes --show-labels
echo ""
kubectl describe nodes | grep -E "Name:|Taints:" | grep -A1 "Name:" || true
echo ""

print_info "MySQL StatefulSet status:"
kubectl get statefulset,pods,svc -n todo-mysql
echo ""

print_info "ToDo App Deployment status:"
kubectl get deployment,pods,svc -n todoapp
echo ""

print_info "Pod scheduling information:"
echo "MySQL Pods:"
kubectl get pods -n todo-mysql -o wide
echo ""
echo "ToDo App Pods:"
kubectl get pods -n todoapp -o wide
echo ""

echo "==================== ACCESS INFORMATION ===================="
print_status "Applications are ready!"
echo ""
print_info "ToDo App Access:"
echo "  • NodePort: http://localhost:30000"
echo "  • Internal: todoapp-service.todoapp.svc.cluster.local"
echo ""
print_info "MySQL Access:"
echo "  • NodePort: localhost:30306"
echo "  • Internal: mysql-service.todo-mysql.svc.cluster.local:3306"
echo "  • Credentials: user=todoapp, password=todoapp, db=todoapp"
echo ""

print_info "Validation commands:"
echo "  kubectl get pods -n todo-mysql -o wide"
echo "  kubectl get pods -n todoapp -o wide"
echo "  kubectl describe pod <pod-name> -n <namespace>"
echo "  curl http://localhost:30000"
echo ""
print_status "Bootstrap completed successfully! 🎉"