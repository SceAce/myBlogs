#!/bin/zsh

set -euo pipefail

ASTRO_ROOT="/home/source/My_github/myBlogs"
ASTRO_POSTS_DIR="$ASTRO_ROOT/src/content/posts"

IMAGE_REPO_LOCAL="$HOME/My_github/picx-images-hosting"
IMAGE_REPO_GH="SceAce/picx-images-hosting"
IMAGE_BRANCH="master"
CDN_BASE="https://cdn.jsdelivr.net/gh/$IMAGE_REPO_GH@$IMAGE_BRANCH"

TEMP_DIR="/tmp/astro_post_import_$$"

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

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || {
		echo -e "${RED}缺少命令: $1${NC}"
		exit 1
	}
}

abs_path() {
	python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$1"
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

yaml_escape() {
	python3 -c 'import json,sys; print(json.dumps(sys.argv[1], ensure_ascii=False))' "$1"
}

normalize_date() {
	python3 - "$1" <<'PY'
from datetime import datetime
import re
import sys

raw = sys.argv[1].strip()
match = re.fullmatch(r"(\d{4})-(\d{1,2})-(\d{1,2})", raw)
if not match:
    raise SystemExit(1)

normalized = f"{match.group(1)}-{int(match.group(2)):02d}-{int(match.group(3)):02d}"
print(datetime.strptime(normalized, "%Y-%m-%d").strftime("%Y-%m-%d"))
PY
}

prompt_with_default() {
	local var_name="$1"
	local prompt_text="$2"
	local default_value="${3:-}"
	local input=""

	if [[ -n "$default_value" ]]; then
		echo -e "${YELLOW}${prompt_text}（默认: $default_value）:${NC}"
	else
		echo -e "${YELLOW}${prompt_text}:${NC}"
	fi

	read input
	[[ -z "$input" ]] && input="$default_value"
	typeset -g "$var_name=$input"
}

strip_frontmatter() {
	local source_file="$1"
	local target_file="$2"

	python3 - "$source_file" "$target_file" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
target = Path(sys.argv[2])

lines = source.splitlines(keepends=True)
if lines and lines[0].strip() == "---":
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            target.write_text("".join(lines[i + 1:]), encoding="utf-8")
            break
    else:
        target.write_text(source, encoding="utf-8")
else:
    target.write_text(source, encoding="utf-8")
PY
}

rewrite_and_upload_images() {
	local body_file="$1"
	local source_dir="$2"
	local image_repo_target_dir="$3"
	local cdn_base="$4"
	local year="$5"
	local article_slug="$6"
	local custom_image_dir="${7:-}"

	python3 - "$body_file" "$source_dir" "$image_repo_target_dir" "$cdn_base" "$year" "$article_slug" "$custom_image_dir" <<'PY'
from html import unescape
from pathlib import Path
from urllib.parse import quote
import re
import shutil
import sys

body_path = Path(sys.argv[1])
source_dir = Path(sys.argv[2])
image_target_dir = Path(sys.argv[3])
cdn_base = sys.argv[4]
year = sys.argv[5]
article_slug = sys.argv[6]
custom_image_dir = Path(sys.argv[7]) if sys.argv[7] else None

content = body_path.read_text(encoding="utf-8")
uploaded = {}


def is_remote(path: str) -> bool:
    lowered = path.lower()
    return (
        lowered.startswith("http://")
        or lowered.startswith("https://")
        or lowered.startswith("data:")
        or lowered.startswith("#")
        or lowered.startswith("/")
        or lowered.startswith("mailto:")
    )


def clean_relative_parts(raw_path: str):
    parts = [part for part in Path(raw_path).parts if part not in ("", ".", "..")]
    if parts and parts[0] == "img":
        parts = parts[1:]
    return parts


def resolve_source(raw_path: str) -> Path | None:
    clean_path = raw_path.split("?", 1)[0].split("#", 1)[0]

    candidates = [source_dir / clean_path]
    if custom_image_dir:
        stripped = clean_path
        if stripped.startswith("./"):
            stripped = stripped[2:]
        if stripped.startswith("img/"):
            stripped = stripped[4:]
        candidates.insert(0, custom_image_dir / stripped)
        candidates.append(custom_image_dir / Path(clean_path).name)

    for candidate in candidates:
        if candidate.exists() and candidate.is_file():
            return candidate.resolve()
    return None


def upload(raw_path: str) -> str:
    if raw_path in uploaded:
        return uploaded[raw_path]

    source = resolve_source(unescape(raw_path))
    if source is None:
        print(f"[WARN] 图片不存在，跳过替换: {raw_path}", file=sys.stderr)
        return raw_path

    safe_parts = clean_relative_parts(raw_path)
    if not safe_parts:
        safe_parts = [source.name]

    destination = image_target_dir.joinpath(*safe_parts)
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)

    encoded_path = "/".join(quote(part) for part in safe_parts)
    url = f"{cdn_base}/blog/{year}/{article_slug}/{encoded_path}"
    uploaded[raw_path] = url
    return url


markdown_pattern = re.compile(r'!\[([^\]]*)\]\(([^)\s]+)(\s+"[^"]*")?\)')
html_pattern = re.compile(r'(<img\b[^>]*?\bsrc=["\'])([^"\']+)(["\'][^>]*>)', re.IGNORECASE)


def replace_markdown(match):
    alt = match.group(1)
    raw_path = match.group(2)
    suffix = match.group(3) or ""
    if is_remote(raw_path):
        return match.group(0)
    return f"![{alt}]({upload(raw_path)}{suffix})"


def replace_html(match):
    prefix = match.group(1)
    raw_path = match.group(2)
    suffix = match.group(3)
    if is_remote(raw_path):
        return match.group(0)
    return f"{prefix}{upload(raw_path)}{suffix}"


content = markdown_pattern.sub(replace_markdown, content)
content = html_pattern.sub(replace_html, content)
body_path.write_text(content, encoding="utf-8")
PY
}

