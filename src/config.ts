import type {
	CommentConfig,
	ExpressiveCodeConfig,
	LicenseConfig,
	NavBarConfig,
	ProfileConfig,
	SiteConfig,
} from "./types/config";
import { LinkPreset } from "./types/config";

export const siteConfig: SiteConfig = {
	title: "閑時雜記",
	subtitle: "尋蹤流跡漸芙蓉，淺向紅虹映影空",
	lang: "zh_CN",
	themeColor: {
		hue: 250,
		fixed: false,
	},
	banner: {
		enable: true,
		src: "https://cdn.jsdelivr.net/gh/SceAce/picx-images-hosting@master/burning_cherry.3yezms7b6m.jpeg",
		position: "center",
		credit: {
			enable: true,
			text: "一點浩然氣，千裏快哉風",
			url: "https://cdn.jsdelivr.net/gh/SceAce/picx-images-hosting@master/Fantasy---Sunset.77e3jfdnyp.webp",
		},
	},
	toc: {
		enable: true,
		depth: 3,
	},
	favicon: [
		{
			src: "/favicon/favicon.svg",
		},
	],
};

export const navBarConfig: NavBarConfig = {
	links: [
		LinkPreset.Archive,
		LinkPreset.Friends,
		LinkPreset.About,
		LinkPreset.Collections,
	],
};

export const profileConfig: ProfileConfig = {
	avatar:
		"https://cdn.jsdelivr.net/gh/SceAce/picx-images-hosting@master/UID.6wr9q56fry.webp",
	name: "Source",
	bio: "尋蹤流跡漸芙蓉，淺向紅虹映影空",
	links: [
		{
			name: "Home",
			icon: "material-symbols:verified-outline-rounded",
			url: "https://www.sceace.net",
		},
		{
			name: "BilBili",
			icon: "simple-icons:bilibili",
			url: "https://space.bilibili.com/1720469706?spm_id_from=333.1007.0.0",
		},
		{
			name: "GitHub",
			icon: "tabler:brand-github",
			url: "https://github.com/SceAce",
		},
		{
			name: "RedQueen",
			icon: "mingcute:discord-line",
			url: "https://discord.gg/nP2gFZKFgm",
		},
	],
};

export const licenseConfig: LicenseConfig = {
	enable: true,
	name: "CC BY-NC-SA 4.0",
	url: "https://creativecommons.org/licenses/by-nc-sa/4.0/",
};

export const expressiveCodeConfig: ExpressiveCodeConfig = {
	themes: ["catppuccin-latte", "catppuccin-macchiato"],
};

export const commentConfig: CommentConfig = {
	giscus: {
		repo: "SceAce/assembly.rip",
		repoId: "R_kgDOOGUE-g",
		category: "Announcements",
		categoryId: "DIC_kwDOOGUE-s4C0V7E",
		mapping: "title",
		strict: "0",
		reactionsEnabled: "1",
		emitMetadata: "1",
		inputPosition: "top",
		theme: "reactive",
		lang: "zh-CN",
		loading: "lazy",
	},
};
