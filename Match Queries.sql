
--------------------------------------------------------------------------------
-- Queries related to match (and tournament) wins for different snooker players:
--------------------------------------------------------------------------------

-- Note that the data, and therefore the statistics generated, only considers matches from 1982-2020.
-- We'll first create a view summarizing the fields relevant for our queries.

DROP VIEW IF EXISTS matches_view;

CREATE VIEW matches_view AS (
SELECT a.match_id, b.name AS tournament_name, b.year, b.status, b.category, a.stage,
	a.player1_name AS winner, c.country AS winner_country, a.score1 AS winner_score, 
	a.player2_name AS loser, d.country AS loser_country, a.score2 AS loser_score
FROM Snooker..matches AS a
JOIN Snooker..tournaments AS b
ON a.tournament_id = b.id
JOIN Snooker..players AS c
ON a.player1_name = c.full_name
JOIN Snooker..players AS d
ON a.player2_name = d.full_name)

-------------------------------------------------------------
-- Which players win the highest percentage of their matches?
-------------------------------------------------------------

WITH w_l_d AS ( -- CTE to list wins, losses, and draws, so that a count can be done with less code
SELECT winner AS player, 
	COUNT(CASE WHEN winner_score > loser_score THEN 1 END) AS wins,
	COUNT(CASE WHEN winner_score = loser_score THEN 1 END) + MAX(player_losses.draws) AS draws,
	MAX(player_losses.losses) AS losses
FROM matches_view AS a -- these are all the matches the player won (and some they drew)
JOIN (SELECT loser AS player, -- must also consider matches where the player is listed as the loser
		COUNT(CASE WHEN loser_score < winner_score THEN 1 END) AS losses,
		COUNT(CASE WHEN winner_score = loser_score THEN 1 END) AS draws
	FROM matches_view
	GROUP BY loser) AS player_losses
ON a.winner = player_losses.player
WHERE a.status = 'Professional' -- for many of the following queries we will only be interested in professional matches
GROUP BY winner)

SELECT *, 
	ROUND(100* CAST(wins AS FLOAT)/(wins+draws+losses), 3)  AS match_win_percentage
FROM w_l_d
WHERE wins+draws+losses >= 100 -- don't want to consider small sample results
ORDER BY match_win_percentage DESC;

-- We can also see which players played the most matches:

SELECT player, wins+losses+draws AS matches_played 
FROM (SELECT winner AS player, -- same as CTE above, just used as a subquery instead
		COUNT(CASE WHEN winner_score > loser_score THEN 1 END) AS wins,
		COUNT(CASE WHEN winner_score = loser_score THEN 1 END) + MAX(player_losses.draws) AS draws,
		MAX(player_losses.losses) AS losses
	FROM matches_view AS a
	JOIN (SELECT loser AS player, 
			COUNT(CASE WHEN loser_score < winner_score THEN 1 END) AS losses,
			COUNT(CASE WHEN winner_score = loser_score THEN 1 END) AS draws
		FROM matches_view
		GROUP BY loser) AS player_losses
	ON a.winner = player_losses.player
	WHERE a.status = 'Professional'
	GROUP BY winner) AS a
ORDER BY matches_played DESC;

-------------------------------------------------------------------
-- Which players whitewashed their opponents in matches most often?
-------------------------------------------------------------------

-- A whitewash is when a player wins a match without their opponent winning a single frame.
-- This is more significant when more frames are required to win, therefore we'll filter for a minimum of 6 wining frames.

SELECT winner AS player, 
	COUNT(CASE WHEN loser_score = 0 THEN 1 END) AS whitewashes,
	COUNT(*) AS matches_played,
	ROUND(100* CAST(COUNT(CASE WHEN loser_score = 0 THEN 1 END) AS FLOAT)/COUNT(*), 3) AS whitewash_percentage
FROM matches_view
WHERE winner_score >= 6 AND status = 'Professional'
GROUP BY winner
HAVING COUNT(*) >= 100 -- again don't want to consider small samples
ORDER BY whitewash_percentage DESC;

