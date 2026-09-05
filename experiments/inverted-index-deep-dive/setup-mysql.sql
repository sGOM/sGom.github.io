-- 역인덱스 파고들기 실험 (MySQL InnoDB FULLTEXT의 삭제 표시와 병합).
-- docker compose -f experiments/compose.yml exec -T mysql mysql -uroot -plab --default-character-set=utf8mb4 --table < experiments/inverted-index-deep-dive/setup-mysql.sql
-- DB 이름에 하이픈을 쓰지 못한다. innodb_ft_aux_table이 하이픈이 든 이름을 거부한다.

SELECT VERSION();

DROP DATABASE IF EXISTS `inverted_index_deep_dive`;
CREATE DATABASE `inverted_index_deep_dive` CHARACTER SET utf8mb4;
USE `inverted_index_deep_dive`;

CREATE TABLE articles (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  body TEXT,
  FULLTEXT (body)
) ENGINE=InnoDB;

INSERT INTO articles (body) VALUES
 ('the quick brown fox jumps over the lazy dog'),
 ('a lazy dog sleeps in the sun'),
 ('quick foxes run and run again');

SET GLOBAL innodb_optimize_fulltext_only = ON;
OPTIMIZE TABLE articles;
SET GLOBAL innodb_ft_aux_table = 'inverted_index_deep_dive/articles';

SELECT '1. 삭제 전 sleeps 포스팅' AS step;
SELECT WORD, DOC_ID FROM INFORMATION_SCHEMA.INNODB_FT_INDEX_TABLE WHERE WORD = 'sleeps';
SELECT '1. 삭제 전 검색' AS step;
SELECT id FROM articles WHERE MATCH(body) AGAINST('sleeps');

DELETE FROM articles WHERE id = 2;

SELECT '2. 삭제 후 INNODB_FT_DELETED' AS step;
SELECT DOC_ID FROM INFORMATION_SCHEMA.INNODB_FT_DELETED;
SELECT '2. 삭제 후에도 포스팅은 남아 있다' AS step;
SELECT WORD, DOC_ID FROM INFORMATION_SCHEMA.INNODB_FT_INDEX_TABLE WHERE WORD = 'sleeps';
SELECT '2. 그래도 검색 결과에는 안 나온다' AS step;
SELECT id FROM articles WHERE MATCH(body) AGAINST('sleeps');

OPTIMIZE TABLE articles;

SELECT '3. 병합 후 INNODB_FT_DELETED' AS step;
SELECT DOC_ID FROM INFORMATION_SCHEMA.INNODB_FT_DELETED;
SELECT '3. 병합 후 포스팅' AS step;
SELECT WORD, DOC_ID FROM INFORMATION_SCHEMA.INNODB_FT_INDEX_TABLE WHERE WORD = 'sleeps';
