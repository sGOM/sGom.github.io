import { describe, it, expect } from 'vitest';
import {
  sortByDate,
  filterDrafts,
  collectTags,
  collectCategories,
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
