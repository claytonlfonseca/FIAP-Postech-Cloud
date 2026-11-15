#!/usr/bin/env bash
set -Eeuo pipefail

TARGET_USER_HINT="${1:-}"
POLICY_NAME="ToggleMasterProjectProvisioner"
PROFILE_NAME="${AWS_PROFILE:-${AWS_DEFAULT_PROFILE:-default}}"

if ! command -v aws >/dev/null 2>&1; then
  echo "Erro: AWS CLI não encontrado." >&2
  exit 1
fi

aws_cli() {
  aws --profile "$PROFILE_NAME" "$@"
}

if ! REGION="$(aws_cli configure get region 2>/dev/null)" || [[ -z "$REGION" || "$REGION" == "None" ]]; then
  echo "Erro: o profile AWS '${PROFILE_NAME}' não possui uma região configurada." >&2
  echo "Configure a região no profile e execute novamente." >&2
  exit 1
fi

if [[ -r /dev/tty && -w /dev/tty ]]; then
  if [[ -n "$TARGET_USER_HINT" ]]; then
    if ! read -r -p "Usuário IAM que receberá a policy [${TARGET_USER_HINT}]: " TARGET_USER </dev/tty; then
      echo "Erro: não foi possível ler o nome do usuário IAM." >&2
      exit 1
    fi
    TARGET_USER="${TARGET_USER:-$TARGET_USER_HINT}"
  else
    if ! read -r -p "Digite o nome do usuário IAM que receberá a policy: " TARGET_USER </dev/tty; then
      echo "Erro: não foi possível ler o nome do usuário IAM." >&2
      exit 1
    fi
  fi
elif [[ -n "$TARGET_USER_HINT" ]]; then
  TARGET_USER="$TARGET_USER_HINT"
else
  echo "Erro: informe o usuário IAM como argumento quando executar sem terminal interativo." >&2
  exit 1
fi

if [[ -z "$TARGET_USER" ]]; then
  echo "Erro: o nome do usuário IAM não pode ficar vazio." >&2
  exit 1
fi

ACCOUNT_ID="$(aws_cli sts get-caller-identity --query Account --output text)"
CALLER_ARN="$(aws_cli sts get-caller-identity --query Arn --output text)"
STATE_BUCKET_NAME="togglemaster-tfstate-${ACCOUNT_ID}"
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"

if ! aws_cli iam get-user --user-name "$TARGET_USER" >/dev/null; then
  echo "Erro: o usuário IAM '${TARGET_USER}' não existe na conta ${ACCOUNT_ID}." >&2
  exit 1
fi

if aws_cli iam get-policy --policy-arn "$POLICY_ARN" >/dev/null 2>&1; then
  ATTACHED_POLICY="$(aws_cli iam list-attached-user-policies \
    --user-name "$TARGET_USER" \
    --query "AttachedPolicies[?PolicyArn=='${POLICY_ARN}'].PolicyArn | [0]" \
    --output text)"

  if [[ "$ATTACHED_POLICY" == "$POLICY_ARN" ]]; then
    echo "A policy ${POLICY_NAME} já está anexada a ${TARGET_USER}."
    echo "Este script não altera policies existentes; peça a um administrador IAM para publicar uma nova versão."
    exit 0
  fi

  echo "Erro: a policy ${POLICY_ARN} já existe, mas não está anexada a ${TARGET_USER}." >&2
  echo "Inspecione a policy existente antes de anexá-la ou alterá-la." >&2
  exit 1
fi

POLICY_FILE="$(mktemp)"
trap 'rm -f "$POLICY_FILE"' EXIT

