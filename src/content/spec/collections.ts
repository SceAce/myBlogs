export interface CollectionItem {
	title: string;
	subtitle?: string;
	link?: string;
	note?: string;
}

export interface CollectionsData {
	books: CollectionItem[];
	music: CollectionItem[];
	games: CollectionItem[];
}

export const collectionsData: CollectionsData = {
	books: [
		{
			title: "六壬辨疑",
			subtitle: "偶尔看一看",
			link: "https://github.com/SceAce/picx-images-hosting/blob/master/Books/%E5%85%AD%E5%A3%AC%E8%BE%A8%E7%96%91%20%20%E6%AF%95%E6%B3%95%E6%A1%88%E5%BD%95%20(%EF%BC%88%E6%B8%85%EF%BC%89%E5%BC%A0%E5%AE%98%E5%BE%B7%E6%92%B0)%20(z-lib.org)%20(1).pdf",
			note: "夫公则生明，龟筮无私，所以前知，每自占不准，非神不告，私意在胸，先为之曲解耳",
		},
	],
	music: [
		{
			title: "为爱追寻",
			subtitle: "暂无",
			link: "https://y.qq.com/n/ryqq_v2/search?w=%E4%B8%BA%E7%88%B1%E8%BF%BD%E5%AF%BB",
			note: "挺有宿命感的,脑补出了一段虐恋的故事",
		},
	],
	games: [
		{
			title: "MC",
			subtitle: "励志成为红石大佬",
			link: "",
			note: "红石还是太强了！！！",
		},
	],
};
