WITH
# Select the initial set of download test results
dl_per_location AS (
  SELECT
    date,
    client.Geo.continent_code AS continent_code,
    client.Geo.country_code AS country_code,
    client.Geo.country_name AS country_name,
    CONCAT(client.Geo.country_code, '-', client.Geo.region) AS ISO3166_2region1,
    a.MeanThroughputMbps AS mbps,
    NET.SAFE_IP_FROM_STRING(Client.IP) AS ip
  FROM `measurement-lab.ndt.unified_downloads`
  WHERE date BETWEEN @startdate AND @enddate
  AND client.geo.region != ""
  AND client.geo.region IS NOT NULL
  AND a.MeanThroughputMbps != 0
),
# Clean the initial set of results so we're only using those with good location values and valid IPs
dl_per_location_cleaned AS (
  SELECT
    date,
    continent_code,
    country_code,
    country_name,
    ISO3166_2region1,
    mbps,
    ip
  FROM dl_per_location
  WHERE
    continent_code IS NOT NULL AND continent_code != ""
    AND country_code IS NOT NULL AND country_code != ""
    AND country_name IS NOT NULL AND country_name != ""
    AND ISO3166_2region1 IS NOT NULL AND ISO3166_2region1 != ""
    AND ip IS NOT NULL
),
# Gather descriptive statistics per geo, day, per ip
dl_stats_perip_perday AS (
  SELECT
    date,
    continent_code,
    country_code,
    country_name,
    ISO3166_2region1,
    ip,
    MIN(mbps) AS download_MIN,
    APPROX_QUANTILES(mbps, 100) [SAFE_ORDINAL(25)] AS download_Q25,
    APPROX_QUANTILES(mbps, 100) [SAFE_ORDINAL(50)] AS download_MED,
    AVG(mbps) AS download_AVG,
    APPROX_QUANTILES(mbps, 100) [SAFE_ORDINAL(75)] AS download_Q75,
    MAX(mbps) AS download_MAX
  FROM dl_per_location_cleaned
  GROUP BY
    date,
    continent_code,
    country_code,
    country_name,
    ISO3166_2region1,
    ip
),
# Calculate final stats per day from 1x test per ip per day normalization in prev. step
dl_stats_perday AS (
  SELECT
    date,
    continent_code,
    country_code,
    country_name,
    ISO3166_2region1,
    MIN(download_MIN) AS download_MIN,
    APPROX_QUANTILES(download_Q25, 100) [SAFE_ORDINAL(25)] AS download_Q25,
    APPROX_QUANTILES(download_MED, 100) [SAFE_ORDINAL(50)] AS download_MED,
    AVG(download_MED) AS download_AVG,
    APPROX_QUANTILES(download_Q75, 100) [SAFE_ORDINAL(75)] AS download_Q75,
    MAX(download_MAX) AS download_MAX
  FROM
    dl_stats_perip_perday
  GROUP BY
    date,
    continent_code,
    country_code,
    country_name,
    ISO3166_2region1
),
# Total samples pergeo perday counts ALL tests in the day, from the original cleaned data.
dl_total_samples_pergeo_perday AS (
  SELECT
    date,
    COUNT(*) AS dl_total_samples,
    continent_code,
    country_code,
    country_name,
    ISO3166_2region1
  FROM dl_per_location_cleaned
  GROUP BY
    date,
    continent_code,
    country_code,
    country_name,
    ISO3166_2region1
),
# Now generate the daily histograms of the Maximum measured download speed, per IP, per day.

