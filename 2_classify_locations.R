# --------------------------------
# Description: Classify input locations according to RUCA, FCC Rural Tribal High-speed Wireless Eligibility Status
# Date: 10/10/2024
#
# Logan Piepmeier
# --------------------------------

library(tigris)
library(readxl)
library(sf)
library(tidyverse)
library(arrow)

reference_locs <- read_parquet('data/reference_locs.parquet')

native_areas <- read_sf('data/Tribal_Priority_2_5_combined.shp') %>%
  summarize(
    geometry = st_union(geometry),
    tribal = TRUE
  )

ruca_def <- tribble(
  ~ruca, ~ruca_urban, ~ruca_desc, 
  '1' 	, 'urban', 'Metropolitan area core: primary flow within an urbanized area (UA)', 
  '2' 	, 'urban', 'Metropolitan area high commuting: primary flow 30% or more to a UA', 
  '3' 	, 'urban', 'Metropolitan area low commuting: primary flow 10% to 30% to a UA', 
  '4' 	, 'nonurban', 'Micropolitan area core: primary flow within an urban cluster of 10,000 to 49,999 (large UC)', 
  '5' 	, 'nonurban', 'Micropolitan high commuting: primary flow 30% or more to a large UC', 
  '6' 	, 'nonurban', 'Micropolitan low commuting: primary flow 10% to 30% to a large UC', 
  '7' 	, 'nonurban', 'Small town core: primary flow within an urban cluster of 2,500 to 9,999 (small UC)', 
  '8' 	, 'nonurban', 'Small town high commuting: primary flow 30% or more to a small UC', 
  '9' 	, 'nonurban', 'Small town low commuting: primary flow 10% to 30% to a small UC', 
  '10' 	, 'nonurban', 'Rural areas: primary flow to a tract outside a UA or UC', 
  '99' 	, 'nonurban', 'Not coded: Census tract has zero population and no rural-urban identifier information'
)
tr <- map(c(state.abb, 'DC', 'PR'), tracts, year = 2010) %>%
  bind_rows() %>%
  select(GEOID10)

ruca <- read_excel('data/ruca.xlsx', skip = 1, col_types = 'text') %>%
  select(
    ruca = `Primary RUCA Code 2010`,
    GEOID10 = `State-County-Tract FIPS Code (lookup by address at http://www.ffiec.gov/Geocode/)`
  )

loc_class <- reference_locs %>%
  mutate(state_territory = if_else(!(state_abbr %in% c('DC', state.abb)), 'territory', 'state or DC')) %>% 
  st_as_sf(coords = c('longitude', 'latitude'), crs = 4326, na.fail = FALSE) %>%
  st_transform(st_crs(tr)) %>% 
  st_join(tr, left = TRUE) %>%
  left_join(ruca, by = 'GEOID10') %>%
  select(Location_id, state_territory, ruca) %>% 
  left_join(ruca_def, by = 'ruca') %>% 
  st_transform(st_crs(native_areas)) %>% 
  st_join(native_areas, left = TRUE) %>%
  st_drop_geometry() %>% 
  mutate(tribal = if_else(is.na(tribal), 'nontribal', 'tribal'))

write_parquet(loc_class, 'data/loc_class.parquet')
