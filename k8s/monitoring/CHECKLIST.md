# Checklist de Implementação - Monitoramento Opensource

Use este checklist para garantir que todo o stack de monitoramento foi implementado corretamente.

## ✅ Pré-requisitos

Sequência e instruções de instalação: [guia central Ubuntu/WSL](../../../README.md).

- [ ] Cluster Kubernetes rodando (EKS, GKE, AKS ou local)
- [ ] kubectl instalado no Ubuntu/WSL, no PATH e compatível com a versão do cluster
- [ ] Contexto e identidade conferidos; `kubectl get nodes` funciona
- [ ] Helm 3.x instalado
- [ ] ArgoCD instalado no cluster
- [ ] Git com acesso ao repositório FIAP-Postech-Cloud
- [ ] Fontes Git, conta AWS, imagens e versões de charts revisadas para o ambiente
- [ ] Capacidade suficiente nos nodes e StorageClass padrão funcional
- [ ] EBS CSI Driver e IAM configurados, quando usar EBS no EKS
- [ ] CRDs do Prometheus Operator estabelecidas antes de aplicar ServiceMonitors
- [ ] Script atualizado e todos os manifests presentes na estrutura do projeto

Se ocorrer `kubectl: command not found`, instale o binário **dentro do Ubuntu**
e confira `command -v kubectl`. Uma instalação apenas no Windows não basta.
O script pode rodar no WSL ou na AWS; o destino é o contexto do kubectl.

## ✅ Implantação do Stack

### Prometheus + Grafana (kube-prometheus-stack)

- [ ] Repository do Helm adicionado: `prometheus-community`
- [ ] ArgoCD Application `prometheus-helm` criada
- [ ] Prometheus pod rodando em namespace `monitoring`
- [ ] Grafana pod rodando em namespace `monitoring`
- [ ] PVC do Prometheus criado e Bound
- [ ] PVC do Grafana criado e Bound
- [ ] Service do Prometheus acessível
- [ ] Service do Grafana acessível na porta 3000

**Verificar**:
```bash
kubectl get pod -n monitoring -l app.kubernetes.io/name=prometheus
kubectl get pvc -n monitoring
kubectl get svc -n monitoring
```

### Loki Stack

- [ ] Repository do Helm adicionado: `grafana` (loki)
- [ ] ArgoCD Application `loki-helm` criada
- [ ] Loki pod rodando em namespace `monitoring`
- [ ] Promtail pods rodando (um por node)
- [ ] PVC do Loki criado e Bound
- [ ] Service do Loki acessível na porta 3100

**Verificar**:
```bash
kubectl get pod -n monitoring -l app=loki
kubectl get pod -n monitoring -l app=promtail
kubectl get pvc -n monitoring | grep loki
```

## ✅ Configuração e Datasources

### Grafana

- [ ] Grafana acessível via `kubectl port-forward`
- [ ] Login com credenciais padrão funciona
- [ ] Datasource Prometheus configurado
- [ ] Datasource Loki configurado
- [ ] Ambos os datasources com status "✅ green"

**Verificar no Grafana**:
1. Ir para Home > Connections > Data Sources
2. Verificar "Prometheus" com conexão verde
3. Verificar "Loki" com conexão verde

### Prometheus

- [ ] Prometheus acessível via `kubectl port-forward`
- [ ] Status > Targets mostra todos os targets como "UP"
- [ ] ServiceMonitors registrados aparecem como targets
- [ ] Métricas estão sendo coletadas

**Verificar em http://localhost:9090**:
1. Ir para Status > Targets
2. Verificar que nenhum está com status "DOWN"
3. Ir para Graph e testar query: `up`

## ✅ ServiceMonitors para Microsserviços

- [ ] `auth-service-monitor` criado no namespace `auth`
- [ ] `flag-service-monitor` criado no namespace `flag`
- [ ] `targeting-service-monitor` criado no namespace `targeting`
- [ ] `evaluation-service-monitor` criado no namespace `evaluation`
- [ ] `analytics-service-monitor` criado no namespace `analytics`

**Verificar**:
```bash
kubectl get servicemonitor -A
kubectl get servicemonitor -n auth
kubectl describe servicemonitor auth-service-monitor -n auth
```

## ✅ Instrumentação dos Microsserviços

Para cada microsserviço (auth, flag, targeting, evaluation, analytics):

