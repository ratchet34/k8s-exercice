# 🚀 Exercice Kubernetes - Infrastructure as Code

## Vue d'ensemble

Ce repository contient un exercice complet de déploiement d'une application web sur Kubernetes en utilisant l'Infrastructure as Code (IaC). L'exercice couvre tous les aspects essentiels de Kubernetes en production.

## 📋 Contenu

- **[EXERCICE.md](EXERCICE.md)** - Énoncé détaillé de l'exercice
- **[CORRECTION.md](CORRECTION.md)** - Vue d'ensemble de la correction
- **[correction/](correction/)** - Solution complète avec tous les manifests

## 🎯 Objectifs pédagogiques

Cet exercice permet d'apprendre et de maîtriser :

- ✅ **Pods** - Déploiement des conteneurs
- ✅ **Deployments** - Gestion des déploiements applicatifs  
- ✅ **Services** - Exposition des services (ClusterIP, LoadBalancer)
- ✅ **ReplicaSets** - Gestion automatique des répliques
- ✅ **Ingress** - Routage externe et gestion des domaines
- ✅ **HPA** - Mise à l'échelle automatique horizontale
- ✅ **PersistentVolumes/PVC** - Stockage persistant
- ✅ **ConfigMaps & Secrets** - Configuration et données sensibles
- ✅ **Jobs** - Tâches ponctuelles (migration DB)
- ✅ **CronJobs** - Tâches récurrentes (nettoyage logs)
- ✅ **NetworkPolicies** - Sécurité réseau
- ✅ **SecurityContext** - Sécurité des conteneurs

## 🏗️ Architecture

```
Internet → Ingress → Frontend (LB) → Backend API → PostgreSQL + Redis
                      ↕ HPA        ↕ HPA          ↕        ↕
                   2-6 replicas   3-10 replicas  PVC      PVC
```

## 🚀 Démarrage rapide

### Prérequis
- Cluster Kubernetes (minikube, kind, ou cloud)
- kubectl configuré
- Ingress controller (nginx-ingress)
- Metrics server (pour HPA)

#### Prérequis spécifiques Windows
Pour exécuter les scripts sur Windows, vous avez plusieurs options :

1. **PowerShell** (recommandé - scripts natifs disponibles)
   ```powershell
   # Activer l'exécution des scripts PowerShell (une seule fois)
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   
   # Puis exécuter les scripts
   .\scripts\deploy.ps1
   ```

2. **Git Bash** (installé avec Git pour Windows)
   ```cmd
   # Télécharger depuis https://git-scm.com/download/win
   # Les scripts bash fonctionnent directement
   bash scripts/deploy.sh
   ```

3. **WSL (Windows Subsystem for Linux)**
   ```powershell
   # Installer WSL
   wsl --install
   # Puis utiliser : wsl bash scripts/deploy.sh
   ```

### Déploiement automatisé

#### Sur Linux/Mac
```bash
cd correction/
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

#### Sur Windows
```cmd
cd correction
# Option 1: Git Bash (recommandé)
bash scripts/deploy.sh

# Option 2: WSL (Windows Subsystem for Linux)
wsl bash scripts/deploy.sh

# Option 3: PowerShell (recommandé sur Windows)
# Activer l'exécution de scripts (une seule fois)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
# Puis exécuter
powershell -File scripts/deploy.ps1
```

### Validation
#### Sur Linux/Mac
```bash
./scripts/validate.sh
```

#### Sur Windows
```cmd
# Git Bash
bash scripts/validate.sh

# WSL
wsl bash scripts/validate.sh
```

### Nettoyage
#### Sur Linux/Mac
```bash
./scripts/cleanup.sh
```

#### Sur Windows
```cmd
# Git Bash
bash scripts/cleanup.sh

# WSL
wsl bash scripts/cleanup.sh
```

## 💻 Support Windows

### Scripts disponibles pour Windows

En plus des scripts bash, des scripts PowerShell équivalents sont disponibles :

- **deploy.ps1** - Déploiement automatisé PowerShell
- **cleanup.ps1** - Nettoyage des ressources PowerShell  
- **validate.ps1** - Validation du déploiement PowerShell

### Exemples d'utilisation Windows

#### PowerShell (Recommandé)
```powershell
cd correction\scripts

