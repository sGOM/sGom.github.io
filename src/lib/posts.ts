export type PostLike = {
  id: string;
  data: {
    title: string;
    pubDate: Date;
    tags: string[];
    category: string;
    draft: boolean;
  };
};

export function sortByDate<T extends PostLike>(posts: T[]): T[] {
  return [...posts].sort(
    (a, b) => b.data.pubDate.valueOf() - a.data.pubDate.valueOf()
  );
}

export function filterDrafts<T extends PostLike>(
  posts: T[],
  includeDrafts: boolean
): T[] {
  return includeDrafts ? posts : posts.filter((p) => !p.data.draft);
}

export function collectTags<T extends PostLike>(
  posts: T[]
): { tag: string; count: number }[] {
  const counts = new Map<string, number>();
  for (const p of posts) {
    for (const tag of p.data.tags) {
      counts.set(tag, (counts.get(tag) ?? 0) + 1);
    }
  }
  return [...counts.entries()]
    .map(([tag, count]) => ({ tag, count }))
    .sort((a, b) => b.count - a.count || a.tag.localeCompare(b.tag, 'ko'));
}

export function collectCategories<T extends PostLike>(
  posts: T[]
): { category: string; count: number }[] {
  const counts = new Map<string, number>();
  for (const p of posts) {
    counts.set(p.data.category, (counts.get(p.data.category) ?? 0) + 1);
  }
  return [...counts.entries()]
    .map(([category, count]) => ({ category, count }))
    .sort((a, b) => b.count - a.count || a.category.localeCompare(b.category, 'ko'));
}