- [ ] Dependência `spring-boot-starter-actuator` adicionada
- [ ] Dependência `micrometer-registry-prometheus` adicionada
- [ ] Endpoint `/actuator/prometheus` exposto
- [ ] Configuração `management.endpoints.web.exposure.include` inclui `prometheus`
- [ ] Service tem port com nome "http"
- [ ] Service tem label `app: <service-name>`
- [ ] Serviço iniciou sem erros

**Verificar**:
```bash
# Para cada serviço
kubectl get svc -n <namespace> -o yaml | grep -A 5 ports:
kubectl logs -n <namespace> <pod> | grep "prometheus\|actuator"
curl <pod-ip>:8001/actuator/prometheus
```

## ✅ Dashboard Customizado

- [ ] ConfigMap `grafana-dashboard-togglemaster` criado
- [ ] Dashboard aparece na lista de dashboards do Grafana
- [ ] UID do dashboard: `togglemaster-health`
- [ ] Dashboard contém 9 widgets:
  - [ ] CPU Usage by Namespace
  - [ ] Memory Usage by Namespace
  - [ ] HTTP Request Rate by Service
  - [ ] HTTP Request Latency (p95) by Service
  - [ ] Real-time Logs - Microservices
  - [ ] Service Health Status
  - [ ] Total Running Pods
  - [ ] API Error Rate
  - [ ] Total Request Rate

**Verificar no Grafana**:
1. Ir para Home > Dashboards > ToggleMaster
2. Verificar que todos os widgets carregam dados
3. Testar filtros e zoom

## ✅ Logs Centralizados (Loki)

- [ ] Logs de todos os pods aparecem no Loki
- [ ] Promtail está coletando logs
- [ ] Labels estão corretos: namespace, pod, container, app
- [ ] Posso filtrar logs por namespace
- [ ] Posso filtrar logs por serviço

**Verificar no Grafana**:
1. Ir para Explore > Select Loki datasource
2. Testar query: `{namespace="auth"}`
3. Testar query: `{app="auth"}`
4. Verificar que logs aparecem com timestamps

## ✅ Alerts e Rules

- [ ] PrometheusRule `togglemaster-alerts` criada
- [ ] Alert `ServiceHighErrorRate` configurado
- [ ] Alert `ServiceResponseTimeHigh` configurado
- [ ] Alert `ServiceDown` configurado
- [ ] Recording rules compiladas com sucesso

**Verificar em Prometheus**:
1. Status > Rules
2. Verificar que regras aparecem na seção `togglemaster.rules`
3. Status > Alerts
4. Verificar que alertas estão criados

## ✅ Armazenamento e Volumes

- [ ] PVC do Prometheus com 10Gi alocado
- [ ] PVC do Grafana com 10Gi alocado
- [ ] PVC do Loki com 10Gi alocado
- [ ] Todos os PVCs com status "Bound"
- [ ] Todos os PVCs linked a um PV

**Verificar**:
```bash
kubectl describe pvc -n monitoring
kubectl get pv
```

## ✅ Conectividade Inter-Componentes

- [ ] Prometheus consegue conectar em Loki
- [ ] Grafana consegue conectar em Prometheus
- [ ] Grafana consegue conectar em Loki
- [ ] Prometheus consegue scrape de todos os ServiceMonitors

**Verificar**:
```bash
# Do Prometheus para Loki
kubectl exec -it <prometheus-pod> -n monitoring -- \
  curl http://loki:3100/ready

# Do Grafana para Prometheus
kubectl exec -it <grafana-pod> -n monitoring -- \
  curl http://prometheus-operated:9090/-/healthy

# Do Grafana para Loki
kubectl exec -it <grafana-pod> -n monitoring -- \
  curl http://loki:3100/ready
```

## ✅ GitOps (ArgoCD)

- [ ] ArgoCD Application `monitoring-stack` criada
- [ ] ArgoCD Application `prometheus-helm` criada
- [ ] ArgoCD Application `loki-helm` criada
- [ ] Status de todas as applications: "Synced"
- [ ] Auto-sync habilitado para redeployment automático

**Verificar**:
```bash
kubectl get applications -n argocd | grep monitoring
```

## ✅ Documentação

