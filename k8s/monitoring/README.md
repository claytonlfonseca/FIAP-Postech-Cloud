# Monitoramento Opensource - ToggleMaster Phase 4

> **Comece pelo [guia central Ubuntu/WSL](../../../README.md)** para instalar
> ferramentas, configurar o acesso ao EKS e seguir a ordem correta.
> Esta referência descreve a arquitetura pretendida, não comprova que ela já
> esteja implantada. Os ServiceMonitors atuais usam pressupostos de Spring Boot
> que precisam ser adaptados aos serviços Go/Flask; charts, fontes Git,
> armazenamento e regras também exigem revisão. Veja a seção 8 do guia central.
>
> O script pode ser executado no WSL, apontando para EKS. Ele exige kubectl,
> jq e ArgoCD disponíveis. Helm não é necessário localmente: o ArgoCD obtém os
> charts diretamente dos repositórios declarados nas Applications. O script
> valida e agrupa os manifests multi-documento, registra primeiro os charts e
> aguarda a CRD ServiceMonitor antes de aplicar os monitores. Os caminhos dos
> manifests são resolvidos pela localização do script, independentemente do
> diretório atual.
> Para `kubectl: command not found`, instale kubectl no
> Ubuntu e confira o PATH antes de executar novamente.

Os charts com PVC declaram `storageClassName: gp3` explicitamente. Antes da
sincronização, confirme que a StorageClass `gp3` existe e que o EBS CSI está
saudável; os charts não dependem da StorageClass padrão do cluster.

## Visão Geral

Este documento descreve a implementação completa do stack de observabilidade para o ToggleMaster, incluindo:
- **Prometheus**: Coleta e armazenamento de métricas
- **Loki**: Centralização e indexação de logs
- **Grafana**: Visualização e dashboards

## Arquitetura

```
┌─────────────────────────────────────────────────────────────────┐
│                        Kubernetes Cluster                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              Microserviços (Namespaces)                  │   │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────────┐   │   │
│  │  │  auth   │ │  flag   │ │targeting│ │ evaluation  │   │   │
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────────┘   │   │
│  │  ┌─────────────────────────┐                            │   │
│  │  │     analytics           │                            │   │
│  │  └─────────────────────────┘                            │   │
│  └──────────────────────────────────────────────────────────┘   │
│           ↓ Expõe métricas             ↓ Gera logs              │
│           :9090/metrics                stdout/stderr            │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │          Monitoring Stack (Namespace: monitoring)        │   │
│  │                                                           │   │
│  │  ┌─────────────────────────────────────────────────┐    │   │
│  │  │        Prometheus + Node Exporter              │    │   │
│  │  │  (TSDB - Time Series Database)                 │    │   │
│  │  │  - Armazena métricas por 15 dias               │    │   │
│  │  │  - Storage: 10Gi (PVC)                         │    │   │
│  │  │  - Scrape interval: 30s (microserviços)        │    │   │
│  │  └─────────────────────────────────────────────────┘    │   │
│  │           ↓                                              │   │
│  │  ┌─────────────────────────────────────────────────┐    │   │
│  │  │             Loki                               │    │   │
│  │  │  (Log Aggregation)                             │    │   │
│  │  │  - Centraliza logs dos containers              │    │   │
│  │  │  - Indexação eficiente                         │    │   │
│  │  │  - Storage: 10Gi (PVC)                         │    │   │
│  │  │  - Promtail coleta logs de todos os pods       │    │   │
│  │  └─────────────────────────────────────────────────┘    │   │
│  │           ↓                                              │   │
│  │  ┌─────────────────────────────────────────────────┐    │   │
│  │  │             Grafana                            │    │   │
│  │  │  (Visualização)                                │    │   │
│  │  │  - Datasources: Prometheus + Loki              │    │   │
│  │  │  - Dashboard customizado ToggleMaster          │    │   │
│  │  │  - Acesso: http://grafana:3000                 │    │   │
│  │  │  - Admin: admin / admin123                     │    │   │
│  │  └─────────────────────────────────────────────────┘    │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

## Componentes Implantados

### 1. Prometheus Stack (kube-prometheus-stack)

**Helm Chart**: `prometheus-community/kube-prometheus-stack`
**Versão**: 57.0.1
**Namespace**: monitoring

**Componentes incluídos**:
- Prometheus Operator
- Prometheus (TSDB)
- AlertManager
- Grafana
- Node Exporter
- kube-state-metrics

**Configurações principais**:
```yaml
prometheus:
  retention: 15d           # Retém métricas por 15 dias
  storage: 10Gi            # Volume persistente de 10GB
  scrape_interval: 30s     # Coleta métricas a cada 30 segundos
  serviceMonitors: enabled # Detecta ServiceMonitors automaticamente