---------------------------------------------------------------------------------------------
-- Which players have won the most tournaments? And what is their most recent tournament win?
---------------------------------------------------------------------------------------------

-- Tournament wins are indicated by a player winning any type of final in the matches table.
-- Through exploration we've deduced that this is exactly all the matches with a 'Final' status.
-- Tournaments are only dated by year, therefore two tournaments in the same year will be sorted alphabetically
-- (there is a date column but it contains too much missing data.)

WITH player_tournament_wins AS ( -- CTE for number of tournament wins by player
SELECT winner, COUNT(*) AS tournament_wins
FROM matches_view
WHERE stage COLLATE Latin1_General_CS_AS LIKE 'Final' AND status = 'Professional'
-- COLLATE required as we want to perform a case-sensitive search
GROUP BY winner)

SELECT a.winner AS player, MAX(c.tournament_wins) AS tournament_wins,
	CONCAT(MAX(year), ' ', MIN(tournament_name)) AS most_recent_win
FROM matches_view AS a 
JOIN (SELECT winner, MAX(year) AS most_recent_year -- subquery returns most recent tournament win year by player
	FROM matches_view
	WHERE stage COLLATE Latin1_General_CS_AS LIKE 'Final' AND status = 'Professional'
	GROUP BY winner) AS b
ON a.winner = b.winner AND a.year = b.most_recent_year
JOIN player_tournament_wins AS c -- tournament win count from CTE
ON a.winner = c.winner
WHERE stage COLLATE Latin1_General_CS_AS LIKE 'Final' AND status = 'Professional'
GROUP BY a.winner
ORDER BY tournament_wins DESC;

-- We'll create a view of this to be used later when we want to order results by the 'best' players
-- i.e. the ones with the most tournament wins.
-- We can't use a CTE in a view, therefore we will put it in a subquery.

DROP VIEW IF EXISTS top_players;

CREATE VIEW top_players AS (
SELECT a.winner AS player, MAX(c.tournament_wins) AS tournament_wins,
	CONCAT(MAX(year), ' ', MIN(tournament_name)) AS most_recent_win
FROM matches_view AS a
JOIN (SELECT winner, MAX(year) AS most_recent_year
	FROM matches_view
	WHERE stage COLLATE Latin1_General_CS_AS LIKE 'Final' AND status = 'Professional'
	GROUP BY winner) AS b
ON a.winner = b.winner AND a.year = b.most_recent_year
JOIN (SELECT winner, COUNT(*) AS tournament_wins
	FROM matches_view
	WHERE stage COLLATE Latin1_General_CS_AS LIKE 'Final' AND status = 'Professional'
	GROUP BY winner) AS c
ON a.winner = c.winner
WHERE stage COLLATE Latin1_General_CS_AS LIKE 'Final' AND status = 'Professional'
GROUP BY a.winner)

----------------------------------------------------------------------
-- Which players win the highest percentage of tournaments they enter?
-- (With a ranking/ non-ranking category breakdown, and a grand total)
----------------------------------------------------------------------

WITH tournaments_entered AS ( -- CTE of all the distinct tournaments each player has entered
SELECT winner AS player, tournament_name, year, category
FROM matches_view
WHERE status = 'Professional'
UNION -- each player will have been a winner and loser in different matches, therefore we use UNION
SELECT loser AS player, tournament_name, year, category
FROM matches_view
WHERE status = 'Professional'),

tournaments_entered_count AS ( -- CTE to count entries here, making later code slightly tidier
SELECT player, 
	COUNT(CASE WHEN category = 'Ranking' THEN 1 END) AS ranking_entries,
	COUNT(CASE WHEN category <> 'Ranking' THEN 1 END) AS non_ranking_entries
FROM tournaments_entered
GROUP BY player)

