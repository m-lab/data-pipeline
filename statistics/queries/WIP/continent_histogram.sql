WITH
# Select the initial set of results
dl_per_location AS (
  SELECT
    test_date,
    client.Geo.continent_code AS continent_code,
    a.MeanThroughputMbps AS mbps,
    NET.SAFE_IP_FROM_STRING(Client.IP) AS ip
  FROM `measurement-lab.ndt.unified_downloads`
  WHERE test_date = @startday
),
# With good locations and valid IPs
dl_per_location_cleaned AS (
  SELECT
    test_date,
    continent_code,
    mbps,
    ip          
  FROM dl_per_location
  WHERE 
    continent_code IS NOT NULL AND continent_code != ""
    AND ip IS NOT NULL
),
# Gather descriptive statistics per geo, day, per ip
dl_stats_perip_perday AS (
  SELECT
    test_date,
    continent_code,
    ip,
    MIN(mbps) AS MIN_download_Mbps,
    APPROX_QUANTILES(mbps, 100) [SAFE_ORDINAL(25)] AS LOWER_QUART_download_Mbps,
    APPROX_QUANTILES(mbps, 100) [SAFE_ORDINAL(50)] AS MED_download_Mbps,
    AVG(mbps) AS MEAN_download_Mbps,
    APPROX_QUANTILES(mbps, 100) [SAFE_ORDINAL(75)] AS UPPER_QUART_download_Mbps,
    MAX(mbps) AS MAX_download_Mbps
  FROM dl_per_location_cleaned
  GROUP BY test_date, continent_code, ip
),
# Calculate final stats per day from 1x test per ip per day normalization in prev. step
dl_stats_per_day AS (
  SELECT 
    test_date,
    continent_code,
    MIN(MIN_download_Mbps) AS MIN_download_Mbps,
    APPROX_QUANTILES(LOWER_QUART_download_Mbps, 100) [SAFE_ORDINAL(25)] AS LOWER_QUART_download_Mbps,
    APPROX_QUANTILES(MED_download_Mbps, 100) [SAFE_ORDINAL(50)] AS MED_download_Mbps,
    AVG(MEAN_download_Mbps) AS MEAN_download_Mbps,
    APPROX_QUANTILES(UPPER_QUART_download_Mbps, 100) [SAFE_ORDINAL(75)] AS UPPER_QUART_download_Mbps,
    MAX(MAX_download_Mbps) AS MAX_download_Mbps
  FROM
    dl_stats_perip_perday
  GROUP BY test_date, continent_code
),
dl_total_samples_per_geo AS (
  SELECT
    test_date,
    COUNT(*) AS dl_total_samples,
    continent_code
  FROM dl_per_location_cleaned
  GROUP BY test_date, continent_code
),
# Now generate daily histograms of Max DL
max_dl_per_day_ip AS (
  SELECT 
    test_date,
    continent_code,
    ip,
    MAX(mbps) AS mbps
  FROM dl_per_location_cleaned
  GROUP BY 
    test_date,
    continent_code,
    ip
),
# Count the samples
dl_sample_counts AS (
  SELECT 
    test_date,
    continent_code,
    COUNT(*) AS samples
  FROM max_dl_per_day_ip
  GROUP BY
    test_date,
    continent_code
),
# Generate equal sized buckets in log-space
buckets AS (
  SELECT POW(10,x) AS bucket_right, POW(10, x-.2) AS bucket_left
  FROM UNNEST(GENERATE_ARRAY(0, 4.2, .2)) AS x
),
# Count the samples that fall into each bucket
dl_histogram_counts AS (
  SELECT 
    test_date,
    continent_code,
    bucket_left AS bucket_min,
    bucket_right AS bucket_max,
    COUNTIF(mbps < bucket_right AND mbps >= bucket_left) AS bucket_count
  FROM max_dl_per_day_ip CROSS JOIN buckets
  GROUP BY 
    test_date,
    continent_code,
    bucket_min,
    bucket_max
),
# Turn the counts into frequencies
dl_histogram AS (
  SELECT 
    test_date,
    continent_code,
    bucket_min,
    bucket_max,
    bucket_count / samples AS dl_frac,
    samples AS dl_samples
  FROM dl_histogram_counts 
  JOIN dl_sample_counts USING (test_date, continent_code)
),
# Repeat for Upload tests
# Select the initial set of upload results
ul_per_location AS (
  SELECT
    test_date,
    client.Geo.continent_code AS continent_code,
    a.MeanThroughputMbps AS mbps,
    NET.SAFE_IP_FROM_STRING(Client.IP) AS ip
  FROM `measurement-lab.ndt.unified_uploads`
  WHERE test_date = @startday
),
# With good locations and valid IPs
ul_per_location_cleaned AS (
  SELECT
    test_date,
    continent_code,
    mbps,
    ip          
  FROM ul_per_location
  WHERE 
    continent_code IS NOT NULL AND continent_code != ""
    AND ip IS NOT NULL
),
# Gather descriptive statistics per geo, day, per ip
ul_stats_perip_perday AS (
  SELECT
    test_date,
    continent_code,
    ip,
    MIN(mbps) AS MIN_upload_Mbps,
    APPROX_QUANTILES(mbps, 100) [SAFE_ORDINAL(25)] AS LOWER_QUART_upload_Mbps,
    APPROX_QUANTILES(mbps, 100) [SAFE_ORDINAL(50)] AS MED_upload_Mbps,
    AVG(mbps) AS MEAN_upload_Mbps,
    APPROX_QUANTILES(mbps, 100) [SAFE_ORDINAL(75)] AS UPPER_QUART_upload_Mbps,
    MAX(mbps) AS MAX_upload_Mbps
  FROM ul_per_location_cleaned
  GROUP BY test_date, continent_code, ip
),
# Calculate final stats per day from 1x test per ip per day normalization in prev. step
ul_stats_per_day AS (
  SELECT 
    test_date,
    continent_code,
    MIN(MIN_upload_Mbps) AS MIN_upload_Mbps,
    APPROX_QUANTILES(LOWER_QUART_upload_Mbps, 100) [SAFE_ORDINAL(25)] AS LOWER_QUART_upload_Mbps,
    APPROX_QUANTILES(MED_upload_Mbps, 100) [SAFE_ORDINAL(50)] AS MED_upload_Mbps,
    AVG(MEAN_upload_Mbps) AS MEAN_upload_Mbps,
    APPROX_QUANTILES(UPPER_QUART_upload_Mbps, 100) [SAFE_ORDINAL(75)] AS UPPER_QUART_upload_Mbps,
    MAX(MAX_upload_Mbps) AS MAX_upload_Mbps
  FROM
    ul_stats_perip_perday
  GROUP BY test_date, continent_code
),
ul_total_samples_per_geo AS (
  SELECT
    test_date,
    COUNT(*) AS ul_total_samples,
    continent_code
  FROM ul_per_location_cleaned
  GROUP BY test_date, continent_code
),
# Now generate daily histograms of Max UL
max_ul_per_day_ip AS (
  SELECT 
    test_date,
    continent_code,
    ip,
    MAX(mbps) AS mbps
  FROM ul_per_location_cleaned
  GROUP BY 
    test_date,
    continent_code,
    ip
),
# Count the samples
ul_sample_counts AS (
  SELECT 
    test_date,
    continent_code,
    COUNT(*) AS samples
  FROM max_ul_per_day_ip
  GROUP BY
    test_date,
    continent_code
),
# Count the samples that fall into each bucket
ul_histogram_counts AS (
  SELECT 
    test_date,
    continent_code,
    bucket_left AS bucket_min,
    bucket_right AS bucket_max,
    COUNTIF(mbps < bucket_right AND mbps >= bucket_left) AS bucket_count
  FROM max_ul_per_day_ip CROSS JOIN buckets
  GROUP BY 
    test_date,
    continent_code,
    bucket_min,
    bucket_max
),
# Turn the counts into frequencies
ul_histogram AS (
  SELECT 
    test_date,
    continent_code,
    bucket_min,
    bucket_max,
    bucket_count / samples AS ul_frac,
    samples AS ul_samples
  FROM ul_histogram_counts 
  JOIN ul_sample_counts USING (test_date, continent_code)
)
# Show the results
SELECT * FROM dl_histogram
JOIN ul_histogram USING (test_date, continent_code, bucket_min, bucket_max)
JOIN dl_stats_per_day USING (test_date, continent_code)
JOIN dl_total_samples_per_geo USING (test_date, continent_code)
JOIN ul_stats_per_day USING (test_date, continent_code)
JOIN ul_total_samples_per_geo USING (test_date, continent_code)
ORDER BY test_date, continent_code, bucket_min, bucket_max