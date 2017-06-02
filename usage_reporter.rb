#
# usage_reporter.rb
#
# Provides approximate reporting of monthly usage to date according
#   to a specified billing period, including breakdown by index.
#
# Usage:
#   ruby monthly_usage_reporter.rb <username> <account API key> [billing period start date (number)]
#
# Disclaimer: this tool is offered for demonstration purposes only
#   and does not provide true audits of interaction counts due to
#   redaction and other platform limitations.
#   
# For accurate interaction accounting relevant to monthly billing, 
#   contact your Technical Account Manager for a total generated
#   by our data warehouse backend.


require_relative 'account_selector'
require 'datasift'
require 'json'
require 'active_support'
require 'active_support/core_ext/hash'
require 'active_support/number_helper'
require 'terminal-table'
require 'csv'

PAGE_LENGTH = 1000

time = Time.now.localtime("-08:00")

unless ARGV.empty?
  config = {}
  config[:username], config[:api_key], billing_period_start, end_date = ARGV
  if billing_period_start
    billing_period_start = billing_period_start.match(/\d+-\d+-\d+/) ? billing_period_start : billing_period_start.to_i
  end
else
  # TODO: add feature to select arbitrary accounts for reporting from identities.yml
  account ||= :default
  config, options = AccountSelector.select account, :admin, with_billing_start: true
  billing_period_start = options[:billing_start]
end
billing_period_start ||= 1

admin_client = DataSift::Pylon.new(config)

page = 0
pages = 1

def find_valid_date(year, month, day)
  valid = Date.valid_date?(year, month, day)
  until valid
    day -= 1
    valid = Date.valid_date?(year, month, day)
  end
  Date.new(year, month, day)
end

def delimit(value)
  ActiveSupport::NumberHelper.number_to_delimited(value)
end

# calculate beginning of billing period
# TODO: simplify? decrement month by 1 if condition is met. Send both through #find_valid_date

if billing_period_start.is_a?(String)
  billing_start_date = Date.parse(billing_period_start)
elsif time.day < billing_period_start
  billing_start_date = find_valid_date(time.year, time.month - 1, billing_period_start)
else
  billing_start_date = Date.new(time.year, time.month, billing_period_start)
end
billing_start_time = Time.new(billing_start_date.year, billing_start_date.month, billing_start_date.day, 0, 0, 0, "-08:00")
if end_date
  end_date = Date.parse(end_date)
  end_time = Time.new(end_date.year, end_date.month, end_date.day, 0, 0, 0, "-08:00")
end

msg = "[Start] Calculating consumption for the period beginning on #{ billing_start_date.to_s }" 
msg += " and ending on #{ end_date.to_s }" if end_date
puts msg

identities = {}
indexes_by_identity = {}
indexes_by_volume = {}
volume_by_index = {}
indexes_found = 0
volume = 0
# missing_segments = 0 (not generally possible if an index is stopped & started)
redacted_indexes = []
indexes_for_analysis = []

until page == pages
  page += 1
  response = admin_client.list(page, PAGE_LENGTH)
  pages = response[:data][:pages]

  # TODO: Handle empty susbcriptions array
  indexes = response[:data][:subscriptions]
  if indexes.nil? || (indexes && indexes.empty?)
    puts "[Error] No indexes found for this account. Did you remember to use your account API key?"
  end

  indexes.each do |index|
    # qualify index based on time
    # next unless ((index[:status] == "running" && index[:end].nil?) || (index[:status] == "stopped" && index[:end] > billing_start_time.to_i)) && (!end_time || index[:start] < end_time.to_i)
    indexes_found += 1

    indexes_by_identity[index[:identity_id]] ||= {}
    indexes_by_identity[index[:identity_id]][index[:id]] = index
    
    indexes_for_analysis << index[:id]
    next
    
    if index[:start] >= billing_start_time.to_i
      # index has run only inside the billing period
      indexes_by_volume[index[:volume]] ||= []
      indexes_by_volume[index[:volume]] << index
      volume_by_index[index[:id]] = index[:volume]
      volume += index[:volume]
      # puts "No analysis necessary for index #{ index[:id] }"
    else # run analysis query for volume
      indexes_for_analysis << index[:id]
    end
  end
