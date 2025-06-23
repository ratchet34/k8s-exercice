# Guide de Dépannage - Application Kubernetes

## 🔧 Problèmes courants et solutions

### 1. Pods ne démarrent pas

#### Symptôme : Pod en état `Pending`
```bash
# Diagnostic
kubectl describe pod <pod-name> -n production
kubectl get events -n production --sort-by='.lastTimestamp'
```

**Causes possibles :**

##### A. Ressources insuffisantes
```bash
# Vérifier les ressources du cluster
kubectl top nodes
kubectl describe nodes

# Solution : Ajuster les requests/limits
kubectl patch deployment <deployment-name> -n production -p '{"spec":{"template":{"spec":{"containers":[{"name":"<container-name>","resources":{"requests":{"cpu":"100m","memory":"128Mi"}}}]}}}}'
```

##### B. PVC non disponible
```bash
# Vérifier les PVC
kubectl get pvc -n production
kubectl describe pvc <pvc-name> -n production

# Solution : Vérifier les PV et StorageClass
kubectl get pv
kubectl get storageclass
```

##### C. Node selector ou affinity
```bash
# Vérifier les contraintes de placement
kubectl get pods <pod-name> -n production -o yaml | grep -A 10 affinity

# Solution : Modifier ou supprimer les contraintes
kubectl patch deployment <deployment-name> -n production --type='merge' -p='{"spec":{"template":{"spec":{"affinity":null}}}}'
```

#### Symptôme : Pod en état `CrashLoopBackOff`
```bash
# Diagnostic
kubectl logs <pod-name> -n production
kubectl logs <pod-name> -n production --previous
```

**Solutions courantes :**

##### A. Problème de configuration
```bash
# Vérifier les ConfigMaps et Secrets
kubectl get configmaps -n production
kubectl get secrets -n production
kubectl describe configmap <configmap-name> -n production
```

##### B. Problème de santé
```bash
# Désactiver temporairement les health checks
kubectl patch deployment <deployment-name> -n production --type='json' -p='[{"op": "remove", "path": "/spec/template/spec/containers/0/livenessProbe"}]'
```

##### C. Problème de permissions
```bash
# Vérifier le SecurityContext
kubectl get pod <pod-name> -n production -o yaml | grep -A 5 securityContext

# Solution : Ajuster les permissions
kubectl patch deployment <deployment-name> -n production -p '{"spec":{"template":{"spec":{"securityContext":{"runAsUser":1000,"fsGroup":1000}}}}}'
```

### 2. Services inaccessibles

#### Symptôme : Service sans endpoints
```bash
# Diagnostic
kubectl get endpoints -n production
kubectl describe service <service-name> -n production
```

**Solutions :**

##### A. Sélecteur de pods incorrect
```bash
# Vérifier les labels des pods
kubectl get pods -n production --show-labels
kubectl get service <service-name> -n production -o yaml | grep selector

# Solution : Corriger le sélecteur
kubectl patch service <service-name> -n production -p '{"spec":{"selector":{"app":"correct-app-name"}}}'
```

##### B. Pods non prêts
```bash
# Vérifier l'état des pods
kubectl get pods -n production -l app=<app-name>
kubectl describe pod <pod-name> -n production

# Solution : Corriger les readiness probes
kubectl patch deployment <deployment-name> -n production --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/initialDelaySeconds", "value": 10}]'
```

##### C. Port incorrect
```bash
# Vérifier la configuration des ports
kubectl get service <service-name> -n production -o yaml

# Solution : Corriger le port
kubectl patch service <service-name> -n production -p '{"spec":{"ports":[{"port":80,"targetPort":3000}]}}'
```

### 3. Problèmes de base de données

#### Symptôme : PostgreSQL ne démarre pas
```bash
# Diagnostic
kubectl logs deployment/postgres-deployment -n production
kubectl describe pod -l app=postgres -n production
```

**Solutions courantes :**

