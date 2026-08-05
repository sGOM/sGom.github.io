export type PostLike = {
  id: string;
  data: {
    title: string;
    pubDate: Date;
    tags: string[];
    draft: boolean;
    series?: string;
    seriesOrder?: number;
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

export function getSeriesPosts<T extends PostLike>(
  posts: T[],
  series: string
): T[] {
  return posts
    .filter((p) => p.data.series === series)
    .sort((a, b) => (a.data.seriesOrder ?? 0) - (b.data.seriesOrder ?? 0));
}

export function getSeriesNeighbors<T extends PostLike>(
  posts: T[],
  current: T
): { prev: T | null; next: T | null } {
  if (!current.data.series) return { prev: null, next: null };
  const ordered = getSeriesPosts(posts, current.data.series);
  const i = ordered.findIndex((p) => p.id === current.id);
  if (i === -1) return { prev: null, next: null };
  return {
    prev: ordered[i - 1] ?? null,
    next: ordered[i + 1] ?? null,
  };
}

export function collectSeries<T extends PostLike>(
  posts: T[]
): { name: string; count: number }[] {
  const counts = new Map<string, number>();
  for (const p of posts) {
    if (!p.data.series) continue;
    counts.set(p.data.series, (counts.get(p.data.series) ?? 0) + 1);
  }
  return [...counts.entries()]
    .map(([name, count]) => ({ name, count }))
    .sort((a, b) => a.name.localeCompare(b.name, 'ko'));
}
