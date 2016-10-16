#!/usr/bin/env ruby
require_relative '../email_list_cleaner'

# This starts a run of Email List Cleaner.
# You can savely cancel out of it (CTRL-C), and it will continue to run in the background.
EmailListCleaner.instance.run