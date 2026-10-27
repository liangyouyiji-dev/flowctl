#!/usr/bin/env bash
# v6.33 #82: flowctl 一键安装脚本
#
# 用法 (curl pipe):
#   curl -fsSL https://raw.githubusercontent.com/liangyouyiji-dev/flowctl/main/scripts/install.sh | bash
#
# 自定义版本 / 安装目录:
#   FLOWCTL_VERSION=v0.2.0 INSTALL_DIR=/usr/local/bin curl -fsSL ... | bash
#
# 离线模式必须同时提供已签名 checksum 的三个 sidecar:
#   bash install.sh --from-archive ./flowctl_0.1.0_linux_amd64.tar.gz \
#     --checksum ./flowctl_0.1.0_checksums.txt \
#     --signature ./flowctl_0.1.0_checksums.txt.sig \
#     --certificate ./flowctl_0.1.0_checksums.txt.pem

set -euo pipefail

REPO_OWNER="${FLOWCTL_REPO_OWNER:-liangyouyiji-dev}"
REPO_NAME="${FLOWCTL_REPO_NAME:-flowctl}"
VERSION="${FLOWCTL_VERSION:-latest}"
INSTALL_DIR="${INSTALL_DIR:-${HOME}/.local/bin}"
SKILL_DIR="${FLOWCTL_SKILL_DIR:-}"
ARCHIVE_FROM=""
CHECKSUM_FROM=""
SIGNATURE_FROM=""
CERTIFICATE_FROM=""
CERTIFICATE_ISSUER="https://token.actions.githubusercontent.com"
CERTIFICATE_IDENTITY='^https://github\.com/liangyouyiji-dev/flowctl/\.github/workflows/release\.yml@refs/tags/v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="$2"; shift 2;;
    --install-dir) INSTALL_DIR="$2"; shift 2;;
    --skill-dir) SKILL_DIR="$2"; shift 2;;
    --from-archive) ARCHIVE_FROM="$2"; shift 2;;
    --checksum) CHECKSUM_FROM="$2"; shift 2;;
    --signature) SIGNATURE_FROM="$2"; shift 2;;
    --certificate) CERTIFICATE_FROM="$2"; shift 2;;
    --no-skill) SKIP_SKILL=1; shift;;
    --help|-h)
      cat <<EOF
flowctl installer

环境变量:
  FLOWCTL_VERSION    版本 (默认 latest)
  INSTALL_DIR        二进制安装目录 (默认 ~/.local/bin)
  FLOWCTL_SKILL_DIR  自定义 Skill 安装目录（默认同时安装 Claude Code 和 Codex）

参数:
  --version <v>          指定版本 (e.g. v0.1.0)
  --install-dir <dir>    二进制安装目录
  --skill-dir <dir>      仅安装到指定 Skill 目录
  --from-archive <path>  离线模式: 从本地 tar.gz/zip 安装
  --checksum <path>      离线 checksum manifest（必填）
  --signature <path>     离线 checksum cosign 签名（必填）
  --certificate <path>   离线 checksum cosign 证书（必填）
  --no-skill             跳过 Skill 安装
  -h, --help             此帮助
EOF
      exit 0;;
    *) echo "✗ unknown arg: $1" >&2; exit 2;;
  esac
done

err() { echo "✗ $*" >&2; exit 1; }
info() { echo "  $*"; }

# 1. 检测 OS / arch
detect_platform() {
  local os arch
  case "$(uname -s)" in
    Darwin)  os=darwin;;
    Linux)   os=linux;;
    MINGW*|MSYS*|CYGWIN*) os=windows;;
    *) err "不支持的 OS: $(uname -s) (Windows 用户请直接下载 zip)";;
  esac
  case "$(uname -m)" in
    x86_64|amd64)    arch=amd64;;
    arm64|aarch64)   arch=arm64;;
    i386|i486|i586|i686) arch=386;;
    riscv64)         arch=riscv64;;
    *) err "不支持的 arch: $(uname -m)";;
  esac
  # macOS 无 386/riscv64 build
  if [ "$os" = darwin ] && { [ "$arch" = "386" ] || [ "$arch" = "riscv64" ]; }; then
    err "macOS $arch build 没出 (只有 amd64/arm64)"
  fi
  echo "${os}_${arch}"
}

