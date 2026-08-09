export type RssItem = {
  title: string;
  link: string;
  pubDate: Date;
};

function decodeEntities(text: string): string {
  return text
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#0*39;|&apos;/g, "'")
    .replace(/&amp;/g, '&');
}

function extractTag(block: string, tag: string): string {
  const matched = new RegExp(
    `<${tag}(?:\\s[^>]*)?>([\\s\\S]*?)</${tag}>`
  ).exec(block);
  if (!matched) return '';

  const raw = matched[1].trim();
  const cdata = /^<!\[CDATA\[([\s\S]*?)\]\]>$/.exec(raw);
  return decodeEntities((cdata ? cdata[1] : raw).trim());
}

export function parseRssItems(xml: string, limit: number): RssItem[] {
  const items: RssItem[] = [];
  const itemPattern = /<item>([\s\S]*?)<\/item>/g;

  let matched: RegExpExecArray | null;
  while ((matched = itemPattern.exec(xml)) !== null) {
    if (items.length >= limit) break;

    const block = matched[1];
    const title = extractTag(block, 'title');
    const link = extractTag(block, 'link');
    const pubDate = extractTag(block, 'pubDate');
    if (!title || !link || !pubDate) continue;

    const parsed = new Date(pubDate);
    if (Number.isNaN(parsed.valueOf())) continue;

    items.push({ title, link, pubDate: parsed });
  }

  return items;
}

export const LIST_START = '<!-- BLOG-POST-LIST:START -->';
export const LIST_END = '<!-- BLOG-POST-LIST:END -->';

const EMPTY_MESSAGE = '_아직 발행한 글이 없다._';

function escapeLinkText(title: string): string {
  return title.replace(/([[\]])/g, '\\$1');
}

function formatDate(date: Date): string {
  return date.toISOString().slice(0, 10);
}

export function renderPostList(items: RssItem[]): string {
  if (items.length === 0) return EMPTY_MESSAGE;

  return items
    .map(
      (item) =>
        `- [${escapeLinkText(item.title)}](${item.link}) · ${formatDate(item.pubDate)}`
    )
    .join('\n');
}

export function replaceMarkedSection(readme: string, block: string): string {
  const start = readme.indexOf(LIST_START);
  const end = readme.indexOf(LIST_END);
  if (start === -1 || end === -1 || end < start) {
    throw new Error(
      `README에서 ${LIST_START} / ${LIST_END} 마커를 찾지 못했다`
    );
  }

  return (
    readme.slice(0, start + LIST_START.length) +
    '\n' +
    block +
    '\n' +
    readme.slice(end)
  );
}
