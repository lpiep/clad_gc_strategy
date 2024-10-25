FROM rocker/geospatial:latest

COPY ./ /app
WORKDIR /app
RUN /rocker_scripts/install_quarto.sh
RUN Rscript -e install.packages('tigris')
RUN Rscript -e install.packages('quarto')
RUN Rscript -e source('2_classify_locations.R')
RUN Rscript -e source('3_assign_census_tracts.R')
RUN Rscript -e source('4_build_analytic_dataset.R')
RUN Rscript -e source('5_build_combination_dataset.R')
RUN Rscript -e quarto::quarto_render('geocoder_evaluation.qmd')
