#!/bin/bash
# Source development/install-prow.sh
# Changes:
#  - Removed secret creation
#  - Removed default ingress `ing` after installation
#  - Added TLS configuration
#  - Added Branch Protector deployment

set -o errexit

readonly PROW_DIR="$( dirname "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" )"
readonly KUBECONFIG=${KUBECONFIG:-"${HOME}/.kube/config"}
readonly CLUSTER_DIR="$( cd "${PROW_DIR}/cluster" && pwd )"

# requried by External Secrets Syncer to access Secret Manager
if [ -z "$GOOGLE_APPLICATION_CREDENTIALS" ]; then
      echo "\$GOOGLE_APPLICATION_CREDENTIALS is empty"
      exit 1
fi

# We are using GKE so we need initialize our user as a cluster-admin
kubectl create clusterrolebinding cluster-admin-binding \
  --clusterrole cluster-admin --user "$(gcloud config get-value account)"

# Deploy NGINX Ingress Controller
# Source https://kubernetes.github.io/ingress-nginx/deploy/
# Apply mandatory file for all deployments except minikube.
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.30.0/deploy/static/mandatory.yaml
# Apply GKE provider specific settings.
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.30.0/deploy/static/provider/cloud-generic.yaml

# Create secrets
# namespace
kubectl create namespace external-secrets
# Service account
kubectl create secret generic sa-secret-manager-prow --namespace "external-secrets" --from-file=service-account.json="$GOOGLE_APPLICATION_CREDENTIALS"
# install helm chart
helm repo add external-secrets https://external-secrets.github.io/kubernetes-external-secrets/
helm install 8.2.1 external-secrets/kubernetes-external-secrets
helm install -f "${CLUSTER_DIR}/resources/external-secrets/values_prow.yaml" -n external-secrets kubernetes-external-secrets external-secrets/kubernetes-external-secrets
# kubectl apply
kubectl apply -f "${CLUSTER_DIR}/resources/external-secrets/external_secrets_prow.yaml"
# one empty secret that is not synced
kubectl create secret generic prometheus-prow-tls-assets --namespace "prow-monitoring"

# Create ConfigMap with Kyma images for deck
kubectl create configmap branding --from-file "${PROW_DIR}/branding"

# Deploy GCE SSD StorageClass
kubectl apply -f "${CLUSTER_DIR}/01-gce-ssd-retain_storageclass.yaml"

# Deploy ghProxy
kubectl apply -f "${CLUSTER_DIR}/02-ghproxy_pvc.yaml"
kubectl apply -f "${CLUSTER_DIR}/03-ghproxy.yaml"
kubectl apply -f "${CLUSTER_DIR}/04-ghproxy.yaml"

# Deploy config maps
kubectl apply -f "${CLUSTER_DIR}/05-cluster_config-maps.yaml"

# Deploy prow CRD
kubectl apply -f "${CLUSTER_DIR}/06-prowjob_customresourcedefinition.yaml"

# Deploy hook
kubectl apply -f "${CLUSTER_DIR}/07-hook_rbac.yaml"
kubectl apply -f "${CLUSTER_DIR}/08-hook_deployment.yaml"
kubectl apply -f "${CLUSTER_DIR}/09-hook_service.yaml"

# Deploy plank
kubectl apply -f "${CLUSTER_DIR}/10-plank_rbac.yaml"
kubectl apply -f "${CLUSTER_DIR}/11-plank_deployment.yaml"

# Deploy sinker
kubectl apply -f "${CLUSTER_DIR}/12-sinker_rbac.yaml"
kubectl apply -f "${CLUSTER_DIR}/13-sinker_deployment.yaml"

# Deploy deck
kubectl apply -f "${CLUSTER_DIR}/14-deck_rbac.yaml"
kubectl apply -f "${CLUSTER_DIR}/15-deck_deployment.yaml"
kubectl apply -f "${CLUSTER_DIR}/16-deck_service.yaml"

# Deploy horologium
kubectl apply -f "${CLUSTER_DIR}/17-horologium_rbac.yaml"
kubectl apply -f "${CLUSTER_DIR}/18-horologium_deployment.yaml"

# Deploy ingress
# TODO: check if this can be replaced by tls-ing ingress and used before cert-manager deployment
kubectl apply -f "${CLUSTER_DIR}/19-ing_ingress.yaml"

# Deploy cert-manager
kubectl apply -f "${CLUSTER_DIR}/20-cert-manager.yaml"
kubectl apply -f "${CLUSTER_DIR}/21-cluster-issuer.yaml"

# Deploy secure ingress
kubectl apply -f "${CLUSTER_DIR}/22-tls-ing_ingress.yaml"

# Deploy branch protector
kubectl apply -f "${CLUSTER_DIR}/23-branchprotector_cronjob.yaml"

# Deploy tiller
kubectl apply -f "${CLUSTER_DIR}/24-tiller.yaml"

# Deploy pushgateway
kubectl apply -f "${CLUSTER_DIR}/25-pushgateway_deployment.yaml"
kubectl apply -f "${CLUSTER_DIR}/26-pushgateway_service.yaml"

# Deploy PodDisruptionBudgets
kubectl apply -f "${CLUSTER_DIR}/27-kube-system_poddisruptionbudgets.yaml"

# Deploy gcsweb
kubectl apply -f "${CLUSTER_DIR}/28-gcsweb_deployment.yaml"
kubectl apply -f "${CLUSTER_DIR}/29-gcsweb_service.yaml"

kubectl apply -f "${CLUSTER_DIR}/30-crier_deployment.yaml"
kubectl apply -f "${CLUSTER_DIR}/31-crier_rbac.yaml"

# Remove Insecure ingress 
kubectl delete ingress ing
