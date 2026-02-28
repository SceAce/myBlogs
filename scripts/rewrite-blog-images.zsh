#!/bin/zsh

set -e

# =========================
# 配置区
# =========================
ASTRO_ROOT="/home/source/My_github/myBlogs"
ASTRO_POSTS_DIR="$ASTRO_ROOT/src/content/posts"

IMAGE_REPO_LOCAL="$HOME/My_github/picx-images-hosting"
IMAGE_REPO_GH="SceAce/picx-images-hosting"
IMAGE_BRANCH="master"
CDN_BASE="https://cdn.jsdelivr.net/gh/$IMAGE_REPO_GH@$IMAGE_BRANCH"

TEMP_DIR="/tmp/astro_blog_upload_$$"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

mkdir -p "$TEMP_DIR"

# =========================
# 工具函数
# =========================

slugify() {
  local input="$1"
  echo "$input" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[[:space:]]\+/-/g' \
    | sed 's/[^a-z0-9_-]/-/g' \
    | sed 's/-\+/-/g' \
    | sed 's/^-//' \
    | sed 's/-$//'
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo -e "${RED}缺少命令: $1${NC}"
    exit 1
  }
}

upload_images_and_rewrite_md() {
  local md_file="$1"
  local article_slug="$2"
  local year="$3"

  local image_target_dir="$IMAGE_REPO_LOCAL/blog/$year/$article_slug"
  mkdir -p "$image_target_dir"

  local rewritten_md="$TEMP_DIR/rewritten.md"
  cp "$md_file" "$rewritten_md"

  # 匹配 Markdown 图片语法中的本地路径
  # 支持:
  # ![alt](./img/xxx.png)
  # ![alt](img/xxx.png)
  # ![alt](../img/xxx.png) -> 这里暂不处理，建议统一用 ./img 或 img
  python3 - "$rewritten_md" "$image_target_dir" "$CDN_BASE" "$year" "$article_slug" <<'PY'
import os
import re
import sys
import shutil
from pathlib import Path

md_path = Path(sys.argv[1])
image_target_dir = Path(sys.argv[2])
cdn_base = sys.argv[3]
year = sys.argv[4]
article_slug = sys.argv[5]

content = md_path.read_text(encoding="utf-8")
md_dir = md_path.parent

pattern = re.compile(r'!\[([^\]]*)\]\((\.?/)?img/([^)]+)\)')

def replace(match):
    alt = match.group(1)
    filename = match.group(3)

    src = md_dir / "img" / filename
    if not src.exists():
        print(f"[WARN] 图片不存在: {src}", file=sys.stderr)
        return match.group(0)

    dst = image_target_dir / Path(filename).name
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)

    cdn_url = f"{cdn_base}/blog/{year}/{article_slug}/{Path(filename).name}"
    return f"![{alt}]({cdn_url})"

new_content = pattern.sub(replace, content)
md_path.write_text(new_content, encoding="utf-8")
PY

  echo "$rewritten_md"
}

commit_and_push_image_repo() {
  local message="$1"
  cd "$IMAGE_REPO_LOCAL"

  git add .
  if ! git diff --cached --quiet; then
    git commit -m "$message"
    git push origin "$IMAGE_BRANCH"
    echo -e "${GREEN}✓ 图片已推送到图床仓库${NC}"
  else
    echo -e "${YELLOW}没有新的图片变更，跳过图床仓库提交${NC}"
  fi
}

show_help() {
  echo "用法:"
  echo "  publish-astro <markdown文件> [图片目录]"
  echo ""
  echo "示例:"
  echo "  publish-astro my-post.md"
  echo "  publish-astro my-post.md img"
}

# =========================
# 前置检查
# =========================
require_cmd git
require_cmd python3

