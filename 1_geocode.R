# --------------------------------
# Description: Geocode & Download Raw Data
# Date: 9/20/2024
#
# Logan Piepmeier
# --------------------------------

library(tidyverse)
library(httr2)
library(jsonlite)
library(future)
library(furrr)
library(glue)
library(arrow)
library(sfarrow)

plan(multisession(workers = 10))

reference_locs <- read_csv("https://github.com/brian-cy-chang/CLAD_Geospatial/raw/refs/heads/main/output/OMOP_location_flagged_successful.csv")
#reference_locs <- reference_locs %>% sample_n(100)
write_parquet(reference_locs, 'data/reference_locs.parquet')

# tribal boundaries
# https://www.fcc.gov/25-ghz-rural-tribal-maps (eligible FCC 2.5GHz areas)
system('wget https://github.com/brian-cy-chang/CLAD_Geospatial/raw/90d16d84bfe4c5ca961f3827a971331373425f6b/output/Tribal_Priority_2_5/Tribal_Priority_2_5_combined.shp')
system('wget https://github.com/brian-cy-chang/CLAD_Geospatial/raw/90d16d84bfe4c5ca961f3827a971331373425f6b/output/Tribal_Priority_2_5/Tribal_Priority_2_5_combined.prj')
system('wget https://github.com/brian-cy-chang/CLAD_Geospatial/raw/90d16d84bfe4c5ca961f3827a971331373425f6b/output/Tribal_Priority_2_5/Tribal_Priority_2_5_combined.shx')
system('wget https://github.com/brian-cy-chang/CLAD_Geospatial/raw/90d16d84bfe4c5ca961f3827a971331373425f6b/output/Tribal_Priority_2_5/Tribal_Priority_2_5_combined.cpg')
system('wget https://github.com/brian-cy-chang/CLAD_Geospatial/raw/90d16d84bfe4c5ca961f3827a971331373425f6b/output/Tribal_Priority_2_5/Tribal_Priority_2_5_combined.dbf')
system('mv Tribal_Priority_2_5_combined.* data')


### GEOCODE ME BABY ###
geocode <- function(addr, geocoder = c('degauss', 'nominatim', 'postgis'), ...){
  extra_args = list(...)
  stopifnot(length(addr) == 1)
  geocoder <- match.arg(geocoder)
  geocoder_url <- case_when(
    geocoder == 'degauss' ~ 'http://cladgeocoder.rit.uw.edu:50002',
    geocoder == 'nominatim' ~ 'http://swarm02.rit.uw.edu:50003',
    geocoder == 'postgis' ~ 'http://cladgeocoder.rit.uw.edu:50000'
    
  )
  geocoder_path <- case_when(
    geocoder == 'degauss' ~ 'degausslatlong',
    geocoder == 'nominatim' ~ 'search', 
    geocoder == 'postgis' ~ 'latlong'
  )
  req <- request(geocoder_url) %>% 
    req_url_path_append(geocoder_path) %>%
    req_throttle(120/60) %>%
    req_retry(max_tries = 10)# %>% #, is_transient = ~ TRUE) %>%
    #req_verbose()

  if(geocoder %in% c('degauss', 'postgis')){
    req <- req %>% req_url_query(q = addr) 
  }else{ 
    req <- req %>% 
      req_url_query(
        street = extra_args$address_1,
        city = extra_args$city,
        state = extra_args$state, 
        country = 'United States',
        postalcode = extra_args$zip,
        addressdetails = 1, 
        format = 'json'
      ) 
  }

  req %>%
    req_perform() %>%
    resp_body_string() %>%
    fromJSON(simplifyVector = TRUE)
}


nominatim_gc <- future_pmap(
  reference_locs %>% select(address_1, city, state, zip),
  function(...) tryCatch(geocode('dummy', geocoder = 'nominatim', ...), error = function(e) NULL)
) %>%
  setNames(reference_locs$Location_id) %>%
  bind_rows(.id = 'Location_id') %>% 
  group_by(Location_id) %>% 
  mutate(result_id = row_number()) %>%
  ungroup() %>%
  st_drop_geometry()
write_parquet(nominatim_gc, 'data/nominatim_gc.parquet')

stop('donezo!') 

degauss_gc <- future_map(
  reference_locs$location_source_value, 
  function(x) tryCatch(geocode(x, geocoder = 'degauss'), error = function(e) NULL)
) %>%
  setNames(reference_locs$Location_id) %>%
  bind_rows(.id = 'Location_id') %>%
  group_by(Location_id) %>% 
  mutate(result_id = row_number()) %>%
  ungroup() %>%
  st_drop_geometry()
write_parquet(degauss_gc, 'data/degauss_gc.parquet')


postgis_gc <- future_map(
  reference_locs$location_source_value, 
  function(x) tryCatch(geocode(x, geocoder = 'postgis'), error = function(e) NULL)
) %>%
  setNames(reference_locs$Location_id) %>%
  bind_rows(.id = 'Location_id') %>%
  group_by(Location_id) %>% 
  mutate(result_id = row_number()) %>%
  ungroup() %>%
  st_drop_geometry()

write_parquet(postgis_gc, 'data/postgis_gc.parquet')


degauss_missed <-   mutate(reference_locs, Location_id = as.character(Location_id)) %>% anti_join(degauss_gc, by = 'Location_id')
postgis_missed <-   mutate(reference_locs, Location_id = as.character(Location_id)) %>% anti_join(postgis_gc, by = 'Location_id')
nominatim_missed <- mutate(reference_locs, Location_id = as.character(Location_id)) %>% anti_join(nominatim_gc, by = 'Location_id')

# 
# degauss_gc_missed <- future_map(
#   degauss_missed$location_source_value, 
#   function(x) tryCatch(geocode(x, geocoder = 'degauss'), error = function(e) NULL)
# ) %>%
#   setNames(degauss_missed$Location_id) %>%
#   bind_rows(.id = 'Location_id')
# 
# 
# postgis_gc_missed <- future_map(
#   postgis_missed$location_source_value, 
#   function(x) tryCatch(geocode(x, geocoder = 'postgis'), error = function(e) {message(e); return(NULL)})
# ) %>%
#   setNames(postgis_missed$Location_id) %>%
#   bind_rows(.id = 'Location_id')
# 
# 
# nominatim_gc_missed <- future_pmap(
#   nominatim_missed %>% select(address_1, city, state, zip),
#   function(...) tryCatch(geocode('dummy', geocoder = 'nominatim', ...), error = function(e) NULL)
# ) %>%
#   setNames(nominatim_missed$Location_id) %>%
#   bind_rows(.id = 'Location_id')



# these don't return anything after a few tries, so I think it's safe to call them GC failures

