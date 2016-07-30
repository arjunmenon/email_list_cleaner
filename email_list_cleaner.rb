#!/usr/bin/env ruby
require "rubygems"
require "bundler/setup"
require "yaml"
require "csv"
require "singleton"
Bundler.require(:default)

Dir.glob("lib/**/*.rb") {|f| require_relative f}

# Cleans list of emails (_list.csv) by looking for gibberish,
# de-duping, and connecting to SMTP servers.
class EmailListCleaner
  include Singleton

  # Redis namespace & keys
  # Operates out of "db 1"
  R_DEFAULT_DB = 1
  R_NAMESPACE  = "email_cleaner"
  R_SET_TODO   = "unverified"
  R_SET_GOOD   = "good"
  R_SET_BAD    = "bad"

  attr_reader :r_named, :config

  def initialize
    @config = YAML::load_file("config.yml")
    config_redis
    config_email_verifier
  end

  # If proxy_addresses defined in config.yml, this provides
  # random proxy in that list to Net::SMTP"s method that fetches a
  # TCPConnection.
  def random_proxy
    c = @config["proxy_addresses"]
    return nil unless c.kind_of?(Array) && c.length > 0
    return c.sample
  end

  def run
    load_csv_into_redis_set
    enum_and_verify
    dump_csv_files
    print_stats
  end

  # CSV expected to have "Name", "Email address" in each row
  def load_csv_into_redis_set
    csv_arr = CSV.read("_list.csv")
    @pg = ProgressBar.create(
      title: "Load into Redis",
      total: csv_arr.length
    )
    csv_arr.each do |row|
      email = row[1]
      @r_named.sadd(R_SET_TODO, email)
      @pg.increment
    end
    return @r_named.scard(R_SET_TODO)
  end

  # Writes CSV files based on our current redis sets.
  def dump_csv_files
    write_csv_file(R_SET_TODO, "_list_todo.csv")
    write_csv_file(R_SET_GOOD, "_list_good.csv")
    write_csv_file(R_SET_BAD,  "_list_bad.csv")
  end

  def write_csv_file(redis_key, file_name)
    email_arr = @r_named.smembers(redis_key)
    File.open(file_name, "w") do |f|
      f << email_arr.join("\n")
    end
  end

  def enum_and_verify
    @pg = ProgressBar.create(
      title: "Verifying",
      total: @r_named.scard(R_SET_TODO)
    )
    email = nil 
    while email = @r_named.spop(R_SET_TODO) do
      sleep @config["sleep_time"]
      verify_email(email)
      @pg.increment
    end
  # For ctrl-c support
  rescue SystemExit, Interrupt
    return
  end

  def verify_email(email)
    success = false
    begin
      success = EmailVerifier.check(email)
    rescue => e
      @pg.log "  = #{email}"
      @pg.log "    - #{e.message}"
    end
    if success
      @r_named.sadd(R_SET_GOOD, email)
    else
      @r_named.sadd(R_SET_BAD, email)
    end
  end

  def print_stats
    puts "REMAINING: #{@r_named.scard(R_SET_TODO)}"
    puts "GOOD: #{@r_named.scard(R_SET_GOOD)}"
    puts "BAD: #{@r_named.scard(R_SET_BAD)}"
  end

  # ===========================================================================
  private

  def config_redis
    r_config = {db: R_DEFAULT_DB}
    unless @config["redis_password"].to_s.empty?
      r_config["password"] = @config["redis_password"]
    end
    r_conn = Redis.new(r_config)
    @r_named = Redis::Namespace.new(R_NAMESPACE, redis: r_conn)
  end

  def config_email_verifier    
    EmailVerifier.config do |c|
      c.verifier_email = @config["from_email_address"]
    end
  end

end