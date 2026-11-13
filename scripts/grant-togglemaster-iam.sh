#!/usr/bin/env bash
set -Eeuo pipefail

TARGET_USER="${1:-user_togglemaster}"
POLICY_NAME="ToggleMasterProjectProvisioner"
REGION="${AWS_REGION:-us-east-2}"

if ! command -v aws >/dev/null 2>&1; then
  echo "Erro: AWS CLI não encontrado no CloudShell." >&2
  exit 1
fi

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
CALLER_ARN="$(aws sts get-caller-identity --query Arn --output text)"
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"

if ! aws iam get-user --user-name "$TARGET_USER" >/dev/null; then
  echo "Erro: o usuário IAM '$TARGET_USER' não existe na conta ${ACCOUNT_ID}." >&2
  exit 1
fi

if aws iam get-policy --policy-arn "$POLICY_ARN" >/dev/null 2>&1; then
  ATTACHED_POLICY="$(aws iam list-attached-user-policies \
    --user-name "$TARGET_USER" \
    --query "AttachedPolicies[?PolicyArn=='${POLICY_ARN}'].PolicyArn | [0]" \
    --output text)"

  if [[ "$ATTACHED_POLICY" == "$POLICY_ARN" ]]; then
    echo "A policy ${POLICY_NAME} já está anexada a ${TARGET_USER}."
    echo "Este script não atualiza uma policy existente; peça a um administrador IAM para publicar uma nova versão."
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
      "Sid": "ManageProjectInfrastructureInSelectedRegion",
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "eks:*",
        "rds:*",
        "elasticache:*",
        "dynamodb:*",
        "sqs:*",
        "ecr:*",
        "autoscaling:Describe*"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "${REGION}"
        }
      }
    },
    {
      "Sid": "ManageTerraformStateBucket",
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket",
        "s3:DeleteBucket",
        "s3:GetAccelerateConfiguration",
        "s3:GetBucketAcl",
        "s3:GetBucketCORS",
        "s3:GetBucketLocation",
        "s3:GetBucketPolicy",
        "s3:GetBucketPolicyStatus",
        "s3:GetBucketTagging",
        "s3:PutBucketTagging",
        "s3:DeleteBucketTagging",
        "s3:GetBucketLogging",
        "s3:GetBucketNotification",
        "s3:GetBucketObjectLockConfiguration",
        "s3:GetBucketOwnershipControls",
        "s3:GetBucketPublicAccessBlock",
        "s3:GetBucketRequestPayment",
        "s3:GetBucketWebsite",
        "s3:GetBucketVersioning",
        "s3:PutBucketVersioning",
        "s3:GetEncryptionConfiguration",
        "s3:PutEncryptionConfiguration",
        "s3:GetLifecycleConfiguration",
        "s3:GetReplicationConfiguration",
        "s3:PutBucketPublicAccessBlock",
        "s3:ListBucket",
        "s3:ListBucketVersions"
      ],
      "Resource": "arn:aws:s3:::togglemaster-tfstate-*"
    },
    {
      "Sid": "ManageTerraformStateObjects",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:DeleteObjectVersion"
      ],
      "Resource": "arn:aws:s3:::togglemaster-tfstate-*/*"
    },
    {
      "Sid": "ManageProjectCloudFormationStacks",
      "Effect": "Allow",
      "Action": [
        "cloudformation:CreateStack",
        "cloudformation:UpdateStack",
        "cloudformation:DeleteStack",
        "cloudformation:DescribeStacks",
        "cloudformation:DescribeStackEvents",
        "cloudformation:DescribeStackResources",
        "cloudformation:GetTemplate",
        "cloudformation:GetTemplateSummary",
        "cloudformation:ListStackResources",
        "cloudformation:CreateChangeSet",
        "cloudformation:ExecuteChangeSet",
        "cloudformation:DeleteChangeSet",
        "cloudformation:DescribeChangeSet",
        "cloudformation:ContinueUpdateRollback",
        "cloudformation:CancelUpdateStack"
      ],
      "Resource": [
        "arn:aws:cloudformation:${REGION}:${ACCOUNT_ID}:stack/eksctl-*/*",
        "arn:aws:cloudformation:${REGION}:${ACCOUNT_ID}:stack/togglemaster-*/*"
      ]
    },
    {
      "Sid": "ListProjectCloudFormationStacks",
      "Effect": "Allow",
      "Action": [
        "cloudformation:ListStacks"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "${REGION}"
        }
      }
    },
    {
      "Sid": "ManageProjectIamRolesAndPolicies",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:UpdateAssumeRolePolicy",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:ListRoleTags",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:ListAttachedRolePolicies",
        "iam:ListRolePolicies",
        "iam:GetRolePolicy",
        "iam:ListInstanceProfilesForRole"
      ],
      "Resource": "arn:aws:iam::${ACCOUNT_ID}:role/togglemaster-*",
      "Condition": {
        "StringLikeIfExists": {
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
      "Sid": "ReadEKSNodegroupServiceLinkedRole",
      "Effect": "Allow",
      "Action": "iam:GetRole",
      "Resource": "*"
    },
    {
      "Sid": "PassProjectRolesToRequiredAwsServices",
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
      "Sid": "ManageProjectIamPolicies",
      "Effect": "Allow",
      "Action": [
        "iam:CreatePolicy",
        "iam:DeletePolicy",
        "iam:GetPolicy",
        "iam:ListEntitiesForPolicy"
      ],
      "Resource": "arn:aws:iam::${ACCOUNT_ID}:policy/togglemaster-*"
    },
    {
      "Sid": "InspectIamAndReadProjectDatabaseSecrets",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:DescribeSecret",
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "arn:aws:secretsmanager:${REGION}:${ACCOUNT_ID}:secret:rds!db-togglemaster-*"
    },
    {
      "Sid": "AllowRdsToCreateManagedDatabaseSecrets",
      "Effect": "Allow",
      "Action": [
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
      "Sid": "TagProjectDatabaseSecrets",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:TagResource"
      ],
      "Resource": "arn:aws:secretsmanager:${REGION}:${ACCOUNT_ID}:secret:rds!db-togglemaster-*"
    },
    {
      "Sid": "ListIamResources",
      "Effect": "Allow",
      "Action": [
        "iam:ListRoles",
        "iam:ListPolicies",
        "iam:ListOpenIDConnectProviders"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ManageProjectOpenIdConnectProvider",
      "Effect": "Allow",
      "Action": [
        "iam:CreateOpenIDConnectProvider",
        "iam:DeleteOpenIDConnectProvider",
        "iam:UpdateOpenIDConnectProviderThumbprint",
        "iam:AddClientIDToOpenIDConnectProvider",
        "iam:RemoveClientIDFromOpenIDConnectProvider",
        "iam:TagOpenIDConnectProvider",
        "iam:UntagOpenIDConnectProvider",
        "iam:GetOpenIDConnectProvider"
      ],
      "Resource": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/*"
    },
    {
      "Sid": "CreateRequiredServiceLinkedRoles",
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
            "rds.amazonaws.com",
            "autoscaling.amazonaws.com"
          ]
        }
      }
    },
    {
      "Sid": "ManageKmsKeysForRdsEncryption",
      "Effect": "Allow",
      "Action": [
        "kms:GenerateDataKey",
        "kms:Decrypt",
        "kms:Encrypt",
        "kms:ReEncrypt*",
        "kms:ListKeys",
        "kms:DescribeKey",
        "kms:CreateGrant",
        "kms:ListAliases"
      ],
      "Resource": "*"
    },
    {
      "Sid": "GetCallerIdentity",
      "Effect": "Allow",
      "Action": "sts:GetCallerIdentity",
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
echo "Região autorizada: ${REGION}"
echo
echo "ATENÇÃO: ec2/eks/rds/elasticache/dynamodb/sqs/ecr podem ser gerenciados"
echo "em toda a região, não somente nos recursos ToggleMaster; exclusões são possíveis."
echo "A policy também administra roles/policies IAM do projeto e lê segredos RDS."
echo "iam:GetRole e as ações KMS usam Resource '*'; isso amplia o acesso a roles e chaves da conta/região."
echo "Acesso elevado: não use em conta compartilhada nem mantenha após o laboratório."
read -r -p "Digite APPLY para criar e anexar a policy: " CONFIRMATION

if [[ "$CONFIRMATION" != "APPLY" ]]; then
  echo "Cancelado; nenhuma policy foi criada ou anexada."
  exit 0
fi

POLICY_ARN="$(aws iam create-policy \
  --policy-name "$POLICY_NAME" \
  --description "Permissões para provisionar e operar a infraestrutura AWS do ToggleMaster" \
  --policy-document "file://${POLICY_FILE}" \
  --query 'Policy.Arn' \
  --output text)"

aws iam attach-user-policy \
  --user-name "$TARGET_USER" \
  --policy-arn "$POLICY_ARN"

echo "Policy criada e anexada a ${TARGET_USER}: ${POLICY_ARN}"
echo "Para remover o acesso: aws iam detach-user-policy --user-name ${TARGET_USER} --policy-arn ${POLICY_ARN}"
