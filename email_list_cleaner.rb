#!/usr/bin/env ruby
require "rubygems"
require "bundler/setup"
require "yaml"
require "csv"
require "fileutils"
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

  # ruby-progressbar format
  # https://github.com/jfelchner/ruby-progressbar/wiki/Formatting
  PROGRESS_FORMAT = "%t [%c/%C] %w"
  EXP_MICROSOFT = /.*\@(passport|hotmail|msn|live|outlook)\..*/i

  attr_reader :r_named, :config, :proxy_list, :pg

  def initialize
    @config = YAML::load_file("config.yml")
    @sleep_time = @config["sleep_time"].to_i
    config_redis
    config_email_verifier
    config_proxy_list
  end

  # If proxy_addresses defined in proxylist.csv or config.yml, this provides
  # random proxy in that list to Net::SMTPs method that fetches a
  # TCPConnection.
  def random_proxy
    return nil unless num_proxies > 0
    return @proxy_list.sample
  end
  # Similarly, this provides round-robin proxy access
  def next_proxy
    return nil unless num_proxies > 0
    return @proxy_list[next_proxy_counter]
  end
  def next_proxy_counter
    @next_proxy_counter ||= 0
    max = num_proxies-1
    if @next_proxy_counter >= max
      @next_proxy_counter = 0
    else
      @next_proxy_counter += 1
    end
    return @next_proxy_counter 
  end

  def run
    load_csv_into_redis_set
    enum_and_verify
    dump_csv_files
    print_stats
  end

  # CSV expected to have "Name", "Email address" in each row
  # Optionally filters only emails that match regexp
  def load_csv_into_redis_set(regexp=nil)
    csv_arr = CSV.read("_list.csv")
    @pg = ProgressBar.create(
      title: "Load into Redis",
      format: PROGRESS_FORMAT,
      total: csv_arr.length
    )
    # reset key
    @r_named.del(R_SET_TODO)
    csv_arr.each do |row|
      email = row[1]

      next unless email =~ regexp if regexp

      @r_named.sadd(R_SET_TODO, email)
      @pg.increment
    end
    return @r_named.scard(R_SET_TODO)
  end

  def reset_redis_sets
    @r_named.del(R_SET_TODO)
    @r_named.del(R_SET_GOOD)
    @r_named.del(R_SET_BAD)
  end

  # Writes CSV files based on our current redis sets.
  def dump_csv_files
    FileUtils.mkdir_p('tmp')
    write_csv_file(R_SET_TODO, "tmp/_list_todo.csv")
    write_csv_file(R_SET_GOOD, "tmp/_list_good.csv")
    write_csv_file(R_SET_BAD,  "tmp/_list_bad.csv")
    puts "CSV files written to 'tmp' directory."
  end

  def write_csv_file(redis_key, file_name)
    email_arr = @r_named.smembers(redis_key)
    File.open(file_name, "w") do |f|
      f << email_arr.join("\n")
    end
  end

  # Loops through all addresses and verifies.
  # The 'meat' of this program.
  #
  # (Creates 1 thread per proxy for speed)
  def enum_and_verify
    puts "Verifying..."
    @pg = ProgressBar.create(
      title: "Verifying",
      format: PROGRESS_FORMAT,
      total: @r_named.scard(R_SET_TODO)
    )
    @mutex = Mutex.new
    threads = []
    num_threads = num_proxies > 0 ? num_proxies : 1
    (1..num_threads).each do |i|
      threads << Thread.new { verify_until_done }
    end
    threads.each { |t| t.join }
  rescue SystemExit, Interrupt
    puts "Caught CTRL-C...stopping!"
    Thread.list.each { |t| Thread.kill(t) }
    return
  end

  def verify_until_done
    email = nil 
    while email = @r_named.spop(R_SET_TODO) do
      sleep @sleep_time
      verify_email(email)
      @pg.increment
    end
  end

  def verify_email(email)
    @pg.log "\n= #{email}"
    success = false
    begin
      success = EmailVerifier.check(email)
    rescue => e
      @pg.log "  (!) #{e.message}"
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

  def config_proxy_list
    @proxy_list = @config["proxy_addresses"] || []
  end

  def num_proxies
    @proxy_list.length
  end

end

# For quick irb reference
ELC = EmailListCleaner.instance