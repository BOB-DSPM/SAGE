<div align="center">

# SAGE

### Security And Governance Engine

**Kubernetes 기반 종합 DSPM(Data Security Posture Management) 플랫폼**

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![GitHub Stars](https://img.shields.io/github/stars/BOB-DSPM/SAGE.svg)](https://github.com/BOB-DSPM/SAGE/stargazers)
[![GitHub Issues](https://img.shields.io/github/issues/BOB-DSPM/SAGE.svg)](https://github.com/BOB-DSPM/SAGE/issues)

[빠른 시작](#-빠른-시작) •
[문서](#-문서) •
[아키텍처](#-아키텍처) •
[컴포넌트](#-아키텍처)

</div>

---

## 📖 개요

SAGE는 기업의 데이터 보안 및 거버넌스를 위한 통합 솔루션입니다. Kubernetes 환경에서 데이터 보안, 컴플라이언스 감사, 데이터 계통 추적, 데이터 분류 등 데이터 관리의 전 영역을 포괄하는 플랫폼을 제공합니다.

### 주요 기능

- **완전한 데이터 라이프사이클 관리**: 데이터 수집부터 분류, 추적, 감사까지 통합 관리
- **자동화된 컴플라이언스**: 규정 위반 자동 감지 및 수정 제안
- **실시간 데이터 계통 추적**: 데이터의 생성부터 소비까지 전체 흐름 시각화
- **AI 기반 보안**: 머신러닝을 활용한 이상 접근 탐지 및 신원 관리
- **멀티 클라우드 지원**: AWS, Azure, GCP 등 다양한 클라우드 환경 통합 지원
- **증적 자동화**: 다양한 오픈소스를 통해 스캔을 진행하고 증적 자료 제공

---

## 🏗️ 아키텍처

SAGE는 마이크로서비스 아키텍처를 기반으로 다음의 컴포넌트들로 구성됩니다:

### 핵심 컴포넌트

| 컴포넌트 | 설명 | 저장소 |
|---------|------|--------|
| **SAGE-FRONT** | 통합 관리 대시보드 및 사용자 인터페이스 | [→ GitHub](https://github.com/BOB-DSPM/SAGE-FRONT) |
| **Compliance Audit & Fix** | 컴플라이언스 위반 감지 및 자동 수정 | [→ GitHub](https://github.com/BOB-DSPM/DSPM_Compliance-audit-fix) |
| **Compliance Show** | 컴플라이언스 상태 시각화 및 보고서 생성 | [→ GitHub](https://github.com/BOB-DSPM/DSPM_Compliance-show) |
| **Data Lineage Tracking** | 데이터 계통 추적 및 흐름 분석 | [→ GitHub](https://github.com/BOB-DSPM/DSPM_DATA-Lineage-Tracking) |
| **Data Identification & Classification** | AI 기반 데이터 자동 식별 및 분류 | [→ GitHub](https://github.com/BOB-DSPM/DSPM_DATA-Identification-Classification) |
| **Opensource Runner** | 오픈소스 보안 스캐너 통합 실행 엔진 | [→ GitHub](https://github.com/BOB-DSPM/DSPM_Opensource-Runner) |
| **Data Collector** | 다중 소스 데이터 수집 및 통합 | [→ GitHub](https://github.com/BOB-DSPM/DSPM_Data-Collector) |
| **Identity AI** | AI 기반 신원 및 접근 관리 | [→ GitHub](https://github.com/BOB-DSPM/SAGE_Identity-AI) |

### 아키텍처 다이어그램
```
┌─────────────────────────────────────────────────────────────┐
│                         SAGE-FRONT                          │
│                    (통합 관리 대시보드)                        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                       │
├─────────────────┬─────────────────┬─────────────────────────┤
│  Compliance     │  Data Lineage   │  Data Classification   │
│  Audit & Fix    │  Tracking       │  & Identification      │
├─────────────────┼─────────────────┼─────────────────────────┤
│  Opensource     │  Data           │  Identity AI           │
│  Runner         │  Collector      │                        │
└─────────────────┴─────────────────┴─────────────────────────┘
```

---

## 🛠️ 기술 스택

SAGE는 다양한 오픈소스 기술을 활용하여 구축되었습니다:

### 컨테이너 오케스트레이션
- **[Kubernetes](https://kubernetes.io/)** - 컨테이너화된 애플리케이션 자동 배포, 스케일링 및 관리

### 보안 스캐닝 도구
- **[Prowler](https://github.com/prowler-cloud/prowler)** - AWS, Azure, GCP, Kubernetes 환경에 대한 보안 모범 사례 및 컴플라이언스 검사
- **[ScoutSuite](https://github.com/nccgroup/ScoutSuite)** - 멀티 클라우드 보안 감사 도구
- **[Trivy](https://github.com/aquasecurity/trivy)** - 컨테이너 이미지, 파일 시스템, Git 저장소의 취약점 스캐너
- **[CloudSploit](https://github.com/aquasecurity/cloudsploit)** - 클라우드 인프라 보안 위험 탐지
- **[Checkov](https://github.com/bridgecrewio/checkov)** - Infrastructure as Code 정적 분석 도구
- **[OpenSCAP](https://www.open-scap.org/)** - 보안 컴플라이언스 자동화 프로토콜

### 데이터베이스 및 스토리지
- **[PostgreSQL](https://www.postgresql.org/)** - 관계형 데이터베이스
- **[Redis](https://redis.io/)** - 인메모리 데이터 구조 저장소
- **[MongoDB](https://www.mongodb.com/)** - NoSQL 문서 데이터베이스

### AI/ML 프레임워크
- **[TensorFlow](https://www.tensorflow.org/)** - 머신러닝 플랫폼
- **[PyTorch](https://pytorch.org/)** - 딥러닝 프레임워크
- **[Scikit-learn](https://scikit-learn.org/)** - 머신러닝 라이브러리

### 모니터링 및 로깅
- **[Prometheus](https://prometheus.io/)** - 메트릭 수집 및 모니터링
- **[Grafana](https://grafana.com/)** - 메트릭 시각화 및 대시보드
- **[ELK Stack](https://www.elastic.co/elastic-stack)** - 로그 수집, 검색 및 분석 (Elasticsearch, Logstash, Kibana)

### 데이터 처리
- **[Apache Kafka](https://kafka.apache.org/)** - 분산 이벤트 스트리밍 플랫폼
- **[Apache Spark](https://spark.apache.org/)** - 대규모 데이터 처리 엔진

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

#### 2. SAGE 배포
```bash
# Kubernetes 네임스페이스 생성
kubectl create namespace sage

# SAGE 리소스 배포
kubectl apply -f deploy/
```

#### 3. 각 컴포넌트 배포
```bash
# 각 컴포넌트를 순차적으로 배포
kubectl apply -f deploy/data-collector/
kubectl apply -f deploy/data-classification/
kubectl apply -f deploy/lineage-tracking/
kubectl apply -f deploy/compliance/
kubectl apply -f deploy/identity-ai/
kubectl apply -f deploy/frontend/
```

### 설치 확인
```bash
# Pod 상태 확인
kubectl get pods -n sage

# 서비스 확인
kubectl get svc -n sage

# SAGE 프론트엔드 접속
kubectl port-forward -n sage svc/sage-front 8080:80
```

브라우저에서 `http://localhost:8080`으로 접속하여 SAGE 대시보드를 확인할 수 있습니다.

---

## 📚 문서

각 컴포넌트의 상세한 문서는 해당 저장소의 README를 참고하시기 바랍니다.

- [SAGE Frontend](https://github.com/BOB-DSPM/SAGE-FRONT) - 프론트엔드 사용자 가이드
- [Compliance Audit & Fix](https://github.com/BOB-DSPM/DSPM_Compliance-audit-fix) - 컴플라이언스 감사 가이드
- [Compliance Show](https://github.com/BOB-DSPM/DSPM_Compliance-show) - 컴플라이언스 보고서 가이드
- [Data Lineage Tracking](https://github.com/BOB-DSPM/DSPM_DATA-Lineage-Tracking) - 데이터 흐름 추적 가이드
- [Data Identification & Classification](https://github.com/BOB-DSPM/DSPM_DATA-Identification-Classification) - 데이터 분류 가이드
- [Opensource Runner](https://github.com/BOB-DSPM/DSPM_Opensource-Runner) - 보안 스캐너 실행 가이드
- [Data Collector](https://github.com/BOB-DSPM/DSPM_Data-Collector) - 데이터 수집 가이드
- [Identity AI](https://github.com/BOB-DSPM/SAGE_Identity-AI) - AI 기반 신원 관리 가이드

---

## 💻 개발

### 개발 환경 구성
```bash
# 개발용 로컬 클러스터 시작 (minikube 예시)
minikube start --cpus 4 --memory 8192

# SAGE 개발 환경 배포
kubectl apply -f deploy/dev/
```

### 빌드 및 테스트
```bash
# 전체 컴포넌트 빌드
make build

# 테스트 실행
make test

# 로컬 배포
make deploy-local
```

---

<div align="center">

**[⬆ 맨 위로](#sage)**

</div>