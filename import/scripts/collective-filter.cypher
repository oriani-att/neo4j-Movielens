MATCH (u:User)-[r:RATED]->(m:Movie)
// WHERE u.id = 2
WITH u, collect(r) AS rcol
WITH u, head(rcol) AS r1
MATCH (u)-[r1]->(m)
WITH u, m, r1.rating AS actual_rating
LIMIT 100

// Find other users who rated the same movie
MATCH (u2:User)-[r2:RATED]->(m)
WHERE u2.id <> u.id  // Exclude user 1
WITH u, m, actual_rating, u2, r2.rating AS r2

// Find other common movies that are rated by both user 1 and user 2
MATCH (u)-[r1_common:RATED]->(common_movie:Movie)<-[r2_common:RATED]-(u2)
WHERE common_movie.id <> m.id

// We only return users that have more than 3 common movies with target user u
WITH u, m, actual_rating, u2, r2,
    COUNT(common_movie) AS nb_common_movie, 
    COLLECT(common_movie.id) AS common_movies,
    COLLECT(r1_common.rating) AS u_common_ratings,
    COLLECT(r2_common.rating) AS u2_common_ratings
WHERE nb_common_movie > 3
ORDER BY nb_common_movie DESC

// Calculate cosine similarity
WITH u, m, actual_rating, 
    u2, r2, common_movies, nb_common_movie,
    REDUCE(dot_product = 0, i IN RANGE(0, SIZE(u_common_ratings) - 1) | dot_product + (u_common_ratings[i] * u2_common_ratings[i])) AS dot_product,
    SQRT(REDUCE(xDot = 0.0, a IN u_common_ratings | xDot + a^2)) AS x_length,
    SQRT(REDUCE(yDot = 0.0, b IN u2_common_ratings | yDot + b^2)) AS y_length

WITH u, m, actual_rating, 
    u2, r2, common_movies, nb_common_movie, x_length, y_length, dot_product,
    CASE WHEN x_length * y_length = 0 THEN 0 ELSE dot_product / (x_length * y_length) END AS similarity

MERGE (u)-[s:SIMILARITY]-(u2)
SET   s.similarity = similarity

// Find k-nearest neighbors of target user
// We set k = 10
WITH u, m, actual_rating,
    u2, r2, similarity, nb_common_movie
ORDER BY u.id, similarity DESC, nb_common_movie DESC

WITH u, m, actual_rating,
    COLLECT(r2)[0..10] AS r2_rating,
    COLLECT(similarity)[0..10] AS similarity, 
    COLLECT(nb_common_movie)[0..10] AS nb_common_movie

// Calculate the predict rating
WITH u, m, actual_rating,
    REDUCE(sum = 0, i IN RANGE(0, SIZE(similarity) - 1) | sum + (similarity[i] * r2_rating[i])) AS weighted_sum,
    REDUCE(sum = 0, i IN RANGE(0, SIZE(similarity) - 1) | sum + similarity[i]) AS total_weight
    // SIZE(similarity) AS count_similarity
    
WITH u, m, actual_rating,
    weighted_sum / total_weight AS predict_rating

WITH u, m, actual_rating,
    ROUND(predict_rating * 2) / 2 AS predict_rating

// Model evaluation with square error    
WITH u, m ,actual_rating, predict_rating, 
    (predict_rating - actual_rating) * (predict_rating - actual_rating) AS square_error

// RETURN u.id AS user, 
//     m.title AS movie,
//     actual_rating,
//     predict_rating,
//     square_error
// ORDER BY square_error DESC

// Total RMSE of test dataset
WITH COUNT(*) AS count, SUM(square_error) AS sse
RETURN count, SQRT(tofloat(sse)/count) AS RMSE

