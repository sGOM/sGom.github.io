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

/** 글의 성격을 나누는 상위 축. 배열 순서가 곧 좌측 트리에 표시되는 순서다 */
export const GROUPS = ['기본개념', '파고들기', '오답노트'] as const;

export type GroupNode = {
  group: string;
  count: number;
  categories: { category: string; count: number }[];
};

/**
 * tags에서 그룹 태그를 찾는다.
 * 스키마가 "정확히 하나"를 보장하므로 실제로는 항상 값이 나온다.
 */
export function groupOf(post: PostLike): string | undefined {
  return post.data.tags.find((t) => (GROUPS as readonly string[]).includes(t));
}

/** GROUPS 순서로 고정된 2-depth 트리를 만든다. 글이 0개인 그룹도 남긴다 */
export function buildGroupTree<T extends PostLike>(posts: T[]): GroupNode[] {
  return GROUPS.map((group) => {
    const inGroup = posts.filter((p) => groupOf(p) === group);
    return {
      group,
      count: inGroup.length,
      categories: collectCategories(inGroup),
    };
  });
}
