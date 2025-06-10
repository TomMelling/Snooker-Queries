
-- The following queries will return data in the form most suitable for their respective
-- visualisations in Tableau.

--------------------------------------------------------------------------------------------------
-- How 'easily' did each World Champion win the World Championship final in the years they won it?
--------------------------------------------------------------------------------------------------

-- A line graph with frames played on the x-axis and frames won by the eventual winner on the 
-- y-axis will be used to visualise.
-- Different matches will be represented by lines with different colours.

WITH world_finals_frames AS ( -- CTE lists each frame played and both players' scores for every world final
SELECT year, winner, loser, b.frame, b.score AS winner_score, c.score AS loser_score
FROM matches_view AS a
JOIN Snooker..scores AS b
ON a.match_id = b.match_id
JOIN Snooker..scores AS c
ON a.match_id = c.match_id AND b.frame = c.frame
WHERE tournament_name = 'World Championship' AND stage = 'Final'
	AND b.player = 1 AND c.player = 2)

SELECT year, winner, loser,
	frame AS frames_played,
	COUNT(CASE WHEN winner_score > loser_score THEN 1 END) 
	OVER(PARTITION BY year ORDER BY frame) AS frames_won
FROM world_finals_frames;

--------------------------------------------------------------------------------
-- How many tournaments have players won compared to how many they have entered?
-- (With a ranking/ non-ranking category breakdown)
--------------------------------------------------------------------------------

-- We want to make stacked bar chart listing tournament entries and wins 
-- for each player, with a ranking/ non-ranking category breakdown.

WITH winners AS ( -- CTE lists professional tournaments and their winners
SELECT *
FROM matches_view
WHERE stage COLLATE Latin1_General_CS_AS LIKE 'Final' AND status = 'Professional')

SELECT player, tournaments_entered.tournament_name, b.year, b.category,
	CASE WHEN tournaments_entered.player = b.winner THEN 'Won'
	ELSE 'Lost' END AS outcome
FROM (SELECT tournament_name, year, category, winner AS player
	FROM matches_view
	UNION -- union required as we must consider players as winners and losers
	SELECT tournament_name, year, category, loser AS player
	FROM matches_view) AS tournaments_entered
JOIN winners AS b -- inner join therefore will only contain Professional matches due to CTE
ON tournaments_entered.tournament_name = b.tournament_name AND tournaments_entered.year = b.year
ORDER BY player;

----------------------------------------------------------------------
-- Which countries do the most professional snooker players come from?
-- And which countries hold the most professional events?
----------------------------------------------------------------------

-- We aim to make heat maps indicating where in the world snooker is the most popular
-- in terms of tournaments held and their playerbases.
-- We'll put the data into one table, listing a tournament, its location, and that country's player count.
-- We don't need to worry about players with the same name as, in these cases, the names are numbered within
-- the field e.g. 'Nick Jones (II)'

WITH country_player_counts AS ( -- CTE calculates the professional player count of each country
SELECT country,
	COUNT(*) AS player_count
FROM (SELECT winner AS player, -- subquery lists all players who have played in a professional match
	CASE WHEN winner_country IN ('England', 'Scotland', 'Wales', 'Northern Ireland') THEN 'United Kingdom'
	-- Tableau doesn't recognise England etc. therefore we group these nations here
	ELSE winner_country END AS country
	FROM matches_view
	WHERE status = 'Professional'
	UNION 
	SELECT loser AS player,
	CASE WHEN loser_country IN ('England', 'Scotland', 'Wales', 'Northern Ireland') THEN 'United Kingdom'
	ELSE loser_country END AS country
	FROM matches_view
	WHERE status = 'Professional') AS a
GROUP BY country)

SELECT tournament_name, year, b.country, city,
	player_count AS country_player_count
FROM (SELECT name AS tournament_name, year, -- must convert to 'United Kingdom' here too
		CASE WHEN country IN ('England', 'Scotland', 'Wales', 'Northern Ireland') THEN 'United Kingdom'
		ELSE country END AS country,
		city
	FROM Snooker..tournaments
	WHERE status = 'Professional') AS tournaments_corrected
RIGHT JOIN country_player_counts AS b -- right join includes countries with no tournaments
ON tournaments_corrected.country = b.country;
