# Kubernetes ToDo App with MySQL - Node Affinity & Anti-Affinity Validation

## Prerequisites
- Docker installed and running
- `kind` (Kubernetes IN Docker) installed
- `kubectl` installed

## Architecture Overview

This setup demonstrates advanced Kubernetes scheduling concepts:

```
┌─────────────────────────────────────────────────────────────────┐
│                     Kubernetes Cluster                         │
├─────────────────┬─────────────────┬─────────────────┬─────────────────┤
│   Control Plane │   Worker Node   │   Worker Node   │   Worker Node   │
│                 │   app=mysql     │   app=mysql     │   app=todoapp   │
│                 │   TAINTED       │   TAINTED       │                 │
├─────────────────┼─────────────────┼─────────────────┼─────────────────┤
│                 │   MySQL Pod 1   │   MySQL Pod 2   │  ToDo App Pod   │
│                 │  (Tolerates     │  (Tolerates     │  (Preferred     │
│                 │   taint)        │   taint)        │   Scheduling)   │
└─────────────────┴─────────────────┴─────────────────┴─────────────────┘
```

## Setup and Deployment

### 1. Automated Deployment
```bash
# Make bootstrap script executable and run
chmod +x bootstrap.sh
./bootstrap.sh
```

The bootstrap script will automatically:
- Create the Kind cluster if it doesn't exist
- Apply node labels if missing
- Taint MySQL nodes
- Deploy all resources
- Wait for readiness

## Detailed Validation Steps

### 1. Verify Node Labels
Check that nodes have the correct labels assigned:

```bash
kubectl get nodes --show-labels | grep -E "app=(mysql|todoapp)"
```

**Expected Output:**
```
todo-mysql-cluster-worker    Ready    <none>   app=mysql
todo-mysql-cluster-worker2   Ready    <none>   app=mysql  
todo-mysql-cluster-worker3   Ready    <none>   app=todoapp
todo-mysql-cluster-worker4   Ready    <none>   app=todoapp
```

### 2. Verify Node Taints
Check that MySQL nodes are properly tainted:

```bash
kubectl get nodes -o json | jq -r '.items[] | {name:.metadata.name, taints:.spec.taints}'
```

**Expected Output:**
```json
{
  "name": "todo-mysql-cluster-worker",
  "taints": [
    {
      "effect": "NoSchedule",
      "key": "app",
      "value": "mysql"
    }
  ]
}
{
  "name": "todo-mysql-cluster-worker2", 
  "taints": [
    {
      "effect": "NoSchedule",
      "key": "app",
      "value": "mysql"
    }
  ]
}
```

### 3. Verify MySQL Pod Placement and Tolerations

#### Check Pod Placement
Confirm MySQL pods are scheduled only on `app=mysql` nodes:

```bash
kubectl -n todo-mysql get pods -o wide
```

**Expected Output:**
```
NAME      READY   STATUS    RESTARTS   NODE
mysql-0   1/1     Running   0          todo-mysql-cluster-worker
mysql-1   1/1     Running   0          todo-mysql-cluster-worker2
```

#### Check Pod Tolerations
Verify MySQL pods have the correct tolerations:

```bash
kubectl -n todo-mysql get pod mysql-0 -o jsonpath='{.spec.tolerations}' | jq .
```

**Expected Output:**
```json
[
  {
    "effect": "NoSchedule",
    "key": "app",
    "operator": "Equal",
    "value": "mysql"
  }
]
```

### 4. Verify MySQL Anti-Affinity Rules

#### Check Pod Distribution
Confirm MySQL pods are spread across different nodes:

```bash
kubectl -n todo-mysql get pods -o wide --no-headers | awk '{print $1 " -> " $7}'
```

**Expected Output:**
```
mysql-0 -> todo-mysql-cluster-worker
mysql-1 -> todo-mysql-cluster-worker2
```

#### Verify Anti-Affinity Configuration
Check the anti-affinity rules in pod description:

