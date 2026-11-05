# Início rápido - monitoramento no Ubuntu/WSL

O procedimento completo está no [guia central](../../../README.md),
especialmente nas seções 3 (ferramentas), 5 (EKS) e 8 (monitoramento).
Execute os comandos abaixo na raiz `FIAP-Postech-Cloud`, que contém `k8s`.

## 1. Preparar o terminal e o cluster

O script pode ser executado no WSL ou em uma máquina AWS. Ele instala recursos
no **cluster do contexto kubectl**, não na máquina que executa o script.
Ele não opera sobre Docker Compose.

São necessários kubectl compatível com o cluster, Helm 3, jq, cluster acessível,
ArgoCD, capacidade e armazenamento persistente. Para EKS, também AWS CLI
autenticada e autorização para acessar o cluster.

```bash
command -v kubectl helm jq
kubectl version --client
helm version
kubectl config current-context
kubectl get nodes
kubectl get crd applications.argoproj.io
kubectl get pods -n argocd
kubectl get storageclass
```

Se o EKS ainda não estiver configurado:

```bash
aws sts get-caller-identity
aws eks list-clusters --region us-east-1
aws eks update-kubeconfig --region us-east-1 --name NOME_DO_CLUSTER
kubectl get nodes
```

Substitua o nome e a região. Não prossiga se a conta/contexto não for o esperado.

## 2. Instalar na ordem correta

O script atualizado registra os charts antes dos monitores e aguarda a CRD.
Com ArgoCD operacional, armazenamento preparado e Applications revisadas, você
pode usá-lo diretamente. Para instalar manualmente, siga esta ordem:

1. Siga a seção 8.2 do [guia central](../../../README.md).
2. Revise os repositórios, caminhos Git e versões dos charts nas Applications.
3. Registre primeiro apenas `prometheus-helm` e `loki-helm`.
4. Aguarde os charts saudáveis e a CRD:

   ```bash
   kubectl wait --for=condition=Established \
     crd/servicemonitors.monitoring.coreos.com --timeout=300s
   kubectl get applications -n argocd
   kubectl get pods,pvc -n monitoring
   ```

5. Aplique os ServiceMonitors/dashboard e depois a Application
   `monitoring-stack`, com fonte e escopo revisados.

Como alternativa à instalação manual, execute o script atualizado:

```bash
# Partindo da raiz FIAP-Postech-Cloud:
bash k8s/monitoring/install-monitoring.sh
```

O script também funciona em outro diretório quando chamado pelo caminho correto
(por exemplo, `bash ./install-monitoring.sh` dentro de `k8s/monitoring`).
Os manifests são resolvidos pela localização do script e verificados antes
de qualquer alteração no cluster.

Ele registra Applications no ArgoCD; não instala charts diretamente via Helm.
Alterações locais não são lidas pelo ArgoCD até serem publicadas no Git remoto.
A espera pela criação e pelo estabelecimento da CRD tem limite de 300 segundos
por etapa. Se expirar, o script para antes de aplicar ServiceMonitors e mostra
comandos para diagnosticar a sincronização do Prometheus.

## 3. Acessar e validar

```bash
kubectl get pods,pvc,svc -n monitoring
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
```

Abra `http://localhost:3000`. Verifique a senha configurada e substitua qualquer
senha de exemplo antes de compartilhar o ambiente.

Em terminais separados:

```bash
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090
kubectl port-forward -n monitoring svc/loki 3100:3100
```

Confirme os nomes reais dos Services. Valide PVCs `Bound`, targets Prometheus
e logs recentes no Grafana. Métricas dos microsserviços exigem os ajustes de
instrumentação/seletores descritos na seção 8.4 do guia central.

## Problemas frequentes

| Erro | Ação |
|---|---|
| `kubectl: command not found` | Instale kubectl no Ubuntu/WSL e confira `PATH`; seção 3.4 do guia central. |
| `helm: command not found` | Instale Helm 3 no Ubuntu/WSL. |
| `current-context is not set` | Configure o acesso ao cluster antes de executar o script. |
| Caminho `k8s/...` não encontrado | Atualize o script e confira se a cópia contém os manifests indicados pelo erro. |
| `no matches for kind ServiceMonitor` | Atualize o script; se a espera pela CRD falhar, inspecione a Application `prometheus-helm` no ArgoCD. |
| PVC `Pending` | Verifique StorageClass, EBS CSI Driver/IAM e eventos do PVC. |
| ArgoCD não sincroniza | Inspecione `kubectl describe application NOME -n argocd`. |
