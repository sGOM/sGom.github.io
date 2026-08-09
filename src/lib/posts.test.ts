import { describe, it, expect } from 'vitest';
import {
  sortByDate,
  filterDrafts,
  collectTags,
  collectCategories,
  GROUPS,
  groupOf,
  buildGroupTree,
  hasExactlyOneGroupTag,
  type PostLike,
} from './posts';

function post(
  id: string,
  overrides: Partial<PostLike['data']> = {}
): PostLike {
  return {
    id,
    data: {
      title: id,
      pubDate: new Date('2026-01-01'),
      tags: ['기타'],
      category: '기타',
      draft: false,
      ...overrides,
    },
  };
}

describe('sortByDate', () => {
  it('최신 글이 앞에 온다', () => {
    const posts = [
      post('old', { pubDate: new Date('2026-01-01') }),
      post('new', { pubDate: new Date('2026-06-01') }),
      post('mid', { pubDate: new Date('2026-03-01') }),
    ];
    expect(sortByDate(posts).map((p) => p.id)).toEqual(['new', 'mid', 'old']);
  });

  it('원본 배열을 변경하지 않는다', () => {
    const posts = [
      post('a', { pubDate: new Date('2026-01-01') }),
      post('b', { pubDate: new Date('2026-06-01') }),
    ];
    sortByDate(posts);
    expect(posts.map((p) => p.id)).toEqual(['a', 'b']);
  });
});

describe('filterDrafts', () => {
  it('includeDrafts가 false면 초안을 제외한다', () => {
    const posts = [post('published'), post('wip', { draft: true })];
    expect(filterDrafts(posts, false).map((p) => p.id)).toEqual(['published']);
  });

  it('includeDrafts가 true면 초안도 남긴다', () => {
    const posts = [post('published'), post('wip', { draft: true })];
    expect(filterDrafts(posts, true)).toHaveLength(2);
  });
});

describe('collectTags', () => {
  it('태그별 글 수를 센다', () => {
    const posts = [
      post('a', { tags: ['Spring', 'JPA'] }),
      post('b', { tags: ['Spring'] }),
    ];
    expect(collectTags(posts)).toEqual([
      { tag: 'Spring', count: 2 },
      { tag: 'JPA', count: 1 },
    ]);
  });

  it('같은 개수면 가나다순으로 정렬한다', () => {
    const posts = [post('a', { tags: ['Redis'] }), post('b', { tags: ['Kafka'] })];
    expect(collectTags(posts).map((t) => t.tag)).toEqual(['Kafka', 'Redis']);
  });
});

describe('collectCategories', () => {
  it('카테고리별 글 수를 센다', () => {
    const posts = [
      post('a', { category: 'Spring' }),
      post('b', { category: 'Spring' }),
      post('c', { category: '데이터베이스' }),
    ];
    expect(collectCategories(posts)).toEqual([
      { category: 'Spring', count: 2 },
      { category: '데이터베이스', count: 1 },
    ]);
  });

  it('같은 개수면 가나다순으로 정렬한다', () => {
    const posts = [
      post('a', { category: '서버' }),
      post('b', { category: '네트워크' }),
      post('c', { category: '데이터베이스' }),
    ];
    expect(collectCategories(posts).map((c) => c.category)).toEqual([
      '네트워크',
      '데이터베이스',
      '서버',
    ]);
  });

  it('글이 없으면 빈 배열이다', () => {
    expect(collectCategories([])).toEqual([]);
  });
});

describe('groupOf', () => {
  it('tags에 있는 그룹 태그를 반환한다', () => {
    expect(groupOf(post('a', { tags: ['파고들기', 'Spring'] }))).toBe('파고들기');
  });

  it('그룹 태그의 위치와 무관하게 찾아낸다', () => {
    expect(groupOf(post('a', { tags: ['Spring', '트랜잭션', '오답노트'] }))).toBe(
      '오답노트'
    );
  });

  it('그룹 태그가 없으면 undefined를 반환한다', () => {
    expect(groupOf(post('a', { tags: ['Spring'] }))).toBeUndefined();
  });
});

describe('hasExactlyOneGroupTag', () => {
  it('그룹 태그가 정확히 하나면 true다', () => {
    expect(hasExactlyOneGroupTag(['Spring', '기본개념'])).toBe(true);
  });

  it('그룹 태그가 없으면 false다', () => {
    expect(hasExactlyOneGroupTag(['Spring', 'JPA'])).toBe(false);
  });

  it('그룹 태그가 둘 이상이면 false다', () => {
    expect(hasExactlyOneGroupTag(['기본개념', '오답노트'])).toBe(false);
  });
});

describe('buildGroupTree', () => {
  it('글이 없어도 그룹 3개를 모두 만든다', () => {
    expect(buildGroupTree([])).toEqual([
      { group: '기본개념', count: 0, categories: [] },
      { group: '파고들기', count: 0, categories: [] },
      { group: '오답노트', count: 0, categories: [] },
    ]);
  });

  it('그룹 순서는 건수와 무관하게 GROUPS 순서를 따른다', () => {
    const posts = [
      post('a', { tags: ['오답노트'] }),
      post('b', { tags: ['오답노트'] }),
      post('c', { tags: ['기본개념'] }),
    ];
    expect(buildGroupTree(posts).map((g) => g.group)).toEqual([...GROUPS]);
  });

  it('그룹별 글 수를 센다', () => {
    const posts = [
      post('a', { tags: ['기본개념'] }),
      post('b', { tags: ['파고들기'] }),
      post('c', { tags: ['파고들기'] }),
    ];
    expect(buildGroupTree(posts).map((g) => g.count)).toEqual([1, 2, 0]);
  });

  it('하위 카테고리를 건수 내림차순으로 정렬한다', () => {
    const posts = [
      post('a', { tags: ['기본개념'], category: 'Spring' }),
      post('b', { tags: ['기본개념'], category: 'Spring' }),
      post('c', { tags: ['기본개념'], category: '데이터베이스' }),
    ];
    const basics = buildGroupTree(posts)[0];
    expect(basics.count).toBe(3);
    expect(basics.categories).toEqual([
      { category: 'Spring', count: 2 },
      { category: '데이터베이스', count: 1 },
    ]);
  });

  it('건수가 같으면 카테고리 이름 가나다순으로 정렬한다', () => {
    const posts = [
      post('a', { tags: ['파고들기'], category: '서버' }),
      post('b', { tags: ['파고들기'], category: '네트워크' }),
      post('c', { tags: ['파고들기'], category: '데이터베이스' }),
    ];
    expect(buildGroupTree(posts)[1].categories.map((c) => c.category)).toEqual([
      '네트워크',
      '데이터베이스',
      '서버',
    ]);
  });

  it('다른 그룹의 글은 서로 섞이지 않는다', () => {
    const posts = [
      post('a', { tags: ['기본개념'], category: 'Spring' }),
      post('b', { tags: ['오답노트'], category: 'Spring' }),
    ];
    const tree = buildGroupTree(posts);
    expect(tree[0].categories).toEqual([{ category: 'Spring', count: 1 }]);
    expect(tree[2].categories).toEqual([{ category: 'Spring', count: 1 }]);
  });

  it('그룹 태그가 없는 글은 어느 그룹에도 들어가지 않는다', () => {
    const posts = [post('a', { tags: ['Spring'] })];
    expect(buildGroupTree(posts)).toEqual([
      { group: '기본개념', count: 0, categories: [] },
      { group: '파고들기', count: 0, categories: [] },
      { group: '오답노트', count: 0, categories: [] },
    ]);
  });
});
