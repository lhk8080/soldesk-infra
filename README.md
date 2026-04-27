# soldesk-infra

Ticketing 서비스의 **인프라 정의 repo** (Terraform). 팀원이 자기 AWS 계정에서 전체 스택을 재현하려면 이 repo 부터 시작.

## 3-repo 구조

| repo | 역할 |
|---|---|
| **soldesk-infra** (이 repo) | Terraform — EKS, RDS, ElastiCache, S3, CloudFront, API Gateway, Cognito, WAF, ArgoCD/ALB/KEDA helm install |
| [soldesk-k8s](https://github.com/lhk8080/soldesk-k8s) | Helm chart + ArgoCD Application 설정 (**계정 중립, 읽기전용 공용 repo — fork 불필요**) |
| [soldesk-app](https://github.com/lhk8080/soldesk-app) | 애플리케이션 소스 (ticketing-was, worker-svc, frontend) + DB 스키마 + seed.sh |

## 현재 운영 단계: 멀티 계정 개발

팀원들이 각자 무료 크레딧 AWS 계정에서 개발 중. 계정 고유 값(ECR URL, IRSA ARN, image tag 등)은 git 에 박지 않고 `apply.sh` / `seed.sh` 가 런타임 주입.

GitHub Actions CI 는 현재 **비활성화** (`soldesk-app/.github/workflows/*.disabled`). 모든 배포는 로컬 `seed.sh` 로 수행.

> 팀 공용 단일 AWS 계정으로 전환하면 원래 GitOps 흐름(CI 가 soldesk-k8s 에 image tag bump commit → ArgoCD 자동 sync) 으로 복구 예정.

## 사전 준비

- AWS 계정 + AdministratorAccess 권한의 IAM 사용자
- 로컬에 설치:
  - `terraform` (>= 1.5)
  - `aws` CLI (자격증명 설정 완료 — `aws configure`)
  - `kubectl`, `helm`
  - `docker`
  - `git`

## 디렉토리 구조

```
soldesk-infra/
├── apply.sh        # 전체 apply 진입점 (bootstrap → infra → k8s → ArgoCD App)
├── destroy.sh      # 전체 삭제 진입점 (k8s 리소스 선제 정리 후 단계별 destroy)
├── bootstrap/      # Terraform remote state 용 S3/DynamoDB + GitHub OIDC Role
├── infra/          # EKS, RDS, ElastiCache, S3, CloudFront, API Gateway, Cognito, WAF
├── k8s/            # ALB Controller / KEDA / ArgoCD / ESO helm install (별도 state)
└── modules/        # 위 두 root에서 참조하는 모듈들
```

> "bootstrap" 이라는 단어가 두 가지 의미로 쓰임에 주의.
> - **`bootstrap/` 디렉토리** = Terraform 자체를 굴리기 위한 meta-인프라 (state backend, OIDC role)
> - **아래 "Bootstrap 개념" 섹션** = 서비스 스택을 처음 세울 때 필요한 의존성 순서 (`apply.sh` / `seed.sh`)

## bootstrap/ — Terraform 메타 인프라

`terraform/` 보다 **먼저 한 번만** apply 하는 meta 레이어. 생성 리소스:

| 리소스 | 용도 |
|---|---|
| S3 bucket `soldesk-tfstate` | Terraform remote state 저장 (여러 사람이 같은 state 공유 시 필수). 버전 관리 + SSE + public block 설정. `prevent_destroy = true`. |
| DynamoDB `soldesk-tflock` | `terraform apply` 동시 실행 방지용 state lock. PAY_PER_REQUEST. |
| GitHub OIDC provider | `token.actions.githubusercontent.com` 을 AWS IAM 이 신뢰 |
| IAM Role `soldesk-github-actions-role` | GitHub Actions 워크플로우가 OIDC 로 assume. `AdministratorAccess` 부착. Trust 조건: `repo:<github_org>/<github_repo>:*` |

### 언제 쓰는가
- **현재(멀티 계정 개발)**: 안 써도 됨. `terraform/` 은 local state 사용 중이고 CI 도 disabled.
- **팀 공용 단일 계정 전환 시**:
  1. 공용 계정에서 `bootstrap/` 을 한 번 apply → S3 버킷 / DynamoDB / OIDC Role 생성
  2. `terraform/` 에 `backend "s3"` 블록을 추가하여 remote state 로 전환
  3. GitHub Secrets 에 OIDC Role ARN 등록하여 CI 재활성화

### 사용 방법 (필요 시점에)

```bash
cd bootstrap
terraform init

cat > terraform.tfvars <<EOF
project     = "soldesk"
region      = "ap-northeast-2"
github_org  = "<공용 조직>"
github_repo = "soldesk-app"
EOF

terraform apply
terraform output github_actions_role_arn  # → GitHub Secrets 에 등록
```

적용 후 `terraform/` 에 backend 설정 추가:
```hcl
terraform {
  backend "s3" {
    bucket         = "soldesk-tfstate"
    key            = "terraform/prod.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "soldesk-tflock"
    encrypt        = true
  }
}
```
그리고 `terraform init -migrate-state` 로 기존 local state 를 S3 로 이전.

> **주의**: `bootstrap/` 의 S3 버킷은 `prevent_destroy = true`. 삭제하려면 코드에서 flag 제거 후 `terraform destroy`. 이 안에 state 파일이 있으면 "계란을 담은 바구니를 먼저 버리는" 격이라 위험 — 필요 시 수동으로 object 비우고 버킷 삭제.

## Bootstrap 개념 (terraform/ 서비스 스택)

"Bootstrap" = 비어있는 AWS 계정에 소스만 가지고 스택을 처음부터 세우는 과정. 의존성이 순환하는 지점들이 있어서 **단순히 `terraform apply` 한 번으로는 안 됨**:

1. **EKS cold-start 문제**
   Terraform 의 `kubernetes` / `helm` provider 는 plan 시점에 클러스터 API 에 접속하려 함. 클러스터가 존재하지 않으면 "no client config" 에러. → `apply.sh` 가 **EKS 먼저 `-target` apply** 해서 해결.

2. **ArgoCD CRD 의존성**
   `argoproj.io/Application` 리소스를 만들려면 먼저 ArgoCD Helm 이 CRD 를 등록해야 함. → **2단계에서 ArgoCD helm_release 먼저 apply**, CRD 등록을 `kubectl` 로 대기 후 3단계에서 Application CR 생성.

3. **계정 고유 값 주입**
   soldesk-k8s 는 계정 중립이라 ECR URL / IRSA ARN 이 placeholder. → 3단계에서 `terraform output` 의 ACCOUNT_ID 를 읽어 **ArgoCD Application CR 의 `spec.source.helm.parameters`** 로 동적 주입. 이미 Application 이 있으면 현재 image tag 를 보존(seed.sh 로 push 한 SHA 가 덮이지 않도록).

4. **ALB 프로비저닝**
   API Gateway VPC Link 가 NLB/ALB 를 요구. Application sync 로 Ingress 가 생성돼야 ALB controller 가 ALB 를 만들고, 그 ARN 이 준비돼야 API Gateway 모듈이 apply 됨. → 4단계 전체 apply 에서 `wait_for_alb` 데이터 소스가 blocking.

5. **DB 스키마 부재**
   RDS 는 빈 MySQL 인스턴스로 생성됨. 테이블 없음 → ticketing-was 가 500 에러. → `seed.sh` 의 step 0 에서 ephemeral `mysql-init` pod 로 `create.sql`, `Insert.sql` 실행.

6. **최초 이미지 부재**
   ECR 에 아직 이미지 없음 → Application CR 은 `seed-pending` 태그로 생성 (pod ImagePullBackOff 상태로 대기). → `seed.sh` step 1 이 첫 이미지 push, step 2 가 Application tag patch 로 실제 배포 트리거.

결국 bootstrap 은 **`apply.sh` (인프라) → `seed.sh` (앱/DB/프론트)** 2-phase. 이후 재배포는 코드 수정 후 `seed.sh` 한 번이면 끝 (인프라 변경 없으면 `apply.sh` 재실행 불필요).

## 재현 순서

전체 흐름: **`apply.sh` (1차) → `seed.sh` → `apply.sh` (2차)**

`apply.sh` 가 1차 apply 시점엔 ALB 가 아직 없어서 API Gateway → ALB 라우팅을 못 채움. seed 가 ticketing-ingress 를 만들면서 ALB 가 생성되면, listener ARN 을 `infra/terraform.tfvars` 에 채워 한 번 더 apply.

### 1. soldesk-infra 1차 apply

```bash
git clone <본인 fork>/soldesk-infra
cd soldesk-infra

# infra/terraform.tfvars 수정 (필수)
#   aws_account     = "<본인 12자리>"
#   github_repo     = "<본인>/soldesk-app"
#   alb_listener_arn = ""        # 1차 apply 시점에는 비워둠
#   cloudfront_domain = ""       # 자동으로 채워짐 (apply.sh pass2)

./script/apply.sh
```

`apply.sh` 단계:
1. **infra apply (pass 1)** — VPC / EKS / RDS / ElastiCache / Cognito / API Gateway / CloudFront 생성
2. **infra apply (pass 2)** — `cloudfront_domain` output 을 Cognito callback URL 등에 주입
3. **k8s addons apply** — ALB Controller, KEDA, ArgoCD, ESO 설치 (별도 state `k8s/`)
4. **ArgoCD Application 등록** — `argocd/platform/*.yaml` 의 ticketing/monitoring Application 적용

`TF_STATE_BUCKET` 미설정 시 `bootstrap/` 을 자동 apply 후 output 에서 읽어옴.

### 2. soldesk-app 시드

```bash
git clone <본인 fork>/soldesk-app
cd soldesk-app
./seed.sh
```

`seed.sh` 단계:
1. **DB 마이그레이션 Job** — `db-schema/migrations/*.sql` 적용 (`schema_migrations` 테이블로 idempotent)
2. **ECR push** — 현재 git HEAD SHA 로 이미지 태깅 후 push
3. **ArgoCD Application image tag patch** — 새 SHA 로 sync 트리거
4. **프론트엔드 S3 sync + CloudFront invalidation** + `index.html` 에 Cognito/API origin 주입

### 3. soldesk-infra 2차 apply (ALB listener ARN)

seed 가 끝나면 ticketing ALB 가 생성됨. listener ARN 을 채워 API Gateway 가 ALB 로 라우팅하도록 마무리:

```bash
# ALB listener ARN 확인
aws elbv2 describe-listeners --region ap-northeast-2 \
  --load-balancer-arn $(aws elbv2 describe-load-balancers --region ap-northeast-2 \
    --query 'LoadBalancers[?contains(LoadBalancerName,`ticketin`)].LoadBalancerArn' --output text) \
  --query 'Listeners[0].ListenerArn' --output text

# infra/terraform.tfvars 의 alb_listener_arn 에 위 값 기입
cd soldesk-infra
./script/apply.sh
```

이 시점부터 `https://<cloudfront_domain>` 에서 `/api/*` 요청까지 정상 동작.

## 재배포 (코드 수정 후)

```bash
cd soldesk-app
git pull
./seed.sh
```

인프라 변경 없으면 `apply.sh` 재실행 불필요.

## 운영 대시보드 접근

apply 완료 후 ALB DNS 로 외부 접근 가능 (모두 `internet-facing` ingress):

```bash
kubectl get ingress -A
# argocd-server, monitoring-grafana 의 ADDRESS 컬럼이 ALB DNS
```

| 대시보드 | 로그인 |
|---|---|
| ArgoCD | `root` / `soldesk1` (`accounts.root` + bcrypt 패스워드, `infra/terraform.tfvars` 의 `root_password_bcrypt` 변경 가능) |
| Grafana | `admin` / `soldesk1` (SSM `/ticketing/prod/GRAFANA_ADMIN_PASSWORD` 값) |

> Grafana 패스워드 변경 시: SSM 값 갱신 후 grafana pod 재시작. 단, 이미 sqlite DB 에 admin user 가 박혀 있으면 env 만 바꿔서는 반영 안 됨 → `kubectl exec ... -- grafana cli admin reset-admin-password <새 값>` 필요.

## 전체 삭제

```bash
cd soldesk-infra
./script/destroy.sh
```

순서:
1. **K8s 선제 정리** — ArgoCD Application → ingress / LoadBalancer Service → workload(sts/deploy/ds/job) → 잔여 pod 강제 종료 → PVC. ALB controller 가 ALB/SG/TG 회수할 60초 대기.
2. **`k8s/` terraform destroy** — addon helm release 정리
3. **`infra/` terraform destroy** — compute 모듈의 destroy provisioner 가 잔여 ENI/ALB/SG 정리 후 VPC 삭제

> destroy 가 멈추면 가장 흔한 원인은 **orphan ALB** (controller 가 ingress 삭제 전에 죽은 경우). 콘솔 또는 `aws elbv2 describe-load-balancers` 로 잔여 ALB 확인 후 수동 삭제하고 `destroy.sh` 재실행.

## 참고 문서

- `terraform/apply.sh` — 4-stage apply 상세 주석
- `terraform/destroy.sh` — 단계별 destroy 주석
- `../soldesk-k8s/argocd/README.md` — ArgoCD Application 수동 조작법 (롤백, image tag 확인)
- `../soldesk-app/scripts/seed.sh` — 배포 스크립트 주석
