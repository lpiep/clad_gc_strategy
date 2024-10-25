FROM rocker/binder:latest

COPY ./ /app
WORKDIR /app
RUN /rocker_scripts/install_quarto.sh
RUN Rscript -e "install.packages('tigris')"
RUN Rscript -e "install.packages('quarto')"
RUN Rscript -e "install.packages('kableExtra')"
RUN Rscript -e "quarto::quarto_render('geocoder_evaluation.qmd')"
