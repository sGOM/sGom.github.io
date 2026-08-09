import { readFile, writeFile } from 'node:fs/promises';
import {
  parseRssItems,
  renderPostList,
  replaceMarkedSection,
} from '../src/lib/profile-readme.js';

const RSS_URL = 'https://sgom.github.io/rss.xml';
const POST_LIMIT = 5;

const readmePath = process.argv[2];
if (!readmePath) {
  console.error('사용법: tsx scripts/update-profile-readme.ts <README 경로>');
  process.exit(1);
}

const response = await fetch(RSS_URL);
if (!response.ok) {
  throw new Error(`RSS를 가져오지 못했다: ${response.status} ${response.statusText}`);
}

const items = parseRssItems(await response.text(), POST_LIMIT);
const readme = await readFile(readmePath, 'utf8');
const updated = replaceMarkedSection(readme, renderPostList(items));

if (updated === readme) {
  console.log('변경 없음');
  process.exit(0);
}

await writeFile(readmePath, updated);
console.log(`README를 갱신했다 (글 ${items.length}개)`);
