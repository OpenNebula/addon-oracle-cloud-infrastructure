#!/usr/bin/env ruby

ONE_LOCATION = ENV['ONE_LOCATION'] unless defined? ONE_LOCATION

if !ONE_LOCATION
    RUBY_LIB_LOCATION ||= '/usr/lib/one/ruby'
else
    RUBY_LIB_LOCATION ||= ONE_LOCATION + '/lib/ruby'
end

$LOAD_PATH << RUBY_LIB_LOCATION

require 'oci_driver'

host    = ARGV[-1]
host_id = ARGV[-2]
oci_drv = OCIDriver.new(host, host_id)

begin
    puts oci_drv.probe_host_system
rescue StandardError => e
    OpenNebula.handle_driver_exception('im probe_host_system', e, host)
end