SELECT winner AS player, -- wins are counted here and compared with total entries, for each category
	SUM(CASE WHEN category = 'Ranking' AND stage COLLATE Latin1_General_CS_AS LIKE 'Final' THEN 1 END) AS ranking_wins,
	MAX(b.ranking_entries) AS ranking_entries, 
	ROUND(100* CAST(SUM(CASE WHEN category = 'Ranking' AND stage COLLATE Latin1_General_CS_AS LIKE 'Final' THEN 1 END)
		AS FLOAT)/ MAX(b.ranking_entries),3) AS ranking_win_percentage,
	SUM(CASE WHEN category <> 'Ranking' AND stage COLLATE Latin1_General_CS_AS LIKE 'Final' THEN 1 END) AS non_ranking_wins,
	MAX(b.non_ranking_entries) AS non_ranking_entries,
	ROUND(100* CAST(SUM(CASE WHEN category <> 'Ranking' AND stage COLLATE Latin1_General_CS_AS LIKE 'Final' THEN 1 END)
		AS FLOAT)/ MAX(b.non_ranking_entries),3) AS non_ranking_win_percentage,
	SUM(CASE WHEN stage COLLATE Latin1_General_CS_AS LIKE 'Final' THEN 1 END) AS total_wins,
	MAX(ranking_entries) + MAX(non_ranking_entries) AS total_entries,
	ROUND(100* CAST(SUM(CASE WHEN stage COLLATE Latin1_General_CS_AS LIKE 'Final' THEN 1 END)
		AS FLOAT)/ (MAX(ranking_entries) + MAX(non_ranking_entries)),3) AS total_win_percentage
FROM matches_view AS a
JOIN tournaments_entered_count AS b
ON a.winner = b.player
WHERE status = 'Professional'
GROUP BY winner
HAVING MAX(ranking_entries) + MAX(non_ranking_entries) >= 100 
ORDER BY total_win_percentage DESC;

---------------------------------------------------------
-- Who are the best players never to win a ranking event?
---------------------------------------------------------

-- Ranking events are loosely considered the most prestigious events.
-- We will judge the best players to be the ones with the most (non-ranking) tournament wins.

WITH ranking_event_winners AS ( -- CTE of ranking winners to be used in an anti-join with top players
SELECT *
FROM matches_view
WHERE stage COLLATE Latin1_General_CS_AS LIKE 'Final' AND status = 'Professional'
	AND category = 'Ranking')

SELECT player, tournament_wins
FROM top_players AS a
LEFT JOIN ranking_event_winners AS b
ON a.player = b.winner
WHERE b.winner IS NULL -- this will leave players with only non-ranking wins
ORDER BY tournament_wins DESC;

-------------------------------------------------------------------------------------
-- What is each of the top players' worst defeats at each of the Triple Crown events?
-------------------------------------------------------------------------------------

-- The Triple Crown events are the three most prestigious events every year.
-- We will evaluate how bad a loss is according to how many frames the player lost by.

WITH player_triple_crown_losses AS ( -- CTE of losses and how bad they rank
SELECT loser AS player, tournament_name, year, stage, winner AS lost_to,
	winner_score, loser_score,
	ROW_NUMBER() OVER(PARTITION BY loser, tournament_name
		ORDER BY winner_score - loser_score DESC) AS loss_rank
FROM matches_view
WHERE tournament_name IN ('UK Championship', 'World Championship', 'Masters'))

SELECT a.player, tournament_name, year, stage, lost_to,
	CONCAT(a.loser_score, ' - ', a.winner_score) AS score
FROM player_triple_crown_losses AS a
JOIN (SELECT TOP 40 * -- subquery used to order players in output with 'best' at the top
	FROM top_players
	ORDER BY tournament_wins DESC) AS b
ON a.player = b.player
WHERE a.loss_rank = 1
ORDER BY b.tournament_wins DESC, a.player, tournament_name DESC;

---------------------------------------------------------------------------------------
-- Which Triple Crown tournament stages have the highest percentage of deciding frames?
---------------------------------------------------------------------------------------

-- A deciding frame occurs when both players are one frame away from the target number to win the match.

WITH triple_crown_matches AS ( -- CTE sorts matches by whether they had a deciding frame or not
SELECT *, 
	CASE WHEN winner_score - loser_score = 1 THEN 1 END AS decider_indicator
FROM matches_view
WHERE tournament_name IN ('UK Championship', 'World Championship', 'Masters'))

