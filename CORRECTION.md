# Correction de l'Exercice Kubernetes

## Vue d'ensemble

Cette correction présente une implémentation complète de l'exercice Kubernetes. Tous les manifests sont organisés de manière logique et suivent les bonnes pratiques.

## Structure des fichiers

```
correction/
├── manifests/
│   ├── 00-namespaces.yaml
│   ├── 01-storage/
│   ├── 02-config/
│   ├── 03-database/
│   ├── 04-cache/
│   ├── 05-backend/
│   ├── 06-frontend/
│   ├── 07-ingress/
│   ├── 08-jobs/
│   └── 09-security/
├── scripts/
│   ├── deploy.sh
│   ├── cleanup.sh
│   └── validate.sh
└── docs/
    ├── deployment-guide.md
    └── troubleshooting.md
```

## Instructions de déploiement

### Prérequis
- Cluster Kubernetes fonctionnel (minikube, kind, ou cluster cloud)
- kubectl configuré
- Ingress controller installé (nginx-ingress recommandé)
- Metrics server installé (pour HPA)

### Déploiement pas à pas

1. **Cloner et naviguer**
   ```bash
   cd correction/
   ```

2. **Déployer avec le script automatisé**
   ```bash
   chmod +x scripts/deploy.sh
   ./scripts/deploy.sh
   ```

3. **Ou déployer manuellement dans l'ordre**
   ```bash
   # 1. Namespaces
   kubectl apply -f manifests/00-namespaces.yaml
   
   # 2. Stockage
   kubectl apply -f manifests/01-storage/
   
   # 3. Configuration
   kubectl apply -f manifests/02-config/
   
   # 4. Base de données
   kubectl apply -f manifests/03-database/
   
   # 5. Cache
   kubectl apply -f manifests/04-cache/
   
   # 6. Backend
   kubectl apply -f manifests/05-backend/
   
   # 7. Frontend
   kubectl apply -f manifests/06-frontend/
   
   # 8. Ingress
   kubectl apply -f manifests/07-ingress/
   
   # 9. Jobs
   kubectl apply -f manifests/08-jobs/
   
   # 10. Sécurité
   kubectl apply -f manifests/09-security/
   ```

### Validation du déploiement

```bash
# Vérifier les pods
kubectl get pods -n production

# Vérifier les services
kubectl get svc -n production

# Vérifier l'ingress
kubectl get ingress -n production

# Vérifier le HPA
kubectl get hpa -n production

# Tester l'application
curl -H "Host: myapp.local" http://<INGRESS_IP>/
```

## Points clés de la correction

### 1. Organisation et structure
- Séparation logique des composants
- Naming convention cohérente
- Labels et annotations standardisés

### 2. Sécurité implémentée
- Secrets pour les mots de passe
- SecurityContext sur tous les pods
- NetworkPolicies pour l'isolation réseau
- Non-root containers

### 3. Haute disponibilité
- Anti-affinity rules
- Multiple répliques
- Health checks complets
- Graceful shutdown

### 4. Scalabilité
- HPA configuré avec métriques appropriées
- Ressources requests/limits optimisées
- Stratégies de déploiement rolling update

### 5. Observabilité
- Labels Prometheus
- Health endpoints
- Logs structurés
- Monitoring hooks

## Commandes de test et validation

### Tests fonctionnels
```bash
# Test de connectivité frontend
kubectl port-forward svc/frontend-service 8080:80 -n production

# Test API backend
kubectl port-forward svc/backend-service 3000:3000 -n production
curl http://localhost:3000/health

# Test base de données
kubectl exec -it deployment/postgres-deployment -n production -- psql -U myuser -d myapp

# Test Redis
kubectl exec -it deployment/redis-deployment -n production -- redis-cli ping
```

### Tests de scalabilité
```bash
# Générer de la charge pour tester HPA
kubectl run -i --tty load-generator --rm --image=busybox --restart=Never -- /bin/sh
# Dans le pod :
while true; do wget -q -O- http://frontend-service.production.svc.cluster.local; done

# Observer la mise à l'échelle
kubectl get hpa -n production -w
```

### Tests de résilience
```bash
# Supprimer un pod pour tester la résilience
kubectl delete pod <frontend-pod-name> -n production

# Vérifier que les répliques sont recréées
kubectl get pods -n production -w
```

## Optimisations avancées

### 1. Stratégie Blue/Green
- Utilisation de labels pour router le trafic
- Service selector dynamique
- Scripts de bascule automatisés

### 2. Sauvegarde PostgreSQL
- CronJob de sauvegarde avec pgdump
- Stockage des backups sur S3/GCS
- Restauration automatisée

### 3. Monitoring avancé
- Intégration Prometheus/Grafana
- Alertes personnalisées
- Dashboards applicatifs

### 4. Gestion des secrets
- Intégration avec HashiCorp Vault
- Sealed Secrets pour GitOps
- Rotation automatique des secrets

## Troubleshooting courant

### Pod en état Pending
```bash
# Vérifier les ressources
kubectl describe pod <pod-name> -n production

# Vérifier les PVC
kubectl get pvc -n production
```

### Service non accessible
```bash
# Vérifier les endpoints
kubectl get endpoints -n production

# Vérifier les labels/selectors
kubectl describe service <service-name> -n production
```

### HPA ne fonctionne pas
```bash
# Vérifier metrics-server
kubectl get pods -n kube-system | grep metrics

# Vérifier les métriques
kubectl top pods -n production
```

Cette correction complète couvre tous les aspects demandés dans l'exercice et fournit une base solide pour un déploiement Kubernetes en production.
