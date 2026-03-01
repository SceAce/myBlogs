#!/bin/zsh

set -euo pipefail

ASTRO_ROOT="/home/source/My_github/myBlogs"
ASTRO_POSTS_DIR="$ASTRO_ROOT/src/content/posts"

IMAGE_REPO_LOCAL="$HOME/My_github/picx-images-hosting"
IMAGE_BRANCH="master"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || {
		echo -e "${RED}缺少命令: $1${NC}"
		exit 1
	}
}

abs_path() {
	python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$1"
}

extract_post_meta() {
	python3 - "$1" <<'PY'
from pathlib import Path
import re
import sys

post_path = Path(sys.argv[1])
stem = post_path.stem
slug = stem
year = ""

name_match = re.match(r"^(\d{4})-\d{2}-\d{2}-(.+)$", stem)
if name_match:
    year = name_match.group(1)
    slug = name_match.group(2)

content = post_path.read_text(encoding="utf-8")
if content.startswith("---"):
    for line in content.splitlines()[1:]:
        if line.strip() == "---":
            break
        if line.startswith("published:"):
            raw = line.split(":", 1)[1].strip().strip('"').strip("'")
            date_match = re.match(r"^(\d{4})-\d{2}-\d{2}$", raw)
            if date_match:
                year = date_match.group(1)
            break

print(slug)
print(year)
PY
}

commit_and_push_image_repo() {
	local target_rel_dir="$1"
	local commit_message="$2"

	cd "$IMAGE_REPO_LOCAL"
	git add -A -- "$target_rel_dir"

	if ! git diff --cached --quiet -- "$target_rel_dir"; then
		git commit -m "$commit_message"
		git push origin "$IMAGE_BRANCH"
		echo -e "${GREEN}✓ 图床仓库删除已提交并推送${NC}"
	else
		echo -e "${YELLOW}图床仓库没有需要提交的删除变更${NC}"
	fi
}

show_help() {
	echo "用法:"
	echo "  zsh scripts/delete-post.zsh <文章文件>"
	echo "  zsh scripts/delete-post.zsh --yes <文章文件>"
	echo ""
	echo "说明:"
	echo "  1. 删除 src/content/posts 下的文章文件"
	echo "  2. 按 blog/<year>/<slug>/ 规则删除图床仓库里的对应图片目录"
	echo "  3. 可选提交并推送图床仓库删除"
	echo ""
	echo "示例:"
	echo "  zsh scripts/delete-post.zsh src/content/posts/2026-01-03-2025年终总结.md"
}

require_cmd git
require_cmd python3

ASSUME_YES="false"
POST_ARG=""

while [[ $# -gt 0 ]]; do
	case "$1" in
		--help|-h)
			show_help
			exit 0
			;;
		--yes|-y)
			ASSUME_YES="true"
			shift
			;;
		*)
			if [[ -n "$POST_ARG" ]]; then
				echo -e "${RED}只支持传入一个文章文件${NC}"
				exit 1
			fi
			POST_ARG="$1"
			shift
			;;
	esac
done

if [[ -z "$POST_ARG" ]]; then
	show_help
	exit 1
fi

POST_FILE="$(abs_path "$POST_ARG")"

if [[ ! -f "$POST_FILE" ]]; then
	echo -e "${RED}文章文件不存在: $POST_FILE${NC}"
	exit 1
fi

case "$POST_FILE" in
	"$ASTRO_POSTS_DIR"/*) ;;
	*)
		echo -e "${RED}文章文件必须位于 $ASTRO_POSTS_DIR 下${NC}"
		exit 1
		;;
esac

if [[ ! -d "$IMAGE_REPO_LOCAL/.git" ]]; then
	echo -e "${RED}本地图床仓库不存在或不是 git 仓库: $IMAGE_REPO_LOCAL${NC}"
	exit 1
fi

POST_EXT="${POST_FILE##*.}"
if [[ "$POST_EXT" != "md" && "$POST_EXT" != "mdx" ]]; then
	echo -e "${RED}只支持删除 md/mdx 文章: $POST_FILE${NC}"
	exit 1
fi

META_OUTPUT="$(extract_post_meta "$POST_FILE")"
ARTICLE_SLUG="$(echo "$META_OUTPUT" | sed -n '1p')"
PUBLISHED_YEAR="$(echo "$META_OUTPUT" | sed -n '2p')"

if [[ -z "$ARTICLE_SLUG" || -z "$PUBLISHED_YEAR" ]]; then
	echo -e "${RED}无法从文章解析 slug 或年份: $POST_FILE${NC}"
	exit 1
fi

IMAGE_TARGET_REL_DIR="blog/$PUBLISHED_YEAR/$ARTICLE_SLUG"
IMAGE_TARGET_DIR="$IMAGE_REPO_LOCAL/$IMAGE_TARGET_REL_DIR"

echo -e "${CYAN}=== 删除博客文章 ===${NC}"
echo -e "${BLUE}文章文件:${NC} $POST_FILE"
echo -e "${BLUE}推断 slug:${NC} $ARTICLE_SLUG"
echo -e "${BLUE}图片目录:${NC} $IMAGE_TARGET_DIR"

if [[ "$ASSUME_YES" != "true" ]]; then
	echo -e "${YELLOW}确认删除文章文件和对应图片目录? (y/N):${NC}"
	read CONFIRM_DELETE
	if [[ ! "$CONFIRM_DELETE" =~ ^[Yy]$ ]]; then
		echo -e "${YELLOW}已取消${NC}"
		exit 0
	fi
fi

rm -f -- "$POST_FILE"
echo -e "${GREEN}✓ 已删除文章文件${NC}"

if [[ -d "$IMAGE_TARGET_DIR" ]]; then
	rm -rf -- "$IMAGE_TARGET_DIR"
	echo -e "${GREEN}✓ 已删除图片目录${NC}"
else
	echo -e "${YELLOW}未找到对应图片目录，已跳过: $IMAGE_TARGET_DIR${NC}"
fi

echo -e "${YELLOW}是否提交并推送图床仓库删除? (y/N):${NC}"
read CONFIRM_PUSH
if [[ "$CONFIRM_PUSH" =~ ^[Yy]$ ]]; then
	commit_and_push_image_repo "$IMAGE_TARGET_REL_DIR" "delete images for $ARTICLE_SLUG"
else
	echo -e "${YELLOW}已跳过图床仓库提交，你之后可以手动在 $IMAGE_REPO_LOCAL 提交${NC}"
fi

echo -e "${CYAN}=== 完成 ===${NC}"
