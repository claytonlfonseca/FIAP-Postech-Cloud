#!/usr/bin/env bash
set -Eeuo pipefail

TARGET_USER_HINT="${1:-}"
POLICY_NAME="ToggleMasterProjectProvisioner"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
POLICY_TEMPLATE="${SCRIPT_DIR}/ToggleMasterProjectProvisioner.json"
PROFILE_NAME="${AWS_PROFILE:-${AWS_DEFAULT_PROFILE:-}}"

for dependency in aws python3; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    echo "Erro: ${dependency} não encontrado." >&2
    exit 1
  fi
done

aws_cli() {
  if [[ -n "$PROFILE_NAME" ]]; then
    aws --profile "$PROFILE_NAME" "$@"
  else
    aws "$@"
  fi
}

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
if [[ -z "$REGION" ]]; then
  if ! REGION="$(aws_cli configure get region)"; then
    echo "Erro: não foi possível obter a região do profile AWS." >&2
    exit 1
  fi
fi
if [[ ! "$REGION" =~ ^[a-z]{2}(-[a-z0-9]+)+-[0-9]+$ ]]; then
  echo "Erro: região AWS inválida ou não configurada: '${REGION}'." >&2
  exit 1
fi

if [[ -r /dev/tty && -w /dev/tty ]] && { true </dev/tty; } 2>/dev/null; then
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

if [[ ! "$TARGET_USER" =~ ^[a-zA-Z0-9_+=,.@-]{1,64}$ ]]; then
  echo "Erro: nome de usuário IAM inválido." >&2
  exit 1
fi

ACCOUNT_ID="$(aws_cli sts get-caller-identity --query Account --output text)"
CALLER_ARN="$(aws_cli sts get-caller-identity --query Arn --output text)"
if [[ ! "$ACCOUNT_ID" =~ ^[0-9]{12}$ ]]; then
  echo "Erro: a conta retornada pelo STS é inválida: '${ACCOUNT_ID}'." >&2
  exit 1
fi
STATE_BUCKET_NAME="togglemaster-tfstate-${ACCOUNT_ID}"
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"

if ! aws_cli iam get-user --user-name "$TARGET_USER" >/dev/null; then
  echo "Erro: não foi possível consultar o usuário IAM '${TARGET_USER}' na conta ${ACCOUNT_ID}." >&2
  exit 1
fi

if POLICY_RESULT="$(aws_cli iam get-policy --policy-arn "$POLICY_ARN" 2>&1)"; then
  echo "Erro: a policy ${POLICY_ARN} já existe; o script não altera nem anexa policies existentes." >&2
  echo "Peça a um administrador IAM para inspecionar e atualizar a policy e sua associação." >&2
  exit 1
elif [[ "$POLICY_RESULT" != *"NoSuchEntity"* ]]; then
  echo "Erro ao consultar a policy ${POLICY_ARN}: ${POLICY_RESULT}" >&2
  exit 1
fi

POLICY_FILE="$(mktemp)"
trap 'rm -f -- "$POLICY_FILE"' EXIT

python3 - "$POLICY_TEMPLATE" "$POLICY_FILE" "$ACCOUNT_ID" "$REGION" <<'PY'
import json
import sys

template_path, output_path, account, region = sys.argv[1:]
with open(template_path, encoding="utf-8") as template:
    document = template.read().replace("{{ACCOUNT_ID}}", account).replace("{{REGION}}", region)
policy = json.loads(document)
with open(output_path, "w", encoding="utf-8") as output:
    json.dump(policy, output, separators=(",", ":"), ensure_ascii=True)
PY

POLICY_SIZE="$(wc -c <"$POLICY_FILE")"
if (( POLICY_SIZE > 6144 )); then
  echo "Erro: policy com ${POLICY_SIZE} caracteres excede o limite IAM de 6144 caracteres." >&2
  exit 1
fi

echo "Conta AWS: ${ACCOUNT_ID}"
echo "Executado por: ${CALLER_ARN}"
echo "Usuário que receberá a policy: ${TARGET_USER}"
echo "Profile AWS: ${PROFILE_NAME:-padrão/cadeia de credenciais}"
echo "Região autorizada para infraestrutura: ${REGION}"
echo "Bucket de state autorizado: ${STATE_BUCKET_NAME}"
echo
echo "ATENÇÃO: a policy concede permissões elevadas de infraestrutura e IAM."
echo "As permissões S3 ficam limitadas ao bucket ${STATE_BUCKET_NAME}."
echo "Login e publicação no ECR são permitidos em qualquer região e repositório autorizado."
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

if ! aws_cli iam attach-user-policy --user-name "$TARGET_USER" --policy-arn "$POLICY_ARN"; then
  echo "Erro: a policy ${POLICY_ARN} foi criada, mas não foi anexada; inspecione-a antes de tentar novamente." >&2
  exit 1
fi

echo "Policy criada e anexada a ${TARGET_USER}: ${POLICY_ARN}"
echo "Para remover o acesso, use o mesmo profile AWS e execute:"
printf 'aws iam detach-user-policy --user-name %q --policy-arn %q\n' "$TARGET_USER" "$POLICY_ARN"
