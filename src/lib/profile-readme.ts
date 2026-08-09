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
