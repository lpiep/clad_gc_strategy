
library(tidyverse)
library(sf)

# Rank
# 1. PostGIS with confidence = 0 
# 2. Degauss with precision "range" (N = 1)
# 3. PostGIS with confidence <= 20
# 4. Nominatim (N = 1)
# 5. Degauss with precision "street" (N = 1)
# 999. PostGIS with confidence > 20 OR NA 

compare <- read_rds('data/geocode_comparison_clean.rds')
compare_w_ranks <- compare %>% 
  group_by(geocoder, id) %>%
  filter(n() == 1 & !input_qc_fail) %>% # singletons only
  mutate(
    rank = case_when(
      is.na(gc_tract_correct) ~ '999 - None',
      geocoder == 'postgis' & postgis_rating == 0 ~ '1 - Postgis Rating = 0',
      geocoder == 'degauss' & degauss_precision == 'range' ~ '2 - Degauss Precision = "range"',
      geocoder == 'postgis' & postgis_rating <= 20 ~ '3 - Postgis Rating <= 20', 
      geocoder == 'nominatim' ~ '4 - Nominatim',
      geocoder == 'degauss' & degauss_precision == 'street' ~ '5 - Degauss Precision = "street"',
      TRUE ~ '999 - None'
    )
  ) %>% 
  ungroup() %>%
  group_by(id) %>%
  filter(as.numeric(substr(rank, 1, 1)) == min(as.numeric(substr(rank, 1, 1)))) %>%
  mutate(gc_tract_correct = if_else(rank == '999 - None', NA, gc_tract_correct)) 
write_rds(st_drop_geometry(compare_w_ranks), 'data/compare_w_ranks.rds')


tr <- map(setdiff(unique(fips_codes$state_code), '74'), tracts, year = 2020, cb = FALSE, progress_bar = FALSE) %>% 
  bind_rows() %>% 
  select(GEOID) %>%
  st_transform('WGS84')

compare_centroid <- compare_w_ranks %>%
  st_as_sf(coords = c('long_gc', 'lat_gc'), crs = 4326, na.fail = FALSE) %>% 
  filter(as.numeric(substr(rank, 1, 1)) <= 4) %>% 
  st_set_geometry('geometry') %>% 
  group_by(id, tract_geoid_true) %>%
  summarize(
    spread = max(as.numeric(st_distance(geometry))),
    n_pts = n(),
    ranks = list(rank),
    geometry = st_centroid(st_combine(geometry)),
    .groups = 'drop'
  ) %>% 
  st_join(tr) %>%
  rename(tract_geoid = GEOID) %>%
  mutate(gc_tract_correct = tract_geoid_true == tract_geoid)


write_rds(compare_centroid, 'data/compare_w_centroid.rds')