SELECT tournament_name, stage, SUM(decider_indicator) AS number_of_deciders,
	COUNT(*) AS matches_played,
	ROUND(100* CAST(SUM(decider_indicator) AS FLOAT)/ COUNT(*), 3) AS perc_deciders
FROM triple_crown_matches
GROUP BY tournament_name, stage
HAVING COUNT(*) >= 30 
ORDER BY perc_deciders DESC;

--------------------------------------------------------------
-- How many Triple Crown wins do each of the top players have?
--------------------------------------------------------------

-- We will break it down by event and include a total for each player and a grand total for all players

SELECT COALESCE(a.winner, 'All Players') AS player, -- COALESCE used to fill in NULLs generated by ROLLUP
	COALESCE(a.tournament_name, 'Total') AS tournament_name,
	COUNT(*) AS number_of_titles
FROM matches_view AS a
JOIN top_players AS b -- again used to order results
ON a.winner = b.player
WHERE tournament_name IN ('UK Championship', 'World Championship', 'Masters')
	AND stage = 'Final'
GROUP BY ROLLUP(winner, tournament_name)
ORDER BY MIN(b.tournament_wins) DESC;

-- We can pivot this information for an alternate view, with the events as columns:

SELECT winner AS player, [World Championship], [Masters], [UK Championship],
	[World Championship] + [Masters] + [UK Championship] AS total
FROM (SELECT winner, tournament_name
	FROM matches_view
	WHERE tournament_name IN ('UK Championship', 'World Championship', 'Masters')
		AND stage = 'Final') AS src
PIVOT
(COUNT(tournament_name)
FOR tournament_name IN ([World Championship], [Masters], [UK Championship])
) AS pvt
ORDER BY [World Championship] + [Masters] + [UK Championship] DESC;

---------------------------------------------------------------------------------
-- Which opponents do the top players have the best and worst win record against?
---------------------------------------------------------------------------------

-- We will judge this simply by the number of wins each player has against opponents,
-- compared with the number of matches they have played together.

WITH player_wins_losses_draws AS ( -- CTE returns matches and whether the player won
SELECT winner AS player, loser AS opponent, match_id,
	CASE WHEN winner_score = loser_score THEN 2 ELSE 1 END AS win_indicator -- accounts for draws
FROM matches_view
WHERE status = 'Professional' AND winner_score >= 4 -- removes walkovers and matches with a small number of frames
UNION -- must consider when players are in the winner and loser columns separately
SELECT loser AS player, winner AS opponent, match_id,
	CASE WHEN winner_score = loser_score THEN 2 ELSE 0 END AS win_indicator
FROM matches_view
WHERE status = 'Professional' AND winner_score >= 4), 

player_opponent_outcomes AS ( -- CTE counts number of wins and matches players have with each opponent
SELECT player, opponent,
	COUNT(CASE WHEN win_indicator = 1 THEN 1 END) AS wins,
	COUNT(*) AS matches_played
FROM player_wins_losses_draws
GROUP BY player, opponent
HAVING COUNT(*) >= 10), -- only considering players who have played 10+ matches against each other

player_opponent_win_perc_ranked AS ( -- CTE records how many opponents each player has listed, to be used in final query
SELECT *, MAX(rank_) OVER(PARTITION BY player) AS max_rank
FROM (SELECT player, opponent, wins, matches_played,
		ROUND(100* CAST(wins AS FLOAT)/matches_played, 3) AS win_percentage,
		ROW_NUMBER() OVER(PARTITION BY player ORDER BY CAST(wins AS FLOAT)/matches_played DESC, matches_played DESC) AS rank_
	FROM player_opponent_outcomes) AS a)

SELECT a.player,
	CASE WHEN rank_ = 1 THEN 'Best' ELSE 'Worst' END AS opponent_type,
	opponent AS opponent_name, wins, matches_played, win_percentage
FROM player_opponent_win_perc_ranked AS a
JOIN top_players AS b -- used to order results by 'best' players
ON a.player = b.player
WHERE rank_ = 1 OR rank_ = max_rank
ORDER BY tournament_wins DESC, a.player, rank_ ASC;


