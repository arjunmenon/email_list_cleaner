#!/usr/bin/env ruby
require_relative '../email_list_cleaner'

# If the run of Email List Cleaner got interrupted for any reason,
# this will continue with the data available inside Redis.
EmailListCleaner.instance.enum_and_verify