upload_cover_image() {
	local raw_cover_path="$1"
	local source_dir="$2"
	local image_repo_target_dir="$3"
	local cdn_base="$4"
	local year="$5"
	local article_slug="$6"
	local custom_image_dir="${7:-}"

	python3 - "$raw_cover_path" "$source_dir" "$image_repo_target_dir" "$cdn_base" "$year" "$article_slug" "$custom_image_dir" <<'PY'
from pathlib import Path
from urllib.parse import quote
import shutil
import sys

raw_cover_path = sys.argv[1].strip()
source_dir = Path(sys.argv[2])
image_target_dir = Path(sys.argv[3])
cdn_base = sys.argv[4]
year = sys.argv[5]
article_slug = sys.argv[6]
custom_image_dir = Path(sys.argv[7]) if sys.argv[7] else None

if not raw_cover_path:
    print("")
    raise SystemExit(0)


def resolve_source(path_str: str) -> Path | None:
    path = Path(path_str)
    candidates = []

    if path.is_absolute():
        candidates.append(path)
    else:
        candidates.append(source_dir / path)
        if custom_image_dir:
            candidates.append(custom_image_dir / path)
            candidates.append(custom_image_dir / path.name)

    for candidate in candidates:
        if candidate.exists() and candidate.is_file():
            return candidate.resolve()
    return None


source = resolve_source(raw_cover_path)
if source is None:
    print("")
    raise SystemExit(0)

destination = image_target_dir / "cover" / source.name
destination.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(source, destination)

encoded_name = quote(source.name)
print(f"{cdn_base}/blog/{year}/{article_slug}/cover/{encoded_name}")
PY
}

