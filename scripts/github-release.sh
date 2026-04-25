#!/usr/bin/env bash
#
# github-release.sh — GitHub Actions 빌드를 트리거하는 release 시작 스크립트
#
# 동작:
#   1. project.yml 또는 인자로부터 버전 결정
#   2. git working tree clean 검증
#   3. v{VERSION} 태그 생성 + origin push
#   4. Actions가 release.yml workflow를 자동 실행 → DMG/PKG 빌드 → release 업로드
#
# Usage:
#   ./scripts/github-release.sh                          # project.yml의 MARKETING_VERSION 사용
#   ./scripts/github-release.sh 1.2.0                    # 버전 명시
#   ./scripts/github-release.sh 1.2.0 "Release notes"    # 태그 메시지 명시
#   ./scripts/github-release.sh --bump patch             # patch 버전 자동 증가 후 release
#
# Prerequisites:
#   - gh CLI (https://cli.github.com) 로그인 필수
#   - git origin remote 설정
#   - .github/workflows/release.yml 존재 (이미 포함)
#   - GitHub repo Settings → Secrets에 코드사인용 시크릿 등록 (선택, 없으면 unsigned 빌드)
#
# 진행 모니터링:
#   gh run watch
#   gh release view v1.2.0

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

readonly PROJECT_YML="$ROOT_DIR/project.yml"

log()  { printf "\033[36m▸ %s\033[0m\n" "$*"; }
warn() { printf "\033[33m! %s\033[0m\n" "$*"; }
die()  { printf "\033[31m✘ %s\033[0m\n" "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "$1 명령이 없습니다. (gh: https://cli.github.com)"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  sed -n '2,22p' "$0"
  exit 0
fi

require_cmd git
require_cmd gh
require_cmd grep
require_cmd sed

# ----- 사전 검증 -----

# 1. gh 로그인
gh auth status >/dev/null 2>&1 || die "gh CLI에 로그인되어 있지 않습니다. 'gh auth login' 실행."

# 2. git working tree clean
if [[ -n "$(git status --porcelain)" ]]; then
  warn "Working tree가 clean하지 않습니다."
  git status --short
  die "변경사항을 커밋 또는 stash 후 재시도하세요."
fi

# 3. main(또는 현재) 브랜치가 origin과 동기화되어 있는지
git fetch --tags origin >/dev/null 2>&1 || die "origin에서 fetch 실패"
LOCAL_HEAD="$(git rev-parse HEAD)"
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
REMOTE_HEAD="$(git rev-parse "origin/$CURRENT_BRANCH" 2>/dev/null || echo "")"
if [[ -n "$REMOTE_HEAD" && "$LOCAL_HEAD" != "$REMOTE_HEAD" ]]; then
  warn "$CURRENT_BRANCH 가 origin/$CURRENT_BRANCH 와 동기화되지 않았습니다."
  die "git push로 동기화 후 재시도하세요."
fi

# ----- 버전 결정 -----

read_marketing_version() {
  grep -E '^\s*MARKETING_VERSION:' "$PROJECT_YML" \
    | head -1 \
    | sed -E 's/.*MARKETING_VERSION:[[:space:]]*"?([0-9]+\.[0-9]+\.[0-9]+)"?.*/\1/'
}

bump_version() {
  local part="$1"
  local current
  current="$(read_marketing_version)"
  [[ -n "$current" ]] || die "현재 MARKETING_VERSION을 project.yml에서 읽을 수 없습니다."

  local major minor patch
  IFS='.' read -r major minor patch <<<"$current"

  case "$part" in
    major) major=$((major + 1)); minor=0; patch=0 ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    patch) patch=$((patch + 1)) ;;
    *) die "--bump 인자는 major|minor|patch 중 하나여야 합니다 (받은 값: $part)" ;;
  esac

  echo "${major}.${minor}.${patch}"
}

VERSION=""
NOTES=""

if [[ "${1:-}" == "--bump" ]]; then
  [[ -n "${2:-}" ]] || die "--bump 뒤에 major|minor|patch 를 지정하세요."
  VERSION="$(bump_version "$2")"
  NOTES="${3:-Release v${VERSION}}"

  # project.yml MARKETING_VERSION 업데이트 + 커밋
  log "project.yml: MARKETING_VERSION → $VERSION"
  sed -i.bak -E "s/(MARKETING_VERSION:[[:space:]]*\")[^\"]+(\")/\1${VERSION}\2/" "$PROJECT_YML"
  rm -f "${PROJECT_YML}.bak"
  git add "$PROJECT_YML"
  git commit -m "chore: bump version to ${VERSION}"
  git push origin "$CURRENT_BRANCH"
elif [[ -n "${1:-}" ]]; then
  VERSION="$1"
  NOTES="${2:-Release v${VERSION}}"
else
  VERSION="$(read_marketing_version)"
  [[ -n "$VERSION" ]] || die "MARKETING_VERSION을 project.yml에서 읽을 수 없습니다. 인자로 버전을 지정하세요."
  NOTES="Release v${VERSION}"
fi

# 버전 형식 검증 (semver-ish)
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "버전 형식이 X.Y.Z 가 아닙니다: $VERSION"

readonly TAG="v${VERSION}"

# ----- 태그 충돌 검사 -----

if git rev-parse "$TAG" >/dev/null 2>&1; then
  die "로컬에 이미 $TAG 태그가 존재합니다. (git tag -d $TAG 후 재시도)"
fi
if git ls-remote --tags origin "refs/tags/$TAG" 2>/dev/null | grep -q .; then
  die "원격에 이미 $TAG 태그가 존재합니다."
fi
if gh release view "$TAG" >/dev/null 2>&1; then
  die "GitHub에 이미 $TAG release가 존재합니다."
fi

# ----- 태그 생성 + push -----

log "태그 생성: $TAG"
git tag -a "$TAG" -m "$NOTES"

log "origin에 태그 push (workflow 트리거)"
git push origin "$TAG"

# ----- 안내 -----

REPO_SLUG="$(gh repo view --json nameWithOwner -q .nameWithOwner)"

cat <<EOF

✅ $TAG 태그가 push되어 GitHub Actions가 빌드를 시작합니다.

진행 상황 모니터링:
  gh run watch
  gh run list --workflow=release.yml

빌드 완료 후 release 확인:
  gh release view $TAG
  https://github.com/${REPO_SLUG}/releases/tag/${TAG}

빌드가 실패한 경우:
  gh run view --log-failed
  태그 제거: git push origin --delete $TAG && git tag -d $TAG
EOF
