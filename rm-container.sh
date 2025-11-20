#!/usr/bin/env bash
# 파일 이름 예시: cleanup-containers.sh
# 사용법: chmod +x cleanup-containers.sh && ./cleanup-containers.sh

set -e

echo "[INFO] 모든 Docker 컨테이너를 stop 후 rm 합니다."

# 현재 존재하는 컨테이너 ID 목록
CONTAINERS=$(docker ps -aq)

if [ -z "$CONTAINERS" ]; then
  echo "[INFO] 실행 중이거나 생성된 컨테이너가 없습니다."
  exit 0
fi

echo "[INFO] 대상 컨테이너:"
echo "$CONTAINERS"
echo

read -p "[CONFIRM] 위 컨테이너들을 전부 중지하고 삭제합니다. 진행할까요? (y/N): " ANSWER

case "$ANSWER" in
  y|Y|yes|YES)
    echo "[STEP] 컨테이너 중지 중..."
    docker stop $CONTAINERS || true

    echo "[STEP] 컨테이너 삭제 중..."
    docker rm $CONTAINERS || true

    echo "[DONE] 모든 컨테이너 stop + rm 완료."
    ;;
  *)
    echo "[CANCEL] 작업을 취소했습니다."
    exit 0
    ;;
esac

echo
echo "[INFO] 모든 Docker 이미지(rmi)도 삭제할 수 있습니다."
IMAGES=$(docker images -q)
if [ -z "$IMAGES" ]; then
  echo "[INFO] 삭제할 이미지가 없습니다."
  exit 0
fi

echo "[INFO] 대상 이미지:"
docker images
echo

read -p "[CONFIRM] 위 모든 이미지를 삭제합니다. 진행할까요? (y/N): " IMG_ANSWER

case "$IMG_ANSWER" in
  y|Y|yes|YES)
    echo "[STEP] 이미지 삭제 중..."
    docker rmi -f $IMAGES || true
    echo "[DONE] 모든 이미지 삭제 완료."
    ;;
  *)
    echo "[CANCEL] 이미지 삭제를 건너뜁니다."
    ;;
esac
