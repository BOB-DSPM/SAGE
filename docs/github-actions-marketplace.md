# GitHub Actions Marketplace 게시 가이드 (SAGE 메인 레포)

이 리포지토리는 여러 마이크로서비스 이미지를 한 번에 올려주는 **메인 오케스트레이션 레포**입니다. Marketplace에는 이 레포만으로도 게시가 가능하며, `docker-compose.marketplace.yml`과 `setup.sh`를 활용해 "한 번에 SAGE 스택을 띄우는" 액션을 제공하는 것을 권장합니다. 개별 마이크로서비스 레포는 해당 서비스만 따로 배포하거나 테스트하고 싶을 때 별도로 액션을 만들면 됩니다.

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

## 3. Composite 액션 예시 스켈레톤
아래는 `action.yml` 초안 예시입니다. 러너에 Docker가 켜져 있다고 가정합니다.

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
          front_image: comnyang/sage-front:latest
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
