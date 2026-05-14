# soldesk-infra

Ticketing 서비스의 **인프라 정의 repo** (Terraform). 팀원이 자기 AWS 계정에서 전체 스택을 재현하려면 이 repo 부터 시작.

## 3-repo 구조

| 레포지토리명 | 책임 범위 | 링크 |
|---|---|---|
| **soldesk-infra** (이 repo) | • 테라폼 코드 전반<br>• AWS 리소스 + IAM<br>• 클러스터 운용에 필요한 애드온 (helm provider) | — |
| soldesk-k8s | • ArgoCD에 의해 동기화되는 대상<br>• monitoring, service app | [github](https://github.com/lhk8080/soldesk-k8s) |
| soldesk-app | • 애플리케이션 소스 코드<br>• 이미지 빌드 & 레지스트리 푸시 지점 | [github](https://github.com/lhk8080/soldesk-app) |


## 디렉토리 구조

```
soldesk-infra/
├── bootstrap/   # tfstate 백엔드(S3 + DynamoDB), Route53 hosted zone
├── infra/       # VPC, EKS, RDS, ElastiCache, S3, CloudFront, API Gateway, Cognito, WAF
├── k8s/         # EKS 애드온 (ALB Controller, KEDA, ArgoCD, ESO)
├── modules/     # 공용 모듈
└── script/      # apply.sh / destroy.sh
```

- `bootstrap/` 에서는 인프라보다 수명이 긴 리소스를 분리해서 관리
- `infra/` 와 `k8s/` 는 별도 state 로 분리함. Kubernetes 클러스터가 먼저 생성되어야 Helm이 정상적으로 연결될 수 있기 때문에, 하나의 state로 함께 관리하면 초기 배포 plan 과정에서 오류가 발생할 수 있음.

## modules/

```
modules/
├── network/                       # 네트워크 관련 리소스
│   ├── vpc.tf                       VPC, IGW
│   ├── subnets-routes.tf            AZ별 서브넷 + 라우트 테이블
│   └── security-groups.tf           ALB / EKS node / RDS / Redis 용 베이스 SG
│
├── compute/                       # 컴퓨팅 관련 리소스
│   ├── main.tf                      EKS 클러스터 / 노드 그룹
│   ├── irsa.tf                      OIDC provider + 핵심 IRSA Role
│   ├── ebs_csi.tf                   EBS CSI 드라이버 애드온
│   ├── cleanup.tf                   destroy 할 때  ENI/ALB/SG 정리용
│   └── alb-controller-policy.json   ALB Controller IAM 정책 
│
├── data/                          # 상태 저장소
│   ├── rds/                         MySQL
│   └── elasticache/                 Redis
│
├── messaging/                     # 비동기 메시징
│   └── sqs/                         예약 큐 + DLQ(처리 실패용)
│
├── edge/                          # 외부 트래픽 진입
│   ├── route53/                     도메인 / 레코드
│   ├── acm/                         TLS 인증서
│   ├── cloudfront/                  프론트엔드 CDN (S3 origin + API origin)
│   ├── api-gateway/                 /api/* → ALB VPC Link로 연결
│   ├── waf-regional/                ALB 단 WebACL (CloudFront 우회 경로 보호)
│   └── waf/                         CloudFront에 붙이는 WAF 규칙
│
├── identity/                      # 사용자 인증
│   ├── cognito/                     User Pool + App Client
│   └── lambda/                      Cognito auto-confirm 트리거
│
├── shared/                        # 공용 리소스
│   ├── s3/                          frontend 정적 호스팅 버킷
│   ├── ecr/                         ticketing-was / worker-svc 이미지용 레지스트리
│   ├── ssm/                         시크릿 중앙 관리를 위한 Parameter Store
│   └── cicd/                        CI 용 IAM Role
│
└── kubernetes/                    # 클러스터 위에 helm 으로 까는 것들 (k8s/ root 에서 호출)
    ├── gitops/
    │   └── argocd/                  ArgoCD helm install (CRD + 서버)
    └── addons/
        ├── alb_controller/          AWS Load Balancer Controller
        ├── eso/                     External Secrets Operator (SSM/Secrets Manager → k8s Secret)
        └── keda/                    KEDA + 우선순위 PriorityClass
```

### AWS 리소스

`network` 부터 `shared` 모듈은 AWS 리소스를 생성 담당. `infra/` root 에서 호출하며, EKS·RDS·CloudFront·Cognito 등 클러스터 외부에 존재하는 자원을 담당한다. 모듈 간 필요한 값은 `infra/main.tf` 에서 output → input 으로 연결.

### EKS 애드온

`kubernetes/` 하위 모듈은 helm provider 를 통해 클러스터 내부에 helm chart 를 설치. `k8s/` root 에서 호출하며 별도 state로 분리.

ArgoCD 자신을 ArgoCD 로 배포할 수 없음, ALB Controller 도 Ingress 보다 먼저 존재해야 함. IAM (IRSA Role) 과 직접 연결되는 애드온은 Terraform 으로 Role 을 만들면서 같이 설치하는 편이 관리에 용이하다 판단

## 스크립트

`script/` 폴더에는 배포와 삭제 과정을 자동화하는 스크립트가 존재함. 각 스크립트는 이전 단계에서 생성된 값(`terraform output` 또는 AWS 조회 결과)을 다음 단계에 자동으로 전달하며 동작.

| 스크립트 | 역할 |
|---|---|
| `apply.sh` | infra → k8s addon → ArgoCD 순서로 전체 리소스를 배포 |
| `apply-alb.sh` | Kubernetes Ingress 가 생성한 ALB 정보를 다시 infra 설정에 반영 |
| `seed-ops-dns.sh` | argocd · grafana 도메인을 ALB 와 연결해 Route53 DNS 등록 |
| `destroy.sh` | Kubernetes 리소스를 먼저 삭제한 뒤 infra 리소스를 순서대로 제거 |

런타임 주입 방식을 사용하는 이유:

- **의존성 이슈**
  일부 AWS 리소스(ALB Listener 등)는 Kubernetes 리소스가 먼저 생성되어야 값이 나오기 때문에, 한 번의 Terraform 실행만으로 처리할 수 없음.
- **계정 환경별 독립성 유지**
  ECR 주소, CloudFront 도메인 같은 계정별 값들을 코드에 직접 작성하지 않고 조회해서 참조함.

## 개선사항
- **scripts 통합**: `apply.sh` 와 `apply-alb.sh` 는 분리 실행 구조라 ALB 생성 대기를 사람이 챙겨야 한다. 단일 진입점에서 ALB 대기까지 처리하도록 통합 고려.

