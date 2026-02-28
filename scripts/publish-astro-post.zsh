#!/bin/zsh

set -e

# =========================
# 配置区
# =========================
ASTRO_ROOT="/home/source/My_github/myBlogs"
ASTRO_POSTS_DIR="$ASTRO_ROOT/src/content/posts"

AUTO_GIT_COMMIT="false"   # true / false
AUTO_BUILD="false"        # true / false

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

# =========================
# 工具函数
# =========================
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo -e "${RED}缺少命令: $1${NC}"
    exit 1
  }
}

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

trim() {
  echo "$1" | sed 's/^ *//;s/ *$//'
}

show_help() {
  echo "用法:"
  echo "  publish-astro-post <markdown文件>"
  echo ""
  echo "示例:"
  echo "  publish-astro-post /tmp/rewritten.md"
  echo "  publish-astro-post my-post.md"
}

# =========================
# 前置检查
# =========================
require_cmd git

if [[ $# -lt 1 ]]; then
  show_help
  exit 1
fi

INPUT_MD="$1"
if [[ "$INPUT_MD" != /* ]]; then
  INPUT_MD="$(pwd)/$INPUT_MD"
fi

if [[ ! -f "$INPUT_MD" ]]; then
  echo -e "${RED}Markdown 文件不存在: $INPUT_MD${NC}"
  exit 1
fi

if [[ ! -d "$ASTRO_ROOT" ]]; then
  echo -e "${RED}Astro 项目目录不存在: $ASTRO_ROOT${NC}"
  exit 1
fi

mkdir -p "$ASTRO_POSTS_DIR"

ARTICLE_NAME="$(basename "$INPUT_MD")"
ARTICLE_NAME="${ARTICLE_NAME%.md}"
ARTICLE_NAME="${ARTICLE_NAME%.markdown}"

DEFAULT_SLUG="$(slugify "$ARTICLE_NAME")"
CURRENT_DATE="$(date +%Y-%m-%d)"
CURRENT_DATETIME="$(date +'%Y-%m-%dT%H:%M:%S%z')"

echo -e "${CYAN}=== Astro 文章发布 ===${NC}"
echo -e "${BLUE}源文件: $INPUT_MD${NC}"
echo -e "${BLUE}默认 slug: $DEFAULT_SLUG${NC}"

echo -e "${YELLOW}请输入文章标题（默认: $ARTICLE_NAME）:${NC}"
read TITLE
[[ -z "$TITLE" ]] && TITLE="$ARTICLE_NAME"

echo -e "${YELLOW}请输入文章 slug（默认: $DEFAULT_SLUG）:${NC}"
read ARTICLE_SLUG
[[ -z "$ARTICLE_SLUG" ]] && ARTICLE_SLUG="$DEFAULT_SLUG"

echo -e "${YELLOW}请输入文章描述（可留空）:${NC}"
read DESCRIPTION

echo -e "${YELLOW}请输入标签 tags（逗号分隔，可留空）:${NC}"
read TAGS_INPUT

echo -e "${YELLOW}请输入分类 categories（逗号分隔，可留空）:${NC}"
read CATEGORIES_INPUT

echo -e "${YELLOW}是否设为草稿 draft? (y/N):${NC}"
read DRAFT_INPUT
DRAFT="false"
if [[ "$DRAFT_INPUT" =~ ^[Yy]$ ]]; then
  DRAFT="true"
fi

echo -e "${YELLOW}是否设置封面 cover? (y/N):${NC}"
read COVER_CHOICE
COVER=""
if [[ "$COVER_CHOICE" =~ ^[Yy]$ ]]; then
  echo -e "${YELLOW}请输入 cover 图片 URL:${NC}"
  read COVER
fi

echo -e "${YELLOW}是否设置 heroImage? (y/N):${NC}"
read HERO_CHOICE
HERO_IMAGE=""
if [[ "$HERO_CHOICE" =~ ^[Yy]$ ]]; then
  echo -e "${YELLOW}请输入 heroImage 图片 URL:${NC}"
  read HERO_IMAGE
fi

TARGET_FILE="$ASTRO_POSTS_DIR/${CURRENT_DATE}-${ARTICLE_SLUG}.md"

COUNTER=1
while [[ -f "$TARGET_FILE" ]]; do
  TARGET_FILE="$ASTRO_POSTS_DIR/${CURRENT_DATE}-${ARTICLE_SLUG}-${COUNTER}.md"
  ((COUNTER++))
done

echo -e "${PURPLE}=== Frontmatter 预览 ===${NC}"
echo "---"
echo "title: \"$TITLE\""
echo "pubDate: \"$CURRENT_DATETIME\""
[[ -n "$DESCRIPTION" ]] && echo "description: \"$DESCRIPTION\""
echo "draft: $DRAFT"

if [[ -n "$TAGS_INPUT" ]]; then
  echo "tags:"
  IFS=',' read -rA TAGS <<< "$TAGS_INPUT"
  for tag in "${TAGS[@]}"; do
    tag="$(trim "$tag")"
    [[ -n "$tag" ]] && echo "  - \"$tag\""
  done
fi

if [[ -n "$CATEGORIES_INPUT" ]]; then
  echo "categories:"
  IFS=',' read -rA CATES <<< "$CATEGORIES_INPUT"
  for cate in "${CATES[@]}"; do
    cate="$(trim "$cate")"
    [[ -n "$cate" ]] && echo "  - \"$cate\""
  done
fi

[[ -n "$COVER" ]] && echo "cover: \"$COVER\""
[[ -n "$HERO_IMAGE" ]] && echo "heroImage: \"$HERO_IMAGE\""
echo "---"

echo -e "${YELLOW}确认写入 Astro 文章目录? (y/N):${NC}"
read CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo -e "${YELLOW}已取消${NC}"
  exit 0
fi

{
  echo "---"
  echo "title: \"$TITLE\""
  echo "pubDate: \"$CURRENT_DATETIME\""
  [[ -n "$DESCRIPTION" ]] && echo "description: \"$DESCRIPTION\""
  echo "draft: $DRAFT"

  if [[ -n "$TAGS_INPUT" ]]; then
    echo "tags:"
    IFS=',' read -rA TAGS <<< "$TAGS_INPUT"
    for tag in "${TAGS[@]}"; do
      tag="$(trim "$tag")"
      [[ -n "$tag" ]] && echo "  - \"$tag\""
    done
  fi

  if [[ -n "$CATEGORIES_INPUT" ]]; then
    echo "categories:"
    IFS=',' read -rA CATES <<< "$CATEGORIES_INPUT"
    for cate in "${CATES[@]}"; do
      cate="$(trim "$cate")"
      [[ -n "$cate" ]] && echo "  - \"$cate\""
    done
  fi

  [[ -n "$COVER" ]] && echo "cover: \"$COVER\""
  [[ -n "$HERO_IMAGE" ]] && echo "heroImage: \"$HERO_IMAGE\""

  echo "---"
  echo
  cat "$INPUT_MD"
} > "$TARGET_FILE"

echo -e "${GREEN}✓ 文章已生成: $TARGET_FILE${NC}"

if [[ "$AUTO_GIT_COMMIT" == "true" ]]; then
  cd "$ASTRO_ROOT"
  git add .
  if ! git diff --cached --quiet; then
    git commit -m "add post: $ARTICLE_SLUG"
    echo -e "${GREEN}✓ 已提交 Astro 博客仓库${NC}"
  else
    echo -e "${YELLOW}无变更可提交${NC}"
  fi
fi

if [[ "$AUTO_BUILD" == "true" ]]; then
  cd "$ASTRO_ROOT"
  if command -v pnpm >/dev/null 2>&1; then
    pnpm build
  elif command -v npm >/dev/null 2>&1; then
    npm run build
  fi
  echo -e "${GREEN}✓ 构建完成${NC}"
fi

echo -e "${CYAN}=== 完成 ===${NC}"
