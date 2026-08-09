import { describe, it, expect } from 'vitest';
import { parseRssItems } from './profile-readme';

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
