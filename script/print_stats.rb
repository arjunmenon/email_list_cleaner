#!/usr/bin/env ruby
require_relative '../email_list_cleaner'

# Dumps statistics of current run to the console.
EmailListCleaner.instance.print_stats