#!/bin/bash

# Script de verificação da saúde do stack de monitoramento
# Uso: ./check-monitoring-health.sh

set -e

NAMESPACE="monitoring"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 Verificação de Saúde do Stack de Monitoramento${NC}"
echo "=================================================="
echo ""

# 1. Verificar namespace
echo -e "${BLUE}1. Namespace 'monitoring'${NC}"
if kubectl get namespace $NAMESPACE &> /dev/null; then
    echo -e "${GREEN}✅ Namespace existe${NC}"
else
    echo -e "${RED}❌ Namespace não encontrado${NC}"
    exit 1
fi
echo ""

# 2. Verificar Prometheus
echo -e "${BLUE}2. Prometheus${NC}"
echo "   Pods:"
kubectl get pod -n $NAMESPACE -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null || echo "   (Nenhum pod encontrado)"
echo ""
echo "   PVC (Persistent Volume Claim):"
kubectl get pvc -n $NAMESPACE -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null || echo "   (Nenhum PVC encontrado)"
echo ""
echo "   Service:"
PROM_SVC=$(kubectl get svc -n $NAMESPACE -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ ! -z "$PROM_SVC" ]; then
    echo -e "${GREEN}✅ Service: $PROM_SVC${NC}"
    PROM_IP=$(kubectl get svc -n $NAMESPACE $PROM_SVC -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
    echo "   IP: $PROM_IP:9090"
else
    echo -e "${YELLOW}⚠️  Service não encontrado${NC}"
fi
echo ""

# 3. Verificar Grafana
echo -e "${BLUE}3. Grafana${NC}"
echo "   Pods:"
kubectl get pod -n $NAMESPACE -l app.kubernetes.io/name=grafana --no-headers 2>/dev/null || echo "   (Nenhum pod encontrado)"
echo ""
echo "   PVC:"
kubectl get pvc -n $NAMESPACE -l app.kubernetes.io/name=grafana --no-headers 2>/dev/null || echo "   (Nenhum PVC encontrado)"
echo ""
echo "   Service:"
GRAFANA_SVC=$(kubectl get svc -n $NAMESPACE -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ ! -z "$GRAFANA_SVC" ]; then
    echo -e "${GREEN}✅ Service: $GRAFANA_SVC${NC}"
    GRAFANA_PORT=$(kubectl get svc -n $NAMESPACE $GRAFANA_SVC -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)
    echo "   Acesso local:"
    echo "   kubectl port-forward -n $NAMESPACE svc/$GRAFANA_SVC 3000:$GRAFANA_PORT"
    echo "   http://localhost:3000"
else
    echo -e "${YELLOW}⚠️  Service não encontrado${NC}"
fi
echo ""

# 4. Verificar Loki
echo -e "${BLUE}4. Loki${NC}"
echo "   Pods:"
kubectl get pod -n $NAMESPACE -l app=loki --no-headers 2>/dev/null || echo "   (Nenhum pod encontrado)"
echo ""
echo "   PVC:"
kubectl get pvc -n $NAMESPACE -l app=loki --no-headers 2>/dev/null || echo "   (Nenhum PVC encontrado)"
echo ""
echo "   Service:"
LOKI_SVC=$(kubectl get svc -n $NAMESPACE -l app=loki -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ ! -z "$LOKI_SVC" ]; then
    echo -e "${GREEN}✅ Service: $LOKI_SVC${NC}"
    echo "   URL: http://$LOKI_SVC:3100"
else
    echo -e "${YELLOW}⚠️  Service não encontrado${NC}"
fi
echo ""

# 5. Verificar Promtail
echo -e "${BLUE}5. Promtail (Log Collection)${NC}"
echo "   Pods:"
kubectl get pod -n $NAMESPACE -l app=promtail --no-headers 2>/dev/null || echo "   (Nenhum pod encontrado)"
echo ""

# 6. Verificar ServiceMonitors
echo -e "${BLUE}6. ServiceMonitors (Scrape Config)${NC}"
echo "   ServiceMonitors registrados:"
kubectl get servicemonitor -A --no-headers 2>/dev/null | while read line; do
    echo "   $line"
done || echo "   (Nenhum ServiceMonitor encontrado)"
echo ""

# 7. Verificar Volumes
echo -e "${BLUE}7. Storage - PersistentVolumeClaims${NC}"
echo "   PVCs no namespace monitoring:"
kubectl get pvc -n $NAMESPACE --no-headers 2>/dev/null | while read pvc_info; do
    pvc_name=$(echo $pvc_info | awk '{print $1}')
    pvc_status=$(echo $pvc_info | awk '{print $2}')
    pvc_size=$(echo $pvc_info | awk '{print $4}')
    
    if [ "$pvc_status" = "Bound" ]; then
        echo -e "   ${GREEN}✅${NC} $pvc_name ($pvc_size)"
    else
        echo -e "   ${RED}❌${NC} $pvc_name ($pvc_status)"
    fi
done || echo "   (Nenhum PVC encontrado)"
echo ""

# 8. Verificar ArgoCD Applications
echo -e "${BLUE}8. ArgoCD Applications${NC}"
ARGOCD_NS="argocd"
if kubectl get namespace $ARGOCD_NS &> /dev/null; then
    echo "   Applications:"
    kubectl get applications -n $ARGOCD_NS -l app.kubernetes.io/part-of=monitoring --no-headers 2>/dev/null | while read app_info; do
        app_name=$(echo $app_info | awk '{print $1}')
        app_status=$(echo $app_info | awk '{print $3}')
        
        if [ "$app_status" = "Synced" ]; then
            echo -e "   ${GREEN}✅${NC} $app_name ($app_status)"
        else
            echo -e "   ${YELLOW}⚠️${NC} $app_name ($app_status)"
        fi
    done || echo "   (Nenhuma Application encontrada)"
else
    echo -e "   ${YELLOW}⚠️  ArgoCD namespace não encontrado${NC}"
fi
echo ""

# 9. Verificar recursos dos pods
echo -e "${BLUE}9. Recursos dos Pods${NC}"
echo "   Pod Memory & CPU:"
kubectl top pod -n $NAMESPACE --no-headers 2>/dev/null | head -10 || echo "   (Metrics server não disponível)"
echo ""

# 10. Mostrar eventos recentes
echo -e "${BLUE}10. Eventos Recentes${NC}"
echo "   (últimos 5 eventos)"
kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | tail -6
echo ""

# 11. Summary
echo -e "${BLUE}📊 Resumo de Verificação${NC}"
echo "=================================================="
POD_COUNT=$(kubectl get pod -n $NAMESPACE --no-headers 2>/dev/null | wc -l)
READY_COUNT=$(kubectl get pod -n $NAMESPACE --no-headers 2>/dev/null | grep "1/1\|2/2\|3/3" | wc -l)

echo "Total de Pods: $POD_COUNT"
echo "Pods Prontos: $READY_COUNT"

if [ $POD_COUNT -gt 0 ] && [ $POD_COUNT -eq $READY_COUNT ]; then
    echo -e "${GREEN}✅ Stack de monitoramento está saudável!${NC}"
else
    echo -e "${YELLOW}⚠️  Alguns componentes ainda estão iniciando${NC}"
    echo "   Execute novamente em alguns momentos"
fi

echo ""
echo "🔗 Links Úteis:"
echo "   Prometheus: kubectl port-forward -n $NAMESPACE svc/prometheus-operated 9090:9090"
echo "   Grafana:    kubectl port-forward -n $NAMESPACE svc/prometheus-grafana 3000:80"
echo "   Loki:       kubectl port-forward -n $NAMESPACE svc/loki 3100:3100"
echo ""