PLATFORM="$(detect_platform)"
OS="${PLATFORM%_*}"
ARCH="${PLATFORM#*_}"

echo "flowctl installer"
info "platform:    ${PLATFORM}"
info "version:     ${VERSION}"
info "install dir: ${INSTALL_DIR}"
echo

# 2. 解析 latest 版本
if [ -z "$ARCHIVE_FROM" ] && [ "$VERSION" = "latest" ]; then
  info "[1/4] 解析 latest 版本"
  api="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"
  if ! VERSION="$(curl -fsSL "$api" 2>/dev/null | grep -E '"tag_name"' | head -1 | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"; then
    err "拉 latest release 失败 (检查网络 / repo $REPO_OWNER/$REPO_NAME 是否存在)"
  fi
  if [ -z "$VERSION" ]; then
    err "解析 latest 版本失败 (没有 release? 用 --version 显式指定)"
  fi
  info "  → ${VERSION}"
fi

# 3. 下载 / 解压
TMPDIR="$(mktemp -d -t flowctl-install-XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

VERSION_NO_V="${VERSION#v}"
EXT="tar.gz"
[ "$OS" = "windows" ] && EXT="zip"
ARCHIVE_NAME="flowctl_${VERSION_NO_V}_${PLATFORM}.${EXT}"
if [ -n "$ARCHIVE_FROM" ]; then
  ARCHIVE_NAME="$(basename "$ARCHIVE_FROM")"
fi
ARCHIVE_PATH="$TMPDIR/$ARCHIVE_NAME"
CHECKSUM_NAME="flowctl_${VERSION_NO_V}_checksums.txt"
CHECKSUM_PATH="$TMPDIR/$CHECKSUM_NAME"
SIGNATURE_PATH="$CHECKSUM_PATH.sig"
CERTIFICATE_PATH="$CHECKSUM_PATH.pem"

if [ -n "$ARCHIVE_FROM" ]; then
  info "[2/4] 离线模式: 复制 $ARCHIVE_FROM"
  [ -n "$CHECKSUM_FROM" ] || err "离线安装必须指定 --checksum"
  [ -n "$SIGNATURE_FROM" ] || err "离线安装必须指定 --signature"
  [ -n "$CERTIFICATE_FROM" ] || err "离线安装必须指定 --certificate"
  cp "$ARCHIVE_FROM" "$ARCHIVE_PATH"
  cp "$CHECKSUM_FROM" "$CHECKSUM_PATH"
  cp "$SIGNATURE_FROM" "$SIGNATURE_PATH"
  cp "$CERTIFICATE_FROM" "$CERTIFICATE_PATH"
else
  RELEASE_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/${VERSION}"
  URL="${RELEASE_URL}/${ARCHIVE_NAME}"
  info "[2/4] 下载 $URL"
  curl -fsSL "$URL" -o "$ARCHIVE_PATH" || err "下载失败"
  curl -fsSL "${RELEASE_URL}/${CHECKSUM_NAME}" -o "$CHECKSUM_PATH" || err "下载 checksum 失败"
  curl -fsSL "${RELEASE_URL}/${CHECKSUM_NAME}.sig" -o "$SIGNATURE_PATH" || err "下载 checksum 签名失败"
  curl -fsSL "${RELEASE_URL}/${CHECKSUM_NAME}.pem" -o "$CERTIFICATE_PATH" || err "下载 checksum 证书失败"
fi

command -v cosign >/dev/null 2>&1 || err "需要 cosign 验证发布签名，请先安装 cosign"
info "[3/5] 验证发布者身份和 archive checksum"
cosign verify-blob \
  --certificate "$CERTIFICATE_PATH" \
  --signature "$SIGNATURE_PATH" \
  --certificate-oidc-issuer "$CERTIFICATE_ISSUER" \
  --certificate-identity-regexp "$CERTIFICATE_IDENTITY" \
  "$CHECKSUM_PATH" >/dev/null || err "checksum 发布签名或发布者身份无效"

EXPECTED_SUM="$(awk -v name="$ARCHIVE_NAME" '{ file=$2; sub(/^\*/, "", file); if (file == name) { print tolower($1); exit } }' "$CHECKSUM_PATH")"
[ -n "$EXPECTED_SUM" ] || err "checksum manifest 中找不到 $ARCHIVE_NAME"
if command -v sha256sum >/dev/null 2>&1; then
  ACTUAL_SUM="$(sha256sum "$ARCHIVE_PATH" | awk '{print tolower($1)}')"
