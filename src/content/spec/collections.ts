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
      title: "示例书籍",
      subtitle: "你可以改成自己正在读或喜欢的书",
      link: "",
      note: "这里写一句备注，比如：最近在读、很喜欢其中的某个观点。",
    },
  ],
  music: [
    {
      title: "示例专辑 / 歌曲",
      subtitle: "你可以放专辑名、歌手名或者播放链接",
      link: "",
      note: "这里写一句备注，比如：循环很久、适合夜里听。",
    },
  ],
  games: [
    {
      title: "示例游戏",
      subtitle: "你可以写平台、类型或系列",
      link: "",
      note: "这里写一句备注，比如：很喜欢美术风格 / 机制设计。",
    },
  ],
};