# First, select the MAX download metric and geo fields from the original cleaned data.
max_dl_per_day_ip AS (
  SELECT
    date,
    continent_code,
    country_code,
    country_name,
    ISO3166_2region1,
    ip,
    MAX(mbps) AS download_MAX
  FROM dl_per_location_cleaned
  GROUP BY
    date,
    continent_code,
    country_code,
    country_name,
    ISO3166_2region1,
    ip
),
# Count the samples for the daily histogram of Max dowload tests.
#   The counts here are drawn from: dl_stats_perip_perday > max_dl_per_day_ip
#   and therefore represent the **one** MAX download value per IP on that day.
#
#   This count is different from "dl_total_samples_pergeo_perday" because the
#   histogram is meant to communicate the number of **testers** who could or could
#   not reach specific bucket thresholds, while dl_total_samples_pergeo_perday
#   is the count of **all tests** from all IPs in the sample on that day.
dl_sample_counts AS (
  SELECT
    date,
    continent_code,
    country_code,
    country_name,
    ISO3166_2region1,
    COUNT(*) AS samples
  FROM max_dl_per_day_ip
  GROUP BY
    date,
    continent_code,
    country_code,
    country_name,
    ISO3166_2region1
),
# Generate equal sized buckets in log-space. This returns 21 buckets pergeo perday from 0.63 to 10000.
# Five steps per logarithmic decade, from 0.63 to 10000, i.e. 0.63, 1.0, 1.58, 2.51, 3.98, 6.30, 10.0, ...

