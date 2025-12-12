environment ENV.fetch("RACK_ENV", "development")
rackup File.expand_path("../config.ru", __dir__)
port ENV.fetch("PORT", 9292)
threads 0, 5