# Déploiement
.\deploy.ps1

# Validation
.\validate.ps1

# Nettoyage
.\cleanup.ps1
```

#### Git Bash sur Windows
```bash
cd correction/scripts

# Déploiement
bash deploy.sh

# Validation  
bash validate.sh

# Nettoyage
bash cleanup.sh
```

#### WSL (Windows Subsystem for Linux)
```cmd
# Depuis CMD ou PowerShell
wsl bash correction/scripts/deploy.sh
wsl bash correction/scripts/validate.sh
wsl bash correction/scripts/cleanup.sh
```

#### Commandes kubectl manuelles (toutes plateformes)
```cmd
# Déploiement pas à pas
kubectl apply -f correction\manifests\00-namespaces.yaml
kubectl apply -f correction\manifests\01-storage\
kubectl apply -f correction\manifests\02-config\
# ... etc

# Vérification
kubectl get pods -n production
kubectl get services -n production
```

## 📁 Structure des fichiers

```
k8s-exercice/
├── EXERCICE.md                 # Énoncé détaillé
├── CORRECTION.md               # Guide de correction
├── README.md                   # Ce fichier
└── correction/
    ├── manifests/              # Manifests Kubernetes
    │   ├── 00-namespaces.yaml
    │   ├── 01-storage/         # PV, PVC
    │   ├── 02-config/          # ConfigMaps, Secrets
    │   ├── 03-database/        # PostgreSQL
    │   ├── 04-cache/           # Redis
    │   ├── 05-backend/         # API Node.js + HPA
    │   ├── 06-frontend/        # React/nginx + HPA
    │   ├── 07-ingress/         # Routage externe
    │   ├── 08-jobs/            # Job migration + CronJob cleanup
    │   └── 09-security/        # NetworkPolicies
    ├── scripts/                # Scripts d'automatisation
    │   ├── deploy.sh           # Déploiement complet
    │   ├── cleanup.sh          # Nettoyage des ressources
    │   └── validate.sh         # Validation du déploiement
    └── docs/                   # Documentation
        ├── deployment-guide.md # Guide de déploiement détaillé
        └── troubleshooting.md  # Guide de dépannage
```

## 🔧 Composants déployés

### Base de données et Cache
- **PostgreSQL** - Base de données principale avec PVC 10Gi
- **Redis** - Cache en mémoire avec persistence 5Gi

### Applications
- **Backend API** - Node.js avec connexions DB/Redis
- **Frontend** - Interface React servie par nginx

### Infrastructure
- **Load Balancer** - Service frontend accessible externe
- **Ingress** - Routage avec TLS et rate limiting
- **HPA** - Autoscaling basé sur CPU/Memory

### Jobs et maintenance
- **Migration Job** - Initialisation de la base de données
- **Cleanup CronJob** - Nettoyage quotidien des logs

### Sécurité
- **NetworkPolicies** - Isolation réseau entre composants
- **Secrets** - Stockage sécurisé des mots de passe
- **SecurityContext** - Conteneurs non-root

## 🌐 Accès à l'application

Une fois déployé, l'application est accessible via :

1. **Ingress** : `https://myapp.local` (après configuration DNS)
2. **LoadBalancer** : IP externe du service frontend
3. **Port-forward** : `kubectl port-forward svc/frontend-service 8080:80 -n production`

## 📊 Monitoring et observabilité

### Commandes utiles
```bash
# Statut général
kubectl get all -n production

# Métriques de performance  
kubectl top pods -n production
kubectl top nodes

# Logs en temps réel
kubectl logs -f deployment/backend-deployment -n production

# Statut HPA
kubectl get hpa -n production -w
```

### Dashboards
- Labels Prometheus sur tous les composants
- Endpoints `/metrics` pour le monitoring
- Health checks configurés

## 🔒 Sécurité implémentée

- **Isolation réseau** avec NetworkPolicies
- **Secrets** pour les mots de passe et certificats
- **Non-root containers** où possible
- **Resource limits** pour prévenir les attaques DoS
- **TLS** sur l'ingress
- **SecurityContext** sur tous les pods

## 🚀 Déploiement en production

### Recommandations
1. **Backup** - Configurer la sauvegarde automatique de PostgreSQL
2. **Monitoring** - Intégrer Prometheus/Grafana
3. **Secrets Management** - Utiliser Vault ou Sealed Secrets
4. **GitOps** - Déployer via ArgoCD ou Flux
5. **Policy** - Implémenter OPA Gatekeeper