```bash
kubectl -n todo-mysql describe pod mysql-0 | grep -A 10 "Pod Anti-affinity"
```

**Expected Output:**
```
Pod Anti-affinity:
  Required for: 
    LabelSelector: 
      MatchLabels: app=mysql
    TopologyKey: kubernetes.io/hostname
```

### 5. Verify ToDo App Node Affinity and Anti-Affinity

#### Check Pod Placement
Confirm ToDo app pods prefer `app=todoapp` nodes:

```bash
kubectl -n todoapp get pods -o wide
```

**Expected Output:**
```
NAME                       READY   STATUS    RESTARTS   NODE
todoapp-xxx-xxx            1/1     Running   0          todo-mysql-cluster-worker3
todoapp-yyy-yyy            1/1     Running   0          todo-mysql-cluster-worker4  
todoapp-zzz-zzz            1/1     Running   0          todo-mysql-cluster-worker3
```

#### Verify Node Affinity Configuration
Check the preferred node affinity:

```bash
kubectl -n todoapp describe pod $(kubectl -n todoapp get pods -o name | head -1) | grep -A 15 "Node-Selectors"
```

**Expected Output:**
```
Node-Selectors:  <none>
Node-Affinity: 
  Preferred for:
    Weight:        100
    MatchExpressions:
      Key:         app
      Operator:    In
      Values:      todoapp
```

#### Verify Pod Anti-Affinity
Check that pods are distributed when possible:

```bash
kubectl -n todoapp describe pod $(kubectl -n todoapp get pods -o name | head -1) | grep -A 10 "Pod Anti-affinity"
```

**Expected Output:**
```
Pod Anti-affinity:
  Preferred for:
    Weight:        100
    LabelSelector:
      MatchLabels: app=todoapp
    TopologyKey:   kubernetes.io/hostname
```

### 6. Verify Services and Connectivity

#### Check Services Status
```bash
kubectl get services -n todo-mysql
kubectl get services -n todoapp
```

**Expected Output:**
```
# MySQL Services
NAME             TYPE        CLUSTER-IP      PORT(S)          AGE
mysql-external   NodePort    10.96.xxx.xxx   3306:30306/TCP   5m
mysql-service    ClusterIP   None            3306/TCP         5m

# ToDo App Services  
NAME               TYPE        CLUSTER-IP      PORT(S)        AGE
todoapp-external   NodePort    10.96.xxx.xxx   80:30000/TCP   5m
todoapp-service    ClusterIP   10.96.xxx.xxx   80/TCP         5m
```

#### Test Application Access
Test ToDo app via NodePort:

```bash
curl -s http://localhost:30000 | grep -o "<title>.*</title>"
```

**Expected Output:**
```
<title>Advanced ToDo App</title>
```

#### Test MySQL Connectivity
Test MySQL connection via NodePort:

```bash
# Using mysql client (if available)
mysql -h localhost -P 30306 -u todoapp -ptodoapp -e "SHOW DATABASES;"

# Or using kubectl exec
kubectl -n todo-mysql exec mysql-0 -- mysql -u todoapp -ptodoapp -e "SHOW DATABASES;"
```

**Expected Output:**
```
+--------------------+
| Database           |
+--------------------+
| information_schema |
| todoapp           |
+--------------------+
```

### 7. Comprehensive Status Check

Run a complete status check:

```bash
echo "=== NODES AND LABELS ==="
kubectl get nodes --show-labels | grep app=

echo -e "\n=== NODE TAINTS ==="
kubectl describe nodes | grep -E "Name:|Taints:" | grep -A1 "Name:"

echo -e "\n=== MYSQL PODS PLACEMENT ==="
kubectl -n todo-mysql get pods -o wide

echo -e "\n=== TODOAPP PODS PLACEMENT ==="  
kubectl -n todoapp get pods -o wide

echo -e "\n=== SERVICES ==="
kubectl get svc -n todo-mysql
kubectl get svc -n todoapp

echo -e "\n=== APPLICATION ACCESS TEST ==="
curl -I http://localhost:30000 2>/dev/null | head -1
```

