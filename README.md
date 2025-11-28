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
│                    Kubernetes Cluster                       │
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
- **[Cloud Custodian](https://cloudcustodian.io/)** - 클라우드 자원의 정책 기반 관리 및  자동화
- **[Steampipe](https://steampipe.io/downloads)** - 클라우드 API를 SQL로 쿼리할 수 있게 해주는 도구
- **[Powerpipe mods](https://powerpipe.io/downloads)** - 대시보드 및 벤치마크 프레임워크
---

## 🚀 빠른 시작

### 사전 요구사항

시작하기 전에 다음 환경이 준비되어 있어야 합니다:

- Kubernetes v1.24 이상
- kubectl CLI
- 충분한 리소스를 갖춘 Kubernetes 클러스터 (최소 4 CPU, 8GB RAM)

### 설치

#### 1. 저장소 클론
```bash
git clone https://github.com/BOB-DSPM/SAGE.git
cd SAGE
```

#### 2. 자동 설치
SAGE는 모든 컴포넌트를 한 번에 설치할 수 있는 자동 설치 스크립트를 제공합니다.

```bash
# setup.sh를 실행하여 모든 컴포넌트 자동 설치
chmod +x setup.sh
./setup.sh
```

#### 3. 설치 확인
```bash
# 설치된 컴포넌트 확인
./check_status.sh
```
브라우저에서 `http://localhost:8080`으로 접속하여 SAGE 대시보드를 확인할 수 있습니다.

---

## 🛎️ GitHub Actions Marketplace 사용 예시

이 레포만으로 전체 스택을 띄우는 Marketplace 액션을 제공합니다. 러너에 **Docker**가 켜져 있어야 하며, 기본 포트는 `docker-compose.marketplace.yml`의 기본값(8200, 9000, 8000, 8003, 8103, 8300, 8800, 8900)을 사용합니다.

```yaml
jobs:
  launch:
    runs-on: ubuntu-latest
    steps:
      - uses: com_nyang/SAGE@v1
        with:
          front_image: comnyang/sage-front:latest
          analyzer_image: comnyang/sage-analyzer:latest
          aws_region: ap-northeast-2
          host_ip: 127.0.0.1 # 러너에서 서비스에 접근할 호스트 IP (필요 시 수정)
```

필요하면 `public_base`, `*_url`, 포트(`front_port` 등), OSS 워크디렉터리(`react_app_oss_workdir`), PII 모델 URL 등을 `with`에 추가해 커스터마이징할 수 있습니다. 게시/심사 준비 체크리스트는 `docs/github-actions-marketplace.md`를 참고하세요.

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