commit_and_push_image_repo() {
	local target_rel_dir="$1"
	local commit_message="$2"

	cd "$IMAGE_REPO_LOCAL"
	git add -- "$target_rel_dir"

	if ! git diff --cached --quiet -- "$target_rel_dir"; then
		git commit -m "$commit_message"
		git push origin "$IMAGE_BRANCH"
		echo -e "${GREEN}✓ 图片已推送到图床仓库${NC}"
	else
		echo -e "${YELLOW}没有新的图片变更，跳过图床仓库提交${NC}"
	fi
}

show_help() {
	echo "用法:"
	echo "  zsh scripts/import-local-post.zsh <markdown文件> [图片目录]"
	echo ""
	echo "说明:"
	echo "  1. 读取本地 Markdown"
	echo "  2. 上传其中引用的本地图片到图床仓库"
	echo "  3. 将 Markdown 图片链接替换为 jsDelivr CDN 链接"
	echo "  4. 生成符合当前 Astro schema 的文章文件"
	echo ""
	echo "示例:"
	echo "  zsh scripts/import-local-post.zsh /tmp/post.md"
	echo "  zsh scripts/import-local-post.zsh /tmp/post.md /tmp/post-images"
}

require_cmd git
require_cmd python3

if [[ $# -lt 1 || "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
	show_help
	exit 0
fi

SOURCE_MD="$(abs_path "$1")"
CUSTOM_IMAGE_DIR=""
if [[ $# -ge 2 ]]; then
	CUSTOM_IMAGE_DIR="$(abs_path "$2")"
fi

if [[ ! -f "$SOURCE_MD" ]]; then
	echo -e "${RED}Markdown 文件不存在: $SOURCE_MD${NC}"
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

if [[ -n "$CUSTOM_IMAGE_DIR" && ! -d "$CUSTOM_IMAGE_DIR" ]]; then
	echo -e "${RED}指定的图片目录不存在: $CUSTOM_IMAGE_DIR${NC}"
	exit 1
fi

mkdir -p "$ASTRO_POSTS_DIR"

SOURCE_DIR="$(dirname "$SOURCE_MD")"
SOURCE_BASENAME="$(basename "$SOURCE_MD")"
SOURCE_STEM="${SOURCE_BASENAME%.*}"
SOURCE_EXT="${SOURCE_BASENAME##*.}"
if [[ "$SOURCE_EXT" != "md" && "$SOURCE_EXT" != "mdx" ]]; then
	SOURCE_EXT="md"
fi

DEFAULT_TITLE="$SOURCE_STEM"
DEFAULT_SLUG="$(slugify "$SOURCE_STEM")"
DEFAULT_PUBLISHED="$(date +%Y-%m-%d)"
DEFAULT_LANG="zh_CN"

WORK_BODY="$TEMP_DIR/body.$SOURCE_EXT"
strip_frontmatter "$SOURCE_MD" "$WORK_BODY"

echo -e "${CYAN}=== 本地 Markdown 导入 Astro ===${NC}"
echo -e "${BLUE}源文件: $SOURCE_MD${NC}"
echo -e "${BLUE}默认 slug: $DEFAULT_SLUG${NC}"
echo -e "${BLUE}图床仓库: $IMAGE_REPO_LOCAL${NC}"

prompt_with_default TITLE "请输入文章标题" "$DEFAULT_TITLE"
prompt_with_default ARTICLE_SLUG "请输入文章 slug" "$DEFAULT_SLUG"
prompt_with_default PUBLISHED_DATE "请输入发布时间（YYYY-MM-DD）" "$DEFAULT_PUBLISHED"
NORMALIZED_PUBLISHED_DATE="$(normalize_date "$PUBLISHED_DATE" || true)"
if [[ -z "$NORMALIZED_PUBLISHED_DATE" ]]; then
	echo -e "${RED}发布时间格式无效: $PUBLISHED_DATE${NC}"
	echo -e "${YELLOW}请使用 YYYY-MM-DD，例如 2026-01-03${NC}"
	exit 1
fi
PUBLISHED_DATE="$NORMALIZED_PUBLISHED_DATE"
prompt_with_default DESCRIPTION "请输入文章描述（可留空）" ""
prompt_with_default TAGS_INPUT "请输入标签 tags（逗号分隔，可留空）" ""
prompt_with_default CATEGORY_INPUT "请输入分类 category（单个，可留空）" ""
prompt_with_default LANG_INPUT "请输入文章语言 lang" "$DEFAULT_LANG"

echo -e "${YELLOW}是否设为草稿 draft? (y/N):${NC}"
read DRAFT_INPUT
DRAFT_VALUE="false"
if [[ "$DRAFT_INPUT" =~ ^[Yy]$ ]]; then
	DRAFT_VALUE="true"
fi

CURRENT_YEAR="${PUBLISHED_DATE%%-*}"
IMAGE_TARGET_REL_DIR="blog/$CURRENT_YEAR/$ARTICLE_SLUG"
IMAGE_TARGET_DIR="$IMAGE_REPO_LOCAL/$IMAGE_TARGET_REL_DIR"
mkdir -p "$IMAGE_TARGET_DIR"

echo -e "${BLUE}开始检查并上传本地图片...${NC}"
rewrite_and_upload_images \
	"$WORK_BODY" \
	"$SOURCE_DIR" \
	"$IMAGE_TARGET_DIR" \
	"$CDN_BASE" \
	"$CURRENT_YEAR" \
	"$ARTICLE_SLUG" \
	"$CUSTOM_IMAGE_DIR"

echo -e "${YELLOW}请输入封面图片路径（可留空，支持相对路径/绝对路径）:${NC}"
read COVER_PATH_INPUT
IMAGE_INPUT="$(upload_cover_image \
	"$COVER_PATH_INPUT" \
	"$SOURCE_DIR" \
	"$IMAGE_TARGET_DIR" \
	"$CDN_BASE" \
	"$CURRENT_YEAR" \
	"$ARTICLE_SLUG" \
	"$CUSTOM_IMAGE_DIR")"

if [[ -n "$IMAGE_INPUT" ]]; then
	echo -e "${GREEN}✓ 封面已上传: $IMAGE_INPUT${NC}"
else
	echo -e "${YELLOW}未设置封面或封面路径无效，跳过封面${NC}"
fi

commit_and_push_image_repo "$IMAGE_TARGET_REL_DIR" "add images for $ARTICLE_SLUG"

TARGET_FILE="$ASTRO_POSTS_DIR/${PUBLISHED_DATE}-${ARTICLE_SLUG}.$SOURCE_EXT"
COUNTER=1
while [[ -f "$TARGET_FILE" ]]; do
	TARGET_FILE="$ASTRO_POSTS_DIR/${PUBLISHED_DATE}-${ARTICLE_SLUG}-${COUNTER}.$SOURCE_EXT"
	((COUNTER++))
done

{
	echo "---"
	echo "title: $(yaml_escape "$TITLE")"
	echo "published: $PUBLISHED_DATE"
	echo "draft: $DRAFT_VALUE"
	echo "description: $(yaml_escape "$DESCRIPTION")"
	echo "image: $(yaml_escape "$IMAGE_INPUT")"

	if [[ -n "$TAGS_INPUT" ]]; then
		echo "tags:"
		IFS=',' read -rA TAGS <<< "$TAGS_INPUT"
		for tag in "${TAGS[@]}"; do
			tag="$(trim "$tag")"
			[[ -n "$tag" ]] && echo "  - $(yaml_escape "$tag")"
		done
	else
		echo "tags: []"
	fi

	echo "category: $(yaml_escape "$(trim "$CATEGORY_INPUT")")"
	echo "lang: $(yaml_escape "$LANG_INPUT")"
	echo "---"
	echo
	cat "$WORK_BODY"
} > "$TARGET_FILE"

echo -e "${GREEN}✓ 文章已生成: $TARGET_FILE${NC}"
echo -e "${CYAN}=== 完成 ===${NC}"