end

puts "[Done] Index identification complete."
puts "  * Found #{ indexes_found } indexes, #{ indexes_for_analysis.length } of which require analysis.
    This will consume #{ indexes_for_analysis.length * 25 } points from your hourly PYLON /analyze API limit."
puts "  * Indexes first created in this billing period represent #{ delimit(volume) } interactions."

page, pages = 0, 1
identity_client = DataSift::AccountIdentity.new(config)

# TODO: Cannot query for indexes whose identities are inactive

analyze_count = 0
time_series_params = { analysis_type: "timeSeries", parameters: { interval: "day", offset: -8 }}
first_analysis_query = true

puts "[Start] Fetching identity information"

csv_filename = "usage_report_#{ config[:username] }_#{ billing_start_date.to_s }"
csv_filename += "_#{ end_date.to_s }_daily" if end_date
csv_daily = CSV.new(File.new(csv_filename + ".csv", "w"))

until page == pages
  page += 1
  response = identity_client.list('', PAGE_LENGTH.to_s, 1.to_s)
  identity_list = response[:data][:identities]
  identity_list.each do |identity|
    identities[identity[:id]] = identity
    # run logic for required analyses
    indexes = indexes_by_identity[identity[:id]]
    next unless indexes && (indexes_for_analysis & indexes.keys).length > 0
    indexes.each do |id, index|
      next unless indexes_for_analysis.include?(id)

      if first_analysis_query
        print "[Working] Executing analysis queries (#{ indexes_for_analysis.length} total): "
        first_analysis_query = false
      end

      client = DataSift::Pylon.new(config.merge(:api_key => identity[:api_key]))
      analysis_start = billing_start_time.to_i
      analysis_end = end_time.to_i if end_time
      response = client.analyze('', time_series_params, '', analysis_start, analysis_end, id)
      analyze_count += 1
      print "#{ analyze_count } "
      unless response[:data][:analysis][:redacted]
        # puts response.inspect
        index_volume = response[:data][:interactions]
        response[:data][:analysis][:results].each do |day_result|
          csv_daily.add_row [id, Time.at(day_result[:key]).localtime("-08:00"), day_result[:interactions]]
        end
        index[:identity_name] = identity[:label]
        indexes_by_volume[index_volume] ||= []
        indexes_by_volume[index_volume] << index
        volume_by_index[id] = index_volume
        volume += index_volume
      else
        volume_by_index[id] = 0
        redacted_indexes << id
      end
      indexes_for_analysis.delete(index)
    end
  end
end
puts "100%"

puts "[Done] Analyzed target indexes. #{ redacted_indexes.length } indexes were redacted."
puts "  * The final volume count is: #{ delimit(volume) } interactions."

puts "\nUsage Summary:"

table = Terminal::Table.new(
  headings: ["User Name", "Billing Start Date", "Total Usage", "Generated At"],
  rows: [[config[:username], billing_start_date.to_s, delimit(volume), time.to_s ]])
puts table

puts "\nUsage Totals by Index:"

csv_filename = "usage_report_#{ config[:username] }_#{ billing_start_date.to_s }"
csv_filename += "_#{ end_date.to_s }" if end_date
csv = CSV.new(File.new(csv_filename + ".csv", "w"))

headings = ["Volume", "Status", "Index Name", "Identity", "Index ID"]
csv.add_row headings

table = Terminal::Table.new({ :headings => headings }) do |t|
  indexes_by_volume.keys.sort.reverse.each do |index_volume|
    indexes = indexes_by_volume[index_volume]
    indexes.each do |index|
      identity_name = index[:identity_name] || identities[index[:identity_id]][:label]
      formatted_volume = delimit(index_volume)
      row = [formatted_volume, index[:status], index[:name], identity_name, index[:id]]
      csv.add_row row
      t.add_row row
    end
  end
end
table.align_column(0, :right)
puts table

puts "\nDisclaimer: These totals are approximations only and may not accurately represent interaction totals
  for official billing purposes."

puts