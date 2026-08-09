import { describe, it, expect } from 'vitest';
import {
  parseRssItems,
  renderPostList,
  replaceMarkedSection,
  LIST_START,
  LIST_END,
  type RssItem,
} from './profile-readme';

function item(title: string, slug: string, pubDate: string): string {
  return (
    `<item><title>${title}</title>` +
    `<link>https://sgom.github.io/posts/${slug}/</link>` +
    `<guid isPermaLink="true">https://sgom.github.io/posts/${slug}/</guid>` +
    `<description><![CDATA[설명]]></description>` +
    `<pubDate>${pubDate}</pubDate></item>`
  );
}

function feed(items: string[]): string {
  return (
    `<?xml version="1.0" encoding="UTF-8"?><rss version="2.0"><channel>` +
    `<title><![CDATA[sGOM]]></title><link>https://sgom.github.io/</link>` +
    items.join('') +
    `</channel></rss>`
  );
}

describe('parseRssItems', () => {
  it('CDATA로 감싼 제목을 벗겨낸다', () => {
    const xml = feed([
      item('<![CDATA[트랜잭션과 ACID]]>', 'transaction-and-acid', 'Wed, 05 Aug 2026 00:00:00 GMT'),
    ]);

    const result = parseRssItems(xml, 5);

    expect(result).toHaveLength(1);
    expect(result[0].title).toBe('트랜잭션과 ACID');
    expect(result[0].link).toBe('https://sgom.github.io/posts/transaction-and-acid/');
    expect(result[0].pubDate.toISOString().slice(0, 10)).toBe('2026-08-05');
  });

  it('CDATA 없는 평문 제목도 읽는다', () => {
    const xml = feed([item('평문 제목', 'plain', 'Wed, 05 Aug 2026 00:00:00 GMT')]);

    expect(parseRssItems(xml, 5)[0].title).toBe('평문 제목');
  });

  it('HTML 엔티티를 디코드한다', () => {
    const xml = feed([
      item('<![CDATA[A &amp; B &lt;태그&gt; &quot;인용&quot; &#39;작은따옴표&#39;]]>', 'ent', 'Wed, 05 Aug 2026 00:00:00 GMT'),
    ]);

    expect(parseRssItems(xml, 5)[0].title).toBe(`A & B <태그> "인용" '작은따옴표'`);
  });

  it('limit만큼만 반환한다', () => {
    const xml = feed([
      item('1', 'a', 'Wed, 05 Aug 2026 00:00:00 GMT'),
      item('2', 'b', 'Tue, 04 Aug 2026 00:00:00 GMT'),
      item('3', 'c', 'Mon, 03 Aug 2026 00:00:00 GMT'),
    ]);

    expect(parseRssItems(xml, 2).map((i) => i.title)).toEqual(['1', '2']);
  });

  it('글이 limit보다 적으면 있는 만큼 반환한다', () => {
    const xml = feed([item('1', 'a', 'Wed, 05 Aug 2026 00:00:00 GMT')]);

    expect(parseRssItems(xml, 5)).toHaveLength(1);
  });

  it('item이 없으면 빈 배열을 반환한다', () => {
    expect(parseRssItems(feed([]), 5)).toEqual([]);
  });

  it('필수 필드가 빠진 item은 건너뛴다', () => {
    const broken = `<item><title><![CDATA[제목만]]></title></item>`;
    const xml = feed([broken, item('정상', 'ok', 'Wed, 05 Aug 2026 00:00:00 GMT')]);

    expect(parseRssItems(xml, 5).map((i) => i.title)).toEqual(['정상']);
  });
});

describe('renderPostList', () => {
  const item = (title: string, slug: string, date: string): RssItem => ({
    title,
    link: `https://sgom.github.io/posts/${slug}/`,
    pubDate: new Date(date),
  });

  it('제목·링크·날짜를 마크다운 목록으로 만든다', () => {
    const result = renderPostList([
      item('트랜잭션과 ACID', 'transaction-and-acid', '2026-08-05T00:00:00Z'),
      item('격리 수준', 'isolation-levels', '2026-08-04T00:00:00Z'),
    ]);

    expect(result).toBe(
      '- [트랜잭션과 ACID](https://sgom.github.io/posts/transaction-and-acid/) · 2026-08-05\n' +
        '- [격리 수준](https://sgom.github.io/posts/isolation-levels/) · 2026-08-04'
    );
  });

  it('제목의 대괄호를 이스케이프해 링크 문법을 지킨다', () => {
    const result = renderPostList([item('MySQL [8.0] 이야기', 'mysql', '2026-08-05T00:00:00Z')]);

    expect(result).toContain('[MySQL \\[8.0\\] 이야기]');
  });

  it('글이 없으면 안내 문구를 낸다', () => {
    expect(renderPostList([])).toBe('_아직 발행한 글이 없다._');
  });

  it('시간대와 무관하게 UTC 기준 날짜를 쓴다', () => {
    const result = renderPostList([item('글', 'a', '2026-08-05T00:00:00Z')]);

    expect(result).toContain('· 2026-08-05');
  });
});

describe('replaceMarkedSection', () => {
  const readme = (inner: string) =>
    `# 제목\n\n## 최신 글\n\n${LIST_START}\n${inner}\n${LIST_END}\n\n## 그 다음\n`;

  it('마커 사이를 새 블록으로 갈아끼운다', () => {
    const result = replaceMarkedSection(readme('- 예전 글'), '- 새 글');

    expect(result).toBe(readme('- 새 글'));
  });

  it('마커 밖의 내용은 건드리지 않는다', () => {
    const result = replaceMarkedSection(readme('- 예전 글'), '- 새 글');

    expect(result).toContain('# 제목');
    expect(result).toContain('## 그 다음');
  });

  it('마커 사이가 비어 있어도 삽입한다', () => {
    const source = `${LIST_START}\n${LIST_END}`;

    expect(replaceMarkedSection(source, '- 새 글')).toBe(
      `${LIST_START}\n- 새 글\n${LIST_END}`
    );
  });

  it('시작 마커가 없으면 예외를 던진다', () => {
    expect(() => replaceMarkedSection(`# 제목\n${LIST_END}`, '- 글')).toThrow(
      /마커/
    );
  });

  it('끝 마커가 없으면 예외를 던진다', () => {
    expect(() => replaceMarkedSection(`# 제목\n${LIST_START}`, '- 글')).toThrow(
      /마커/
    );
  });

  it('마커 순서가 뒤집혀 있으면 예외를 던진다', () => {
    expect(() =>
      replaceMarkedSection(`${LIST_END}\n${LIST_START}`, '- 글')
    ).toThrow(/마커/);
  });
});
