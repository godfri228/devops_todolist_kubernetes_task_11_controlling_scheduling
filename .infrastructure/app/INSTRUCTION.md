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

### 1. Create Kind Cluster
```bash
# Create multi-node cluster with labeled nodes
kind create cluster --config=cluster.yml

# Verify cluster is running
kubectl cluster-info --context kind-todo-mysql-cluster
```

### 2. Run Bootstrap Script
```bash
# Make bootstrap script executable