source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby "4.0.9"

# json 3.x breaks ActiveSupport::JSON.decode until Rails adapts to keyword-only options
gem "json", "< 3"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.4", ">= 8.1.4.1"

# The original asset pipeline for Rails [https://github.com/rails/sprockets-rails]
gem "sprockets-rails"

# Use postgresql as the database for Active Record
gem "pg", "~> 1.7"

# Use the Puma web server [https://github.com/puma/puma]
gem "puma", "~> 8.0"

# Bundle and transpile JavaScript [https://github.com/rails/jsbundling-rails]
gem "jsbundling-rails"

# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"

# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"

# Bundle and process CSS [https://github.com/rails/cssbundling-rails]
gem "cssbundling-rails"

# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Use Redis adapter to run Action Cable in production
# gem "redis", "~> 4.0"

# Use Kredis to get higher-level data types in Redis [https://github.com/rails/kredis]
# gem "kredis"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Authentication and authorization
gem "devise", "~> 5.0"
gem "omniauth"
gem "omniauth-oauth2"
# Updated to 2.0.1 to fix ActiveSupport::Configurable deprecation warning
# If CSRF issues occur behind reverse proxies, may need to revert to 1.0.2
gem "omniauth-rails_csrf_protection", "~> 2.0"
gem "pundit"

# Pagination
gem "pagy", "~> 43.8"

# Recurring events
gem "ice_cube"

# iCal feed generation
gem "icalendar"

# Background job processing
gem "sidekiq"
gem "sidekiq-scheduler"

# Redis for Sidekiq
gem "redis", "~> 6.0"

# connection_pool for Sidekiq
gem "connection_pool"

# Rate limiting and throttling
gem "rack-attack"

# Error tracking and profiling
gem "sentry-rails"
gem "sentry-ruby"
gem "sentry-sidekiq"
gem "stackprof"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[windows jruby]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Use Sass to process CSS
# gem "sassc-rails"

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 2.2"
gem "mini_magick"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[mri windows]

  # Testing framework
  gem "factory_bot_rails"
  gem "faker"
  gem "rspec-rails", "~> 8.0"

  # Code quality and security
  gem "brakeman", require: false
  gem "bundler-audit", require: false
  gem "rubocop", require: false
  gem "rubocop-rails", require: false
  gem "rubocop-rspec", require: false
end

group :test do
  # Additional testing tools
  gem "capybara"
  gem "database_cleaner-active_record"
  gem "parallel_tests"
  gem "selenium-webdriver"
  gem "shoulda-matchers", "~> 8.0"
  gem "simplecov", require: false
end

# Browser-based mail capture (/letter_opener); delivery_method set per environment
group :development, :staging do
  gem "letter_opener_web", "~> 3.0"
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"

  # Add speed badges [https://github.com/MiniProfiler/rack-mini-profiler]
  # gem "rack-mini-profiler"

  # Speed up commands on slow machines / big apps [https://github.com/rails/spring]
  # gem "spring"
end
