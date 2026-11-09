# mentee-interview — hello world on ECS Express

A tiny Flask app that shows its **app version** and **image version** on the landing page.
Every push to `main` is tested, built, pushed to ECR and deployed to AWS ECS Express Mode — no manual step.

## Architecture

```
push to main ─► GitHub Actions
                 test job:    pytest + version guard (also on PRs)   ── fail = release stops
                 release job: OIDC ─► role exam-hello-gha-deployer (no stored keys)
                              next image version (from git tags) ─► docker build ─► ECR :1.0.N + :<sha>
                              git tag image-v1.0.N ─► update ECS Express service ─► wait until stable
users ─► HTTPS ─► ALB (managed by ECS Express) ─► Fargate task (non-root gunicorn :8080)
```

| AWS service | Why |
|---|---|
| ECR (immutable tags, scan on push) | Private registry; a version can never be overwritten |
| ECS Express Mode on Fargate | One API call gives service + ALB + HTTPS URL + autoscaling; no servers |
| IAM + GitHub OIDC | CI gets short-lived credentials, only from `main` of this repo |

## Versions

| | Source | Who changes it | How it reaches the page |
|---|---|---|---|
| App version | `app/VERSION` | Developer, in the PR (guarded by `scripts/check_version.py`) | App reads the file |
| Image version | git tags `image-v*` | CI, patch bump on every release | `--build-arg IMAGE_VERSION` → `ENV` → app reads env |

## Run and test locally

```bash
uv venv .venv && uv pip install --python .venv -r app/requirements-dev.txt
.venv/bin/pytest -q app scripts
docker build --build-arg IMAGE_VERSION=local -t hello:local .
docker run --rm -p 18080:8080 hello:local   # open http://localhost:18080
```

## Set up AWS (one time)

```bash
aws login --profile exam --region eu-west-2
AWS_PROFILE=exam ./infra/bootstrap.sh   # 1st run: ECR + IAM roles
git push origin main                    # CI builds and pushes image 1.0.0 (deploy fails once: no service yet)
AWS_PROFILE=exam ./infra/bootstrap.sh   # 2nd run: creates the Express service from the CI-built image
```

## Roll back

GitHub → Actions → **rollback** → Run workflow → enter an existing version (e.g. `1.0.0`).
It redeploys that image from ECR, without a rebuild.

## Tear down

```bash
export AWS_PROFILE=exam AWS_REGION=eu-west-2
aws ecs delete-express-gateway-service --service-arn arn:aws:ecs:eu-west-2:030454160336:service/default/hello-world
aws ecr delete-repository --repository-name mentee-interview --force
aws iam detach-role-policy --role-name exam-hello-task-execution --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
aws iam detach-role-policy --role-name exam-hello-ecs-infra --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSInfrastructureRoleforExpressGatewayServices
aws iam delete-role-policy --role-name exam-hello-gha-deployer --policy-name deploy
for r in exam-hello-task-execution exam-hello-ecs-infra exam-hello-gha-deployer; do aws iam delete-role --role-name "$r"; done
```

Decisions and rejected alternatives: [DECISIONS.md](DECISIONS.md).
