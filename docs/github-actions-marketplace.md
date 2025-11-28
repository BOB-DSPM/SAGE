# GitHub Actions Marketplace 게시 가이드 (SAGE 메인 레포)

이 리포지토리는 여러 마이크로서비스 이미지를 한 번에 올려주는 **메인 오케스트레이션 레포**입니다. Marketplace에는 이 레포만으로도 게시가 가능하며, `docker-compose.marketplace.yml`과 `setup.sh`를 활용해 "한 번에 SAGE 스택을 띄우는" 액션을 제공하는 것을 권장합니다. 개별 마이크로서비스 레포는 해당 서비스만 따로 배포하거나 테스트하고 싶을 때 별도로 액션을 만들면 됩니다.

> **현재 리포 상태 요약**
> - `action.yml`: 메인 레포만으로 SAGE 스택을 띄우는 Composite 액션 스켈레톤을 추가했습니다.
> - `docker-compose.marketplace.yml`: 모든 마이크로서비스 이미지를 기본 태그로 사용하도록 구성되어 있습니다.
> - Git 태그/릴리스: 아직 태그가 없습니다. Marketplace 제출 전 `v1` 같은 메이저 태그를 발행하세요.

## 지금 바로 해야 할 것 (3분 요약)
- **이미지와 포트 기본값 확인**: `action.yml` 입력 기본값이 원하는지 빠르게 눈으로 확인합니다.
- **컴포즈 파일 검증**: Docker가 있는 환경에서 `docker compose -f docker-compose.marketplace.yml config`로 최소 유효성 검사를 합니다.
- **태그 발행**: 아래 순서로 메이저 태그를 만듭니다.
  ```bash
  git tag -l 'v*'          # 기존 태그 확인 (없다면 빈 목록이 출력됩니다)
  git tag v1 && git push origin v1
  ```
- **Marketplace 제출**: 리포지토리 페이지의 **Publish this Action to Marketplace** 배너를 눌러 제출합니다.

> **TIP**: self-hosted 러너나 Docker가 활성화된 Ubuntu 러너에서만 동작하므로, README 예시에 "Docker 사용 가능 러너"임을 명시하세요.

## 1. 어떤 액션을 올릴지 결정하기
- **권장: 설치/부트스트랩용 Composite 액션 (이 레포만으로 가능)**
  - 이 레포의 `docker-compose.marketplace.yml`을 사용해 모든 컴포넌트를 한 번에 띄우는 액션을 만듭니다.
  - 러너에서 Docker를 사용할 수 있으므로, self-hosted 러너나 Docker가 활성화된 GitHub-hosted 러너(Ubuntu)에서 동작하도록 안내합니다.
- **선택: 서비스별 액션 (개별 레포에 추가)**
  - 특정 마이크로서비스만 테스트/배포하고 싶다면 각 서비스 레포에 별도 액션을 두고, 이 메인 레포의 README에서 링크하는 방식으로 확장할 수 있습니다.
  - "메인 레포만 올려도 되나?"라는 질문에 대한 답: **가능하다.** 전체 스택을 부트스트랩하는 목적이라면 메인 레포 액션만으로도 Marketplace 등록이 충분하며, 이후 필요한 경우에만 서비스별 액션을 추가한다는 전략을 추천합니다.

## 2. 리포 준비 상태 점검 (체크리스트)
- **퍼블릭 리포**인지 확인합니다. Marketplace 노출은 public만 가능합니다.
- **라이선스** 파일이 루트에 있어야 합니다. (예: Apache-2.0)
- 루트에 `action.yml`(또는 `action.yaml`)과 **README 사용 예시**를 포함해야 합니다.
- 사용할 **컨테이너 이미지 태그**가 공개 레지스트리에 존재하는지 확인합니다. 필요하다면 `SAGE_*_IMAGE` 환경변수로 태그를 입력할 수 있게 만듭니다.
- 안정적인 참조를 위해 **버전 태그**(`v1`, `v1.0.0`)를 발행합니다.

> 빠른 검증 순서
> 1) `LICENSE` 존재 여부 확인 2) `action.yml` 초안 작성 3) README에 "uses: owner/SAGE@v1" 예시 추가 4) `docker compose -f docker-compose.marketplace.yml config`로 기본 유효성 검사 5) `git tag v1 && git push origin v1`으로 태그 발행

