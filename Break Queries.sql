
-----------------------------------------------------------------------------------------------
-- Queries related to breaks that snooker players have made in the matches included in the data
-----------------------------------------------------------------------------------------------

-- First we create a view that includes fields from multiple tables that will be relevant for our queries.
-- The scores table only lists breaks of 50+, but this will be sufficient for our queries.

DROP VIEW IF EXISTS breaks_;

CREATE VIEW breaks_ AS (
SELECT c.name AS tournament_name, c.year, a.match_id, b.stage,
	CASE WHEN player = 1 THEN player1_name ELSE player2_name END AS player,
	[50plus_breaks_str] AS break_ -- field name requires square brackets
FROM Snooker..scores AS a
JOIN Snooker..matches AS b
ON a.match_id = b.match_id
JOIN Snooker..tournaments AS c
ON b.tournament_id = c.id
WHERE [50plus_breaks_str] IS NOT NULL AND c.status = 'Professional') 

------------------------------------------------------------
-- Which players have the most centuries and maximum breaks?
------------------------------------------------------------

-- A century break is one of over 100 points, a maximum is one of exactly 147 points.
-- First we'll look at players with the most century breaks:

SELECT player, COUNT(*) AS century_breaks
FROM breaks_
WHERE break_ >= 100
GROUP BY player
ORDER BY century_breaks DESC;

-- And now we'll look at the players with the most maximum breaks:

SELECT player, COUNT(*) AS maximum_breaks
FROM breaks_
WHERE break_ = 147
GROUP BY player
ORDER BY maximum_breaks DESC;

---------------------------------------------------------------------------------
-- What were the three highest breaks made in each tournament, and who made them?
---------------------------------------------------------------------------------

WITH breaks_ranked_in_tournament AS ( -- CTE of how every break ranks within its tournament
SELECT *, 
	ROW_NUMBER() OVER(PARTITION BY year, tournament_name ORDER BY break_ DESC) AS rank_
	-- order of PARTITION BY matters
FROM breaks_)

SELECT tournament_name, year, rank_, player, break_
FROM breaks_ranked_in_tournament
WHERE rank_ <= 3
ORDER BY year DESC, tournament_name, rank_;

--------------------------------------------------------------------------------------
-- Which tournaments had the highest percentage of frames with century breaks in them?
--------------------------------------------------------------------------------------

-- Only one century can occur per frame, therefore just counting the amount of centuries is sufficient.

WITH tournament_frame_count AS ( -- CTE counting total frames played at each tournament
SELECT b.name AS tournament_name, b.year, 
	SUM(score1) + SUM(score2) AS frames_played
FROM Snooker..matches AS a
JOIN Snooker..tournaments AS b
ON a.tournament_id = b.id
WHERE b.status = 'Professional'
GROUP BY b.name, b.year)

SELECT a.tournament_name, a.year, 
	SUM(CASE WHEN break_ >= 100 THEN 1 END) AS century_breaks,
	MAX(frames_played) AS frames_played,
	ROUND(CAST(SUM(CASE WHEN break_ >= 100 THEN 1 END) AS FLOAT)/MAX(frames_played),3) AS percentage_centuries
FROM breaks_ AS a
JOIN tournament_frame_count AS b
ON a.tournament_name = b.tournament_name AND a.year = b.year
GROUP BY a.tournament_name, a.year
ORDER BY percentage_centuries DESC;

---------------------------------------------------------
-- How many centuries occured at each world championship?
-- (With a running total, average, and record.)
---------------------------------------------------------

-- We will only consider centuries made at the Crucible Theatre, that is in the Last 32 stage and after.
-- As the standard has clearly improved over the years we will take the running average only of the last 5 events.

SELECT year, COUNT(*) AS century_breaks,
	ROUND(AVG(CAST(COUNT(*) AS FLOAT)) OVER(ORDER BY year ROWS BETWEEN 5 PRECEDING AND CURRENT ROW), 3) AS avg_last_5,
	MAX(COUNT(*)) OVER(ORDER BY year ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS record
FROM breaks_
WHERE tournament_name = 'World Championship' 
	AND stage IN ('Final', 'Semi-Final', 'Quarter-Final', 'Last 16', 'Last 32')
	AND break_ >= 100
GROUP BY year;




