# ToggleMaster — Fase 3 (Parte 1: Infraestrutura como Código)

Projeto Terraform que provisiona toda a infraestrutura AWS do ToggleMaster
(microsserviços `auth`, `flag`, `targeting`, `evaluation`, `analytics`),
substituindo a criação manual da Fase 2.

Conta AWS: `052005814846` (clayton.lfonseca) — **Conta pessoal (Opção B)**:
as IAM Roles/Policies do EKS (cluster e node group) são criadas pelo próprio
Terraform, sem depender de uma role pré-existente.

## Estrutura

```
terraform/
├── bootstrap/          # Cria o bucket S3 do backend remoto (rodar 1x, com state local)
├── modules/
│   ├── networking/      # VPC, subnets públicas/privadas, IGW, NAT, route tables
│   ├── eks/             # Cluster EKS + Node Group (cria as IAM Roles necessárias)
│   ├── rds/             # 3 instâncias RDS PostgreSQL (auth, flag, targeting)
│   ├── elasticache/     # Redis (replication group)
│   ├── dynamodb/        # Tabela ToggleMasterAnalytics
│   ├── sqs/              # Fila + DLQ
│   └── ecr/              # 5 repositórios (1 por microsserviço)
├── backend.tf           # Configuração do backend remoto S3
├── main.tf              # Orquestra os módulos
├── variables.tf / outputs.tf
└── terraform.tfvars.example
```

## Pré-requisitos

- Terraform >= 1.9
- AWS CLI configurado com credenciais da conta pessoal (`aws configure` ou
  variáveis `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`)
- O usuário/role usado para aplicar o Terraform precisa de permissão para
  criar recursos IAM (`iam:CreateRole`, `iam:AttachRolePolicy`, etc.), além
  dos serviços de rede, EKS, RDS, ElastiCache, DynamoDB, SQS e ECR.

## Passo 1 — Bootstrap do backend remoto (bucket S3)

O `terraform.tfstate` não pode ficar local. Como o backend S3 precisa existir
antes do `terraform init` do projeto principal, criamos o bucket em um projeto
separado, com state local:

```bash
cd terraform/bootstrap
terraform init
terraform apply -var="bucket_name=togglemaster-tfstate-052005814846"
```

Isso cria o bucket com versionamento, criptografia (SSE-S3) e bloqueio de
acesso público. Ajuste `bucket_name` em `bootstrap/variables.tf` se o nome já
estiver em uso (nomes de bucket S3 são globalmente únicos).

## Passo 2 — Projeto principal

O `backend.tf` já referencia o bucket criado no passo anterior e usa
`use_lockfile = true` (locking nativo do S3, sem precisar de tabela DynamoDB
para lock, conforme a Aula 2 de IaC).

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# ajuste os valores se necessário (região, tamanhos, nomes, etc.)

terraform init
terraform plan
terraform apply
```

## Tempo estimado de criação

O `terraform apply` do projeto principal leva, em média, **20-25 minutos**.
O gargalo é o EKS (cluster + node group); os demais recursos são criados em
paralelo pelo Terraform e não somam ao tempo total:

| Recurso | Tempo típico |
|---|---|
| Networking (VPC, subnets, IGW, NAT) | ~2 min |
| Cluster EKS (control plane) | ~10-15 min |
| Node Group EKS (nodes `Ready`) | ~3-5 min |
| Addons (vpc-cni, coredns, kube-proxy) | ~1-3 min |
| RDS PostgreSQL (3 instâncias, em paralelo) | ~5-10 min |
| ElastiCache Redis | ~5-10 min |
| DynamoDB / SQS / ECR / IAM | < 1 min |

O `terraform destroy` costuma levar ~15-20 min (o NAT Gateway e as ENIs do
EKS podem demorar um pouco mais para serem liberados).

## O que é provisionado

1. **Networking** (`modules/networking`): 1 VPC, 2 subnets públicas + 2
   privadas (em AZs distintas), Internet Gateway, 1 NAT Gateway (custo
   reduzido) e route tables públicas/privadas.
2. **EKS** (`modules/eks`): cluster Kubernetes 1.30 + Node Group (`t3.micro`,
   2 nodes — instância elegível para o Free Tier) nas subnets privadas. O
   módulo cria duas IAM Roles dedicadas:
   - Role do cluster, com `AmazonEKSClusterPolicy` e
     `AmazonEKSVPCResourceController`.
   - Role dos nodes, com `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`
     e `AmazonEC2ContainerRegistryReadOnly`.

   Addons `vpc-cni`, `coredns` e `kube-proxy` também são instalados.
3. **Bancos de Dados** (`modules/rds`, `modules/elasticache`,
   `modules/dynamodb`):
   - 3 instâncias RDS PostgreSQL (`auth`, `flag`, `targeting`), com
     `manage_master_user_password = true` — a AWS gera e gerencia a senha
     master no Secrets Manager automaticamente, evitando credenciais em
     texto plano.
   - 1 cluster ElastiCache Redis, com criptografia em trânsito/repouso e
     `auth_token` gerado via `random_password` (exposto apenas como output
     sensível).
   - 1 tabela DynamoDB `ToggleMasterAnalytics` (billing on-demand).
4. **Mensageria** (`modules/sqs`): fila `toggle-master-events` + Dead Letter
   Queue.
5. **Repositórios** (`modules/ecr`): 5 repositórios ECR (um por
   microsserviço), com scan de vulnerabilidades no push habilitado e política
   de lifecycle (mantém as últimas 10 imagens).

Todos os bancos de dados e o Redis ficam em subnets **privadas**, com
Security Groups que só liberam acesso a partir do Security Group do cluster
EKS.

## Troubleshooting (problemas já encontrados e resolvidos)

- **`AsgInstanceLaunchFailures: ... not eligible for Free Tier`**: a conta
  AWS usada tem uma restrição de conta nova que só permite lançar instâncias
  EC2 elegíveis para o Free Tier. Solução: usar `eks_node_instance_types =
  ["t3.micro"]` (já é o default). Se precisar de mais capacidade depois,
  solicite à AWS a remoção dessa restrição (Service Quotas / Support) antes
  de usar tipos maiores.
- **`DBName flag cannot be used. It is a reserved word for this engine`**:
  o Postgres/RDS trata `flag` como palavra reservada para o parâmetro
  `DBName`. Solução: renomeado para `flagdb` em `rds_databases` (variables.tf
  e tfvars). Ao adicionar novos serviços, evite nomes de banco muito
  genéricos/curtos.
- **`InvalidCredentialsException` / `StatusCode: 408` ao criar o ElastiCache**:
  erro transitório do lado da AWS (timeout interno do serviço), não é causado
  pelo código Terraform. Solução: rodar `terraform apply` novamente — como o
  Terraform é idempotente, ele só recria os recursos que falharam.

## Segurança (pontos já endereçados nesta parte)

- Nenhuma credencial de banco em texto plano: RDS usa `manage_master_user_password`.
- Buckets/objetos do state: versionado, criptografado e sem acesso público.
- ECR com scan de imagem habilitado (`scan_on_push`).
- Redis com criptografia em trânsito e em repouso.
- As IAM Roles do EKS seguem o princípio do menor privilégio, usando apenas
  as managed policies recomendadas pela AWS para cluster e node group.
