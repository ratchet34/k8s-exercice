# Guide de Déploiement - Application Kubernetes

## Vue d'ensemble

Ce guide détaille le processus de déploiement complet d'une application web Kubernetes incluant :
- Frontend (React/nginx)
- Backend (Node.js API)
- Base de données (PostgreSQL)
- Cache (Redis)
- Infrastructure (Load Balancer, Ingress, HPA, etc.)

## Prérequis

### 1. Environnement Kubernetes
- **Cluster Kubernetes** : v1.25+ recommandé
  - Minikube (pour développement local)
  - Kind (pour tests)
  - Cluster cloud (AKS, EKS, GKE)
- **kubectl** : configuré et connecté au cluster
- **Metrics Server** : pour l'autoscaling (HPA)
- **Ingress Controller** : nginx-ingress recommandé

### 2. Ressources cluster minimales
- **CPU** : 4 vCPUs minimum
- **RAM** : 8GB minimum
- **Stockage** : 50GB disponible pour PersistentVolumes

### 3. Outils recommandés
```bash
# Installation kubectl (Linux)
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Installation Minikube (développement local)
curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube /usr/local/bin/

# Démarrage Minikube avec ressources suffisantes
minikube start --cpus=4 --memory=8192 --disk-size=50g
minikube addons enable ingress
minikube addons enable metrics-server
```

## Architecture déployée

```
Internet
    ↓
┌─────────────────┐
│   Ingress       │ ← TLS, Rate Limiting, Routing
│ (nginx-ingress) │
└─────────────────┘
         ↓
┌─────────────────┐
│ Frontend Service│ ← LoadBalancer
│   (nginx)       │
└─────────────────┘
         ↓
┌─────────────────┐    ┌─────────────────┐
│ Frontend Pods   │    │ Backend Service │
│ (2-6 replicas)  │───→│   (ClusterIP)   │
│ + HPA           │    └─────────────────┘
└─────────────────┘            ↓
                     ┌─────────────────┐
                     │ Backend Pods    │
                     │ (3-10 replicas) │
                     │ + HPA           │
                     └─────────────────┘
                              ↓
                ┌─────────────────┬─────────────────┐
                │  PostgreSQL     │     Redis       │
                │   Service       │    Service      │
                │ (ClusterIP)     │  (ClusterIP)    │
                └─────────────────┴─────────────────┘
                         ↓                 ↓
                ┌─────────────────┬─────────────────┐
                │ PostgreSQL Pod  │   Redis Pod     │
                │     + PVC       │     + PVC       │
                └─────────────────┴─────────────────┘
```

## Processus de déploiement

### Étape 1 : Préparation
```bash
# Cloner le projet
git clone <repository>
cd k8s-exercice/correction

# Vérifier l'accès au cluster
kubectl cluster-info
kubectl get nodes

# Vérifier les add-ons nécessaires
kubectl get pods -n kube-system | grep -E "(ingress|metrics)"
```

### Étape 2 : Déploiement automatisé
```bash
# Rendre le script exécutable
chmod +x scripts/deploy.sh

# Lancer le déploiement complet
./scripts/deploy.sh

# Le script déploiera dans l'ordre :
# 1. Namespaces
# 2. Stockage (PV/PVC)
# 3. Configuration (ConfigMaps/Secrets)
# 4. Base de données PostgreSQL
# 5. Cache Redis
# 6. Migration de base de données
# 7. Backend API
# 8. Frontend
# 9. Ingress
# 10. Jobs/CronJobs
# 11. Politiques de sécurité
```

### Étape 3 : Validation
```bash
# Validation complète
./scripts/validate.sh

# Validation rapide
./scripts/validate.sh quick

# Rapport détaillé
./scripts/validate.sh report
```

## Déploiement manuel (étape par étape)

Si vous préférez déployer manuellement :

### 1. Namespaces
```bash
kubectl apply -f manifests/00-namespaces.yaml
```

### 2. Stockage
```bash
kubectl apply -f manifests/01-storage/
kubectl wait --for=condition=bound pvc --all -n production --timeout=60s
```

### 3. Configuration
```bash
kubectl apply -f manifests/02-config/
```

### 4. Base de données
```bash
kubectl apply -f manifests/03-database/
kubectl wait --for=condition=ready pod -l app=postgres -n production --timeout=300s
```

### 5. Cache
```bash
kubectl apply -f manifests/04-cache/
kubectl wait --for=condition=ready pod -l app=redis -n production --timeout=180s
```

### 6. Migration
```bash
kubectl apply -f manifests/08-jobs/migration-job.yaml
kubectl wait --for=condition=complete job/database-migration-job -n production --timeout=600s
```

### 7. Backend
```bash
kubectl apply -f manifests/05-backend/
kubectl wait --for=condition=ready pod -l app=backend -n production --timeout=300s
```