```

**Métricas coletadas**:
- CPU e Memória dos nodes
- API Server do Kubernetes
- Kubelet e Container Runtime
- Métricas dos microsserviços (via ServiceMonitor)

### 2. Loki Stack

**Helm Chart**: `grafana/loki-stack`
**Versão**: 2.10.0
**Namespace**: monitoring

**Componentes inclusos**:
- Loki (Log aggregation engine)
- Promtail (Log shipper)

**Configurações principais**:
```yaml
loki:
  auth_enabled: false      # Sem autenticação (ambiente de desenvolvimento)
  storage: 10Gi            # Volume persistente
  ingestion_rate: 16MB/s   # Taxa máxima de ingestão
  
promtail:
  enabled: true            # Coleta logs de todos os pods
  scrape_configs:
    - role: pod            # Descobre pods automaticamente
    - labels: namespace, pod, container, app
```

**Logs coletados**:
- Todos os containers dos microsserviços
- Logs do cluster (kubelet, controller-manager, etc.)
- Labels automáticos: namespace, pod, container, app

### 3. Grafana

**Integrado ao**: kube-prometheus-stack
**Acesso**: `http://grafana:3000`
**Credenciais**: admin / admin123

**Datasources configurados**:
- Prometheus (http://prometheus-kube-prometheus-prometheus:9090)
- Loki (http://loki:3100)

**Dashboard customizado**: ToggleMaster - Cluster Health & Observability
- UID: `togglemaster-health`
- Painel interativo com 9 widgets

## Dashboard Customizado

### Componentes do Dashboard

1. **CPU Usage by Namespace**
   - Gráfico de série temporal
   - Mostra consumo de CPU por namespace
   - Query: `sum(rate(container_cpu_usage_seconds_total[5m])) by (namespace)`

2. **Memory Usage by Namespace**
   - Gráfico de série temporal
   - Mostra consumo de memória em bytes
   - Query: `sum(container_memory_usage_bytes) by (namespace)`

3. **HTTP Request Rate by Service**
   - Taxa de requisições por segundo (RPS) por serviço
   - Query: `sum(rate(http_requests_total[5m])) by (service)`

4. **HTTP Request Latency (p95) by Service**
   - Percentil 95 de latência em milissegundos
   - Query: `histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (service, le))`

5. **Real-time Logs - Microservices**
   - Painel de logs em tempo real
   - Filtra namespaces: auth, flag, targeting, evaluation, analytics
   - Datasource: Loki

6. **Service Health Status**
   - Status UP/DOWN de cada serviço
   - Indicador visual (green/red)
   - Query: `up{job=~"auth|flag|targeting|evaluation|analytics"}`

7. **Total Running Pods**
   - Quantidade de pods em estado Running
   - Query: `count(kube_pod_status_phase{phase="Running"})`

8. **API Error Rate**
   - Percentual de requisições com status 5xx
   - Query: `(sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))) * 100`

9. **Total Request Rate**
   - Taxa total de requisições por segundo em todo o cluster
   - Query: `sum(rate(http_requests_total[5m]))`

## ServiceMonitor - Integração com Microsserviços

Os microsserviços são monitorados automaticamente através de **ServiceMonitor**, que detecta endpoints Prometheus nos serviços.

### Configuração por Serviço

Para cada microsserviço (auth, flag, targeting, evaluation, analytics):

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: <service>-service-monitor
  namespace: <service-namespace>
spec:
  selector:
    matchLabels:
      app: <service>
  endpoints:
    - port: http
      interval: 30s
      path: /actuator/prometheus  # Spring Boot Actuator
```

**Requisitos nos microsserviços**:
1. Implementar endpoint `/actuator/prometheus` (Spring Boot Actuator)
2. Expor no puerto `http` (porta padrão do serviço)
3. Retornar métricas no formato Prometheus

**Exemplo de dependência Spring Boot**:
```xml
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
</dependency>
```

## Como Usar

### 1. Acessar Grafana

```bash
# Port-forward (se não houver Ingress)
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Abrir no navegador
http://localhost:3000

# Login
Username: admin
Password: admin123
```

### 2. Consultar Métricas no Prometheus

```bash
# Port-forward
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090

# Abrir no navegador
http://localhost:9090

# Exemplos de queries:
# - Container memory usage: container_memory_usage_bytes
# - CPU usage: container_cpu_usage_seconds_total
# - HTTP requests: http_requests_total
# - Request duration: http_request_duration_seconds
```

### 3. Visualizar Logs no Loki

No Grafana:
1. Ir para "Explore"
2. Selecionar datasource "Loki"
3. Usar LogQL queries:
   ```
   {namespace="auth"}              # Logs do namespace auth
   {namespace="auth", status="500"} # Logs com erro
   ```

## Queries PromQL Úteis

### Infraestrutura

```promql
# CPU total do cluster
sum(rate(node_cpu_seconds_total[5m]))

# Memória disponível
sum(node_memory_MemAvailable_bytes)

# Espaço em disco
node_filesystem_avail_bytes{fstype="ext4"}

# Network I/O
sum(rate(node_network_transmit_bytes_total[5m]))
sum(rate(node_network_receive_bytes_total[5m]))
```

### Aplicações (Microsserviços)

```promql
# Requisições por segundo
rate(http_requests_total[5m])

# Taxa de erros (5xx)
rate(http_requests_total{status=~"5.."}[5m])

# Latência (p50, p95, p99)
histogram_quantile(0.5, rate(http_request_duration_seconds_bucket[5m]))
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))

