#!/usr/bin/env bash
#
# release.sh — Korean Outliner 빌드/패키징 스크립트
#
# Usage:
#   ./scripts/release.sh project       Xcode 프로젝트 생성/재생성 (XcodeGen)
#   ./scripts/release.sh app           .app 빌드만
#   ./scripts/release.sh dmg           .app → .dmg
#   ./scripts/release.sh pkg           .app → .pkg
#   ./scripts/release.sh all           project + app + dmg + pkg
#   ./scripts/release.sh notarize PATH 파일 notarize + staple
#   ./scripts/release.sh clean         build/, dist/ 삭제
#
# Environment (선택):
#   DEVELOPER_ID_APPLICATION  "Developer ID Application: Name (TEAMID)" — .app/.dmg 사인용
#   DEVELOPER_ID_INSTALLER    "Developer ID Installer: Name (TEAMID)"   — .pkg 사인용
#   NOTARY_PROFILE            xcrun notarytool store-credentials 프로파일 이름
#   CONFIGURATION             Release | Debug (기본 Release)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

readonly PROJECT_NAME="KoreanOutliner"
readonly SCHEME="$PROJECT_NAME"
readonly PRODUCT_NAME="Korean Outliner"
readonly BUNDLE_ID="com.naxreo.koreanoutliner"
readonly CONFIGURATION="${CONFIGURATION:-Release}"
readonly BUILD_DIR="$ROOT_DIR/build"
readonly DIST_DIR="$ROOT_DIR/dist"
readonly DERIVED_DATA="$BUILD_DIR/DerivedData"
readonly APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/$PRODUCT_NAME.app"

# ---------- helpers ----------

log()  { printf "\033[36m▸ %s\033[0m\n" "$*"; }
warn() { printf "\033[33m! %s\033[0m\n" "$*"; }
die()  { printf "\033[31m✘ %s\033[0m\n" "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "$1 명령이 없습니다. 설치 후 다시 실행하세요."
}

ensure_xcodeproj() {
  if [[ ! -d "$ROOT_DIR/$PROJECT_NAME.xcodeproj" ]]; then
    warn "$PROJECT_NAME.xcodeproj 이 없습니다. './scripts/release.sh project' 로 먼저 생성하세요."
    return 1
  fi
}

read_marketing_version() {
  /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "0.0.0"
}

# ---------- commands ----------

cmd_project() {
  require_cmd xcodegen
  log "XcodeGen으로 $PROJECT_NAME.xcodeproj 생성"
  xcodegen generate --spec "$ROOT_DIR/project.yml" --project "$ROOT_DIR"
  log "생성 완료: $PROJECT_NAME.xcodeproj"
}

cmd_app() {
  ensure_xcodeproj || die "프로젝트가 없습니다."
  require_cmd xcodebuild

  log "빌드 환경 정리"
  rm -rf "$DERIVED_DATA"
  mkdir -p "$BUILD_DIR"

  log "xcodebuild ($CONFIGURATION)"
  xcodebuild \
    -project "$ROOT_DIR/$PROJECT_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" \
    -destination "platform=macOS" \
    CODE_SIGN_IDENTITY="${DEVELOPER_ID_APPLICATION:-}" \
    OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" \
    build

  [[ -d "$APP_PATH" ]] || die ".app 산출물이 보이지 않습니다: $APP_PATH"

  if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    log ".app 코드사인 (Developer ID Application)"
    codesign --force --deep --options runtime --timestamp \
      --sign "$DEVELOPER_ID_APPLICATION" "$APP_PATH"
    codesign --verify --deep --strict --verbose=2 "$APP_PATH"
  else
    warn "DEVELOPER_ID_APPLICATION 미설정 → 사인되지 않은 ad-hoc 빌드"
  fi

  log "산출물: $APP_PATH"
}

cmd_dmg() {
  [[ -d "$APP_PATH" ]] || cmd_app
  require_cmd hdiutil
  mkdir -p "$DIST_DIR"

  local version dmg_name staging
  version="$(read_marketing_version)"
  dmg_name="$DIST_DIR/${PROJECT_NAME}-${version}.dmg"
  staging="$BUILD_DIR/dmg-staging"

  log "DMG 스테이징 준비"
  rm -rf "$staging" "$dmg_name"
  mkdir -p "$staging"
  cp -R "$APP_PATH" "$staging/"
  ln -s /Applications "$staging/Applications"

  log "DMG 생성: $dmg_name"
  hdiutil create \
    -volname "$PRODUCT_NAME" \
    -srcfolder "$staging" \
    -ov -format ULFO \
    "$dmg_name" >/dev/null

  if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    log "DMG 코드사인"
    codesign --force --sign "$DEVELOPER_ID_APPLICATION" --timestamp "$dmg_name"
  else
    warn "DEVELOPER_ID_APPLICATION 미설정 → DMG 미사인"
  fi

  log "산출물: $dmg_name"
}

cmd_pkg() {
  [[ -d "$APP_PATH" ]] || cmd_app
  require_cmd pkgbuild
  require_cmd productbuild
  mkdir -p "$DIST_DIR"

  local version component_pkg dist_pkg
  version="$(read_marketing_version)"
  component_pkg="$BUILD_DIR/${PROJECT_NAME}-component.pkg"
  dist_pkg="$DIST_DIR/${PROJECT_NAME}-${version}.pkg"

  log "Component pkg 생성"
  pkgbuild \
    --component "$APP_PATH" \
    --identifier "$BUNDLE_ID" \
    --version "$version" \
    --install-location "/Applications" \
    "$component_pkg"

  log "Distribution pkg 생성"
  if [[ -n "${DEVELOPER_ID_INSTALLER:-}" ]]; then
    productbuild \
      --package "$component_pkg" \
      --identifier "$BUNDLE_ID" \
      --version "$version" \
      --sign "$DEVELOPER_ID_INSTALLER" \
      "$dist_pkg"
  else
    productbuild \
      --package "$component_pkg" \
      --identifier "$BUNDLE_ID" \
      --version "$version" \
      "$dist_pkg"
    warn "DEVELOPER_ID_INSTALLER 미설정 → PKG 미사인"
  fi

  rm -f "$component_pkg"
  log "산출물: $dist_pkg"
}

cmd_notarize() {
  local target="${1:-}"
  [[ -n "$target" && -e "$target" ]] || die "notarize 대상 파일을 지정하세요 (예: dist/KoreanOutliner-1.0.0.dmg)"
  [[ -n "${NOTARY_PROFILE:-}" ]] || die "NOTARY_PROFILE 환경변수가 필요합니다 (xcrun notarytool store-credentials)"
  require_cmd xcrun

  log "notarytool submit (대기 모드)"
  xcrun notarytool submit "$target" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

  log "스테이플"
  xcrun stapler staple "$target"
  xcrun stapler validate "$target"
  log "notarize 완료: $target"
}

cmd_clean() {
  log "build/, dist/ 정리"
  rm -rf "$BUILD_DIR" "$DIST_DIR"
}

cmd_all() {
  cmd_project
  cmd_app
  cmd_dmg
  cmd_pkg
}

# ---------- entry ----------

case "${1:-help}" in
  project)  cmd_project ;;
  app)      cmd_app ;;
  dmg)      cmd_dmg ;;
  pkg)      cmd_pkg ;;
  notarize) shift; cmd_notarize "$@" ;;
  clean)    cmd_clean ;;
  all)      cmd_all ;;
  help|*)
    sed -n '2,20p' "$0"
    ;;
esac