##### A. Problème de permissions sur le volume
```bash
# Vérifier les permissions
kubectl exec -it deployment/postgres-deployment -n production -- ls -la /var/lib/postgresql/data

# Solution : Corriger les permissions
kubectl patch deployment postgres-deployment -n production -p '{"spec":{"template":{"spec":{"securityContext":{"fsGroup":999}}}}}'
```

##### B. Volume corrompu
```bash
# Sauvegarder les données si possible
kubectl exec -it deployment/postgres-deployment -n production -- pg_dumpall -U postgres

# Recréer le volume
kubectl delete pvc postgres-pvc -n production
kubectl delete pv postgres-pv
kubectl apply -f manifests/01-storage/
```

##### C. Configuration incorrecte
```bash
# Vérifier les secrets
kubectl get secret postgres-secret -n production -o yaml
echo "<base64-value>" | base64 -d  # Décoder pour vérifier

# Recréer le secret si nécessaire
kubectl delete secret postgres-secret -n production
kubectl apply -f manifests/02-config/secrets.yaml
```

#### Symptôme : Connexion PostgreSQL refusée
```bash
# Test de connectivité
kubectl exec -it deployment/postgres-deployment -n production -- pg_isready -U myuser
kubectl exec -it deployment/backend-deployment -n production -- nc -zv postgres-service 5432
```

**Solutions :**
```bash
# Vérifier le service PostgreSQL
kubectl get service postgres-service -n production
kubectl get endpoints postgres-service -n production

# Vérifier les NetworkPolicies
kubectl get networkpolicies -n production
kubectl describe networkpolicy postgres-network-policy -n production
```

### 4. Problèmes d'Ingress

#### Symptôme : Ingress sans IP externe
```bash
# Diagnostic
kubectl get ingress -n production
kubectl describe ingress app-ingress -n production
```

**Solutions :**

##### A. Ingress Controller non installé
```bash
# Vérifier l'ingress controller
kubectl get pods -n ingress-nginx
kubectl get ingressclass

# Installation nginx-ingress (Minikube)
minikube addons enable ingress

# Installation nginx-ingress (cluster)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/cloud/deploy.yaml
```

##### B. Configuration DNS
```bash
# Obtenir l'IP de l'ingress
INGRESS_IP=$(kubectl get ingress app-ingress -n production -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Ajouter à /etc/hosts
echo "$INGRESS_IP myapp.local" | sudo tee -a /etc/hosts

# Test
curl -k https://myapp.local/
```

##### C. Certificats TLS
```bash
# Vérifier le secret TLS
kubectl get secret tls-secret -n production
kubectl describe secret tls-secret -n production

# Test sans TLS
curl -H "Host: myapp.local" http://$INGRESS_IP/
```

### 5. Problèmes d'Autoscaling (HPA)

#### Symptôme : HPA ne fonctionne pas
```bash
# Diagnostic
kubectl describe hpa <hpa-name> -n production
kubectl get hpa -n production
```

**Solutions courantes :**

##### A. Metrics Server manquant
```bash
# Vérifier metrics-server
kubectl get pods -n kube-system | grep metrics-server

# Installation (Minikube)
minikube addons enable metrics-server

# Installation manuelle
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

##### B. Pas de ressources requests définies
```bash
# Vérifier les requests
kubectl get deployment <deployment-name> -n production -o yaml | grep -A 10 resources

# Ajouter des requests
kubectl patch deployment <deployment-name> -n production -p '{"spec":{"template":{"spec":{"containers":[{"name":"<container-name>","resources":{"requests":{"cpu":"100m","memory":"128Mi"}}}]}}}}'
```

##### C. Métriques non disponibles
```bash
# Tester les métriques
kubectl top pods -n production
kubectl get --raw /apis/metrics.k8s.io/v1beta1/namespaces/production/pods

# Redémarrer metrics-server si nécessaire
kubectl rollout restart deployment/metrics-server -n kube-system
```

### 6. Problèmes de stockage

#### Symptôme : PVC en état `Pending`
```bash
# Diagnostic
kubectl describe pvc <pvc-name> -n production
kubectl get storageclass
```

**Solutions :**

##### A. StorageClass manquante
```bash
# Créer une StorageClass pour minikube
kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: standard
provisioner: k8s.io/minikube-hostpath
parameters:
  type: pd-standard