buckets AS (
  SELECT POW(10, x-.2) AS bucket_left, POW(10,x) AS bucket_right
  FROM UNNEST(GENERATE_ARRAY(-5, 4.2, .2)) AS x
),
# Count the samples that fall into each bucket
dl_histogram_counts AS (
  SELECT
    date,
    continent_code,
    country_code,
    country_name,
    ISO3166_2region1,
    bucket_left AS bucket_min,
    bucket_right AS bucket_max,
    COUNTIF(download_MAX BETWEEN bucket_left AND bucket_right) AS bucket_count
  FROM max_dl_per_day_ip CROSS JOIN buckets
  GROUP BY
    date,
    continent_code,
    country_code,
    country_name,
    ISO3166_2region1,
    bucket_min,
    bucket_max
),
# Turn the counts into frequencies
dl_histogram AS (
  SELECT
    date,
    continent_code,
    country_code,
    country_name,
    ISO3166_2region1,
    bucket_min,
    bucket_max,
    bucket_count / samples AS dl_frac,
    samples AS dl_samples
  FROM dl_histogram_counts
  JOIN dl_sample_counts USING (date, continent_code, country_code,
                            country_name, ISO3166_2region1)
),
# Repeat for Upload tests
# Select the initial set of upload results
ul_per_location AS (
  SELECT
    date,
    client.Geo.continent_code AS continent_code,
    client.Geo.country_code AS country_code,
    client.Geo.country_name AS country_name,
    CONCAT(client.Geo.country_code, '-', client.Geo.region) AS ISO3166_2region1,
    a.MeanThroughputMbps AS mbps,
    NET.SAFE_IP_FROM_STRING(Client.IP) AS ip
  FROM `measurement-lab.ndt.unified_uploads`
  WHERE date BETWEEN @startdate AND @enddate
  AND client.geo.region != ""
  AND client.geo.region IS NOT NULL
  AND a.MeanThroughputMbps != 0
),
# With good locations and valid IPs
ul_per_location_cleaned AS (
  SELECT
    date,
    continent_code,
    country_code,
    country_name,
    ISO3166_2region1,
    mbps,
    ip
  FROM ul_per_location
  WHERE
    continent_code IS NOT NULL AND continent_code != ""
    AND country_code IS NOT NULL AND country_code != ""
    AND country_name IS NOT NULL AND country_name != ""
    AND ISO3166_2region1 IS NOT NULL AND ISO3166_2region1 != ""
    AND ip IS NOT NULL
),
# Gather descriptive statistics per geo, day, per ip
ul_stats_perip_perday AS (
  SELECT
    date,
    continent_code,
    country_code,
    country_name,
    ISO3166_2region1,
    ip,
    MIN(mbps) AS upload_MIN,
    APPROX_QUANTILES(mbps, 100) [SAFE_ORDINAL(25)] AS upload_Q25,
    APPROX_QUANTILES(mbps, 100) [SAFE_ORDINAL(50)] AS upload_MED,
    AVG(mbps) AS upload_AVG,
    APPROX_QUANTILES(mbps, 100) [SAFE_ORDINAL(75)] AS upload_Q75,
    MAX(mbps) AS upload_MAX
  FROM dl_per_location_cleaned
  GROUP BY
    date,
    continent_code,
    country_code,
    country_name,
    ISO3166_2region1,
    ip
),
# Calculate final stats per day from 1x test per ip per day normalization in prev. step
ul_stats_perday AS (
  SELECT
    date,
    continent_code,
    country_code,
    country_name,
    ISO3166_2region1,
    MIN(upload_MIN) AS upload_MIN,
    APPROX_QUANTILES(upload_Q25, 100) [SAFE_ORDINAL(25)] AS upload_Q25,
    APPROX_QUANTILES(upload_MED, 100) [SAFE_ORDINAL(50)] AS upload_MED,
    AVG(upload_MED) AS upload_AVG,
    APPROX_QUANTILES(upload_Q75, 100) [SAFE_ORDINAL(75)] AS upload_Q75,
    MAX(upload_MAX) AS upload_MAX
  FROM
    ul_stats_perip_perday
  GROUP BY
    date,
    continent_code,
    country_code,
    country_name,
    ISO3166_2region1
),
ul_total_samples_pergeo_perday AS (
  SELECT
    date,
    COUNT(*) AS ul_total_samples,
    continent_code,
    country_code,
    country_name,
    ISO3166_2region1
  FROM ul_per_location_cleaned
  GROUP BY
    date,
    continent_code,
    country_code,
    country_name,
    ISO3166_2region1
),
# Now generate the daily histograms of the Maximum measured upload speed, per IP, per day.
max_ul_per_day_ip AS (
  SELECT
    date,
    continent_code,
    country_code,
    country_name,
    ISO3166_2region1,
    ip,
    MAX(mbps) AS upload_MAX
  FROM ul_per_location_cleaned
  GROUP BY
    date,
    continent_code,
    country_code,
    country_name,
    ISO3166_2region1,
    ip
),
# Count the samples
ul_sample_counts AS (
  SELECT
    date,
    continent_code,
    country_code,
    country_name,
    ISO3166_2region1,
    COUNT(*) AS samples
  FROM max_ul_per_day_ip
  GROUP BY
    date,
    continent_code,
    country_code,
    country_name,
    ISO3166_2region1
),
# Count the samples that fall into each bucket
ul_histogram_counts AS (
  SELECT
    date,
    continent_code,
    country_code,
    country_name,
    ISO3166_2region1,
    bucket_left AS bucket_min,
    bucket_right AS bucket_max,
    COUNTIF(upload_MAX BETWEEN bucket_left AND bucket_right) AS bucket_count
  FROM max_ul_per_day_ip CROSS JOIN buckets
  GROUP BY
    date,
    continent_code,
    country_code,
    country_name,
    ISO3166_2region1,
    bucket_min,
    bucket_max
),
# Turn the counts into frequencies
ul_histogram AS (
  SELECT
    date,
    continent_code,
    country_code,
    country_name,
    ISO3166_2region1,
    bucket_min,
    bucket_max,
    bucket_count / samples AS ul_frac,
    samples AS ul_samples
  FROM ul_histogram_counts
  JOIN ul_sample_counts USING (date, continent_code, country_code,
                            country_name, ISO3166_2region1)
)
# Show the results
SELECT * FROM dl_histogram
JOIN ul_histogram USING (date, continent_code, country_code, country_name, ISO3166_2region1, bucket_min, bucket_max)
JOIN dl_stats_perday USING (date, continent_code, country_code, country_name, ISO3166_2region1)
JOIN dl_total_samples_pergeo_perday USING (date, continent_code, country_code, country_name, ISO3166_2region1)
JOIN ul_stats_perday USING (date, continent_code, country_code, country_name, ISO3166_2region1)
JOIN ul_total_samples_pergeo_perday USING (date, continent_code, country_code, country_name, ISO3166_2region1)
