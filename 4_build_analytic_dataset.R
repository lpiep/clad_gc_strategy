# --------------------------------
# Description: Build comparison data set
# Date: 10/10/2024
#
# Logan Piepmeier
# --------------------------------

library(tidyverse)
library(sf)

### Reference Data Set ###
input <- read_parquet('data/reference_locs.parquet') %>%
  rename(id = Location_id) %>% 
  mutate(id = as.character(id)) %>% 
  filter(!is.na(latitude))

# do a quick check to make sure the "true" lat longs are at least in the right state, mark those that fail
qc <- function(input){
  input_sf <- st_as_sf(input, coords = c('longitude', 'latitude'), crs = 4326, na.fail = FALSE)
  input_sf <- st_join(input_sf, select(tigris::states(), state_spatial = STUSPS) %>% st_transform(4326), left = TRUE)
  input$qc_fail <- (input_sf$state_abbr != input_sf$state_spatial) | is.na(input_sf$state_spatial)
  input
}
input <- qc(input)

# add location classes to input data
loc_class <- read_parquet('data/loc_class.parquet') %>% 
  rename(id = Location_id) %>% 
  mutate(id = as.character(id)) %>%
  transmute(
    id, 
    loc_class = 
      case_when(
        state_territory == 'territory' ~ 'territory',
        tribal == 'tribal' ~ 'tribal',
        ruca_urban == 'urban' ~   'urban nontribal',
        ruca_urban == 'nonurban' ~ 'nonurban nontribal',
        TRUE ~ NA
      )
  )

input <- input %>% left_join(loc_class, by = 'id')

# add census geography to input data
reference_census <- read_parquet('data/reference_census.parquet') %>% rename(id = Location_id) %>% mutate(id = as.character(id))
input <- input %>% left_join(reference_census, by = 'id')


### Geocoded Data Sets ###
output_long <- list(
  degauss = read_parquet('data/degauss_gc.parquet') %>% st_as_sf(coords = c('lon', 'lat'), crs = 'WGS84', na.fail = FALSE),
  postgis = read_parquet('data/postgis_gc.parquet') %>% st_as_sf(coords = c('long', 'lat'), crs = 'WGS84', na.fail = FALSE),
  nominatim = read_parquet('data/nominatim_gc.parquet') %>% st_as_sf(coords = c('lon', 'lat'), crs = 'WGS84', na.fail = FALSE)
) %>%
  bind_rows(.id = "geocoder") %>%
  select(id = Location_id, result_id, geocoder, degauss_precision = precision, degauss_score = score, postgis_rating = rating) %>%
  mutate(lat_gc = st_coordinates(.)[ ,2], long_gc = st_coordinates(.)[ ,1])

# add in geocode census geography 
census_geog <- bind_rows(
  read_parquet('data/degauss_census.parquet'),
  read_parquet('data/postgis_census.parquet'),
  read_parquet('data/nominatim_census.parquet')
) %>%
  rename(id = Location_id)

stopifnot(nrow(unique(census_geog[ , c('id', 'result_id', 'geocoder')])) == nrow(census_geog))

output_long <- output_long %>% left_join(census_geog, by = c('id', 'result_id', 'geocoder'))

### Combine Input & Outputs to Compare ###
compare <- input %>%
  transmute(
    id,
    location_source_value,
    lat_input = latitude, 
    long_input = longitude,
    input_qc_fail = qc_fail,
    loc_class,
    tract_geoid
  ) %>% 
  expand_grid(geocoder = c('postgis', 'degauss', 'nominatim')) %>% 
  left_join(output_long, by = c('id', 'geocoder'), suffix = c('_true', '')) %>% 
  mutate(failure = is.na(lat_gc) | is.na(long_gc)) %>% 
  arrange(id, geocoder)

compare$geometry_true <- st_as_sf(as.data.frame(compare), coords = c("long_input","lat_input"), crs = 4326, na.fail = FALSE)$geometry

compare <- compare %>% mutate(
  gc_diff_m = as.numeric(st_distance(geometry, geometry_true, by_element = TRUE)),
  gc_tract_correct = tract_geoid_true == tract_geoid, 
  location_source_value = toupper(location_source_value)
) %>%
  group_by(id, geocoder) %>% 
  mutate(result_count = n()) %>%
  ungroup()

st_write_parquet(st_as_sf(compare), 'data/geocode_comparison_clean.parquet')
