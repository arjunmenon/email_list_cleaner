#!/usr/bin/env ruby
require_relative '../email_list_cleaner'

# Saves CSV files to after a run has been completed.
# Will dump tmp/_list_bad.csv and tmp/_list_good.csv
EmailListCleaner.instance.dump_csv_files