### Optimisations
- Ajuster les ressources selon l'usage réel
- Configurer des PodDisruptionBudgets
- Utiliser des taints/tolerations pour l'isolation
- Implémenter des stratégies de déploiement avancées

## 🤝 Contributions

Cet exercice est conçu à des fins pédagogiques. Les suggestions d'amélioration sont les bienvenues !

### Structure pour contributions
- Issues pour signaler des problèmes
- Pull requests pour des améliorations
- Documentation pour des cas d'usage additionnels

## 📚 Ressources supplémentaires

- [Documentation Kubernetes officielle](https://kubernetes.io/docs/)
- [Kubernetes Best Practices](https://kubernetes.io/docs/concepts/configuration/overview/)
- [Helm Charts](https://helm.sh/) - Pour des déploiements plus complexes
- [Kustomize](https://kustomize.io/) - Pour la gestion de configuration

## ⭐ Niveau de difficulté

- **Débutant** : 8-12 heures - Premier contact avec Kubernetes
- **Intermédiaire** : 4-6 heures - Expérience Docker/containers requise  
- **Avancé** : 2-3 heures - Connaissance préalable de Kubernetes

## 🏆 Critères de réussite

1. **Fonctionnalité** - L'application fonctionne correctement
2. **Scalabilité** - HPA fonctionne et adapte les répliques
3. **Persistance** - Les données survivent aux redémarrages
4. **Sécurité** - NetworkPolicies et secrets configurés
5. **Monitoring** - Métriques et logs accessibles

---

**Bonne chance dans votre apprentissage de Kubernetes ! 🚀**

> Ce projet fait partie d'une série d'exercices pratiques pour maîtriser les technologies cloud-native.

## 🔐 Configuration PowerShell pour Windows

### Activation de l'exécution des scripts

Par défaut, Windows bloque l'exécution des scripts PowerShell pour des raisons de sécurité. Voici comment les activer :

#### Méthode 1 : Politique d'exécution utilisateur (Recommandée)
```powershell
# Ouvrir PowerShell en tant qu'utilisateur normal
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Vérifier la configuration
Get-ExecutionPolicy -List
```

#### Méthode 2 : Exécution ponctuelle
```powershell
# Contourner la politique pour un script spécifique
powershell -ExecutionPolicy Bypass -File .\scripts\deploy.ps1
```

#### Méthode 3 : PowerShell en tant qu'Administrateur (Système)
```powershell
# Ouvrir PowerShell en tant qu'Administrateur
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned

# Cette méthode affecte tout le système
```

### Vérification de la configuration
```powershell
# Voir toutes les politiques d'exécution
Get-ExecutionPolicy -List

# Résultat attendu :
#     Scope ExecutionPolicy
#     ----- ---------------
# MachinePolicy       Undefined
#    UserPolicy       Undefined
#       Process       Undefined
#   CurrentUser    RemoteSigned  ← Doit être RemoteSigned ou Unrestricted
#  LocalMachine       Undefined
```

### Niveaux de sécurité PowerShell

| Politique | Description | Sécurité | Recommandation |
|-----------|-------------|----------|----------------|
| `Restricted` | Aucun script (défaut) | Très haute | Trop restrictif |
| `RemoteSigned` | Scripts locaux OK, scripts distants signés | Haute | **Recommandé** |
| `Unrestricted` | Tous scripts autorisés | Faible | Usage avancé uniquement |
| `Bypass` | Aucune restriction | Aucune | Tests uniquement |

### Résolution des erreurs courantes

#### Erreur : "execution of scripts is disabled"
```powershell
# Erreur complète :
# .\deploy.ps1 : File cannot be loaded because running scripts is disabled on this system.

# Solution :
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

#### Erreur : "UnauthorizedAccess"
```powershell
# Si vous voyez cette erreur, utilisez la méthode Bypass temporaire :
powershell -ExecutionPolicy Bypass -File .\scripts\deploy.ps1
```

#### Vérification que les scripts fonctionnent
```powershell
# Test rapide
.\scripts\validate.ps1 -Action help

# Doit afficher l'aide sans erreur
```
