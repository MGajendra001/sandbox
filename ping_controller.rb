class PingController < ApplicationController
  skip_before_action :reject_xml,
    :store_location,
    :verify_authenticity_token
  skip_after_action :set_csrf_cookie_for_ng,
    :unset_return_to_cookie
  before_action :authenticate_a_user!, only: :universal_links_tests

  def index
    render body: nil, status: 200
  end

  def universal_links_tests
    render 'ping/universal_links_test_page'
  end

  def health
    checks = {
      # database: database_connected?,
      redis: redis_connected?,
      cache: cache_read_write?,
      # migrations: migrations_up_to_date?,
      activerecord: user_exists?,
      # assets_precompiled: assets_precompiled?,
      homepage_generated: homepage_generated?
    }

    if checks.values.all?
      render json: {message: "Application is Live"}, status: 200
    else
      render json: checks, status: 503
    end
  rescue StandardError
    render json: checks, status: 503
  end

  private

  def database_connected?
    ActiveRecord::Base.connection.active?
  rescue 
    puts "Database not connected!!!"
    false
  end

  def redis_connected?
    $redis.ping == "PONG"
  rescue
    puts "Redis not connected!!!"
    false
  end

  def cache_read_write?
    cache_key = 'health_check_cache_test'
    cache_value = Time.current.to_s
    Rails.cache.write(cache_key, cache_value)
    Rails.cache.read(cache_key) == cache_value
  end

  def migrations_up_to_date?
    pending_migrations = ActiveRecord::MigrationContext.new(
      ActiveRecord::Migrator.migrations_paths,
      ActiveRecord::SchemaMigration
    ).migrations_status
  
    pending_migrations.none? { |migration| migration[0] == 'down' }
  rescue
    puts "There are some migrations!!!"
    false
  end

  # Ensure ActiveRecord is proper.ly connected and functionning
  def user_exists?
    User.limit(1).exists?
  rescue ActiveRecord::ActiveRecordError
    puts "Active Records is not functioning properly"
    false
  end

  def assets_precompiled?
    Rails.env.production? ? Dir.exist?(Rails.root.join('public', 'assets')) : true
  rescue
    puts "Assets are not precompiled yet!!!"
    false
  end

  def homepage_generated?
    # response = Net::HTTP.get_response(URI.parse(home_page_url))
    # response.is_a?(Net::HTTPSuccess)
    check_url(home_page_url)
    
  rescue StandardError
    puts "Application is not ready to process traffic!!!"
    false
  end

  def check_url(url)
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
  
    request = Net::HTTP::Head.new(uri.request_uri)
    response = http.request(request)
  
    case response
    when Net::HTTPSuccess
      puts "URL is accessible: #{url}"
      true
    when Net::HTTPRedirection
      puts "URL is accessible but redirected: #{url}"
      false
    else
      puts "URL is not accessible: #{url}"
      false
    end
  end

  def home_page_url
    "#{Rails.env.production? ?  ENV['APP_TEST_URL'] : 'http://localhost:3000'}/marketplaces/hobbydb/users/sign_in"
  end
end
