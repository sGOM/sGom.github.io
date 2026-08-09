import { defineCollection } from 'astro:content';
import { glob } from 'astro/loaders';
import { z } from 'astro/zod';
import { GROUPS, hasExactlyOneGroupTag } from './lib/posts';

const posts = defineCollection({
  loader: glob({
    pattern: '**/index.md',
    base: './src/content/posts',
    // 'transaction-isolation-levels/index.md' -> 'transaction-isolation-levels'
    generateId: ({ entry }) => entry.replace(/\/index\.md$/, ''),
  }),
  schema: z
    .object({
      title: z.string(),
      description: z.string(),
      pubDate: z.coerce.date(),
      category: z.string(),
      tags: z.array(z.string()).nonempty(),
      updatedDate: z.coerce.date().optional(),
      draft: z.boolean().default(false),
    })
    .refine((d) => hasExactlyOneGroupTag(d.tags), {
      message: `tags에 그룹 태그(${GROUPS.join(', ')}) 중 정확히 하나가 있어야 한다`,
      path: ['tags'],
    }),
});

export const collections = { posts };