else
  ACTUAL_SUM="$(shasum -a 256 "$ARCHIVE_PATH" | awk '{print tolower($1)}')"
fi
[ "$ACTUAL_SUM" = "$EXPECTED_SUM" ] || err "archive checksum 不匹配"

info "[4/5] 解压 + 安装到 $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
if [ "$EXT" = "tar.gz" ]; then
  tar xzf "$ARCHIVE_PATH" -C "$TMPDIR"
else
  unzip -q "$ARCHIVE_PATH" -d "$TMPDIR"
fi

# 找到 flowctl 二进制 (无论是 root 还是 子目录)
BIN_PATH="$(find "$TMPDIR" -name 'flowctl' -o -name 'flowctl.exe' 2>/dev/null | grep -v "$ARCHIVE_NAME" | head -1)"
[ -z "$BIN_PATH" ] && err "解压后找不到 flowctl 二进制"

# 签名只能证明制品来源；安装前还必须校验版本坐标和命令合同能力，
# 防止同一 SemVer 下安装协议不兼容或缺少构建身份的旧二进制。
VERIFY_HOME="$TMPDIR/verify-home"
mkdir -p "$VERIFY_HOME"
if ! HOME="$VERIFY_HOME" FLOWCTL_DISABLE_ERROR_REPORT=1 "$BIN_PATH" version \
  --verify-artifact \
  --expected-version "$VERSION_NO_V" \
  --require-contract schema/v1 \
  --require-clean \
  --format raw >/dev/null; then
  err "artifact build identity/contract profile invalid; refuse installation"
fi

INSTALL_PATH="$INSTALL_DIR/flowctl"
[ "$OS" = "windows" ] && INSTALL_PATH="${INSTALL_PATH}.exe"
INSTALL_TMP="$INSTALL_PATH.tmp"
mv "$BIN_PATH" "$INSTALL_TMP"
chmod +x "$INSTALL_TMP"

# Warm and verify the exact installation inode before the atomic rename. On
# managed macOS hosts, first execution of a new Mach-O inode may spend seconds
# in provenance/EDR scanning; doing it here keeps the first user command fast.
if ! HOME="$VERIFY_HOME" FLOWCTL_DISABLE_ERROR_REPORT=1 "$INSTALL_TMP" version \
  --verify-artifact \
  --expected-version "$VERSION_NO_V" \
  --require-contract schema/v1 \
  --require-clean \
  --format raw >/dev/null; then
  rm -f "$INSTALL_TMP"
  err "installed artifact build identity/contract profile invalid; refuse installation"
fi
mv "$INSTALL_TMP" "$INSTALL_PATH"

# 4. 装 Skill
if [ "${SKIP_SKILL:-0}" != "1" ]; then
  if [ -n "$SKILL_DIR" ]; then
    info "[5/5] 装 base Skill 到 $SKILL_DIR"
    SKILL_ARGS=(--target "$SKILL_DIR")
  else
    info "[5/5] 同步 Claude Code 和 Codex base Skill"
    SKILL_ARGS=()
  fi
  "$INSTALL_PATH" install-skill "${SKILL_ARGS[@]}" >/dev/null 2>&1 || {
    info "  (Skill 安装失败, 但二进制已装好; 用 \`flowctl install-skill\` 重试)"
  }
fi

echo
echo "✓ Installed flowctl:"
"$INSTALL_PATH" version 2>&1 | sed 's/^/    /'
echo

# PATH 提示
case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *)
    cat <<EOF
⚠ ${INSTALL_DIR} 不在 \$PATH 里. 加到 shell rc:

  echo 'export PATH="$INSTALL_DIR:\$PATH"' >> ~/.zshrc
  source ~/.zshrc

或直接调用全路径: ${INSTALL_PATH}

EOF
    ;;
esac

cat <<EOF
快速上手:
  flowctl status                          # 检查 BE 是否在线
  flowctl whoami                          # 当前身份
  flowctl version --check                 # 检查更新
  flowctl --help                          # 子命令一览

文档: https://github.com/${REPO_OWNER}/${REPO_NAME}
EOF
