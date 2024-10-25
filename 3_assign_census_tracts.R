# --------------------------------
# Description: Assign census tracts to input locations and geocodes
# Date: 10/10/2024
#
# Logan Piepmeier
# --------------------------------

library(sf)
library(tidyverse)

degauss_gc <- read_parquet('data/degauss_gc.parquet') %>% st_as_sf(coords = c('lon', 'lat'), crs = 'WGS84', na.fail = FALSE)
postgis_gc <- read_parquet('data/postgis_gc.parquet') %>% st_as_sf(coords = c('long', 'lat'), crs = 'WGS84', na.fail = FALSE)
nominatim_gc <- read_parquet('data/nominatim_gc.parquet') %>% st_as_sf(coords = c('lon', 'lat'), crs = 'WGS84', na.fail = FALSE)
reference_locs <- read_parquet('data/reference_locs.parquet') %>% st_as_sf(coords = c('longitude', 'latitude'), crs = 'WGS84', na.fail = FALSE)

# Download 2020 Census Tracts (exclude FIPS 74 call bc Midway has no tracts)
tr <- map(setdiff(unique(fips_codes$state_code), '74'), tracts, year = 2020, cb = FALSE, progress_bar = FALSE) %>% 
  bind_rows() %>% 
  select(GEOID) %>%
  st_transform('WGS84')

degauss_census <- st_join(degauss_gc, tr) %>% st_drop_geometry() %>% transmute(Location_id, result_id, geocoder = 'degauss', tract_geoid = GEOID) 
postgis_census <- st_join(postgis_gc, tr) %>% st_drop_geometry() %>% transmute(Location_id, result_id, geocoder = 'postgis', tract_geoid = GEOID) 
nominatim_census <- st_join(nominatim_gc, tr) %>% st_drop_geometry() %>% transmute(Location_id, result_id, geocoder = 'nominatim', tract_geoid = GEOID) 
reference_census <- st_join(reference_locs, tr) %>% st_drop_geometry() %>% transmute(Location_id, tract_geoid = GEOID) 

write_parquet(degauss_census, 'data/degauss_census.parquet')
write_parquet(postgis_census, 'data/postgis_census.parquet')
write_parquet(nominatim_census, 'data/nominatim_census.parquet')
write_parquet(reference_census, 'data/reference_census.parquet')


