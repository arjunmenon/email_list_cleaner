#!/usr/bin/env ruby

require 'rubygems'
require 'bundler/setup'
require 'yaml'
require 'csv'
Bundler.require(:default)

Dir.glob('lib/**/*.rb') {|f| require_relative f}


# Cleans list of emails (_list.csv) by looking for gibberish,
# de-duping, and connecting to SMTP servers.
class EmailListCleaner
  R_NAMESPACE = 'email_cleaner'
  R_SET_TODO  = 'unverified'
  R_SET_GOOD  = 'good'
  R_SET_BAD   = 'bad'

  def initialize
    @config = YAML::load_file('config.yml')
    config_redis
    config_email_verifier
  end

  def run
    load_csv_into_redis_set
    enumerate_and_verify
  end

  # ===========================================================================
  private

  # CSV expected to have "Name", "Email address" in each row
  def load_csv_into_redis_set
    csv_arr = CSV.read('_list.csv')
    pg = ProgressBar.create(
      title: "Adding CSV to Redis",
      total: csv_arr.length
    )
    csv_arr.each do |row|
      email = row[1]
      @r_named.sadd(R_SET_TODO, email)
      pg.increment
    end
  end

  def enumerate_and_verify
    pg = ProgressBar.create(
      title: "Verifying",
      total: @r_named.scard(R_SET_TODO)
    )
    while @r_named.spop(R_SET_TODO) do |email|
      success = false
      begin
        success = EmailVerifier.check(self.email)
      rescue => e
        pg.log "  - #{e.message}"
      end
      if success
        @r_named.sadd(R_SET_GOOD, email)
      else
        @r_named.sadd(R_SET_BAD, email)
      end
      pg.increment
    end
  end

  def config_redis
    r_config = {db: 1}
    unless @config['redis_password'].to_s.empty?
      r_config['password'] = @config['redis_password']
    end
    r_conn = Redis.new(r_config)
    @r_named = Redis::Namespace.new(R_NAMESPACE, redis: r_conn)
  end

  def config_email_verifier    
    EmailVerifier.config do |c|
      c.verifier_email = @config['from_email_address']
    end
  end

end

EmailListCleaner.new.run