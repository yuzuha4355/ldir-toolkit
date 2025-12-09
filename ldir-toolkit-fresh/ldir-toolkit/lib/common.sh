#!/bin/bash
#
# LDIR-Toolkit - Common Functions Library
# 共通関数ライブラリ
#

# カラー定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ログ関数
log_info() {
    local msg="$1"
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - ${msg}"
    if [[ -n "${OUTPUT_DIR:-}" && -d "${OUTPUT_DIR}/metadata" ]]; then
        echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - ${msg}" >> "${OUTPUT_DIR}/metadata/collection.log"
    fi
}

log_error() {
    local msg="$1"
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - ${msg}" >&2
    if [[ -n "${OUTPUT_DIR:-}" && -d "${OUTPUT_DIR}/metadata" ]]; then
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - ${msg}" >> "${OUTPUT_DIR}/metadata/collection.log"
    fi
}

log_success() {
    local msg="$1"
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - ${msg}"
    if [[ -n "${OUTPUT_DIR:-}" && -d "${OUTPUT_DIR}/metadata" ]]; then
        echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - ${msg}" >> "${OUTPUT_DIR}/metadata/collection.log"
    fi
}

log_warn() {
    local msg="$1"
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - ${msg}"
    if [[ -n "${OUTPUT_DIR:-}" && -d "${OUTPUT_DIR}/metadata" ]]; then
        echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - ${msg}" >> "${OUTPUT_DIR}/metadata/collection.log"
    fi
}

log_module() {
    local msg="$1"
    echo -e "${BLUE}[MODULE]${NC} $(date '+%Y-%m-%d %H:%M:%S') - ${msg}"
    if [[ -n "${OUTPUT_DIR:-}" && -d "${OUTPUT_DIR}/metadata" ]]; then
        echo "[MODULE] $(date '+%Y-%m-%d %H:%M:%S') - ${msg}" >> "${OUTPUT_DIR}/metadata/collection.log"
    fi
}

# 安全なファイルコピー（エラーがあっても継続）
safe_copy() {
    local src="$1"
    local dst="$2"
    
    if [[ -e "$src" ]]; then
        cp -r "$src" "$dst" 2>/dev/null && return 0 || {
            log_warn "Failed to copy: $src"
            return 1
        }
    else
        log_warn "File not found: $src"
        return 1
    fi
}

# コマンド出力を保存
save_command_output() {
    local cmd="$1"
    local output_file="$2"
    local description="${3:-$cmd}"
    
    if eval "$cmd" > "$output_file" 2>&1; then
        return 0
    else
        log_warn "Command failed: $description"
        return 1
    fi
}

# ファイルが存在するかチェックして処理
process_if_exists() {
    local file="$1"
    local action="$2"
    
    if [[ -e "$file" ]]; then
        eval "$action"
        return 0
    else
        return 1
    fi
}
