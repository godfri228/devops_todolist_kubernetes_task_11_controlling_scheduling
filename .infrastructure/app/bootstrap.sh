#!/bin/bash

set -e

echo " Starting Kubernetes ToDo App with MySQL deployment..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN} $1${NC}"
}

print_info() {
    echo -e "${BLUE}  $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}  $1${NC}"
}

print_error() {
    echo -e "${RED} $1${NC}"
}

# Step 1: Create cluster if it doesn't exist
if ! kind get clusters 2>/dev/null | grep -q "todo-mysql-cluster"; then
    print_info "Cluster 'todo-mysql-cluster' not found. Creating it from cluster.yml..."
    if [ ! -f "cluster.yml" ]; then
        print_error "cluster.yml file not found. Please ensure it exists in the current directory."
        exit 1
    fi
    kind create cluster --name todo-mysql-cluster --config cluster.yml
    print_status "Cluster created successfully"

    # Wait for cluster to be ready
    print_info "Waiting for cluster nodes to be ready..."
    kubectl wait --for=condition=ready nodes --all --timeout=300s
    print_status "All nodes are ready"
else
    print_info "Using existing cluster: todo-mysql-cluster"
fi

# Switch to the cluster context
kubectl config use-context kind-todo-mysql-cluster

# Step 2: Ensure node labels are present
print_info "Step 2: Ensuring required node labels are present..."

# Get all worker nodes
WORKER_NODES=($(kubectl get nodes --no-headers | grep -v control-plane | awk '{print $1}'))
TOTAL_WORKERS=${#WORKER_NODES[@]}

if [ $TOTAL_WORKERS -lt 4 ]; then
    print_warning "Expected at least 4 worker nodes, found $TOTAL_WORKERS"
fi

# Label first 2 workers as MySQL nodes
print_info "Labeling MySQL nodes..."
for i in 0 1; do
    if [ $i -lt $TOTAL_WORKERS ]; then
        NODE=${WORKER_NODES[$i]}
        kubectl label node $NODE app=mysql --overwrite
        print_status "Labeled node $NODE with app=mysql"
    fi
done

# Label remaining workers as ToDo app nodes
print_info "Labeling ToDo app nodes..."
for i in $(seq 2 $((TOTAL_WORKERS-1))); do
    if [ $i -lt $TOTAL_WORKERS ]; then
        NODE=${WORKER_NODES[$i]}
        kubectl label node $NODE app=todoapp --overwrite
        print_status "Labeled node $NODE with app=todoapp"
    fi
done

# If we have fewer than 4 nodes, label the remaining ones as todoapp
if [ $TOTAL_WORKERS -le 3 ]; then
    for i in $(seq 2 $((TOTAL_WORKERS-1))); do
        NODE=${WORKER_NODES[$i]}
        kubectl label node $NODE app=todoapp --overwrite
        print_status "Labeled node $NODE with app=todoapp"
    done
fi

# Step 3: Create namespaces if they don't exist
print_info "Step 3: Ensuring namespaces exist..."
kubectl get namespace todo-mysql >/dev/null 2>&1 || kubectl create namespace todo-mysql
kubectl get namespace todoapp >/dev/null 2>&1 || kubectl create namespace todoapp
print_status "Namespaces ready"

# Step 4: Inspect nodes for labels and taints
print_info "Step 4: Inspecting nodes for labels and taints..."
echo "==================== NODES BEFORE TAINTING ===================="
kubectl get nodes --show-labels
echo ""
kubectl describe nodes | grep -E "Name:|Labels:|Taints:" || true
echo "================================================================"

# Step 5: Taint nodes labeled with app=mysql
print_info "Step 5: Tainting nodes labeled with app=mysql..."
MYSQL_NODES=$(kubectl get nodes -l app=mysql -o jsonpath='{.items[*].metadata.name}')

if [ -z "$MYSQL_NODES" ]; then
    print_warning "No nodes found with label app=mysql"
else
    for node in $MYSQL_NODES; do
        print_info "Tainting node: $node with app=mysql:NoSchedule"
        kubectl taint node $node app=mysql:NoSchedule --overwrite
    done
fi

# Step 6: Deploy MySQL StatefulSet
print_info "Step 6: Deploying MySQL StatefulSet with tolerations and affinity rules..."
kubectl apply -f infrastructure/mysql/mysql-statefulset.yml
print_status "MySQL StatefulSet deployed"

# Step 7: Deploy ToDo App Deployment
print_info "Step 7: Deploying ToDo App with node affinity and pod anti-affinity..."
kubectl apply -f infrastructure/todoapp/todoapp-deployment.yml
print_status "ToDo App Deployment deployed"

# Step 8: Wait for MySQL to be ready
print_info "Step 8: Waiting for MySQL StatefulSet to be ready..."
kubectl wait --for=condition=ready pod -l app=mysql -n todo-mysql --timeout=300s

print_status "MySQL pods are ready"

# Step 9: Wait for ToDo App to be ready
print_info "Step 9: Waiting for ToDo App Deployment to be ready..."
kubectl wait --for=condition=ready pod -l app=todoapp -n todoapp --timeout=120s

print_status "ToDo App pods are ready"

# Step 10: Display final status
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

# Step 11: Display access information
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

print_info "Quick validation test:"
echo "Testing ToDo app connectivity..."
sleep 5
if curl -s --max-time 10 http://localhost:30000 >/dev/null; then
    print_status "ToDo app is accessible at http://localhost:30000"
else
    print_warning "ToDo app may still be starting up. Try: curl http://localhost:30000"
fi

print_status "Bootstrap completed successfully! 🎉"
print_info "Run the validation steps from INSTRUCTION.md to verify all scheduling rules are working correctly."