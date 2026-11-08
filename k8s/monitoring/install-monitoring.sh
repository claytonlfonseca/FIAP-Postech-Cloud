#!/bin/bash

# Script de instalação do stack de monitoramento
# Uso: ./install-monitoring.sh <cluster-context>

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

for manifest in \
    "$PROJECT_ROOT/k8s/namespaces/monitoring-namespace.yaml" \
    "$PROJECT_ROOT/k8s/monitoring/prometheus-service-monitor.yaml" \
    "$PROJECT_ROOT/k8s/monitoring/grafana-dashboard-togglemaster.yaml" \
    "$PROJECT_ROOT/k8s/argocd/argocd-monitoring-apps.yaml"; do
    if [ ! -f "$manifest" ]; then
        printf 'Erro: manifest obrigatório não encontrado: %s\n' "$manifest" >&2
        exit 1
    fi
done

for command in kubectl helm jq; do
    if ! command -v "$command" >/dev/null 2>&1; then
        printf 'Erro: instale %s no terminal que executa este script.\n' "$command" >&2
        exit 1
    fi
done

CLUSTER_CONTEXT="${1:-}"
NAMESPACE="monitoring"
ARGOCD_NAMESPACE="argocd"

if [ -z "$CLUSTER_CONTEXT" ]; then
    echo "Usando contexto atual do kubectl..."
    CLUSTER_CONTEXT=$(kubectl config current-context)
else
    kubectl config use-context "$CLUSTER_CONTEXT"
fi

echo "🚀 Iniciando instalação do stack de monitoramento"
echo "📍 Cluster: $CLUSTER_CONTEXT"
echo "📦 Namespace: $NAMESPACE"

kubectl get crd applications.argoproj.io >/dev/null
kubectl get namespace "$ARGOCD_NAMESPACE" >/dev/null

APPLICATIONS_JSON=$(kubectl create --dry-run=client \
    -f "$PROJECT_ROOT/k8s/argocd/argocd-monitoring-apps.yaml" -o json)

# 1. Criar namespace
echo ""
echo "1️⃣  Criando namespace 'monitoring'..."
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# 2. Adicionar Helm repositories
echo ""
echo "2️⃣  Adicionando Helm repositories..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# 3. Registrar charts antes dos recursos que dependem do Operator
echo ""
echo "3️⃣  Registrando charts em ArgoCD..."
printf '%s\n' "$APPLICATIONS_JSON" \
    | jq '{apiVersion: "v1", kind: "List", items: [.items[] | select(.spec.source.chart != null)]}' \
    | kubectl apply -f -

echo "Aguardando criação e estabelecimento da CRD ServiceMonitor (até 10 minutos)..."
if ! kubectl wait --for=create crd/servicemonitors.monitoring.coreos.com --timeout=300s \
    || ! kubectl wait --for=condition=Established \
        crd/servicemonitors.monitoring.coreos.com --timeout=300s; then
    echo "Erro: o Prometheus Operator não disponibilizou a CRD ServiceMonitor." >&2
    echo "Confira o ArgoCD, a sincronização do chart e os eventos do cluster:" >&2
    echo "  kubectl describe application prometheus-helm -n $ARGOCD_NAMESPACE" >&2
    echo "  kubectl get pods -n $NAMESPACE" >&2
    echo "  kubectl get events -n $NAMESPACE --sort-by=.lastTimestamp" >&2
    exit 1
fi

# 4. Aplicar recursos locais somente após estabelecer a CRD
echo ""
echo "4️⃣  Aplicando manifests do monitoring stack..."
kubectl apply -f "$PROJECT_ROOT/k8s/namespaces/monitoring-namespace.yaml"
for namespace in auth flag targeting evaluation analytics; do
    kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -
done
kubectl apply -f "$PROJECT_ROOT/k8s/monitoring/prometheus-service-monitor.yaml"
kubectl apply -f "$PROJECT_ROOT/k8s/monitoring/grafana-dashboard-togglemaster.yaml"

# 5. Registrar a fonte Git depois dos recursos dependentes
echo ""
echo "5️⃣  Registrando manifests Git em ArgoCD..."
printf '%s\n' "$APPLICATIONS_JSON" \
    | jq '{apiVersion: "v1", kind: "List", items: [.items[] | select(.spec.source.chart == null)]}' \
    | kubectl apply -f -

echo ""
echo "✅ Instalação iniciada!"
echo ""
echo "📊 Próximos passos:"
echo ""
echo "1. Aguardar sincronização automática do ArgoCD:"
echo "   kubectl get applications -n argocd -w"
echo ""
echo "2. Verificar status do Prometheus:"
echo "   kubectl get pod -n $NAMESPACE | grep prometheus"
echo ""
echo "3. Verificar status do Loki:"
echo "   kubectl get pod -n $NAMESPACE | grep loki"
echo ""
echo "4. Acessar Grafana:"
echo "   kubectl port-forward -n $NAMESPACE svc/prometheus-grafana 3000:80"
echo "   http://localhost:3000"
echo "   Credenciais: admin / admin123"
echo ""
echo "5. Verificar dashboard ToggleMaster:"
echo "   - Ir para Home > Dashboards"
echo "   - Procurar por 'ToggleMaster - Cluster Health & Observability'"
echo ""

# Mostrar status
echo "⏳ Status do deployment:"
kubectl get pod -n "$NAMESPACE"
