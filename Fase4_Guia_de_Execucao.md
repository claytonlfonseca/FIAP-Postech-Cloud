# Fase 4 — Guia de Execução do ToggleMaster

Guia sequencial para preparar o ambiente, autenticar na AWS, provisionar a
infraestrutura, implantar e validar o ToggleMaster no EKS, habilitar
GitOps/monitoramento quando desejado e remover os recursos ao final.

> **Tempo estimado:** reserve em média **4 a 6 horas** para percorrer o fluxo
> principal, incluindo provisionamento, validações e remoção dos recursos,
> considerando que as ferramentas já estão instaladas e o acesso à AWS está
> autorizado. A duração varia conforme a região, as cotas e o tempo de criação
> ou exclusão dos recursos AWS. Instalações locais e resolução de permissões
> podem acrescentar algumas horas; ArgoCD e monitoramento são opcionais e
> também aumentam o tempo.

## Menu

- [1. Visão do sistema e sequência](#1-visão-do-sistema-e-sequência)
- [2. Requisitos do ambiente](#2-requisitos-do-ambiente)
- [3. Autenticar na AWS](#3-autenticar-na-aws)
- [4. Teste local opcional](#4-teste-local-opcional)
- [5. Preparar o backend Terraform](#5-preparar-o-backend-terraform)
- [6. Planejar e provisionar AWS](#6-planejar-e-provisionar-aws)
- [7. Conectar e validar EKS](#7-conectar-e-validar-eks)
- [8. Instalar EBS CSI e criar StorageClass gp3](#8-instalar-ebs-csi-e-criar-storageclass-gp3)
- [9. Publicar imagens no ECR](#9-publicar-imagens-no-ecr)
- [10. Criar identidades AWS para os pods (IRSA)](#10-criar-identidades-aws-para-os-pods-irsa)
- [11. Configurar PostgreSQL, Redis, ConfigMaps e Secrets](#11-configurar-postgresql-redis-configmaps-e-secrets)
  - [11.3 Atualizar ConfigMaps com outputs deste ambiente](#113-atualizar-configmaps-com-outputs-deste-ambiente)
- [12. Implantar serviços e criar a chave de evaluation](#12-implantar-serviços-e-criar-a-chave-de-evaluation)
- [13. Teste ponta a ponta da aplicação](#13-teste-ponta-a-ponta-da-aplicação)
- [14. Verificações gerais de saúde e diagnóstico](#14-verificações-gerais-de-saúde-e-diagnóstico)
- [15. Instalar ArgoCD (opcional para deploy manual)](#15-instalar-argocd-opcional-para-deploy-manual)
- [16. Instalar monitoramento (opcional)](#16-instalar-monitoramento-opcional)
- [17. Encerramento completo e prevenção de cobranças](#17-encerramento-completo-e-prevenção-de-cobranças)
- [18. Checklist de conclusão](#18-checklist-de-conclusão)

> **Custo e risco:** EKS, NAT Gateway, RDS, ElastiCache, volumes EBS, tráfego e
> outros recursos podem gerar cobrança enquanto existirem. Este é um ambiente
> de laboratório, não uma arquitetura pronta para produção. Leia cada plano,
> confirme conta e região e faça backup antes de excluir dados.
>
> **Segredos:** nunca coloque senhas, tokens, DSNs, `MASTER_KEY`,
> `SERVICE_API_KEY`, arquivos `.tfstate` ou planos Terraform no Git, em logs,
> capturas de tela ou mensagens. Não aplique manifests estáticos de Secrets
> antigos.

## 1. Visão do sistema e sequência

O ToggleMaster contém cinco serviços:

| Serviço | Porta no container | Função |
|---|---:|---|
| `auth` | 8001 | Cria e valida chaves de API |
| `flag` | 8002 | Cria e consulta feature flags |
| `targeting` | 8003 | Cria e consulta regras |
| `evaluation` | 8004 | Avalia uma flag, usa Redis e envia eventos ao SQS |
| `analytics` | 8005 | Consome mensagens SQS e grava eventos no DynamoDB |

Fluxo:

```text
Cliente -> evaluation -> Redis
                     -> flag + targeting -> auth -> PostgreSQL
                     -> SQS -> analytics -> DynamoDB
```

Ordem recomendada:

1. Preparar Ubuntu/WSL, ferramentas e acesso ao projeto.
2. Autenticar na conta AWS e conferir a identidade.
3. Criar o backend Terraform e provisionar os recursos AWS.
4. Conectar e validar o cluster EKS.
5. Instalar e validar EBS CSI e StorageClass `gp3`.
6. Publicar imagens no ECR.
7. Configurar identidade dos pods, ConfigMaps e Secrets.
8. Inicializar os schemas PostgreSQL.
9. Implantar os serviços e validar o fluxo completo até DynamoDB.
10. Opcionalmente instalar ArgoCD e monitoramento.
11. Ao terminar, fazer backup e remover os recursos, inclusive os criados
    fora do Terraform.

Os comandos pressupõem Bash no Ubuntu/WSL. Sempre que abrir uma nova aba de
terminal, reaplique as variáveis de ambiente necessárias: elas não são
compartilhadas entre terminais.

## 2. Requisitos do ambiente

### 2.1 Conta e permissões

- Conta AWS ativa e orçamento aprovado para laboratório.
- Identidade IAM autorizada a criar os recursos deste projeto: rede, EKS,
  EC2, RDS, ElastiCache, SQS, DynamoDB, ECR, IAM e Secrets Manager.
- Acesso à região que será usada e ao cluster EKS.
- Navegador para concluir o login interativo da AWS.
- Não use o usuário root para o tutorial. Se
  `aws sts get-caller-identity` mostrar um ARN terminado em `:root`, pare e
  autentique com uma identidade IAM apropriada antes de criar recursos.
- Prefira permissões mínimas e credenciais temporárias. Não grave access keys
  em Secrets Kubernetes.

### 2.2 Máquina local

Recomendado: Ubuntu 24.04 LTS no WSL 2, Bash e acesso à Internet. Instale e
confirme:

| Ferramenta | Uso |
|---|---|
| Git | Baixar e manter o projeto |
| AWS CLI v2, versão 2.32.0 ou posterior | `aws login` e acesso à AWS |
| Terraform 1.10 ou posterior | Backend S3 com locking por `use_lockfile` |
| `kubectl` | Operar o cluster; diferença máxima de uma versão minor do EKS |
| Docker Engine ou Docker Desktop com integração WSL e Compose v2 | Teste local e build |
| `eksctl` | OIDC e associações IAM/ServiceAccount |
| `curl`, `jq`, `openssl`, `unzip`, `python3`, `git` | Comandos auxiliares |
| Helm 3 | Instalar ArgoCD e inspecionar versões de charts |

`helm` não é necessário para executar o script corrigido de monitoramento:
ArgoCD instala os charts definidos nas Applications.

Links oficiais de instalação:

- [WSL](https://learn.microsoft.com/windows/wsl/install)
- [Docker Desktop no Windows e WSL](https://docs.docker.com/desktop/setup/install/windows-install/)
- [Docker Engine no Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
- [AWS CLI para Linux](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [Terraform](https://developer.hashicorp.com/terraform/install)
- [kubectl para Linux](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/)
- [Helm](https://helm.sh/docs/intro/install/)
- [eksctl](https://eksctl.io/installation/)

Instalação dos utilitários Ubuntu:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg unzip git jq openssl python3
mkdir -p "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"
```

Adicione `export PATH="$HOME/.local/bin:$PATH"` ao `~/.bashrc` se instalou
binários nessa pasta. Instale as demais ferramentas seguindo os links oficiais
e confira:

```bash
command -v git aws terraform kubectl docker eksctl helm jq python3
aws --version
terraform version
kubectl version --client
docker version
docker compose version
eksctl version
helm version --short
```

Para buildar imagens, Docker deve estar iniciado e acessível pelo Ubuntu. No
Docker Desktop, habilite a integração com a distribuição WSL.

### 2.3 Obter o projeto e definir a raiz

Entre na pasta que contém os diretórios `terraform/`, `services/` e `k8s/`.
Exemplo de clone do repositório de entrega:

```bash
mkdir -p "$HOME/projetos"
cd "$HOME/projetos"
git clone https://github.com/claytonlfonseca/FIAP-Postech-Devops.git
cd FIAP-Postech-Devops/fase4/FIAP-Postech-Cloud
export PROJECT_ROOT="$PWD"
```

Se já possui o projeto, use a localização real:

```bash
cd "$HOME/Desktop/Pós-Graduação/FIAP/Projetos/fase4/FIAP-Postech-Cloud"
export PROJECT_ROOT="$PWD"
```

Valide antes de continuar:

```bash
test -d "$PROJECT_ROOT/terraform" \
  && test -d "$PROJECT_ROOT/services" \
  && test -d "$PROJECT_ROOT/k8s" \
  && echo "Raiz do projeto válida" \
  || { echo "Entre na raiz FIAP-Postech-Cloud"; exit 1; }
```

## 3. Autenticar na AWS

Defina região e confira a versão da AWS CLI:

```bash
export AWS_REGION="us-east-1"
export AWS_DEFAULT_REGION="$AWS_REGION"
aws --version
```

Tente primeiro validar credenciais existentes:

```bash
aws sts get-caller-identity
```

Se as credenciais estiverem ausentes/expiradas, ou a identidade não for a
correta, autentique com um perfil nomeado:

```bash
aws login --profile togglemaster
export AWS_PROFILE="togglemaster"
export AWS_REGION="us-east-1"
export AWS_DEFAULT_REGION="$AWS_REGION"
aws sts get-caller-identity
```

Conclua o login no navegador com a identidade IAM esperada. Se o WSL não abrir
um navegador, use `aws login --profile togglemaster --remote` e conclua o
fluxo em outro dispositivo. Não use Access Key ID/Secret Access Key como
substituto no histórico do shell.

Confira `Account` e `Arn` retornados pelo STS. Confirme a conta antes de
qualquer `terraform apply`. Não prossiga se a conta estiver errada ou se o ARN
terminar em `:root`.

Defina as variáveis da sessão:

```bash
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export TF_STATE_BUCKET="togglemaster-tfstate-${AWS_ACCOUNT_ID}"
umask 077
export PRIVATE_DIR="$HOME/.secrets/togglemaster"
mkdir -p "$PRIVATE_DIR"
chmod 700 "$PRIVATE_DIR"
printf 'Conta: %s\nRegião: %s\nProjeto: %s\n' \
  "$AWS_ACCOUNT_ID" "$AWS_REGION" "$PROJECT_ROOT"
```

Os arquivos privados em `$PRIVATE_DIR` são temporários e não devem ser
sincronizados ou versionados.

## 4. Teste local opcional

Recomenda-se validar a aplicação antes da AWS:

```bash
cd "$PROJECT_ROOT/services"
docker compose up --build
```

Em outro terminal, confira a saúde dos cinco serviços, substituindo as
URLs por `http://localhost:8001`, `8002`, `8003`, `8004` e `8005` conforme
cada serviço. Este smoke test local só verifica disponibilidade HTTP; o teste
completo SQS/DynamoDB descrito neste guia usa as roles e recursos AWS do EKS.

```bash
for port in 8001 8002 8003 8004 8005; do
  curl --fail-with-body --show-error "http://localhost:$port/health" || exit 1
  printf '\n'
done
```

Pare os containers com:

```bash
cd "$PROJECT_ROOT/services"
docker compose down
```

Esse comando preserva volumes locais. `docker compose down -v` apaga os dados
locais e só deve ser usado se isso for intencional.

## 5. Preparar o backend Terraform

Terraform usa um bucket S3 remoto para state e locking. Crie o bootstrap
somente se o bucket e o state correspondentes ainda não existirem. Não crie
um novo bucket para contornar um state existente.

```bash
terraform -chdir="$PROJECT_ROOT/terraform/bootstrap" init
terraform -chdir="$PROJECT_ROOT/terraform/bootstrap" plan \
  -var="bucket_name=$TF_STATE_BUCKET" -var="region=$AWS_REGION"
```

Revise o plano. Confirme nome do bucket e conta; nomes de bucket S3 são
globalmente únicos. Só então aplique:

```bash
terraform -chdir="$PROJECT_ROOT/terraform/bootstrap" apply \
  -var="bucket_name=$TF_STATE_BUCKET" -var="region=$AWS_REGION"
```

O bootstrap usa state local próprio. Preserve o state local em local seguro.
O bucket habilita versionamento, criptografia e bloqueio de acesso público;
seu `force_destroy` permite apagar objetos e versões no encerramento.

## 6. Planejar e provisionar AWS

Copie o exemplo de variáveis apenas se ainda não houver `terraform.tfvars`:

```bash
cp -n "$PROJECT_ROOT/terraform/terraform.tfvars.example" \
  "$PROJECT_ROOT/terraform/terraform.tfvars"
```

Edite `terraform/terraform.tfvars` e confirme:

- Região e nomes dos recursos.
- Versão EKS ainda suportada pela AWS na região.
- Tipos de instância e capacidade de nodes compatíveis com as cotas e
  restrições da conta. O exemplo do repositório pode estar desatualizado.
- Capacidade para aplicação, ArgoCD e monitoramento; nodes pequenos podem
  não comportar todos os componentes.
- Bancos esperados: `auth`, `flagdb` (recurso `flag`) e `targeting`.
- Nomes ECR, fila SQS e tabela DynamoDB.

O ambiente usa VPC com subnets públicas/privadas, EKS, RDS PostgreSQL,
ElastiCache Redis, SQS com DLQ, DynamoDB e cinco repositórios ECR. RDS e Redis
ficam privados. Os componentes podem gerar custos significativos, sobretudo
NAT Gateway, EKS, bancos e nodes.

Inicialize e planeje o projeto principal:

```bash
terraform -chdir="$PROJECT_ROOT/terraform" init \
  -backend-config="bucket=$TF_STATE_BUCKET" \
  -backend-config="region=$AWS_REGION"
terraform -chdir="$PROJECT_ROOT/terraform" validate
terraform -chdir="$PROJECT_ROOT/terraform" plan -out=tfplan
```

Revise o plano: conta, região, recursos, custos aproximados e mudanças
destrutivas. Não aceite substituições ou destruições inesperadas. Se o `init`
pedir migração/reconfiguração do backend, pare e localize o state correto.

Somente depois da revisão:

```bash
terraform -chdir="$PROJECT_ROOT/terraform" apply tfplan
export EKS_CLUSTER="$(terraform -chdir="$PROJECT_ROOT/terraform" \
  output -raw eks_cluster_name)"
```

`terraform output` sem selecionar outputs pode expor valores sensíveis no
terminal. Prefira consultar apenas outputs não secretos:

```bash
terraform -chdir="$PROJECT_ROOT/terraform" output -raw eks_cluster_name
terraform -chdir="$PROJECT_ROOT/terraform" output -json rds_endpoints
terraform -chdir="$PROJECT_ROOT/terraform" output -json rds_secret_arns
terraform -chdir="$PROJECT_ROOT/terraform" output -raw redis_primary_endpoint
terraform -chdir="$PROJECT_ROOT/terraform" output -raw sqs_queue_url
terraform -chdir="$PROJECT_ROOT/terraform" output -raw dynamodb_table_name
```

Não imprima `redis_auth_token`, senhas RDS ou DSNs.

## 7. Conectar e validar EKS

```bash
aws eks update-kubeconfig --region "$AWS_REGION" --name "$EKS_CLUSTER"
kubectl config current-context
kubectl cluster-info
kubectl get nodes -o wide
kubectl get pods -n kube-system
```

Só avance se o contexto for o cluster esperado, o control plane responder e
todos os nodes estiverem `Ready`. Atualizar kubeconfig não concede permissão:
`Unauthorized`/`Forbidden` indica que a identidade não está autorizada no
EKS. Confira também conectividade de rede se o endpoint do cluster for privado.

## 8. Instalar EBS CSI e criar StorageClass gp3

O addon básico do EKS não instala necessariamente o driver EBS CSI. A
StorageClass antiga `gp2` com provisioner `kubernetes.io/aws-ebs` não
substitui o CSI. O driver e a `gp3` são necessários para volumes persistentes
do stack de monitoramento.

Primeiro inspecione o estado; não crie um addon duplicado:

```bash
aws eks list-addons --cluster-name "$EKS_CLUSTER" --region "$AWS_REGION"
kubectl get csidriver
kubectl get storageclass
kubectl get pods -n kube-system | grep ebs-csi
```

Se `aws-ebs-csi-driver` já existir, consulte estado e health issues:

```bash
aws eks describe-addon --cluster-name "$EKS_CLUSTER" --region "$AWS_REGION" \
  --addon-name aws-ebs-csi-driver \
  --query 'addon.{status:status,issues:health.issues,role:serviceAccountRoleArn,version:addonVersion}' \
  --output yaml
```

Se ainda não existir, associe OIDC e crie uma role dedicada:

```bash
eksctl utils associate-iam-oidc-provider \
  --cluster "$EKS_CLUSTER" --region "$AWS_REGION" --approve

eksctl create iamserviceaccount \
  --cluster "$EKS_CLUSTER" --region "$AWS_REGION" \
  --namespace kube-system \
  --name ebs-csi-controller-sa \
  --role-name "${EKS_CLUSTER}-ebs-csi-role" \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve
```

Confira que a trust policy da role usa o issuer OIDC deste cluster e o subject
`system:serviceaccount:kube-system:ebs-csi-controller-sa`. Se a associação
existir, inspecione antes de recriar ou modificar roles/ServiceAccounts.

Crie o addon apontando para a role:

```bash
aws eks create-addon \
  --cluster-name "$EKS_CLUSTER" --region "$AWS_REGION" \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn \
    "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${EKS_CLUSTER}-ebs-csi-role"
```

Aguarde o estado e valide pods:

```bash
aws eks wait addon-active --cluster-name "$EKS_CLUSTER" \
  --region "$AWS_REGION" --addon-name aws-ebs-csi-driver
kubectl get deployment,daemonset,pods -n kube-system -o wide | grep ebs-csi
kubectl get csidriver ebs.csi.aws.com
```

Se o waiter expirar, consulte `describe-addon`; o timeout não significa que a
criação foi cancelada. Corrija problemas de OIDC/IAM antes de avançar. Só
depois do addon saudável:

```bash
kubectl apply -f "$PROJECT_ROOT/k8s/gp3.yaml"
kubectl get storageclass
```

Confirme que `gp3` usa `ebs.csi.aws.com`, modo `WaitForFirstConsumer` e
criptografia habilitada. Não a marque como padrão sem verificar outras
StorageClasses.

## 9. Publicar imagens no ECR

As imagens devem ser compatíveis com a arquitetura dos nodes. O cluster
validado neste projeto usou nodes `amd64`; confirme a arquitetura antes do
build:

```bash
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.nodeInfo.architecture}{"\n"}{end}'
```

Faça login no ECR e gere uma tag única:

```bash
export ECR_HOST="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
export IMAGE_TAG="wsl-$(date -u +%Y%m%d%H%M%S)"
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ECR_HOST"
```

Construa e publique as cinco imagens:

```bash
for service in auth flag targeting evaluation analytics; do
  docker build --platform linux/amd64 \
    -t "$ECR_HOST/$service:$IMAGE_TAG" \
    "$PROJECT_ROOT/services/$service-service" || exit 1
  docker push "$ECR_HOST/$service:$IMAGE_TAG" || exit 1
done
```

Confirme tags:

```bash
for service in auth flag targeting evaluation analytics; do
  aws ecr describe-images --repository-name "$service" \
    --image-ids imageTag="$IMAGE_TAG" --region "$AWS_REGION" || exit 1
done
```

Edite os cinco arquivos `k8s/deployments/*-deployment.yaml` e substitua cada
imagem pela URL ECR e tag recém-publicadas. Tags de ECR do projeto são
imutáveis: use tag nova a cada rebuild. Não assuma que imagens/tags antigas no
manifest correspondem ao build atual.

## 10. Criar identidades AWS para os pods (IRSA)

Evaluation envia mensagens à fila SQS. Analytics recebe e exclui mensagens da
fila e grava eventos na tabela DynamoDB. Cada serviço deve ter role e policy
separadas, com acesso somente aos recursos necessários. Não passe credenciais
AWS permanentes por Secrets Kubernetes.

Associe OIDC uma vez, se ainda não estiver configurado:

```bash
eksctl utils associate-iam-oidc-provider \
  --cluster "$EKS_CLUSTER" --region "$AWS_REGION" --approve
```

Obtenha os ARNs dos recursos:

```bash
SQS_QUEUE_URL="$(terraform -chdir="$PROJECT_ROOT/terraform" output -raw sqs_queue_url)"
SQS_QUEUE_ARN="$(aws sqs get-queue-attributes --queue-url "$SQS_QUEUE_URL" \
  --attribute-names QueueArn --query 'Attributes.QueueArn' --output text)"
TABLE_NAME="$(terraform -chdir="$PROJECT_ROOT/terraform" output -raw dynamodb_table_name)"
TABLE_ARN="$(aws dynamodb describe-table --table-name "$TABLE_NAME" \
  --region "$AWS_REGION" --query 'Table.TableArn' --output text)"
```

Crie arquivos de policy restritos:

```bash
jq -n --arg queue "$SQS_QUEUE_ARN" \
  '{Version:"2012-10-17",Statement:[{Effect:"Allow",Action:"sqs:SendMessage",Resource:$queue}]}' \
  > "$PRIVATE_DIR/evaluation-policy.json"

jq -n --arg queue "$SQS_QUEUE_ARN" --arg table "$TABLE_ARN" \
  '{Version:"2012-10-17",Statement:[
    {Effect:"Allow",Action:["sqs:ReceiveMessage","sqs:DeleteMessage"],Resource:$queue},
    {Effect:"Allow",Action:"dynamodb:PutItem",Resource:$table}
  ]}' > "$PRIVATE_DIR/analytics-policy.json"
chmod 600 "$PRIVATE_DIR/evaluation-policy.json" "$PRIVATE_DIR/analytics-policy.json"
```

Crie as policies IAM:

```bash
aws iam create-policy \
  --policy-name "${EKS_CLUSTER}-evaluation-runtime" \
  --policy-document "file://$PRIVATE_DIR/evaluation-policy.json"
aws iam create-policy \
  --policy-name "${EKS_CLUSTER}-analytics-runtime" \
  --policy-document "file://$PRIVATE_DIR/analytics-policy.json"
```

Guarde os ARNs devolvidos sem expor documentos ou credenciais. Se a policy já
existir, pare, inspecione a policy existente e sua versão; `create-policy` não
atualiza uma policy já criada.

Crie os ServiceAccounts/roles IRSA usando os ARNs revisados:

```bash
export EVALUATION_POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${EKS_CLUSTER}-evaluation-runtime"
export ANALYTICS_POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${EKS_CLUSTER}-analytics-runtime"

eksctl create iamserviceaccount \
  --cluster "$EKS_CLUSTER" --region "$AWS_REGION" \
  --namespace evaluation --name evaluation-service-account \
  --role-name "${EKS_CLUSTER}-evaluation-role" \
  --attach-policy-arn "$EVALUATION_POLICY_ARN" --approve

eksctl create iamserviceaccount \
  --cluster "$EKS_CLUSTER" --region "$AWS_REGION" \
  --namespace analytics --name analytics-service-account \
  --role-name "${EKS_CLUSTER}-analytics-role" \
  --attach-policy-arn "$ANALYTICS_POLICY_ARN" --approve
```

Os nomes precisam corresponder aos `serviceAccountName` nos Deployments.
Confira antes do rollout:

```bash
kubectl get serviceaccount evaluation-service-account -n evaluation -o yaml
kubectl get serviceaccount analytics-service-account -n analytics -o yaml
```

Revise a anotação da role e trust policy com issuer OIDC, audience
`sts.amazonaws.com` e subject do namespace/ServiceAccount correto. Não
recrie associações que já existem sem antes verificar a role, CloudFormation
stack e policy anexada.

## 11. Configurar PostgreSQL, Redis, ConfigMaps e Secrets

### 11.1 Buscar credenciais RDS em diretório privado

Busque os Secrets Manager usando apenas os ARNs dos outputs:

```bash
for service in auth flag targeting; do
  secret_arn="$(terraform -chdir="$PROJECT_ROOT/terraform" \
    output -json rds_secret_arns | jq -er --arg service "$service" '.[$service]')"
  aws secretsmanager get-secret-value \
    --secret-id "$secret_arn" --region "$AWS_REGION" \
    --query SecretString --output text > "$PRIVATE_DIR/$service-rds.json"
  chmod 600 "$PRIVATE_DIR/$service-rds.json"
done
```

Gere DSNs PostgreSQL URL-encoded. Os nomes são `auth`, `flagdb` e
`targeting`; o banco associado ao serviço `flag` chama-se `flagdb`.

```bash
python3 - "$PRIVATE_DIR" <<'PY'
import json
import sys
from pathlib import Path
from urllib.parse import quote

private_dir = Path(sys.argv[1])
database_names = {"auth": "auth", "flag": "flagdb", "targeting": "targeting"}

for service, database in database_names.items():
    secret = json.loads((private_dir / f"{service}-rds.json").read_text())
    username = quote(secret["username"], safe="")
    password = quote(secret["password"], safe="")
    dsn = (
        f"postgresql://{username}:{password}@{secret['host']}:"
        f"{secret.get('port', 5432)}/{database}?sslmode=require"
    )
    (private_dir / f"{service}.env").write_text(f"DATABASE_URL={dsn}\n")
PY
chmod 600 "$PRIVATE_DIR/auth.env" "$PRIVATE_DIR/flag.env" \
  "$PRIVATE_DIR/targeting.env"
```

Gere uma chave `MASTER_KEY` nova sem imprimi-la:

```bash
openssl rand -hex 32 > "$PRIVATE_DIR/master-key"
chmod 600 "$PRIVATE_DIR/master-key"
python3 - "$PRIVATE_DIR" <<'PY'
import sys
from pathlib import Path

private_dir = Path(sys.argv[1])
master_key = (private_dir / "master-key").read_text().strip()
with (private_dir / "auth.env").open("a") as env_file:
    env_file.write(f"MASTER_KEY={master_key}\n")
PY
```

### 11.2 Montar URL Redis segura

O Redis usa TLS e token; a URL deve começar por `rediss://`.

```bash
terraform -chdir="$PROJECT_ROOT/terraform" output -raw redis_auth_token \
  > "$PRIVATE_DIR/redis-token"
terraform -chdir="$PROJECT_ROOT/terraform" output -raw redis_primary_endpoint \
  > "$PRIVATE_DIR/redis-endpoint"
chmod 600 "$PRIVATE_DIR/redis-token" "$PRIVATE_DIR/redis-endpoint"
```

Codifique o token e grave o env privado:

```bash
python3 - "$PRIVATE_DIR" <<'PY'
import sys
from pathlib import Path
from urllib.parse import quote

private_dir = Path(sys.argv[1])
token = quote((private_dir / "redis-token").read_text().strip(), safe="")
endpoint = (private_dir / "redis-endpoint").read_text().strip()
(private_dir / "evaluation.env").write_text(
    f"REDIS_URL=rediss://:{token}@{endpoint}:6379\n"
)
PY
chmod 600 "$PRIVATE_DIR/evaluation.env"
```

### 11.3 Atualizar ConfigMaps com outputs deste ambiente

O script abaixo coleta `sqs_queue_url` e `dynamodb_table_name` diretamente do
state Terraform e atualiza os valores `AWS_REGION`, `AWS_SQS_URL` e
`AWS_DYNAMODB_TABLE` em `analytics-configmap.yaml` e
`evaluation-configmap.yaml`. Ele não consulta nem exibe outputs secretos.

Execute a partir da raiz do projeto, depois de definir `PROJECT_ROOT` e
`AWS_REGION` e de concluir o `terraform apply`:

```bash
set -euo pipefail
: "${PROJECT_ROOT:?Defina PROJECT_ROOT para a raiz do projeto}"
: "${AWS_REGION:?Defina AWS_REGION para a região deste ambiente}"

TF_DIR="$PROJECT_ROOT/terraform"
SQS_URL="$(terraform -chdir="$TF_DIR" output -raw sqs_queue_url)"
DYNAMODB_TABLE="$(terraform -chdir="$TF_DIR" output -raw dynamodb_table_name)"

AWS_REGION="$AWS_REGION" \
SQS_URL="$SQS_URL" \
DYNAMODB_TABLE="$DYNAMODB_TABLE" \
python3 - "$PROJECT_ROOT" <<'PY'
import json
import os
import re
import sys
from pathlib import Path

project_root = Path(sys.argv[1])
values = {
    "AWS_REGION": os.environ["AWS_REGION"],
    "AWS_SQS_URL": os.environ["SQS_URL"],
    "AWS_DYNAMODB_TABLE": os.environ["DYNAMODB_TABLE"],
}
if any(not value for value in values.values()):
    raise SystemExit("Região, URL SQS e nome da tabela devem estar preenchidos.")
manifest_paths = (
    project_root / "k8s/configmaps/analytics-configmap.yaml",
    project_root / "k8s/configmaps/evaluation-configmap.yaml",
)
updated_manifests = []

for manifest_path in manifest_paths:
    content = manifest_path.read_text()
    for key, value in values.items():
        pattern = re.compile(rf"(?m)^(  {re.escape(key)}:[ \t]*).*$")
        content, replacements = pattern.subn(
            lambda match: match.group(1) + json.dumps(value),
            content,
        )
        if replacements != 1:
            raise SystemExit(
                f"Esperava encontrar uma entrada '{key}' em {manifest_path}; "
                f"encontradas: {replacements}. Nenhum manifesto foi gravado."
            )
    updated_manifests.append((manifest_path, content))

for manifest_path, content in updated_manifests:
    manifest_path.write_text(content)
    print(f"ConfigMap atualizado: {manifest_path}")
PY
```

Valide as alterações antes de aplicar os ConfigMaps:

```bash
git -C "$PROJECT_ROOT" diff -- \
  k8s/configmaps/analytics-configmap.yaml \
  k8s/configmaps/evaluation-configmap.yaml
grep -nE 'AWS_REGION|AWS_SQS_URL|AWS_DYNAMODB_TABLE|AWS_ENDPOINT_URL' \
  "$PROJECT_ROOT/k8s/configmaps/analytics-configmap.yaml" \
  "$PROJECT_ROOT/k8s/configmaps/evaluation-configmap.yaml"
```

Confira que a fila pertence à conta/região esperadas, que a tabela é a deste
ambiente e que não há `AWS_ENDPOINT_URL` apontando para DynamoDB Local.
Preserve as URLs internas dos serviços Kubernetes, por exemplo
`http://flag-service.flag` e `http://targeting-service.targeting`.

### 11.4 Criar namespaces e Secrets Kubernetes

Contrato dos Secrets:

| Namespace | Secret | Conteúdo |
|---|---|---|
| `auth` | `auth-secrets` | `DATABASE_URL`, `MASTER_KEY` |
| `flag` | `flag-secrets` | `DATABASE_URL` |
| `targeting` | `targeting-secrets` | `DATABASE_URL` |
| `evaluation` | `evaluation-secrets` | `REDIS_URL`; `SERVICE_API_KEY` será adicionada após iniciar auth |
| `analytics` | `analytics-secrets` | Pode ser vazio; ConfigMap e IRSA fornecem o restante |

Crie namespaces, ConfigMaps e Secrets. Não mostre o conteúdo do Secret
codificado em Base64: Base64 não é criptografia.

```bash
kubectl apply -f "$PROJECT_ROOT/k8s/namespaces"
kubectl apply -f "$PROJECT_ROOT/k8s/configmaps"

kubectl create secret generic auth-secrets -n auth \
  --from-env-file="$PRIVATE_DIR/auth.env" --dry-run=client -o yaml \
  | kubectl apply -f -
kubectl create secret generic flag-secrets -n flag \
  --from-env-file="$PRIVATE_DIR/flag.env" --dry-run=client -o yaml \
  | kubectl apply -f -
kubectl create secret generic targeting-secrets -n targeting \
  --from-env-file="$PRIVATE_DIR/targeting.env" --dry-run=client -o yaml \
  | kubectl apply -f -
kubectl create secret generic evaluation-secrets -n evaluation \
  --from-env-file="$PRIVATE_DIR/evaluation.env" --dry-run=client -o yaml \
  | kubectl apply -f -
kubectl create secret generic analytics-secrets -n analytics \
  --dry-run=client -o yaml | kubectl apply -f -
```

Não aplique `k8s/secrets/*.yaml`: manifests antigos podem conter credenciais
obsoletas ou uma chave de desenvolvimento.

### 11.5 Inicializar schemas PostgreSQL uma vez

As imagens não criam automaticamente todas as tabelas. Execute os SQLs
`services/auth-service/db/init.sql`,
`services/flag-service/db/init.sql` e
`services/targeting-service/db/init.sql` em pods temporários dentro da VPC.
Não repita se já foram executados com sucesso.

Exemplo para auth:

```bash
kubectl run db-init -n auth --image=postgres:16-alpine --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"db-init","image":"postgres:16-alpine","command":["sleep","3600"],"envFrom":[{"secretRef":{"name":"auth-secrets"}}]}]}}'
kubectl wait -n auth --for=condition=Ready pod/db-init --timeout=120s
kubectl exec -i -n auth db-init -- sh -c \
  'psql "$DATABASE_URL" -v ON_ERROR_STOP=1' \
  < "$PROJECT_ROOT/services/auth-service/db/init.sql"
kubectl delete pod db-init -n auth
```

Repita substituindo namespace, Secret e SQL:

| Namespace | Secret | Arquivo SQL |
|---|---|---|
| `flag` | `flag-secrets` | `services/flag-service/db/init.sql` |
| `targeting` | `targeting-secrets` | `services/targeting-service/db/init.sql` |

Confirme sucesso pelo resultado `CREATE TABLE`/`CREATE FUNCTION`/`CREATE
TRIGGER`. Avisos `trigger ... does not exist, skipping` durante `DROP TRIGGER
IF EXISTS` são esperados na primeira execução. Se o comando SQL falhar, remova
o pod temporário e corrija a conexão/Secret antes de continuar. O SQL de auth
cria a tabela `api_keys`; não semeie chave de desenvolvimento.

Se RDS der timeout, confira Security Groups e rotas: ingressos em TCP 5432
devem permitir somente o Security Group associado aos nodes/pods autorizados.
O Redis exige TLS em TCP 6379. Nunca abra RDS/Redis para `0.0.0.0/0`.

## 12. Implantar serviços e criar a chave de evaluation

### 12.1 Iniciar auth e validar

```bash
kubectl apply -f "$PROJECT_ROOT/k8s/services"
kubectl apply -f "$PROJECT_ROOT/k8s/deployments/auth-deployment.yaml"
kubectl rollout status deployment/auth -n auth --timeout=180s
kubectl get pods,svc,endpoints -n auth
kubectl logs -n auth deployment/auth --all-containers=true --tail=100
```

Os logs devem mostrar conexão PostgreSQL e o servidor escutando na porta
8001. Abra um `port-forward` em um terminal próprio e deixe-o ativo:

```bash
kubectl port-forward -n auth svc/auth-service 8001:80
```

Em outro terminal:

```bash
curl --fail-with-body --show-error http://localhost:8001/health
```

Resposta esperada: `{"status":"ok"}`. O serviço também testa a conexão RDS
antes de iniciar, mas esse endpoint não verifica por si só a existência da
tabela `api_keys`; o SQL de auth precisa ter terminado com sucesso.

### 12.2 Criar uma chave de serviço sem exibi-la

No terminal do port-forward, não execute outros comandos. No terminal de
trabalho, carregue a `MASTER_KEY` sem eco e grave a resposta em arquivo
privado. O servidor retorna a chave em texto puro uma única vez.

```bash
read -rsp "MASTER_KEY do ambiente: " MASTER_KEY
printf '\n'
umask 077
KEY_RESPONSE="$PRIVATE_DIR/evaluation-key-response.json"
HTTP_STATUS="$(
  printf 'header = "Authorization: Bearer %s"\n' "$MASTER_KEY" \
    | curl --config - --silent --show-error \
      --output "$KEY_RESPONSE" --write-out '%{http_code}' \
      -X POST http://localhost:8001/admin/keys \
      -H 'Content-Type: application/json' \
      --data '{"name":"evaluation-service"}'
)"
unset MASTER_KEY
```

Só prossiga se `HTTP_STATUS` for `201` e o JSON tiver campo `key` não vazio:

```bash
if [ "$HTTP_STATUS" != "201" ]; then
  echo "Criação da chave falhou (HTTP $HTTP_STATUS). Consulte o corpo privado da resposta."
  exit 1
fi
jq -er '.key' "$KEY_RESPONSE" > "$PRIVATE_DIR/service-api-key"
chmod 600 "$PRIVATE_DIR/service-api-key"
```

Adicione a chave ao arquivo privado do evaluation e aplique o Secret:

```bash
printf 'SERVICE_API_KEY=%s\n' "$(cat "$PRIVATE_DIR/service-api-key")" \
  >> "$PRIVATE_DIR/evaluation.env"
chmod 600 "$PRIVATE_DIR/evaluation.env"

kubectl create secret generic evaluation-secrets -n evaluation \
  --from-env-file="$PRIVATE_DIR/evaluation.env" --dry-run=client -o yaml \
  | kubectl apply -f -
```

Não reutilize uma chave local e não crie uma nova a cada teste. Confirme
somente a presença da chave, sem imprimir seu valor:

```bash
kubectl get secret evaluation-secrets -n evaluation -o json \
  | jq -e '.data.SERVICE_API_KEY and (.data.SERVICE_API_KEY | length > 0)' \
  >/dev/null && echo "SERVICE_API_KEY presente"
```

### 12.3 Iniciar os demais serviços

Confirme que images, ConfigMaps, Secrets, ServiceAccounts e schemas estão
prontos. Aplique os Deployments:

```bash
for service in flag targeting evaluation analytics; do
  kubectl apply -f "$PROJECT_ROOT/k8s/deployments/$service-deployment.yaml" || exit 1
  kubectl rollout status "deployment/$service" -n "$service" --timeout=180s || exit 1
done
kubectl get pods -A
```

Se a `SERVICE_API_KEY` foi inserida após o Deployment evaluation iniciar,
reinicie-o para carregar o Secret:

```bash
kubectl rollout restart deployment/evaluation -n evaluation
kubectl rollout status deployment/evaluation -n evaluation --timeout=180s
```

Todos os pods da aplicação devem estar `Running` e `Ready`. Rollout concluído
não substitui a validação funcional.

## 13. Teste ponta a ponta da aplicação

### 13.1 Abrir os encaminhamentos locais

Abra um terminal por serviço e mantenha cada comando rodando:

```bash
kubectl port-forward -n flag svc/flag-service 8002:80 --address 127.0.0.1
```

```bash
kubectl port-forward -n targeting svc/targeting-service 8003:80 --address 127.0.0.1
```

```bash
kubectl port-forward -n evaluation svc/evaluation-service 8004:80 --address 127.0.0.1
```

`kubectl port-forward` é uma sessão temporária; não rode os testes no terminal
que o mantém ativo. Se o terminal fechar ou aparecer `lost connection to pod`,
confirme saúde dos pods e reabra o encaminhamento.

### 13.2 Criar flag, regra e avaliar

Cole o bloco completo em um terminal Bash de trabalho. O script usa uma
subshell para que uma falha não feche o terminal interativo. Cria dados reais
no ambiente AWS; usa nome único e não imprime a chave.

```bash
bash <<'BASH'
set -euo pipefail

API_KEY="$(kubectl get secret evaluation-secrets -n evaluation \
  -o jsonpath='{.data.SERVICE_API_KEY}' | base64 --decode)"
test -n "$API_KEY" || { echo "SERVICE_API_KEY ausente"; exit 1; }

RUN_ID="$(date +%s%N)"
FLAG_NAME="validacao-aws-$RUN_ID"
USER_ID="usuario-$RUN_ID"

api_curl() {
  local url="$1"
  shift
  printf 'header = "Authorization: Bearer %s"\n' "$API_KEY" \
    | curl --config - --fail-with-body --show-error --silent \
      --write-out '\nHTTP %{http_code}\n' "$@" "$url"
}

echo "Criando flag $FLAG_NAME"
api_curl http://localhost:8002/flags \
  -X POST -H 'Content-Type: application/json' \
  --data "{\"name\":\"$FLAG_NAME\",\"description\":\"Teste ponta a ponta EKS\",\"is_enabled\":true}"

echo "Criando regra"
api_curl http://localhost:8003/rules \
  -X POST -H 'Content-Type: application/json' \
  --data "{\"flag_name\":\"$FLAG_NAME\",\"is_enabled\":true,\"rules\":{\"type\":\"PERCENTAGE\",\"value\":100}}"

echo "Avaliando flag"
RESPONSE="$(curl --fail-with-body --show-error --silent \
  "http://localhost:8004/evaluate?user_id=$USER_ID&flag_name=$FLAG_NAME")"
printf '%s\n' "$RESPONSE" | jq .
printf '%s\n' "$RESPONSE" | jq -e '.result == true' >/dev/null

echo "Segunda avaliação para gerar outro evento"
curl --fail-with-body --show-error --silent \
  "http://localhost:8004/evaluate?user_id=$USER_ID&flag_name=$FLAG_NAME" \
  | jq .

echo "Teste de API concluído. Consulte DynamoDB com:"
printf 'FLAG_NAME=%s\nUSER_ID=%s\n' "$FLAG_NAME" "$USER_ID"
unset API_KEY
BASH
```

Esperado: flag e regra criadas (normalmente HTTP 201) e avaliações HTTP 200
com `result: true`. Se uma criação retornar 401/403, pare: verifique a chave
do Secret e a conectividade do auth; não crie outra chave às cegas.

### 13.3 Confirmar SQS -> analytics -> DynamoDB

Confira os logs do worker:

```bash
kubectl logs -n analytics deployment/analytics \
  --all-containers=true --since=10m
```

Procure `Recebidas`, `Processando mensagem` e `salvo no DynamoDB`. Aguarde até
30 segundos se ainda não houver mensagem; o worker usa long polling. A
avaliação responde antes do envio assíncrono ao SQS.

Consulte a tabela filtrando pelo usuário e flag retornados pelo bloco:

```bash
read -rp "USER_ID do teste: " USER_ID
read -rp "FLAG_NAME do teste: " FLAG_NAME
TABLE_NAME="$(terraform -chdir="$PROJECT_ROOT/terraform" \
  output -raw dynamodb_table_name)"
VALUES="$(jq -cn --arg uid "$USER_ID" --arg flag "$FLAG_NAME" \
  '{":uid":{"S":$uid},":flag":{"S":$flag}}')"

aws dynamodb scan \
  --table-name "$TABLE_NAME" --region "$AWS_REGION" --consistent-read \
  --filter-expression '#u = :uid AND #f = :flag' \
  --expression-attribute-names \
    '{"#u":"user_id","#f":"flag_name","#id":"eventId","#r":"result","#t":"timestamp"}' \
  --expression-attribute-values "$VALUES" \
  --projection-expression '#id,#u,#f,#r,#t' \
  --query 'Items' --output json
```

Resultado esperado: pelo menos um item com `eventId`, `timestamp`, `user_id`,
`flag_name` e `result: true`. A chave da tabela é `eventId` (partição) e
`timestamp` (ordenação). O código analytics deve gravar com esses nomes exatos.

Se vier `[]`, consulte os logs do analytics. A mensagem
`Missing the key eventId` indica imagem antiga ou contrato da tabela diferente;
`AccessDenied` indica role/policy IAM; ausência de mensagens recebidas indica
fila/URL/identidade SQS incorreta. Confirme a imagem ativa:

```bash
kubectl get deployment analytics -n analytics \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="analytics")].image}{"\n"}'
```

O valor deve corresponder à tag publicada que contém a correção de `eventId`.

## 14. Verificações gerais de saúde e diagnóstico

### 14.1 Cluster e aplicações

```bash
kubectl config current-context
kubectl cluster-info
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl get events -A --sort-by=.lastTimestamp | tail -40
kubectl get services,endpoints -A
```

Expectativas:

- Nodes `Ready`.
- Pods de aplicação `Running` e todos os containers `Ready`.
- Services com Endpoints correspondentes.
- Sem novos `BackOff`, `FailedMount`, `ImagePullBackOff`, `Pending` ou
  reinícios contínuos.

Comandos de diagnóstico (substitua placeholders pelos nomes reais):

```bash
kubectl describe pod -n NAMESPACE POD
kubectl logs -n NAMESPACE deployment/DEPLOYMENT --all-containers=true --tail=100
kubectl logs -n NAMESPACE deployment/DEPLOYMENT \
  --all-containers=true --previous --tail=100
kubectl get events -n NAMESPACE --sort-by=.lastTimestamp
```

`NAMESPACE` e `POD` são placeholders; não os copie literalmente. Se
`kubectl cluster-info` falhar, atualize kubeconfig e confirme conta/região.
`error: lost connection to pod` geralmente significa que o `port-forward`
perdeu seu pod ou conexão: consulte eventos/pods e reinicie somente o
encaminhamento após confirmar que o pod está pronto.

### 14.2 Erros que ocorreram neste projeto

| Mensagem | Significado e ação |
|---|---|
| `relation "flags" does not exist` | Inicialize o SQL do serviço flag no RDS `flagdb`. |
| `relation "targeting_rules" does not exist` | Inicialize o SQL de targeting. |
| Evaluation `HTTP 502` após erros dos serviços | Verifique logs/SQL/Service e auth; pode ser consequência de tabela ausente. |
| `Missing the key eventId` no `PutItem` | O item precisa usar atributo `eventId`, não `event_id`; confirme imagem e chave da tabela. |
| `AccessDenied` em SQS/DynamoDB | Revise ServiceAccount, IRSA trust e policy limitada ao ARN correto. |
| `connection timed out` no RDS/Redis | Verifique SG dos nodes, rotas, DNS, porta e DSN/`rediss://`; não abra acesso público. |
| `connection refused` no port-forward | Processo/porta destino, pod, endpoints e logs; confirme que o Service aponta à porta correta. |
| `ImagePullBackOff` | URL/tag ECR, arquitetura `amd64`/`arm64`, acesso de pull dos nodes. |
| `PVC Pending` | EBS CSI, gp3, zonas e eventos; confirme o controller, não apenas os pods `ebs-csi-node`. |
| `Cannot iterate over null` no script Argo/monitoring | O manifesto multi-documento precisa ser agrupado como lista JSON; use o script corrigido deste projeto. |
| `traces export ... localhost:4318 connection refused` | Não há collector no próprio pod; traces não são exportados. Não significa, sozinho, falha de aplicação/SQS/DynamoDB. |
| `No resources found` ao listar Applications | Applications ainda não foram criadas; isso não comprova falha da CRD ou do ArgoCD. |

## 15. Instalar ArgoCD (opcional para deploy manual)

ArgoCD é opcional para quem mantém `kubectl apply` manual, mas necessário para
GitOps e usado pelo script de monitoramento. Confirme versão EKS e escolha um
chart compatível, sem assumir que a versão mais recente é apropriada:

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm search repo argo/argo-cd --versions | head
read -rp "Versão compatível do chart argo-cd: " ARGO_CHART_VERSION
helm show chart argo/argo-cd --version "$ARGO_CHART_VERSION"
helm upgrade --install argocd argo/argo-cd \
  --version "$ARGO_CHART_VERSION" --namespace argocd --create-namespace \
  --wait --timeout 15m
kubectl wait --for=condition=Established \
  crd/applications.argoproj.io --timeout=120s
kubectl get pods -n argocd
```

Confirme os pods `Ready`. Para a senha inicial:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 --decode
printf '\n'
```

Usuário inicial `admin`. Mantenha a senha privada e troque-a após o primeiro
login. Acesse localmente:

```bash
kubectl port-forward -n argocd svc/argocd-server 8080:443
```

Abra `https://localhost:8080`. Não publique ArgoCD sem autenticação e TLS
adequados.

### 15.1 GitOps exige fonte Git correta

ArgoCD lê o Git remoto, não alterações locais ainda não publicadas. Antes de
criar/sincronizar Applications:

- Ajuste `repoURL`, branch (`targetRevision`) e `path` em
  `k8s/argocd/*.yaml` para o repositório e diretório reais.
- Publique no remoto as alterações que devem ser reconciliadas.
- Exclua Secrets reais e manifests antigos do escopo de sincronização.
- Escolha uma Application ou várias por serviço; não deixe dois
  reconciliadores controlando os mesmos objetos.
- Não mantenha `kubectl apply` e auto-sync do ArgoCD gerenciando
  simultaneamente os mesmos recursos.

## 16. Instalar monitoramento (opcional)

Faça isso somente após a aplicação funcionar, EBS CSI estar saudável, `gp3`
existir e ArgoCD estar pronto. Os charts podem criar PVCs de 10 GiB para
Prometheus, Grafana e Loki; valide capacidade e custo antes.

**Revise antes de executar:** `k8s/argocd/argocd-monitoring-apps.yaml` ainda
precisa apontar para o repositório/branch/path Git corretos. O valor inline
`adminPassword: "admin123"` do Grafana é inseguro: substitua por integração
com Kubernetes Secret apropriado antes de publicar/sincronizar; não grave uma
senha real no Git. Revise também os charts e os seus values na versão
escolhida.

Os ServiceMonitors existentes podem pressupor endpoints Spring Boot
`/actuator/prometheus`, enquanto os serviços atuais são Go/Flask. Até que
exponham métricas compatíveis ou que os monitors sejam adaptados, isso pode
impedir métricas da aplicação sem significar que os pods principais falharam.

Confirme pré-requisitos:

```bash
kubectl get csidriver ebs.csi.aws.com
kubectl get storageclass gp3
kubectl get crd applications.argoproj.io
kubectl get pods -n argocd
```

Após corrigir e publicar a fonte Git e remover a senha insegura:

```bash
bash "$PROJECT_ROOT/k8s/monitoring/install-monitoring.sh"
```

O script registra primeiro as Applications dos charts, espera até dez minutos
pela CRD ServiceMonitor, aplica os manifests locais e registra a Application
de manifests Git. Ele não comprova que todas as Applications ficaram
saudáveis. Verifique:

```bash
kubectl get applications -n argocd
kubectl get pods,pvc,svc -n monitoring
kubectl get events -n monitoring --sort-by=.lastTimestamp
```

Avance somente quando Applications estiverem `Synced`/`Healthy`, pods
`Ready` e PVCs `Bound`. Se o script parar aguardando a CRD, consulte:

```bash
kubectl describe application prometheus-helm -n argocd
kubectl get pods -n monitoring
kubectl get events -n monitoring --sort-by=.lastTimestamp
```

Acesso Grafana local:

```bash
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
```

Abra `http://localhost:3000`. Use a credencial configurada com segurança no
chart/Secret; não assuma que a senha padrão é segura.

## 17. Encerramento completo e prevenção de cobranças

Fechar o WSL, parar Docker, encerrar `port-forward` ou fechar o VS Code **não
remove recursos AWS nem interrompe custos**. O encerramento precisa considerar
recursos Terraform e recursos Kubernetes/IAM criados fora do Terraform.

### 17.1 Preservar dados e localizar recursos

Antes de destruir:

1. Decida se precisa preservar bancos, itens DynamoDB, mensagens SQS, imagens
   ECR ou logs.
2. Exporte/backupe os dados necessários. O RDS está configurado sem snapshot
   final automático e sem proteção contra exclusão; a destruição pode apagar
   dados.
3. Guarde cópia protegida dos states, que podem conter segredos:

   ```bash
   umask 077
   terraform -chdir="$PROJECT_ROOT/terraform" state pull \
     > "$PRIVATE_DIR/main.tfstate.backup"
   chmod 600 "$PRIVATE_DIR/main.tfstate.backup"
   ```

4. Identifique ALBs, EBS volumes/PVCs, snapshots, IPs, filas, tabelas, imagens
   e roles criados manualmente/por `eksctl`. Não exclua recursos de outros
   projetos ou ambientes.

### 17.2 Remover recursos do cluster antes do Terraform

1. Pare os `port-forward` com `Ctrl+C`.
2. Se instalou monitoramento pelo ArgoCD, remova primeiro as Applications
   correspondentes após revisar os recursos que serão removidos:

   ```bash
   kubectl get applications -n argocd
   kubectl delete application prometheus-helm loki-helm monitoring-stack \
     -n argocd
   ```

   Aguarde a remoção/estado final; não prossiga se estiver preso em finalizer.
   Confirme PVCs, PVs, services e LoadBalancers restantes. Dados em volumes
   podem ser removidos conforme a reclaim policy `Delete`.

3. Se instalou ArgoCD via Helm e não precisa mais dele:

   ```bash
   helm uninstall argocd -n argocd
   ```

   Confirme que não há Applications/reconciliações pendentes.

4. Remova serviços ou recursos opcionais criados fora do Terraform
   (Gateway/ALB Controller, HPA, KEDA etc.) enquanto os controllers ainda
   existem. Aguarde a exclusão de ALBs e recursos AWS associados. Não aplique
   indiscriminadamente `kubectl delete -f k8s`.

5. Confira as associações criadas por `eksctl`:

   ```bash
   eksctl get iamserviceaccount --cluster "$EKS_CLUSTER" --region "$AWS_REGION"
   ```

   Se criou evaluation/analytics por `eksctl`, remova as associações
   específicas antes de destruir o cluster:

   ```bash
   eksctl delete iamserviceaccount --cluster "$EKS_CLUSTER" \
     --region "$AWS_REGION" --namespace evaluation \
     --name evaluation-service-account
   eksctl delete iamserviceaccount --cluster "$EKS_CLUSTER" \
     --region "$AWS_REGION" --namespace analytics \
     --name analytics-service-account
   ```

   O EBS CSI addon/role também foi criado fora do Terraform. Remova o addon
   enquanto o cluster existe e confirme o resultado:

   ```bash
   aws eks delete-addon --cluster-name "$EKS_CLUSTER" \
     --region "$AWS_REGION" --addon-name aws-ebs-csi-driver
   ```

   Depois de remover workloads e addon, inspecione e remova somente as roles,
   policies e stacks CloudFormation específicas deste cluster. Não apague uma
   policy gerenciada enquanto estiver anexada a roles ainda usadas.

### 17.3 Destruir o projeto Terraform

Revise o plano de destruição:

```bash
terraform -chdir="$PROJECT_ROOT/terraform" plan -destroy
```

Confirme state, conta, região, nomes e recursos. Somente após aprovação:

```bash
terraform -chdir="$PROJECT_ROOT/terraform" destroy
```

Confirme no console/CLI que o cluster, RDS, Redis, NAT, ECR, SQS, DynamoDB,
volumes, endereços e recursos relacionados foram removidos. Se o Terraform
falhar por dependências criadas por controllers, identifique e remova
especificamente a dependência; não use exclusão ampla.

### 17.4 Remover backend apenas quando não for mais necessário

O state do projeto principal está no bucket S3 do bootstrap. Preserve uma
cópia protegida do state antes de remover esse bucket. Só destrua o bootstrap
quando:

- O projeto principal já foi destruído.
- Nenhum outro workspace/projeto usa esse bucket.
- States/backups necessários foram guardados.

```bash
terraform -chdir="$PROJECT_ROOT/terraform/bootstrap" plan -destroy \
  -var="bucket_name=$TF_STATE_BUCKET" -var="region=$AWS_REGION"
```

O bootstrap tem `force_destroy`: o apply/remove apaga objetos e versões do
bucket, inclusive o state remoto. Se confirmou que não precisa mais dele:

```bash
terraform -chdir="$PROJECT_ROOT/terraform/bootstrap" destroy \
  -var="bucket_name=$TF_STATE_BUCKET" -var="region=$AWS_REGION"
```

### 17.5 Revisão final de cobrança e ambiente

Confirme na conta AWS/região corretas que não restaram:

- EKS, nodes, NAT Gateways, Elastic IPs ou LoadBalancers.
- Instâncias RDS, Redis, snapshots ou backups que decidiu excluir.
- Volumes EBS/PVs, snapshots e interfaces de rede órfãs.
- Repositórios/imagens ECR, filas SQS, DynamoDB ou recursos de monitoramento.
- Roles/policies IAM e stacks CloudFormation `eksctl` específicos do projeto.
- Bucket S3 de state somente se sua destruição foi explicitamente decidida.

Mantenha os backups necessários. Quando não precisar mais dos arquivos locais
de credenciais, remova apenas os arquivos específicos dentro da pasta privada,
após confirmar backups e ausência de dependências:

```bash
ls -la "$PRIVATE_DIR"
```

Não remova a pasta inteira sem conferir se contém dados de outro trabalho.

## 18. Checklist de conclusão

- [ ] Conta AWS, identidade e região conferidas antes de provisionar.
- [ ] State Terraform remoto existente e protegido.
- [ ] Plano revisado antes de cada `apply`/`destroy`.
- [ ] Cluster e nodes EKS saudáveis.
- [ ] EBS CSI saudável e `gp3` disponível se houver PVCs.
- [ ] Imagens corretas publicadas no ECR e referenciadas nos Deployments.
- [ ] Evaluation/analytics usam roles IRSA específicas, sem access keys em Secrets.
- [ ] ConfigMaps usam outputs deste ambiente; Secrets não estão no Git.
- [ ] SQLs de auth, flag e targeting executados sem erro.
- [ ] Pods prontos; flag e regra criadas; evaluation retornou `result: true`.
- [ ] Evento do teste apareceu em `ToggleMasterAnalytics` com `eventId`.
- [ ] Avisos de tracing compreendidos; não confundidos com falha do fluxo principal.
- [ ] ArgoCD/monitoramento instalados somente após revisar Git, senha e charts.
- [ ] Recursos extras e Terraform removidos ao encerrar; nenhum recurso cobrado
      foi deixado sem decisão consciente.
