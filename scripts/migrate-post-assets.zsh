#!/bin/zsh

set -euo pipefail

ASTRO_ROOT="/home/source/My_github/myBlogs"
ASTRO_POSTS_DIR="$ASTRO_ROOT/src/content/posts"

IMAGE_REPO_LOCAL="$HOME/My_github/picx-images-hosting"
IMAGE_REPO_GH="SceAce/picx-images-hosting"
IMAGE_BRANCH="master"
CDN_BASE="https://cdn.jsdelivr.net/gh/$IMAGE_REPO_GH@$IMAGE_BRANCH"

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

extract_post_slug() {
	python3 - "$1" <<'PY'
from pathlib import Path
import re
import sys

stem = Path(sys.argv[1]).stem
match = re.match(r"^\d{4}-\d{2}-\d{2}-(.+)$", stem)
print(match.group(1) if match else stem)
PY
}

show_help() {
	echo "用法:"
	echo "  zsh scripts/migrate-post-assets.zsh <文章文件>"
	echo "  zsh scripts/migrate-post-assets.zsh --cleanup-legacy <文章文件>"
	echo ""
	echo "说明:"
	echo "  1. 扫描文章中的旧 CDN 链接"
	echo "  2. 将图床资源复制到 blog/<slug>/img 或 blog/<slug>/assets"
	echo "  3. 重写文章内的图片链接为新结构"
	echo "  4. 可选清理旧目录 blog/<year>/<old-slug>/"
}

require_cmd python3

CLEANUP_LEGACY="false"
POST_ARG=""

while [[ $# -gt 0 ]]; do
	case "$1" in
		--help|-h)
			show_help
			exit 0
			;;
		--cleanup-legacy)
			CLEANUP_LEGACY="true"
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

POST_SLUG="$(extract_post_slug "$POST_FILE")"

echo -e "${CYAN}=== 迁移旧文章图片 ===${NC}"
echo -e "${BLUE}文章文件:${NC} $POST_FILE"
echo -e "${BLUE}目标 slug:${NC} $POST_SLUG"

python3 - "$POST_FILE" "$IMAGE_REPO_LOCAL" "$CDN_BASE" "$POST_SLUG" "$CLEANUP_LEGACY" <<'PY'
from pathlib import Path
from shutil import copy2
from urllib.parse import quote, unquote
import re
import sys

post_path = Path(sys.argv[1])
image_repo = Path(sys.argv[2])
cdn_base = sys.argv[3]
target_slug = sys.argv[4]
cleanup_legacy = sys.argv[5] == "true"

content = post_path.read_text(encoding="utf-8")
pattern = re.compile(
    re.escape(cdn_base) + r"/blog/([^/]+)/([^/]+)/([^)\s\"'>]+)"
)
matches = list(pattern.finditer(content))

if not matches:
    print("[INFO] 未发现可迁移的旧 CDN 链接")
    raise SystemExit(0)

replacements = []
copied = set()
legacy_dirs: set[Path] = set()

for match in matches:
    year = unquote(match.group(1))
    legacy_slug = unquote(match.group(2))
    tail = match.group(3)
    tail_decoded = unquote(tail)

    # Only migrate the legacy layout: blog/<year>/<slug>/...
    if not re.fullmatch(r"\d{4}", year):
        continue

    legacy_dir = image_repo / "blog" / year / legacy_slug
    source_path = legacy_dir / tail_decoded
    if not source_path.exists():
        print(f"[WARN] 本地旧资源不存在，跳过: {source_path}")
        continue

    parts = Path(tail_decoded).parts
    if parts and parts[0] == "cover":
        destination_rel = Path("blog") / target_slug / "assets" / Path(*parts)
        new_url = f"{cdn_base}/blog/{quote(target_slug)}/assets/" + "/".join(quote(p) for p in parts)
    else:
        destination_rel = Path("blog") / target_slug / "img" / Path(*parts)
        new_url = f"{cdn_base}/blog/{quote(target_slug)}/img/" + "/".join(quote(p) for p in parts)

    destination_path = image_repo / destination_rel
    destination_path.parent.mkdir(parents=True, exist_ok=True)

    copy_key = (source_path.resolve(), destination_path.resolve())
    if source_path.resolve() == destination_path.resolve():
        replacements.append((match.group(0), new_url))
        continue

    if copy_key not in copied:
        copy2(source_path, destination_path)
        copied.add(copy_key)

    replacements.append((match.group(0), new_url))
    legacy_dirs.add(legacy_dir)

matches = replacements
if not matches:
    print("[INFO] 未发现可迁移的旧 CDN 链接")
    raise SystemExit(0)

for old_url, new_url in replacements:
    content = content.replace(old_url, new_url)

post_path.write_text(content, encoding="utf-8")

print(f"[OK] 已重写链接数量: {len(replacements)}")
for legacy_dir in sorted(legacy_dirs):
    print(f"[OLD] {legacy_dir}")
print(f"[NEW] {image_repo / 'blog' / target_slug}")

if cleanup_legacy:
    for legacy_dir in sorted(legacy_dirs, reverse=True):
        if legacy_dir.exists():
            for child in sorted(legacy_dir.rglob('*'), reverse=True):
                if child.is_file():
                    child.unlink()
                elif child.is_dir():
                    try:
                        child.rmdir()
                    except OSError:
                        pass
            try:
                legacy_dir.rmdir()
                print(f"[DEL] 已删除旧目录: {legacy_dir}")
            except OSError:
                print(f"[WARN] 旧目录非空，未删除: {legacy_dir}")
PY

echo -e "${GREEN}✓ 迁移完成${NC}"
