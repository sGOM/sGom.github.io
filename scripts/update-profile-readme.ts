import { readFile, writeFile } from 'node:fs/promises';
import {
  parseRssItems,
  renderPostList,
  replaceMarkedSection,
  extractMarkedSection,
  EMPTY_MESSAGE,
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

if (items.length === 0) {
  const existing = extractMarkedSection(readme);
  if (existing !== '' && existing !== EMPTY_MESSAGE) {
    throw new Error(
      'RSS가 글 0개를 반환했는데 README에는 이미 글 목록이 있다. ' +
        'RSS 응답이 의심스럽다 (배포 직후 전파 지연, rss.xml 회귀 등) — ' +
        '프로필을 비우는 대신 갱신을 중단한다.'
    );
  }
}

const updated = replaceMarkedSection(readme, renderPostList(items));

if (updated === readme) {
  console.log('변경 없음');
  process.exit(0);
}

await writeFile(readmePath, updated);
console.log(`README를 갱신했다 (글 ${items.length}개)`);