# Taxa de erro por endpoint
rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m])
```

### Kubernetes

```promql
# Pods rodando por namespace
count(kube_pod_status_phase{phase="Running"}) by (namespace)

# Pod memory usage
container_memory_usage_bytes

# Pod CPU usage
rate(container_cpu_usage_seconds_total[5m])

# Pod restart count
kube_pod_container_status_restarts_total
```

## LogQL Queries Úteis

```logql
# Todos os logs de um namespace
{namespace="auth"}

# Logs de um container específico
{namespace="auth", container="auth"}

# Logs com palavra-chave "error"
{namespace="auth"} |= "error"

# Logs de erro com contagem
{namespace="auth"} |= "error" | stats count() by namespace

# Latência em logs (exemplo)
{namespace="auth"} |= "duration" | pattern "<_> <duration>" | stats avg(duration) by namespace
```

## Troubleshooting

### Prometheus não coleta métricas dos microsserviços

**Verificar**:
1. ServiceMonitor foi criado no namespace correto?
   ```bash
   kubectl get servicemonitor -A
   ```

2. O serviço tem label correto?
   ```bash
   kubectl get svc -A -o json | jq '.items[] | select(.metadata.labels.app=="auth")'
   ```

3. Endpoint Prometheus está acessível?
   ```bash
   kubectl exec -it <pod> -n <namespace> -- curl localhost:8001/actuator/prometheus
   ```

### Loki não coleta logs

**Verificar**:
1. Promtail está rodando?
   ```bash
   kubectl get pod -n monitoring | grep promtail
   kubectl logs -n monitoring <promtail-pod>
   ```

2. Labels estão corretos?
   ```bash
   kubectl logs -n <namespace> <pod> | head
   ```

### Grafana não conecta com datasources

**Verificar**:
1. Prometheus service está acessível?
   ```bash
   kubectl get svc -n monitoring | grep prometheus
   kubectl exec -it <grafana-pod> -c grafana -n monitoring -- curl http://prometheus-operated:9090/-/healthy
   ```

2. Loki service está acessível?
   ```bash
   kubectl exec -it <grafana-pod> -c grafana -n monitoring -- curl http://loki:3100/ready
   ```

## Armazenamento e Persistência

### Volume Claims

Todos os componentes usam PersistentVolumeClaims (PVC):

```bash
# Ver PVCs
kubectl get pvc -n monitoring

# Verificar espaço
kubectl describe pvc -n monitoring

# Expandir volume (se suportado)
kubectl patch pvc prometheus-kube-prometheus-prometheus -n monitoring -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'
```

## Retenção de Dados

| Componente | Retenção | Espaço |
|---|---|---|
| Prometheus | 15 dias | 10Gi |
| Loki | Indefinida* | 10Gi |

*Ajustar conforme necessário via `limits_config` no Loki

## Segurança (Desenvolvimento)

⚠️ **Ambiente de Desenvolvimento** - Não usar em produção:
- Grafana sem autenticação LDAP/OAuth
- Loki sem autenticação
- Prometheus sem TLS

Para produção:
- Implementar OAuth2/LDAP no Grafana
- Configurar mTLS entre componentes
- Usar secrets para credenciais
- Habilitar autenticação no Loki

## Próximos Passos (Phase 4+)

1. **OpenTelemetry (OTel)**: Instrumentação padronizada de traces
2. **Alerting**: Implementar AlertManager rules
3. **SLO/SLI**: Definir Service Level Indicators
4. **Escalabilidade**: Prometheus remote storage, Loki distribuído
5. **Self-Healing**: Automatizar remediação de alertas

## Referências

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Loki Documentation](https://grafana.com/docs/loki/latest/)
- [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [Loki Stack Helm Chart](https://github.com/grafana/loki/tree/main/production/helm/loki-stack)

## Suporte e Contribuições

Para adicionar métricas customizadas:
1. Modificar `prometheus-helm-values.yaml`
2. Adicionar widget no dashboard `grafana-dashboard-togglemaster.yaml`
3. Fazer commit e push (ArgoCD faz sync automático)