## Troubleshooting

### Common Issues and Solutions

#### 1. Pods Stuck in Pending State

**Symptom:** MySQL pods remain in `Pending` status.

**Diagnosis:**
```bash
kubectl -n todo-mysql describe pod mysql-0 | grep -A 5 "Events:"
```

**Common Causes:**
- Node doesn't have required labels
- Pod doesn't have proper tolerations
- Anti-affinity rules prevent scheduling

**Solutions:**
```bash
# Check node labels
kubectl get nodes --show-labels | grep app=mysql

# Add missing labels if needed
kubectl label node <node-name> app=mysql

# Check tolerations in StatefulSet
kubectl -n todo-mysql get statefulset mysql -o yaml | grep -A 5 tolerations
```

#### 2. Pods Scheduled on Wrong Nodes

**Symptom:** MySQL pods scheduled on non-MySQL nodes or ToDo pods not preferring todoapp nodes.

**Diagnosis:**
```bash
# Check actual vs expected placement
kubectl get pods -A -o wide | grep -E "(mysql|todoapp)"

# Check node affinity rules
kubectl describe pod <pod-name> -n <namespace> | grep -A 10 "Node-Affinity"
```

**Solutions:**
```bash
# Delete and recreate pods to trigger rescheduling
kubectl -n todo-mysql delete pod mysql-0

# Verify affinity rules in deployment/statefulset
kubectl -n todoapp get deployment todoapp -o yaml | grep -A 15 affinity
```

#### 3. Services Not Accessible

**Symptom:** Cannot access applications via NodePort.

**Diagnosis:**
```bash
# Check service configuration
kubectl get svc -n todoapp todoapp-external -o yaml

# Check if pods are ready and endpoints exist
kubectl get endpoints -n todoapp
kubectl get pods -n todoapp
```

**Solutions:**
```bash
# Check Kind port mappings
docker ps | grep todo-mysql-cluster

# Test internal service first
kubectl -n todoapp exec -it <pod-name> -- curl todoapp-service
```

#### 4. Anti-Affinity Not Working

**Symptom:** Multiple pods scheduled on same node despite anti-affinity rules.

**Diagnosis:**
```bash
# Check if there are enough nodes
kubectl get nodes | wc -l

# Check anti-affinity rules
kubectl describe deployment -n todoapp | grep -A 10 "Pod Anti-affinity"
```

**Solutions:**
- Ensure sufficient nodes exist for spreading
- Check if anti-affinity is `required` vs `preferred`
- For MySQL, anti-affinity is `required`, so pods will remain pending if not enough nodes

### 5. Clean Up Commands

```bash
# Delete specific resources
kubectl delete namespace todo-mysql
kubectl delete namespace todoapp

# Remove node taints
kubectl taint nodes --all app=mysql:NoSchedule-

# Delete entire cluster
kind delete cluster --name todo-mysql-cluster
```

## Expected Final State

After successful deployment and validation:

✅ **Cluster:** 5-node Kind cluster (1 control-plane + 4 workers)  
✅ **Node Labels:** 2 nodes with `app=mysql`, 2 nodes with `app=todoapp`  
✅ **Node Taints:** MySQL nodes tainted with `app=mysql:NoSchedule`  
✅ **MySQL StatefulSet:** 2 replicas scheduled only on MySQL nodes with tolerations  
✅ **MySQL Anti-Affinity:** Pods distributed across different MySQL nodes  
✅ **ToDo Deployment:** 3 replicas preferring todoapp nodes  
✅ **ToDo Anti-Affinity:** Pods distributed when possible  
✅ **Services:** All services accessible via NodePort and ClusterIP  
✅ **Application:** ToDo app accessible at `http://localhost:30000`  
✅ **Database:** MySQL accessible at `localhost:30306`  

This setup demonstrates advanced Kubernetes scheduling with node affinity, pod anti-affinity, taints, and tolerations working together to achieve desired workload placement and high availability.