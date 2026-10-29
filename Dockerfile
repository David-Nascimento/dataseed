FROM ruby:3.3-alpine

RUN apk add --no-cache build-base

WORKDIR /app
COPY Gemfile Gemfile.lock* /app/
RUN bundle install

COPY . /app

ENV RACK_ENV=production
ENV PORT=9292
ENV MAX_COUNT=200

EXPOSE 9292
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]