### 현재 리포 상태에서 바로 실행할 수 있는 제출 순서
1. **컴포지트 액션 점검**: 루트의 `action.yml`이 원하는 입력(default 포트, 이미지 오버라이드 등)을 모두 포함하는지 확인합니다.
2. **README 업데이트**: 아래 예시를 `README.md`에 추가/정리하여 사용자가 바로 복사해 쓸 수 있게 합니다.
3. **유효성 검사**: 로컬이나 self-hosted 러너에서 `docker compose -f docker-compose.marketplace.yml config`로 한번 검증합니다.
4. **버전 태그 발행**: `git tag v1 && git push origin v1` (필요하면 `v1.0.0`도 함께 푸시).
5. **Marketplace 제출**: GitHub UI에서 Publish 플로우 진행.

## 3. Composite 액션 예시 스켈레톤
아래는 **현재 리포에 포함된 `action.yml`** 구조와 동일한 스켈레톤입니다. 러너에 Docker가 켜져 있다고 가정합니다.

```yaml
action.yml
---
name: "SAGE stack bootstrap"
description: "Launch the SAGE microservice stack with docker-compose.marketplace.yml"
author: BOB-DSPM
branding:
  icon: "cloud"
  color: "blue"
inputs:
  front_image:
    description: "Override sage-front image tag"
    required: false
  # 필요한 변수만 inputs로 노출하고 나머지는 기본값을 사용합니다.
runs:
  using: "composite"
  steps:
    - name: Check out
      uses: actions/checkout@v4
    - name: Validate compose file
      shell: bash
      run: docker compose -f docker-compose.marketplace.yml config
    - name: Set image overrides
      shell: bash
      run: |
        echo "SAGE_FRONT_IMAGE=${{ inputs.front_image }}" >> $GITHUB_ENV
        # 필요한 경우 다른 이미지/포트도 여기서 설정
    - name: Launch stack
      shell: bash
      run: |
        docker compose -f docker-compose.marketplace.yml up -d
```

## 4. README에 추가할 사용 예시
`action.yml`와 함께 README에 다음과 같은 사용법을 추가해 Marketplace 심사와 사용자 이해를 돕습니다.

```yaml
jobs:
  launch:
    runs-on: ubuntu-latest
    steps:
      - uses: owner/SAGE@v1
        with:
          host-base: http://localhost
          front-port: 8200
          analyzer-port: 9000
          collector-port: 8000
          com-show-port: 8003
          com-audit-port: 8103
          lineage-port: 8300
          oss-port: 8800
          ai-port: 8900
          # 필요 시 이미지 오버라이드도 추가: front-image, analyzer-image 등
```

- 러너가 **Docker를 사용할 수 있는 환경**이어야 함을 명시합니다.
- 필요한 포트/URL/토큰 입력 등도 `inputs`로 정의해 README에 설명합니다.

## 5. Marketplace 제출 플로우
1. `action.yml`과 README 업데이트 → `git tag v1 && git push origin v1`.
2. GitHub 리포지토리 페이지의 **“Publish this Action to Marketplace”** 배너에서 폼을 제출합니다.
3. 자동 검사를 통과하면 카드가 노출됩니다. 부족한 메타데이터가 있으면 반려되니 필드와 README를 꼼꼼히 작성합니다.

## 6. 메인 레포만으로 충분한가?
- **예**. 이 레포에서 Docker Compose로 모든 컴포넌트를 실행할 수 있으므로, "전체 스택 부트스트랩" 액션은 이 레포만으로도 Marketplace에 올릴 수 있습니다.
- 각 마이크로서비스의 세부 배포/테스트 액션이 필요하면 해당 레포에 추가로 만들고, README나 문서에서 링크하는 식으로 확장하면 됩니다.

## 7. 유지보수 팁
- `v1` 태그는 최신 안정 버전으로 업데이트하고, `v1.x.y`는 불변으로 남겨둡니다.
- `docker-compose.marketplace.yml`이 변경되면 새 버전을 태그하고 README 예시도 함께 갱신합니다.
- CI에서 `docker compose -f docker-compose.marketplace.yml config`로 유효성 검사를 돌리면 심사와 사용자 신뢰도에 도움이 됩니다.