EOF
```

##### B. PV incompatible
```bash
# Vérifier les PV disponibles
kubectl get pv
kubectl describe pv <pv-name>

# Matcher les spécifications PV/PVC
kubectl patch pvc <pvc-name> -n production -p '{"spec":{"storageClassName":"standard"}}'
```

### 7. Problèmes de réseau

#### Symptôme : Pods ne peuvent pas communiquer
```bash
# Test de connectivité
kubectl exec -it <pod1> -n production -- nc -zv <service-name> <port>
kubectl exec -it <pod1> -n production -- nslookup <service-name>
```

**Solutions :**

##### A. NetworkPolicies trop restrictives
```bash
# Vérifier les politiques réseau
kubectl get networkpolicies -n production
kubectl describe networkpolicy <policy-name> -n production

# Désactiver temporairement
kubectl delete networkpolicies --all -n production
```

##### B. DNS cluster
```bash
# Vérifier le DNS
kubectl get pods -n kube-system | grep dns
kubectl exec -it <pod-name> -n production -- nslookup kubernetes.default

# Redémarrer CoreDNS si nécessaire
kubectl rollout restart deployment/coredns -n kube-system
```

##### C. Service Mesh (si applicable)
```bash
# Vérifier Istio/Linkerd
kubectl get pods -n istio-system
kubectl get pods -n linkerd
```

### 8. Problèmes de jobs

#### Symptôme : Job ne se termine pas
```bash
# Diagnostic
kubectl describe job <job-name> -n production
kubectl logs job/<job-name> -n production
```

**Solutions :**

##### A. Timeout insuffisant
```bash
# Augmenter le timeout
kubectl patch job <job-name> -n production -p '{"spec":{"activeDeadlineSeconds":1800}}'
```

##### B. Job bloqué
```bash
# Supprimer et recréer
kubectl delete job <job-name> -n production
kubectl apply -f manifests/08-jobs/migration-job.yaml
```

##### C. Dépendances non disponibles
```bash
# Vérifier que PostgreSQL est prêt
kubectl wait --for=condition=ready pod -l app=postgres -n production --timeout=300s
```

## 🚨 Commandes d'urgence

### Redémarrage complet de l'application
```bash
# Redémarrer tous les deployments
kubectl rollout restart deployment -n production

# Ou individuellement
kubectl rollout restart deployment/postgres-deployment -n production
kubectl rollout restart deployment/redis-deployment -n production
kubectl rollout restart deployment/backend-deployment -n production
kubectl rollout restart deployment/frontend-deployment -n production
```

### Nettoyage des ressources en erreur
```bash
# Supprimer tous les pods en erreur
kubectl delete pods --field-selector=status.phase=Failed -n production

# Supprimer les jobs terminés
kubectl delete jobs --field-selector=status.successful=1 -n production
```

### Récupération d'urgence
```bash
# Sauvegarder la configuration actuelle
kubectl get all -n production -o yaml > emergency-backup.yaml

# Supprimer les NetworkPolicies (restaurer connectivité)
kubectl delete networkpolicies --all -n production

# Scale down temporaire pour libérer des ressources
kubectl scale deployment --replicas=1 --all -n production
```

## 📊 Monitoring et diagnostics avancés

### Surveillance en temps réel
```bash
# Surveiller les événements
kubectl get events -n production --sort-by='.lastTimestamp' -w

# Surveiller les pods
kubectl get pods -n production -w

# Surveiller les métriques
watch kubectl top pods -n production
```

### Analyse des logs
```bash
# Logs agrégés de tous les pods backend
kubectl logs -l app=backend -n production --tail=100

# Logs avec timestamp
kubectl logs <pod-name> -n production --timestamps=true

