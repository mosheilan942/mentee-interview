#!/usr/bin/env bash
# One-time AWS setup: ECR repo + IAM roles for ECS Express Mode and GitHub Actions (OIDC).
# Usage: AWS_PROFILE=exam ./infra/bootstrap.sh
set -euo pipefail

export AWS_REGION=eu-west-2
GITHUB_REPO=mosheilan942/mentee-interview
ECR_REPO=mentee-interview
SERVICE_NAME=hello-world
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BOUNDARY=arn:aws:iam::${ACCOUNT_ID}:policy/candidate-exam-boundary
EXEC_ROLE=exam-hello-task-execution
INFRA_ROLE=exam-hello-ecs-infra
GHA_ROLE=exam-hello-gha-deployer

# --- ECR: immutable tags so a version can never be overwritten
aws ecr describe-repositories --repository-names "$ECR_REPO" >/dev/null 2>&1 ||
  aws ecr create-repository --repository-name "$ECR_REPO" \
    --image-tag-mutability IMMUTABLE \
    --image-scanning-configuration scanOnPush=true >/dev/null

create_role() { # name, trust-policy-json, managed-policy-arn (optional)
  aws iam get-role --role-name "$1" >/dev/null 2>&1 ||
    aws iam create-role --role-name "$1" \
      --assume-role-policy-document "$2" \
      --permissions-boundary "$BOUNDARY" >/dev/null
  [ -z "${3:-}" ] || aws iam attach-role-policy --role-name "$1" --policy-arn "$3"
}

# --- ECS pulls the image and writes logs with this role
create_role "$EXEC_ROLE" '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
  arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

# --- ECS Express creates the ALB, certificate, security groups and scaling with this role
create_role "$INFRA_ROLE" '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ecs.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
  arn:aws:iam::aws:policy/service-role/AmazonECSInfrastructureRoleforExpressGatewayServices

# --- GitHub Actions: only the main branch of this repo can assume the deployer role
create_role "$GHA_ROLE" "$(cat <<EOF
{"Version":"2012-10-17","Statement":[{"Effect":"Allow",
  "Principal":{"Federated":"arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"},
  "Action":"sts:AssumeRoleWithWebIdentity",
  "Condition":{"StringEquals":{
    "token.actions.githubusercontent.com:aud":"sts.amazonaws.com",
    "token.actions.githubusercontent.com:sub":"repo:${GITHUB_REPO}:ref:refs/heads/main"}}}]}
EOF
)"

aws iam put-role-policy --role-name "$GHA_ROLE" --policy-name deploy --policy-document "$(cat <<EOF
{"Version":"2012-10-17","Statement":[
  {"Effect":"Allow","Action":"ecr:GetAuthorizationToken","Resource":"*"},
  {"Effect":"Allow","Action":["ecr:BatchCheckLayerAvailability","ecr:InitiateLayerUpload","ecr:UploadLayerPart",
    "ecr:CompleteLayerUpload","ecr:PutImage","ecr:BatchGetImage","ecr:DescribeImages"],
   "Resource":"arn:aws:ecr:${AWS_REGION}:${ACCOUNT_ID}:repository/${ECR_REPO}"},
  {"Effect":"Allow","Action":["ecs:UpdateExpressGatewayService","ecs:DescribeExpressGatewayService","ecs:DescribeServices"],
   "Resource":"arn:aws:ecs:${AWS_REGION}:${ACCOUNT_ID}:service/default/${SERVICE_NAME}"},
  {"Effect":"Allow","Action":"iam:PassRole","Resource":"arn:aws:iam::${ACCOUNT_ID}:role/${EXEC_ROLE}"}]}
EOF
)"

ECR_URI=${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}

# --- Express service: created once, from the first CI-built image (CI only updates it after that)
git fetch -q --tags
LAST_TAG=$(git tag -l 'image-v*' --sort=-v:refname | head -n1)
SERVICE_ACTIVE=$(aws ecs describe-services --cluster default --services "$SERVICE_NAME" \
  --query 'length(services[?status==`ACTIVE`])' --output text 2>/dev/null || echo 0)
if [ -z "$LAST_TAG" ]; then
  echo "No image-v* tag yet: push to main first, then re-run this script to create the service."
elif [ "$SERVICE_ACTIVE" = "0" ]; then
  aws ecs create-express-gateway-service \
    --service-name "$SERVICE_NAME" \
    --execution-role-arn "arn:aws:iam::${ACCOUNT_ID}:role/${EXEC_ROLE}" \
    --infrastructure-role-arn "arn:aws:iam::${ACCOUNT_ID}:role/${INFRA_ROLE}" \
    --primary-container "{\"image\":\"${ECR_URI}:${LAST_TAG#image-v}\",\"containerPort\":8080}" \
    --health-check-path /health
fi

echo "ECR:        ${ECR_URI}"
echo "GHA role:   arn:aws:iam::${ACCOUNT_ID}:role/${GHA_ROLE}"
