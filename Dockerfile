FROM rocker/geospatial:latest

COPY ./ /app
WORKDIR /app
CMD ['/rocker_scripts/install_quarto.sh']
CMD ["Rscript", "-e", "install.packages('tigris')"]
CMD ["Rscript", "-e", "install.packages('quarto')"]
CMD ["Rscript", "-e", "source('2_classify_locations.R')"]
CMD ["Rscript", "-e", "source('3_assign_census_tracts.R')"]
CMD ["Rscript", "-e", "source('4_build_analytic_dataset.R')"]
CMD ["Rscript", "-e", "source('5_build_combination_dataset.R')"]
CMD ["Rscript", "-e", "quarto::quarto_render('geocoder_evaluation.qmd')"]
