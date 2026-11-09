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

for command in kubectl jq; do
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

echo "Iniciando instalação do stack de monitoramento"
echo "Cluster: $CLUSTER_CONTEXT"
echo "Namespace: $NAMESPACE"

kubectl get crd applications.argoproj.io >/dev/null
kubectl get namespace "$ARGOCD_NAMESPACE" >/dev/null

APPLICATIONS_JSON=$(kubectl create --dry-run=client \
    -f "$PROJECT_ROOT/k8s/argocd/argocd-monitoring-apps.yaml" -o json \
    | jq -s -e '
        if length == 3 and all(.[]; .kind == "Application" and .spec.source.repoURL != null)
        then {apiVersion: "v1", kind: "List", items: .}
        else error("Esperadas exatamente 3 Applications válidas no manifesto de monitoramento")
        end
    ')

CHART_APPLICATIONS=$(jq -e '
    {apiVersion: "v1", kind: "List", items: [.items[] | select(.spec.source.chart? != null)]}
    | select(.items | length == 2)
' <<< "$APPLICATIONS_JSON") || {
    echo "Erro: esperado encontrar 2 Applications de charts Helm." >&2
    exit 1
}

MANIFEST_APPLICATIONS=$(jq -e '
    {apiVersion: "v1", kind: "List", items: [.items[] | select(.spec.source.chart? == null)]}
    | select(.items | length == 1)
' <<< "$APPLICATIONS_JSON") || {
    echo "Erro: esperado encontrar 1 Application de manifests Git." >&2
    exit 1
}

# 1. Criar namespace
echo ""
echo "1. Criando namespace 'monitoring'..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# 2. Registrar charts antes dos recursos que dependem do Operator
echo ""
echo "2. Registrando charts em ArgoCD..."
kubectl apply -f - <<< "$CHART_APPLICATIONS"

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

# 3. Aplicar recursos locais somente após estabelecer a CRD
echo ""
echo "3. Aplicando manifests do monitoring stack..."
kubectl apply -f "$PROJECT_ROOT/k8s/namespaces/monitoring-namespace.yaml"
for namespace in auth flag targeting evaluation analytics; do
    kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -
done
kubectl apply -f "$PROJECT_ROOT/k8s/monitoring/prometheus-service-monitor.yaml"
kubectl apply -f "$PROJECT_ROOT/k8s/monitoring/grafana-dashboard-togglemaster.yaml"

# 4. Registrar a fonte Git depois dos recursos dependentes
echo ""
echo "4. Registrando manifests Git em ArgoCD..."
kubectl apply -f - <<< "$MANIFEST_APPLICATIONS"

echo ""
echo "Instalação iniciada."
echo ""
echo "Próximos passos:"
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
