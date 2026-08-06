import rss from '@astrojs/rss';
import { getCollection } from 'astro:content';
import { sortByDate, filterDrafts } from '../lib/posts';

export async function GET(context) {
  const all = await getCollection('posts');
  const posts = sortByDate(filterDrafts(all, false));

  return rss({
    title: 'sGOM',
    description: '개발하며 겪은 문제와 공부한 개념을 남깁니다',
    site: context.site,
    items: posts.map((post) => ({
      title: post.data.title,
      description: post.data.description,
      pubDate: post.data.pubDate,
      link: `/posts/${post.id}/`,
    })),
    customData: '<language>ko</language>',
  });
}
