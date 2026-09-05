-- 역인덱스 기본개념 실험 (MySQL).
-- docker compose -f experiments/compose.yml exec -T mysql mysql -uroot -plab --default-character-set=utf8mb4 --table < experiments/inverted-index-basics/setup-mysql.sql
-- 클라이언트 문자셋을 utf8mb4로 주지 않으면 한국어가 깨진 채 색인된다.
-- DB 이름에 하이픈을 쓰지 못한다. innodb_ft_aux_table이 하이픈을 인코딩한 디렉터리 이름을 요구해
-- 하이픈이 든 이름을 거부한다. 그래서 슬러그의 하이픈만 밑줄로 바꿔 쓴다.

SELECT VERSION();
SHOW VARIABLES WHERE Variable_name IN (
  'innodb_ft_min_token_size', 'innodb_ft_max_token_size',
  'innodb_ft_enable_stopword', 'ft_min_word_len', 'ngram_token_size');

DROP DATABASE IF EXISTS `inverted_index_basics`;
CREATE DATABASE `inverted_index_basics` CHARACTER SET utf8mb4;
USE `inverted_index_basics`;

-- 1. 영어 문서 세 개의 역인덱스를 그대로 열어 본다.
CREATE TABLE articles (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  body TEXT,
  FULLTEXT (body)
) ENGINE=InnoDB;

INSERT INTO articles (body) VALUES
 ('the quick brown fox jumps over the lazy dog'),
 ('a lazy dog sleeps in the sun'),
 ('quick foxes run and run again');

-- 새로 넣은 문서는 FTS 캐시에 있어 아직 보조 테이블에 없다.
SET GLOBAL innodb_optimize_fulltext_only = ON;
OPTIMIZE TABLE articles;
SET GLOBAL innodb_ft_aux_table = 'inverted_index_basics/articles';
SELECT WORD, DOC_ID, POSITION
FROM INFORMATION_SCHEMA.INNODB_FT_INDEX_TABLE
ORDER BY WORD, DOC_ID, POSITION;

-- 2. 같은 텀이 반복될 때 POSITION에 무엇이 들어가는지.
CREATE TABLE pos2 (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  body TEXT,
  FULLTEXT (body)
) ENGINE=InnoDB;

INSERT INTO pos2 (body) VALUES ('aaa bbbb aaa ccccc aaa');
OPTIMIZE TABLE pos2;
SET GLOBAL innodb_ft_aux_table = 'inverted_index_basics/pos2';
SELECT WORD, DOC_ID, POSITION
FROM INFORMATION_SCHEMA.INNODB_FT_INDEX_TABLE
ORDER BY WORD, POSITION;

-- 3. 기본 파서로 색인한 한국어.
CREATE TABLE ko (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  body TEXT,
  FULLTEXT (body)
) ENGINE=InnoDB;

INSERT INTO ko (body) VALUES
 ('역인덱스는 검색어를 문서로 매핑한다'),
 ('검색 엔진은 역인덱스를 쓴다');

SELECT id FROM ko WHERE MATCH(body) AGAINST('역인덱스');
SELECT id FROM ko WHERE MATCH(body) AGAINST('역인덱스는');

OPTIMIZE TABLE ko;
SET GLOBAL innodb_ft_aux_table = 'inverted_index_basics/ko';
SELECT WORD, DOC_ID FROM INFORMATION_SCHEMA.INNODB_FT_INDEX_TABLE ORDER BY DOC_ID, WORD;

-- 4. ngram 파서로 다시 색인하면 명사만으로 걸린다.
CREATE TABLE ko2 (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  body TEXT,
  FULLTEXT (body) WITH PARSER ngram
) ENGINE=InnoDB;

INSERT INTO ko2 (body) VALUES
 ('역인덱스는 검색어를 문서로 매핑한다'),
 ('검색 엔진은 역인덱스를 쓴다');

SELECT id FROM ko2 WHERE MATCH(body) AGAINST('역인덱스');