if [[ $# -lt 1 ]]; then
  show_help
  exit 1
fi

MD_FILE="$1"
if [[ "$MD_FILE" != /* ]]; then
  MD_FILE="$(pwd)/$MD_FILE"
fi

if [[ ! -f "$MD_FILE" ]]; then
  echo -e "${RED}Markdown 文件不存在: $MD_FILE${NC}"
  exit 1
fi

if [[ ! -d "$ASTRO_ROOT" ]]; then
  echo -e "${RED}Astro 项目目录不存在: $ASTRO_ROOT${NC}"
  exit 1
fi

if [[ ! -d "$IMAGE_REPO_LOCAL/.git" ]]; then
  echo -e "${RED}本地图床仓库不存在或不是 git 仓库: $IMAGE_REPO_LOCAL${NC}"
  exit 1
fi

mkdir -p "$ASTRO_POSTS_DIR"

cp "$MD_FILE" "$TEMP_DIR/$(basename "$MD_FILE")"
WORK_MD="$TEMP_DIR/$(basename "$MD_FILE")"

# 如果用户提供了图片目录，就复制到临时目录下 img/
if [[ $# -ge 2 && -d "$2" ]]; then
  mkdir -p "$TEMP_DIR/img"
  cp -r "$2"/* "$TEMP_DIR/img/" 2>/dev/null || true
else
  ORIG_DIR="$(dirname "$MD_FILE")"
  if [[ -d "$ORIG_DIR/img" ]]; then
    mkdir -p "$TEMP_DIR/img"
    cp -r "$ORIG_DIR/img"/* "$TEMP_DIR/img/" 2>/dev/null || true
  fi
fi

ARTICLE_NAME="$(basename "$MD_FILE")"
ARTICLE_NAME="${ARTICLE_NAME%.md}"
ARTICLE_NAME="${ARTICLE_NAME%.markdown}"

DEFAULT_SLUG="$(slugify "$ARTICLE_NAME")"
CURRENT_DATE="$(date +%Y-%m-%d)"
CURRENT_YEAR="$(date +%Y)"

echo -e "${CYAN}=== Astro 发布 ===${NC}"
echo -e "${BLUE}原始文件: $MD_FILE${NC}"
echo -e "${BLUE}默认 slug: $DEFAULT_SLUG${NC}"

echo -e "${YELLOW}请输入文章标题（默认: $ARTICLE_NAME）:${NC}"
read TITLE
[[ -z "$TITLE" ]] && TITLE="$ARTICLE_NAME"

echo -e "${YELLOW}请输入文章 slug（默认: $DEFAULT_SLUG）:${NC}"
read ARTICLE_SLUG
[[ -z "$ARTICLE_SLUG" ]] && ARTICLE_SLUG="$DEFAULT_SLUG"

echo -e "${YELLOW}请输入标签（逗号分隔，可留空）:${NC}"
read TAGS_INPUT

echo -e "${YELLOW}请输入分类（逗号分隔，可留空）:${NC}"
read CATEGORIES_INPUT

echo -e "${YELLOW}请输入描述（可留空）:${NC}"
read DESCRIPTION

# 先上传图片并替换 Markdown 中的本地链接
if [[ -d "$TEMP_DIR/img" ]]; then
  echo -e "${BLUE}检测到本地图片，开始上传并替换链接...${NC}"
  WORK_MD="$(upload_images_and_rewrite_md "$WORK_MD" "$ARTICLE_SLUG" "$CURRENT_YEAR")"
  commit_and_push_image_repo "add images for $ARTICLE_SLUG"
else
  echo -e "${YELLOW}未检测到 img/ 目录，跳过图片上传${NC}"
fi

TARGET_FILE="$ASTRO_POSTS_DIR/${CURRENT_DATE}-${ARTICLE_SLUG}.md"

# 避免重名
COUNTER=1
while [[ -f "$TARGET_FILE" ]]; do
  TARGET_FILE="$ASTRO_POSTS_DIR/${CURRENT_DATE}-${ARTICLE_SLUG}-${COUNTER}.md"
  ((COUNTER++))
done

{
  echo "---"
  echo "title: \"$TITLE\""
  echo "pubDate: $CURRENT_DATE"
  [[ -n "$DESCRIPTION" ]] && echo "description: \"$DESCRIPTION\""

  if [[ -n "$TAGS_INPUT" ]]; then
    echo "tags:"
    IFS=',' read -rA TAGS <<< "$TAGS_INPUT"
    for tag in "${TAGS[@]}"; do
      tag="$(echo "$tag" | sed 's/^ *//;s/ *$//')"
      [[ -n "$tag" ]] && echo "  - \"$tag\""
    done
  fi

  if [[ -n "$CATEGORIES_INPUT" ]]; then
    echo "categories:"
    IFS=',' read -rA CATES <<< "$CATEGORIES_INPUT"
    for cate in "${CATES[@]}"; do
      cate="$(echo "$cate" | sed 's/^ *//;s/ *$//')"
      [[ -n "$cate" ]] && echo "  - \"$cate\""
    done
  fi

  echo "---"
  echo
  cat "$WORK_MD"
} > "$TARGET_FILE"

echo -e "${GREEN}✓ 文章已生成: $TARGET_FILE${NC}"
echo -e "${CYAN}=== 完成 ===${NC}"
