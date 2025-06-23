# Exercice Kubernetes - Déploiement d'une Application Web Complète

## Contexte

Vous êtes DevOps dans une entreprise qui souhaite migrer son application web vers Kubernetes. L'application se compose de :
- **Frontend** : Application React (nginx)
- **Backend** : API REST (Node.js)
- **Base de données** : PostgreSQL
- **Cache** : Redis
- **Tâches batch** : Script de nettoyage des logs

## Objectifs de l'exercice

Déployer une infrastructure Kubernetes complète en utilisant les manifests YAML (Infrastructure as Code) qui inclut :

1. **Pods** - Déploiement des conteneurs applicatifs
2. **ReplicaSets** - Gestion des répliques (via Deployments)
3. **Deployments** - Gestion des déploiements applicatifs
4. **Services** - Exposition des services (ClusterIP, NodePort, LoadBalancer)
5. **Ingress** - Routage externe et gestion des domaines
6. **HPA (Horizontal Pod Autoscaler)** - Mise à l'échelle automatique
7. **PersistentVolumes & PersistentVolumeClaims** - Stockage persistant
8. **ConfigMaps & Secrets** - Configuration et données sensibles
9. **Jobs** - Tâches ponctuelles (migration DB)
10. **CronJobs** - Tâches récurrentes (nettoyage logs)

## Architecture cible

```
Internet
    ↓
 Ingress (nginx-ingress)
    ↓
Frontend Service (LoadBalancer)
    ↓
Frontend Pods (React/nginx) ←→ HPA
    ↓
Backend Service (ClusterIP)
    ↓
Backend Pods (Node.js API) ←→ HPA
    ↓
┌─────────────────┬─────────────────┐
│  PostgreSQL     │     Redis       │
│  Service        │     Service     │
│  (ClusterIP)    │   (ClusterIP)   │
│      ↓          │       ↓         │
│  PostgreSQL     │    Redis        │
│    Pods         │     Pods        │
│      ↓          │       ↓         │
│     PVC         │      PVC        │
└─────────────────┴─────────────────┘
```

## Spécifications détaillées

### 1. Namespaces
- Créer un namespace `production` pour l'application
- Créer un namespace `monitoring` pour les outils de surveillance

### 2. Stockage persistant
- **PostgreSQL** : 10Gi, mode ReadWriteOnce
- **Redis** : 5Gi, mode ReadWriteOnce
- **Logs partagés** : 20Gi, mode ReadWriteMany (pour le nettoyage)

### 3. Base de données PostgreSQL
- Image: `postgres:15`
- Répliques: 1 (master)
- Ressources: CPU 500m-1000m, Memory 512Mi-1Gi
- Variables d'environnement via Secret
- Port: 5432
- Health checks (readiness/liveness)

### 4. Cache Redis
- Image: `redis:7-alpine`
- Répliques: 1
- Ressources: CPU 100m-500m, Memory 128Mi-512Mi
- Configuration via ConfigMap
- Port: 6379
- Persistence activée

### 5. Backend API (Node.js)
- Image: `node:18-alpine`
- Répliques: 3 (minimum)
- Ressources: CPU 200m-800m, Memory 256Mi-512Mi
- Variables d'environnement pour connexion DB/Redis
- Port: 3000
- Health checks
- HPA: 3-10 répliques, cible CPU 70%

### 6. Frontend (React/nginx)
- Image: `nginx:alpine`
- Répliques: 2 (minimum)  
- Ressources: CPU 100m-300m, Memory 128Mi-256Mi
- Configuration nginx via ConfigMap
- Port: 80
- HPA: 2-6 répliques, cible CPU 60%

### 7. Services
- **PostgreSQL** : ClusterIP, port 5432
- **Redis** : ClusterIP, port 6379  
- **Backend** : ClusterIP, port 3000
- **Frontend** : LoadBalancer, port 80

### 8. Ingress
- Host: `myapp.local`
- Règles:
  - `/` → Frontend Service
  - `/api/*` → Backend Service
- TLS activé (certificat auto-signé)
- Annotations pour nginx-ingress-controller

### 9. Job de migration
- Image: `migrate/migrate`
- Exécution unique pour initialiser la DB
- Dépendance sur PostgreSQL
- RestartPolicy: Never

### 10. CronJob de maintenance
- Image: `busybox`
- Schedule: Tous les jours à 2h00 (`0 2 * * *`)
- Nettoie les logs de plus de 7 jours
- ConcurrencyPolicy: Forbid
- SuccessfulJobsHistoryLimit: 3

### 11. Monitoring et observabilité
- Labels appropriés sur toutes les ressources
- Annotations pour Prometheus (si disponible)
- Health checks sur tous les pods applicatifs

## Contraintes techniques

1. **Sécurité** :
   - Utiliser des Secrets pour les mots de passe
   - NetworkPolicies pour isoler les communications
   - SecurityContext pour les pods
   - Non-root containers quand possible

2. **Ressources** :
   - Limits et requests définis pour tous les containers
   - Quality of Service: Guaranteed ou Burstable

3. **Haute disponibilité** :
   - Anti-affinity rules pour éviter les single points of failure
   - Multiple répliques pour les services critiques

4. **Gestion des erreurs** :
   - Proper restart policies
   - Graceful shutdown (terminationGracePeriodSeconds)
   - Circuit breaker patterns dans le code (hors scope)

## Livrables attendus

1. **Fichiers YAML organisés** :
   ```
   manifests/
   ├── 00-namespaces.yaml
   ├── 01-storage/
   │   ├── persistent-volumes.yaml
   │   └── persistent-volume-claims.yaml
   ├── 02-config/
   │   ├── configmaps.yaml
   │   └── secrets.yaml
   ├── 03-database/
   │   ├── postgres-deployment.yaml
   │   └── postgres-service.yaml
   ├── 04-cache/
   │   ├── redis-deployment.yaml
   │   └── redis-service.yaml
   ├── 05-backend/
   │   ├── backend-deployment.yaml
   │   ├── backend-service.yaml
   │   └── backend-hpa.yaml
   ├── 06-frontend/
   │   ├── frontend-deployment.yaml
   │   ├── frontend-service.yaml
   │   └── frontend-hpa.yaml
   ├── 07-ingress/
   │   └── ingress.yaml
   ├── 08-jobs/
   │   ├── migration-job.yaml
   │   └── cleanup-cronjob.yaml
   └── 09-security/
       └── network-policies.yaml
   ```

2. **Scripts de déploiement** :
   - `deploy.sh` : Script pour déployer l'ensemble
   - `cleanup.sh` : Script pour nettoyer les ressources
   - `validate.sh` : Script pour valider le déploiement

3. **Documentation** :
   - Instructions de déploiement
   - Commandes de vérification
   - Troubleshooting guide

## Questions bonus

1. Comment implémenter une stratégie de déploiement Blue/Green ?
2. Comment configurer la sauvegarde automatique de PostgreSQL ?
3. Comment implémenter une stratégie de monitoring avec Prometheus ?
4. Comment gérer les secrets avec un outil externe (Vault, Sealed Secrets) ?
5. Comment optimiser les ressources pour réduire les coûts ?

## Critères d'évaluation

- **Fonctionnalité** (40%) : L'application fonctionne correctement
- **Bonnes pratiques** (30%) : Respect des standards Kubernetes
- **Sécurité** (20%) : Implémentation des mesures de sécurité
- **Documentation** (10%) : Clarté et complétude de la documentation

## Temps estimé
- **Débutant** : 8-12 heures
- **Intermédiaire** : 4-6 heures  
- **Avancé** : 2-3 heures

Bonne chance ! 🚀
