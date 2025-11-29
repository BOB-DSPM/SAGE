<div align="center">
  
# SAGE

### Security And Governance Engine

**MLOps환경에서의 데이터 보호 중점 보안 플랫폼**

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![GitHub Stars](https://img.shields.io/github/stars/BOB-DSPM/SAGE.svg)](https://github.com/BOB-DSPM/SAGE/stargazers)
[![GitHub Issues](https://img.shields.io/github/issues/BOB-DSPM/SAGE.svg)](https://github.com/BOB-DSPM/SAGE/issues)

[빠른 시작](#-빠른-시작) •
[주요 기능](#-주요-기능) •
[아키텍처](#-아키텍처) •
[기술 스택](#-기술-스택) •
[문서](#-문서)

</div>

---

## 📖 개요

SAGE는 MLOps를 사용하는 조직의 데이터 보안 및 거버넌스를 위한 통합 솔루션입니다. AWS환경에서 데이터 보안, 컴플라이언스 감사, 데이터 흐름 추적, 데이터 분류 등 데이터 관리의 전 영역을 포괄하는 플랫폼을 제공합니다.

### 주요 기능

- **데이터 라이프사이클 관리**: 데이터 수집부터 분류, 추적, 감사까지 통합 관리
- **자동화된 컴플라이언스**: 규정 위반 진단 및 해결 방안 제안
- **데이터 흐름 추적**: 데이터의 생성부터 소비까지 전체 흐름 시각화
- **AI 기반 개인식별정보 포함 데이터 식별**: 머신러닝을 활용한 개인식별정보 포함 데이터 식별
- **증적 자동화**: 다양한 오픈소스를 통해 스캔을 진행하고 증적 자료 제공

---

## 🏗️ 아키텍처

SAGE는 다음의 컴포넌트들로 구성됩니다:

### 핵심 컴포넌트

| 컴포넌트 | 설명 | 저장소 |
|---------|------|--------|
| **SAGE-FRONT** | 통합 관리 대시보드 및 사용자 인터페이스 | [→ GitHub](https://github.com/BOB-DSPM/SAGE-FRONT) |
| **Compliance Audit & Fix** | 컴플라이언스 위반 감지 및 자동 수정 | [→ GitHub](https://github.com/BOB-DSPM/DSPM_Compliance-audit-fix) |
| **Compliance Show** | 컴플라이언스 상태 시각화 및 보고서 생성 | [→ GitHub](https://github.com/BOB-DSPM/DSPM_Compliance-show) |
| **Data Lineage Tracking** | 데이터 흐름 추적 및 분석 | [→ GitHub](https://github.com/BOB-DSPM/DSPM_DATA-Lineage-Tracking) |
| **Data Identification & Classification** | AI 기반 데이터 자동 식별 및 분류 | [→ GitHub](https://github.com/BOB-DSPM/DSPM_DATA-Identification-Classification) |
| **Opensource Runner** | 오픈소스 보안 스캐너 통합 실행 엔진 | [→ GitHub](https://github.com/BOB-DSPM/DSPM_Opensource-Runner) |
| **Data Collector** | 다중 소스 데이터 수집 및 통합 | [→ GitHub](https://github.com/BOB-DSPM/DSPM_Data-Collector) |
| **Identity AI** | AI 기반 신원 및 접근 관리 | [→ GitHub](https://github.com/BOB-DSPM/SAGE_Identity-AI) |

### 아키텍처 다이어그램
```
┌─────────────────────────────────────────────────────────────┐
│                         SAGE-FRONT                          │
│                     (통합 관리 대시보드)                     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                DockerContainer/K8s Cluster                  │
├─────────────────┬─────────────────┬─────────────────────────┤
│  Compliance     │  Data Lineage   │  Data Classification    │
│  Audit & Fix    │  Tracking       │  & Identification       │
├─────────────────┼─────────────────┼─────────────────────────┤
│  Opensource     │  Data           │  Identity AI            │
│  Runner         │  Collector      │                         │
└─────────────────┴─────────────────┴─────────────────────────┘
```

---

## 🛠️ 기술 스택

SAGE는 다양한 오픈소스 기술을 활용하여 구축되었습니다:

### 보안 스캐닝 도구
- **[Prowler](https://github.com/prowler-cloud/prowler)** - AWS, Azure, GCP, Kubernetes 환경에 대한 보안 모범 사례 및 컴플라이언스 검사
- **[Scout Suite](https://github.com/nccgroup/ScoutSuite)** - 멀티 클라우드 보안 감사 도구
- **[Cloud Custodian](https://cloudcustodian.io/)** - 클라우드 자원의 정책 기반 관리 및 자동화
- **[Steampipe](https://steampipe.io/downloads)** - 클라우드 API를 SQL로 쿼리할 수 있게 해주는 도구
- **[Powerpipe mods](https://powerpipe.io/downloads)** - 대시보드 및 벤치마크 프레임워크
---

## 🚀 빠른 시작

### 사전 요구사항

로컬/베어메탈(EC2 포함)에서 Docker Compose로 바로 올리는 구성을 기준으로 합니다.

- Linux 호스트 (Ubuntu/Debian 계열 권장)
- Docker & Docker Compose (없으면 스크립트가 자동 설치)
- 포트 여유: 8200(front), 9000(analyzer), 8000(collector), 8003(com-show), 8103(com-audit), 8300(lineage), 8800(oss), 8900(ai)
- Docker Hub 이미지를 풀(Pull)할 수 있는 인터넷 egress

### AWS EC2에서 바로 띄울 때 권장 사양/권한

- 인스턴스: t3.large(2 vCPU/8 GB) 이상 권장, 트래픽 많으면 t3.xlarge 이상
- 스토리지: gp3 50GB+ (Docker 이미지/로그 여유 확보)
- OS: Ubuntu 22.04 LTS (기본 Shell/패키지 가정)
- 네트워크: 인터넷 egress 허용(Docker Hub pull), 인바운드 포트 허용
  - 8200(front), 9000(analyzer), 8000(collector), 8003(com-show), 8103(com-audit), 8300(lineage), 8800(oss), 8900(ai)
- 최소 IAM 권한(인스턴스 프로파일 또는 액세스 키)
  - AWS 리소스 점검/스캔을 쓸 경우: `SecurityAudit` AWS 관리형 정책 1개로 대부분 읽기 전용 커버
  - CloudTrail 로그 조회가 필요하면 `AWSCloudTrail_ReadOnlyAccess` 추가
  - 별도 자원 생성이 필요 없다면 쓰기 권한은 불필요

### 설치

#### 1. 저장소 클론
```bash
git clone https://github.com/BOB-DSPM/SAGE.git
cd SAGE
```

#### 2. 스택 기동
`setup.sh`가 현재 서버 IP를 자동 감지해 `.sage-stack.env`를 생성하고, 필요한 경우 Docker/Compose를 설치한 뒤 전체 스택을 띄웁니다.

```bash
chmod +x setup.sh
./setup.sh       # sudo가 필요할 수 있습니다
```

- 기본 공개 URL: `http://<서버_IP>:8200` (Frontend)
- 개별 API: Analyzer `:9000`, Collector `:8000`, Compliance-show `:8003`, Compliance-audit `:8103`, Lineage `:8300`, OSS `:8800`, AI `:8900`

실행 전에 필요한 값이 있으면 환경변수로 오버라이드하세요. 예:  
`AWS_REGION=ap-northeast-2 FRONT_PORT=8282 SAGE_HOST_IP=1.2.3.4 ./setup.sh`

스택 중지: `docker compose --env-file .sage-stack.env -f docker-compose.marketplace.yml down`

### GitHub Actions Marketplace 액션 사용 예시
루트의 `action.yml` Composite 액션으로 Docker Compose 기반 SAGE 스택을 한 번에 띄울 수 있습니다. 
Docker가 켜진 러너(Ubuntu)에서 사용하세요.

```yaml
jobs:
  launch-sage:
    runs-on: ubuntu-latest # Docker 사용 가능한 러너
    steps:
      - uses: com_nyang/SAGE@v1
        with:
          host_ip: 127.0.0.1
          aws_region: ap-northeast-2
          front_image: comnyang/sage-front:latest
          analyzer_image: comnyang/sage-analyzer:latest
          collector_image: comnyang/sage-collector:latest
          # 필요 시 포트/URL 오버라이드: front_port, analyzer_port, public_base, analyzer_url 등
```

> Marketplace에 게시하려면 `git tag v1 && git push origin v1`으로 메이저 태그를 먼저 발행하고, 리포지토리 페이지의 **Publish this Action to Marketplace** 버튼을 통해 제출하세요.

#### Marketplace 제출 절차 (요약)
1. `docker compose -f docker-compose.marketplace.yml config`로 컴포즈 파일이 유효한지 확인합니다.
2. `git tag -l 'v*'`로 기존 태그를 확인한 뒤 `git tag v1 && git push origin v1`으로 메이저 태그를 발행합니다.
3. 리포지토리 상단 배너 **Publish this Action to Marketplace**에서 제출을 완료합니다. (Docker 사용 가능 러너에서 동작함을 README에 명시)

### GitHub Actions 워크플로우: 최신 이미지로 스택 새로고침
`.github/workflows/refresh-stack.yml`는 Docker Hub의 최신 이미지로 스택을 다시 올리는 워크플로우입니다.

- 트리거: 매일 UTC 03:00(크론) 또는 Actions 탭에서 수동 실행(workflow_dispatch)
- 기본 동작: `docker compose pull` → `docker compose up -d` → `docker image prune -f`
- 입력값: `compose_file`(옵션, 기본 `docker-compose.marketplace.yml`)

수동 실행 예시:
1. GitHub → Actions → “Refresh SAGE stack on Docker image update” 선택
2. `Run workflow` 버튼 클릭 (필요 시 `compose_file` 입력)

---

## 📚 문서

각 컴포넌트의 상세한 문서는 해당 저장소의 README를 참고하시기 바랍니다.

- **[GitHub Actions Marketplace 게시 가이드](docs/github-actions-marketplace.md)** - 메인 레포만으로 Marketplace 액션을 준비하는 방법
- **[SAGE Frontend](https://github.com/BOB-DSPM/SAGE-FRONT)** - 프론트엔드 사용자 가이드
- **[Compliance Audit & Fix](https://github.com/BOB-DSPM/DSPM_Compliance-audit-fix)** - 컴플라이언스 감사 가이드
- **[Compliance Show](https://github.com/BOB-DSPM/DSPM_Compliance-show)** - 컴플라이언스 보고서 가이드
- **[Data Lineage Tracking](https://github.com/BOB-DSPM/DSPM_DATA-Lineage-Tracking)** - 데이터 흐름 추적 가이드
- **[Data Identification & Classification](https://github.com/BOB-DSPM/DSPM_DATA-Identification-Classification)** - 데이터 분류 가이드
- **[Opensource Runner](https://github.com/BOB-DSPM/DSPM_Opensource-Runner)** - 보안 스캐너 실행 가이드
- **[Data Collector](https://github.com/BOB-DSPM/DSPM_Data-Collector)** - 데이터 수집 가이드
- **[Identity AI](https://github.com/BOB-DSPM/SAGE_Identity-AI)** - AI 기반 개인정보 식별 가이드

---
<div align="center">

**[⬆ 맨 위로](#sage)**

</div>




