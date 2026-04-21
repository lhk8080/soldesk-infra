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
├── bootstrap/   # (선행) Terraform remote state 용 S3/DynamoDB + GitHub OIDC Role
└── terraform/   # (본편) 실제 서비스 인프라 — EKS/RDS/ArgoCD 등
```

> "bootstrap" 이라는 단어가 두 가지 의미로 쓰임에 주의.
> - **`bootstrap/` 디렉토리** = Terraform 자체를 굴리기 위한 meta-인프라 (state backend, OIDC role)
> - **아래 "Bootstrap 개념" 섹션** = `terraform/` 의 서비스 스택을 처음 세울 때 필요한 의존성 순서 (`apply.sh` / `seed.sh`)

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

### 1. 인프라 부트스트랩

```bash
git clone <본인 fork>/soldesk-infra
cd soldesk-infra/terraform

cp terraform.tfvars.example terraform.tfvars
# 아래 값들을 본인 것으로 수정:
#   db_password = "..."                 # RDS master password
#   github_repo = "<본인>/soldesk-app"   # OIDC IAM role trust 에 사용
#   key_name    = "<본인 EC2 keypair>"

./apply.sh
```

`apply.sh` 는 의존성 순서 때문에 4단계로 나뉘어 apply:
1. EKS 먼저 (kubernetes provider 가 클러스터 없이 plan 불가)
2. ArgoCD / ALB Controller / KEDA Helm install
3. ArgoCD Application CR 동적 생성 (계정별 ECR URL / IRSA ARN 주입, image tag 는 `seed-pending`)
4. 나머지 리소스 전체 apply

완료 후 `terraform output` 으로 frontend URL, API endpoint 등 확인.

### 2. 애플리케이션 시드 & 배포

```bash
git clone <본인 fork>/soldesk-app
cd soldesk-app
bash scripts/seed.sh
```

`seed.sh` 가 수행하는 작업:
0. **DB 스키마 초기화** — ephemeral `mysql-init` pod 로 `create.sql`, `Insert.sql` 실행
1. **ECR push** — 현재 git HEAD SHA 로 이미지 태깅 후 본인 ECR 에 push
2. **ArgoCD Application patch** — `images.*.tag` parameter 를 새 SHA 로 갱신 → ArgoCD 가 즉시 sync
3. **프론트엔드 S3 sync + CloudFront invalidation**

완료 후 `terraform output cloudfront_domain` 의 URL 에서 서비스 확인.

## 재배포 (코드 수정 후)

```bash
cd soldesk-app
git pull   # 또는 본인 작업 commit
bash scripts/seed.sh
```

`seed.sh` 는 매번 현재 git HEAD SHA 로 태깅하므로, 코드 바뀌면 자동으로 새 이미지로 배포됨.

## 전체 삭제

```bash
cd soldesk-infra/terraform
./destroy.sh
```

ALB, PV, ArgoCD 리소스 정리 순서가 꼬이지 않도록 단계별 destroy.

## 참고 문서

- `terraform/apply.sh` — 4-stage apply 상세 주석
- `terraform/destroy.sh` — 단계별 destroy 주석
- `../soldesk-k8s/argocd/README.md` — ArgoCD Application 수동 조작법 (롤백, image tag 확인)
- `../soldesk-app/scripts/seed.sh` — 배포 스크립트 주석
