import { describe, it, expect } from 'vitest';
import {
  sortByDate,
  filterDrafts,
  collectTags,
  getSeriesPosts,
  getSeriesNeighbors,
  collectSeries,
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

describe('getSeriesPosts', () => {
  it('같은 시리즈 글을 seriesOrder 순으로 반환한다', () => {
    const posts = [
      post('c', { series: 'JVM', seriesOrder: 3 }),
      post('a', { series: 'JVM', seriesOrder: 1 }),
      post('other', { series: 'DB', seriesOrder: 1 }),
      post('b', { series: 'JVM', seriesOrder: 2 }),
    ];
    expect(getSeriesPosts(posts, 'JVM').map((p) => p.id)).toEqual(['a', 'b', 'c']);
  });

  it('시리즈가 없는 글은 포함하지 않는다', () => {
    const posts = [post('none'), post('a', { series: 'JVM', seriesOrder: 1 })];
    expect(getSeriesPosts(posts, 'JVM')).toHaveLength(1);
  });
});

describe('getSeriesNeighbors', () => {
  const posts = [
    post('a', { series: 'JVM', seriesOrder: 1 }),
    post('b', { series: 'JVM', seriesOrder: 2 }),
    post('c', { series: 'JVM', seriesOrder: 3 }),
  ];

  it('가운데 글은 앞뒤가 모두 있다', () => {
    const { prev, next } = getSeriesNeighbors(posts, posts[1]);
    expect(prev?.id).toBe('a');
    expect(next?.id).toBe('c');
  });

  it('첫 글의 prev는 null이다', () => {
    expect(getSeriesNeighbors(posts, posts[0]).prev).toBeNull();
  });

  it('마지막 글의 next는 null이다', () => {
    expect(getSeriesNeighbors(posts, posts[2]).next).toBeNull();
  });

  it('시리즈에 속하지 않은 글은 양쪽 다 null이다', () => {
    const { prev, next } = getSeriesNeighbors(posts, post('solo'));
    expect(prev).toBeNull();
    expect(next).toBeNull();
  });
});

describe('collectSeries', () => {
  it('시리즈 이름과 글 수를 반환한다', () => {
    const posts = [
      post('a', { series: 'JVM', seriesOrder: 1 }),
      post('b', { series: 'JVM', seriesOrder: 2 }),
      post('c'),
    ];
    expect(collectSeries(posts)).toEqual([{ name: 'JVM', count: 2 }]);
  });
});
