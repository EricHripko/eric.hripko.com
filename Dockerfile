FROM jekyll/jekyll:3.8 AS build-env

# Copy everything and build
COPY . .
RUN jekyll build
WORKDIR _site

# Build runtime image
FROM nginx
COPY --from=build-env . /usr/share/nginx/html
