import { defineCollection } from 'astro:content';
import { glob } from 'astro/loaders';
import { z } from 'astro/zod';

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
      tags: z.array(z.string()).nonempty(),
      updatedDate: z.coerce.date().optional(),
      draft: z.boolean().default(false),
      series: z.string().optional(),
      seriesOrder: z.number().int().positive().optional(),
    })
    .refine((d) => (d.series === undefined) === (d.seriesOrder === undefined), {
      message: 'series와 seriesOrder는 함께 있거나 함께 없어야 합니다',
    }),
});

export const collections = { posts };