### 8. Frontend
```bash
kubectl apply -f manifests/06-frontend/
kubectl wait --for=condition=ready pod -l app=frontend -n production --timeout=300s
```

### 9. Ingress
```bash
kubectl apply -f manifests/07-ingress/
```

### 10. Jobs et sécurité
```bash
kubectl apply -f manifests/08-jobs/cleanup-cronjob.yaml
kubectl apply -f manifests/09-security/
```

## Configuration post-déploiement

### 1. Configuration DNS locale
```bash
# Obtenir l'IP de l'ingress
INGRESS_IP=$(kubectl get ingress app-ingress -n production -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Ajouter à /etc/hosts (Linux/Mac) ou C:\Windows\System32\drivers\etc\hosts (Windows)
echo "$INGRESS_IP myapp.local" | sudo tee -a /etc/hosts
```

### 2. Test de connectivité
```bash
# Test frontend
curl -k https://myapp.local/

# Test backend API
curl -k https://myapp.local/api/status

# Test avec port-forward si ingress non disponible
kubectl port-forward svc/frontend-service 8080:80 -n production
```

## Surveillance et maintenance

### 1. Surveillance des pods
```bash
# Statut général
kubectl get pods -n production

# Logs en temps réel
kubectl logs -f deployment/backend-deployment -n production
kubectl logs -f deployment/frontend-deployment -n production

# Métriques de performance
kubectl top pods -n production
kubectl top nodes
```

### 2. Surveillance HPA
```bash
# Statut autoscaling
kubectl get hpa -n production

# Surveiller en temps réel
kubectl get hpa -n production -w

# Générer de la charge pour tester
kubectl run load-generator --image=busybox --rm -it --restart=Never -- /bin/sh
# Dans le pod :
while true; do wget -q -O- http://frontend-service.production.svc.cluster.local; done
```

### 3. Gestion des jobs
```bash
# Vérifier le job de migration
kubectl get jobs -n production
kubectl logs job/database-migration-job -n production

# Déclencher manuellement le CronJob de nettoyage
kubectl create job manual-cleanup --from=cronjob/log-cleanup-cronjob -n production
```

## Mise à l'échelle manuelle

### Frontend
```bash
kubectl scale deployment frontend-deployment --replicas=4 -n production
```

### Backend
```bash
kubectl scale deployment backend-deployment --replicas=6 -n production
```

## Mise à jour de l'application

### Rolling Update
```bash
# Exemple : mise à jour de l'image backend
kubectl set image deployment/backend-deployment backend=node:18-alpine -n production

# Suivre le rollout
kubectl rollout status deployment/backend-deployment -n production

# Rollback si nécessaire
kubectl rollout undo deployment/backend-deployment -n production
```

## Sauvegarde et restauration

### Sauvegarde PostgreSQL
```bash
# Créer un job de sauvegarde
kubectl exec -it deployment/postgres-deployment -n production -- pg_dump -U myuser myapp > backup.sql
```

### Sauvegarde des manifests
```bash
# Exporter toutes les ressources
kubectl get all -n production -o yaml > production-backup.yaml
```

## Dépannage courant

### Pod en état Pending
```bash
kubectl describe pod <pod-name> -n production
# Vérifier : ressources, PVC, node selector
```

### Service inaccessible
```bash
kubectl get endpoints -n production
kubectl describe service <service-name> -n production
# Vérifier : sélecteurs de pods, ports
```

### HPA ne fonctionne pas
```bash
kubectl describe hpa <hpa-name> -n production
kubectl get --raw /apis/metrics.k8s.io/v1beta1/pods
# Vérifier : metrics-server installé
```

### Ingress non accessible
```bash
kubectl get ingress -n production
kubectl describe ingress app-ingress -n production
# Vérifier : ingress controller, DNS
```

## Nettoyage

### Nettoyage complet
```bash
./scripts/cleanup.sh
```

### Nettoyage sélectif
```bash
# Supprimer seulement les applications
kubectl delete -f manifests/05-backend/ -f manifests/06-frontend/

# Supprimer ingress
kubectl delete -f manifests/07-ingress/
```

## Optimisations de performance

### 1. Ressources
- Ajuster les requests/limits selon l'usage réel
- Utiliser des profils de QoS appropriés
- Surveiller l'utilisation des ressources

### 2. Mise en cache
- Configurer Redis pour la mise en cache applicative
- Utiliser des StaticSets pour les données statiques
- Optimiser les requêtes SQL

### 3. Réseau
- Utiliser des NetworkPolicies pour limiter le trafic
- Configurer des anti-affinity rules
- Optimiser la configuration Ingress

Cette configuration offre une base solide pour un déploiement Kubernetes en production, avec toutes les bonnes pratiques de sécurité, performance et maintenabilité.