cat >"$POLICY_FILE" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "RegionScoped",
      "Effect": "Allow",
      "Action": [
        "autoscaling:Describe*",
        "dynamodb:*",
        "ec2:*",
        "ecr:*",
        "eks:*",
        "elasticache:*",
        "rds:*",
        "sqs:*",
        "logs:*",
        "secretsmanager:CreateSecret"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "${REGION}"
        }
      }
    },
    {
      "Sid": "CloudFormation",
      "Effect": "Allow",
      "Action": [
        "cloudformation:CancelUpdateStack",
        "cloudformation:ContinueUpdateRollback",
        "cloudformation:CreateChangeSet",
        "cloudformation:CreateStack",
        "cloudformation:DeleteChangeSet",
        "cloudformation:DeleteStack",
        "cloudformation:DescribeChangeSet",
        "cloudformation:DescribeStackEvents",
        "cloudformation:DescribeStackResources",
        "cloudformation:DescribeStacks",
        "cloudformation:ExecuteChangeSet",
        "cloudformation:GetTemplate",
        "cloudformation:GetTemplateSummary",
        "cloudformation:ListStackResources",
        "cloudformation:UpdateStack"
      ],
      "Resource": [
        "arn:aws:cloudformation:${REGION}:${ACCOUNT_ID}:stack/eksctl-*/*",
        "arn:aws:cloudformation:${REGION}:${ACCOUNT_ID}:stack/togglemaster-*/*"
      ]
    },
    {
      "Sid": "ListCloudFormationStacks",
      "Effect": "Allow",
      "Action": "cloudformation:ListStacks",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "${REGION}"
        }
      }
    },
    {
      "Sid": "S3Bucket",
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket",
        "s3:DeleteBucket",
        "s3:GetAccelerateConfiguration",
        "s3:GetBucketAcl",
        "s3:GetBucketCORS",
        "s3:GetBucketLocation",
        "s3:GetBucketLogging",
        "s3:GetBucketNotification",
        "s3:GetBucketObjectLockConfiguration",
        "s3:GetBucketOwnershipControls",
        "s3:GetBucketPolicy",
        "s3:GetBucketPolicyStatus",
        "s3:GetBucketPublicAccessBlock",
        "s3:GetBucketRequestPayment",
        "s3:GetBucketTagging",
        "s3:GetBucketVersioning",
        "s3:GetBucketWebsite",
        "s3:GetEncryptionConfiguration",
        "s3:GetLifecycleConfiguration",
        "s3:GetReplicationConfiguration",
        "s3:ListBucket",
        "s3:ListBucketVersions",
        "s3:PutBucketPublicAccessBlock",
        "s3:PutBucketTagging",
        "s3:PutBucketVersioning",
        "s3:PutEncryptionConfiguration"
      ],
      "Resource": "arn:aws:s3:::${STATE_BUCKET_NAME}"
    },
    {
      "Sid": "S3Objects",
      "Effect": "Allow",
      "Action": [
        "s3:DeleteObject",
        "s3:DeleteObjectVersion",
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::${STATE_BUCKET_NAME}/*"
    },
    {
      "Sid": "IAMRoles",
      "Effect": "Allow",
      "Action": [
        "iam:AttachRolePolicy",
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:DeleteRolePolicy",
        "iam:DetachRolePolicy",
        "iam:GetRolePolicy",
        "iam:ListAttachedRolePolicies",
        "iam:ListInstanceProfilesForRole",
        "iam:ListRolePolicies",
        "iam:ListRoleTags",
        "iam:PutRolePolicy",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:UpdateAssumeRolePolicy"
      ],
      "Resource": "*",
      "Condition": {
        "ArnLikeIfExists": {
          "iam:PolicyARN": [
            "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
            "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController",
            "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
            "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
            "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
            "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy",
            "arn:aws:iam::${ACCOUNT_ID}:policy/togglemaster-*"
          ]
        }
      }
    },
    {
      "Sid": "IAMGetRole",
      "Effect": "Allow",
      "Action": "iam:GetRole",
      "Resource": "*"
    },
    {
      "Sid": "IAMPassRole",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::${ACCOUNT_ID}:role/togglemaster-*",
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": [
            "eks.amazonaws.com",
            "ec2.amazonaws.com",
            "cloudformation.amazonaws.com"
          ]
        }
      }
    },
    {
      "Sid": "IAMServiceLinkedRole",
      "Effect": "Allow",
      "Action": "iam:CreateServiceLinkedRole",
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "iam:AWSServiceName": [
            "eks.amazonaws.com",
            "eks-nodegroup.amazonaws.com",
            "eks-fargate-pods.amazonaws.com",
            "elasticache.amazonaws.com",
            "elasticloadbalancing.amazonaws.com",
            "rds.amazonaws.com",
            "autoscaling.amazonaws.com"
          ]
        }
      }
    },
    {
      "Sid": "IAMPoliciesAndOIDC",
      "Effect": "Allow",
      "Action": [
        "iam:AddClientIDToOpenIDConnectProvider",
        "iam:CreateOpenIDConnectProvider",
        "iam:CreatePolicy",
        "iam:DeleteOpenIDConnectProvider",
        "iam:DeletePolicy",
        "iam:GetOpenIDConnectProvider",
        "iam:GetPolicy",
        "iam:GetPolicyVersion",
        "iam:ListEntitiesForPolicy",
        "iam:ListOpenIDConnectProviders",
        "iam:ListPolicies",
        "iam:ListRoles",
        "iam:RemoveClientIDFromOpenIDConnectProvider",
        "iam:TagOpenIDConnectProvider",
        "iam:UntagOpenIDConnectProvider",
        "iam:UpdateOpenIDConnectProviderThumbprint"
      ],
      "Resource": "*"
    },
    {
      "Sid": "SecretsAndKMS",
      "Effect": "Allow",
      "Action": [
        "kms:CreateGrant",
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:Encrypt",
        "kms:GenerateDataKey",
        "kms:ListAliases",
        "kms:ListKeys",
        "kms:ReEncrypt*",
        "secretsmanager:DescribeSecret",
        "secretsmanager:GetSecretValue",
        "secretsmanager:TagResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "GlobalReadOnly",
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*",
        "elasticloadbalancing:Describe*",
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    }
  ]
}
EOF

python3 - "$POLICY_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as policy_file:
    policy = json.load(policy_file)

with open(sys.argv[1], "w", encoding="utf-8") as policy_file:
    json.dump(policy, policy_file, separators=(",", ":"))
PY

POLICY_SIZE="$(wc -c <"$POLICY_FILE")"
if (( POLICY_SIZE > 6144 )); then
  echo "Erro: policy com ${POLICY_SIZE} bytes excede o limite IAM de 6144 caracteres." >&2
  exit 1
fi

echo "Conta AWS: ${ACCOUNT_ID}"
echo "Executado por: ${CALLER_ARN}"
echo "Usuário que receberá a policy: ${TARGET_USER}"
echo "Profile AWS: ${PROFILE_NAME}"
echo "Região autorizada: ${REGION}"
echo "Bucket de state autorizado: ${STATE_BUCKET_NAME}"
echo
echo "ATENÇÃO: a policy concede permissões elevadas de infraestrutura e IAM."
echo "As permissões S3 ficam limitadas ao bucket ${STATE_BUCKET_NAME}."
echo "IAM roles/policies, segredos e chaves KMS incluem permissões amplas (*)."
echo "Use somente em conta de laboratório e remova o acesso ao terminar."
if ! read -r -p "Digite APPLY para criar e anexar a policy: " CONFIRMATION; then
  echo "Erro: não foi possível ler a confirmação; nenhuma policy foi criada." >&2
  exit 1
fi

if [[ "$CONFIRMATION" != "APPLY" ]]; then
  echo "Cancelado; nenhuma policy foi criada ou anexada."
  exit 0
fi

POLICY_ARN="$(aws_cli iam create-policy \
  --policy-name "$POLICY_NAME" \
  --description "Permissões para provisionar e operar a infraestrutura AWS do ToggleMaster" \
  --policy-document "file://${POLICY_FILE}" \
  --query 'Policy.Arn' \
  --output text)"

aws_cli iam attach-user-policy \
  --user-name "$TARGET_USER" \
  --policy-arn "$POLICY_ARN"

echo "Policy criada e anexada a ${TARGET_USER}: ${POLICY_ARN}"
echo "Para remover o acesso: aws iam detach-user-policy --user-name ${TARGET_USER} --policy-arn ${POLICY_ARN}"
