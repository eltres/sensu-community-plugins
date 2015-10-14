#! /usr/bin/env ruby
#
#   check-disk-windows
#
# DESCRIPTION:
#   This is mostly copied from the original check-disk.rb plugin and modified
#   to use WMIC.  This is our first attempt at writing a plugin for Windows.
#
#   Uses Windows WMIC facility. Warning/critical levels are percentages for small drives and GB for large drives 

#
# OUTPUT:
#   plain text
#
# PLATFORMS:
#   Windows
#
# DEPENDENCIES:
#   gem: sensu-plugin
#   REQUIRES: ActiveSupport version 4.0 or above.
#
# USAGE:
#
# NOTES:
#
# LICENSE:
#   Copyright 2013 <bp-parks@wiu.edu> <mr-mencel@wiu.edu>
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#

require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'sensu-plugin/check/cli'

class CheckDisk < Sensu::Plugin::Check::CLI
  option :fstype,
         short: '-t TYPE',
         proc: proc { |a| a.split(',') }

  option :ignoretype,
         short: '-x TYPE',
         proc: proc { |a| a.split(',') }

  option :ignoremnt,
         short: '-i MNT',
         proc: proc { |a| a.split(',') }

  option :warn,
         short: '-w PERCENT',
         proc: proc(&:to_i),
         default: 85

  option :crit,
         short: '-c PERCENT',
         proc: proc(&:to_i),
         default: 95

  option :gbcrit,
         short: '-C GB',
         proc: proc(&:to_i),
         default: 100

  option :gbwarn,
         short: '-W GB',
         proc: proc(&:to_i),
         default: 250

  option :disksize,
          short: '-s GB',
          proc: proc(&:to_i),
          default: 2048

  def initialize
    super
    @crit_fs = []
    @warn_fs = []
  end

  def read_wmic
    `wmic volume where DriveType=3 list brief`.split("\n").drop(1).each do |line|
      begin
        # #YELLOW
        capacity, type, _fs, _avail, label, mnt = line.split # rubocop:disable Lint/UnderscorePrefixedVariableName
        next if /\S/ !~ line
        next if _avail.nil?
        next if line.include?('System Reserved')
        next if config[:fstype] && !config[:fstype].include?(type)
        next if config[:ignoretype] && config[:ignoretype].include?(type)
        next if config[:ignoremnt] && config[:ignoremnt].include?(mnt)
      rescue
        unknown "malformed line from df: #{line}"
      end
      # If label value is not set, the drive letter will end up in that column.  Set mnt to label in that case.
      mnt = label if mnt.nil?
      prct_used = (100 * (1 - (_avail.to_f / capacity.to_f)))
      bytes_to_gbytes = 1073741824
      @size = capacity.to_f / bytes_to_gbytes
      gigs_avail = _avail.to_f / bytes_to_gbytes
      if @size >= config[:disksize]
        if gigs_avail <= config[:gbcrit]
          @crit_fs << "#{mnt} #{gigs_avail.round(2)} GB free"
        elsif gigs_avail <= config[:gbwarn]
          @warn_fs << "#{mnt} #{gigs_avail.round(2)} GB free"
        end
          
      else
        if prct_used >= config[:crit]
          @crit_fs << "#{mnt} #{prct_used.round(2)}%"
        elsif prct_used >= config[:warn]
          @warn_fs << "#{mnt} #{prct_used.round(2)}%"
        end  
      end
    end
  end

  def status
    case
    when @crit_fs.length >= 1
      :critical
    when @warn_fs.length >= 1
      :warning
    else
        :ok
    end
  end
  
  def usage_summary
    case(status)
    when :critical, :warning
      (@crit_fs + @warn_fs).join(', ')
    else
      "All disks smaller than #{config[:disksize]} GB are under #{config[:warn]}% used. All larger disks have more than #{config[:gbwarn]} GB free"
    end

  end
  
  def run
    read_wmic
    case(status)
    when :critical
      critical usage_summary
    when :warning
      warning usage_summary
    else
      ok usage_summary
    end
  end
end