# Logs précédents (avant redémarrage)
kubectl logs <pod-name> -n production --previous
```

### Debug interactif
```bash
# Shell dans un pod
kubectl exec -it <pod-name> -n production -- /bin/sh

# Debug avec un pod temporaire
kubectl run debug --image=busybox --rm -it --restart=Never -n production -- /bin/sh

# Port-forward pour accès direct
kubectl port-forward pod/<pod-name> 8080:3000 -n production
```

### Tests de performance
```bash
# Test de charge simple
kubectl run load-test --image=busybox --rm -it --restart=Never -n production -- /bin/sh -c 'while true; do wget -q -O- http://frontend-service; sleep 1; done'

# Test de connectivité réseau
kubectl run network-test --image=nicolaka/netshoot --rm -it --restart=Never -n production
```

## Erreur WSL : execvpe(/bin/bash) failed

### 🔍 Symptôme
```
ERROR: CreateProcessCommon:640: execvpe(/bin/bash) failed: No such file or directory
```

### 📋 Diagnostic
Cette erreur indique que WSL ne trouve pas l'interpréteur bash. Causes possibles :
- Distribution WSL non installée ou non initialisée
- WSL non démarré
- Installation WSL corrompue
- Fonctionnalités Windows manquantes

### 🛠️ Solutions

#### 1. Vérifier l'état WSL
```powershell
# Lister les distributions installées
wsl --list --verbose

# Vérifier le statut WSL
wsl --status
```

#### 2. Installer/Réinstaller une distribution
```powershell
# Installer Ubuntu (recommandé)
wsl --install -d Ubuntu

# Ou réinstaller si corrompue
wsl --unregister Ubuntu
wsl --install -d Ubuntu
```

#### 3. Démarrer WSL
```powershell
# Démarrer la distribution par défaut
wsl

# Ou spécifier la distribution
wsl --distribution Ubuntu
```

#### 4. Réparer WSL
```powershell
# Redémarrer WSL
wsl --shutdown
wsl

# Mettre à jour WSL
wsl --update

# Définir WSL 2 par défaut
wsl --set-default-version 2
```

#### 5. Réinstallation complète (si nécessaire)
```powershell
# Activer les fonctionnalités Windows
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform

# Redémarrer Windows puis :
wsl --install
wsl --set-default-version 2
wsl --install -d Ubuntu
```

### ⚡ Solution alternative
**Utilisez PowerShell natif** pour éviter WSL :
```powershell
# Au lieu de : wsl ./deploy.sh
.\deploy.ps1

# Au lieu de : wsl ./validate.sh
.\validate.ps1

# Au lieu de : wsl ./cleanup.sh
.\cleanup.ps1
```

### 🧪 Script de diagnostic
```powershell
Write-Host "=== Diagnostic WSL ===" -ForegroundColor Cyan

# État WSL
try {
    wsl --list --verbose
    Write-Host "✓ WSL installé" -ForegroundColor Green
} catch {
    Write-Host "✗ WSL non installé" -ForegroundColor Red
}

# Test bash
try {
    $bashPath = wsl which bash 2>$null
    if ($bashPath) {
        Write-Host "✓ bash disponible : $bashPath" -ForegroundColor Green
    } else {
        Write-Host "✗ bash non trouvé" -ForegroundColor Red
    }
} catch {
    Write-Host "✗ Impossible de tester bash" -ForegroundColor Red
}

# Fonctionnalités Windows
$wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
$vmFeature = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform

Write-Host "WSL Feature: $($wslFeature.State)" -ForegroundColor $(if($wslFeature.State -eq 'Enabled'){'Green'}else{'Red'})
Write-Host "VM Platform: $($vmFeature.State)" -ForegroundColor $(if($vmFeature.State -eq 'Enabled'){'Green'}else{'Red'})
```

Ce guide couvre les problèmes les plus courants rencontrés lors du déploiement et de l'exploitation d'applications Kubernetes. Pour des problèmes spécifiques non couverts ici, consultez la documentation officielle Kubernetes et les logs détaillés de vos composants.