- [ ] Arquivo [README.md](./README.md) criado com documentação completa
- [ ] Arquivo [INSTRUMENTATION.md](./INSTRUMENTATION.md) criado
- [ ] Script [install-monitoring.sh](./install-monitoring.sh) criado e testado
- [ ] Script [check-monitoring-health.sh](./check-monitoring-health.sh) criado e testado

## ✅ Testes de Funcionalidade

### Teste 1: Coleta de Métricas

- [ ] Executar query no Prometheus: `http_requests_total`
- [ ] Verificar que dados aparecem
- [ ] Filtrar por job/serviço
- [ ] Alterar time range e verificar dados históricos

### Teste 2: Dashboard em Tempo Real

- [ ] Abrir dashboard ToggleMaster
- [ ] Gerar tráfego nos microsserviços
- [ ] Verificar que gráficos atualizam em tempo real
- [ ] Testar zoom e drill-down nos gráficos

### Teste 3: Logs em Tempo Real

- [ ] Abrir painel de logs no dashboard
- [ ] Gerar logs nos serviços
- [ ] Verificar que novos logs aparecem instantaneamente
- [ ] Testar filtros de log

### Teste 4: Alertas

- [ ] Simular alta taxa de erro em um serviço
- [ ] Verificar que alerta é disparado
- [ ] Visualizar no AlertManager (se configurado)

**Simular erro**:
```bash
# Gerar requisições de erro
for i in {1..100}; do
  kubectl exec -it <service-pod> -n <namespace> -- \
    curl http://localhost:8001/error
done
```

## ✅ Performance e Escalabilidade

- [ ] CPU do Prometheus < 500m
- [ ] Memory do Prometheus < 1Gi
- [ ] CPU do Grafana < 200m
- [ ] Memory do Grafana < 512Mi
- [ ] CPU do Loki < 300m
- [ ] Memory do Loki < 512Mi
- [ ] Scrape latency < 100ms

**Verificar**:
```bash
kubectl top pod -n monitoring
```

## ✅ Backup e Disaster Recovery

- [ ] PVCs estão configuradas com snapshot schedule
- [ ] Prometheus data pode ser exportado
- [ ] Grafana dashboards podem ser exportadas como JSON
- [ ] Plano de recovery documentado

## ✅ Segurança (Desenvolvimento)

### ⚠️ Importante: Ajustar para Produção

- [ ] Entendo que Grafana/Loki não têm autenticação (dev mode)
- [ ] Documentação menciona upgrades de segurança necessárias
- [ ] Senhas padrão serão mudadas antes de produção

**Próximas etapas de segurança**:
- [ ] Implementar OAuth2 no Grafana
- [ ] Habilitar autenticação no Loki
- [ ] Configurar mTLS entre componentes
- [ ] Rotacionar senhas de admin

## ✅ Monitoramento do Monitoramento

- [ ] Prometheus monitora a si mesmo
- [ ] Grafana expõe métricas em `/metrics`
- [ ] Loki expõe métricas em `/metrics`
- [ ] Pode-se consultar saúde dos componentes de monitoramento

**Queries úteis**:
```promql
# Saúde do Prometheus
up{job="prometheus"}

# Throughput do Prometheus
rate(prometheus_tsdb_symbol_table_size_bytes[5m])

# Saúde do Loki
up{job="loki"}

# Saúde do Grafana
up{job="grafana"}
```

## ✅ Integração Contínua/GitOps

- [ ] Todos os manifests estão no Git
- [ ] ArgoCD faz sync automático
- [ ] Mudanças em YAML atualizam cluster automaticamente
- [ ] Rollback automático em caso de erro

**Verificar**:
```bash
git log --oneline k8s/monitoring/
git log --oneline k8s/argocd/argocd-monitoring-apps.yaml
```

## Assinatura e Aprovação

- [ ] Responsável: ___________________________
- [ ] Data: ___________________________
- [ ] Ambiente (dev/staging/prod): ___________________________

## Observações

```
[Espaço para notas adicionais]
```

---

## Próximos Passos (Fase 4+)

Após completar este checklist:

1. **OpenTelemetry (OTel)**: Adicionar distributed tracing
2. **AlertManager**: Integrar com Slack/PagerDuty
3. **SLO/SLI**: Definir e monitorar objetivos
4. **Escalabilidade**: Remote storage para Prometheus
5. **Machine Learning**: Anomaly detection
6. **Cost Optimization**: Tuning de retenção e storage
