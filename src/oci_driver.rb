#!/usr/bin/env ruby

ONE_LOCATION = ENV["ONE_LOCATION"] if !defined?(ONE_LOCATION)

if !ONE_LOCATION
    RUBY_LIB_LOCATION = "/usr/lib/one/ruby" if !defined?(RUBY_LIB_LOCATION)
    ETC_LOCATION      = "/etc/one/" if !defined?(ETC_LOCATION)
else
    RUBY_LIB_LOCATION = ONE_LOCATION + "/lib/ruby" if !defined?(RUBY_LIB_LOCATION)
    ETC_LOCATION      = ONE_LOCATION + "/etc/" if !defined?(ETC_LOCATION)
end


OCI_DRIVER_CONF = "#{ETC_LOCATION}/oci_driver.conf"
OCI_DRIVER_DEFAULT = "#{ETC_LOCATION}/oci_driver.default"


# Load OCI credentials and needed gems
require 'yaml'
require 'rubygems'
require 'oci'
require 'json'
require 'rexml/document'
require 'date'

$: << RUBY_LIB_LOCATION


require 'CommandManager'
require 'scripts_common'
require 'VirtualMachineDriver'


# The main class for the OCI driver
class OCIDriver

    ACTION          = VirtualMachineDriver::ACTION
    POLL_ATTRIBUTE  = VirtualMachineDriver::POLL_ATTRIBUTE
    VM_STATE        = VirtualMachineDriver::VM_STATE


    # Key that will be used to store the monitoring information in the template
    OCI_MONITOR_KEY = "OCIDRIVER_MONITOR"

    OCI_POLL_ATTRS = [
        'CpuUtilization',
        'NetworksBytesIn',
        'NetworksBytesOut',
        'MemoryUtilization',
        'DiskBytesRead',
        'DiskBytesWritten',
        'DiskIopsRead',
        'DiskIopsWritten'
    ]

    OCI_REQUIRED_PARAMS = %w[
        SHAPE
        AVAILABILITY_DOMAIN
        COMPARTMENT_ID 
        SUBNET_ID
        SSH_KEY
        DISPLAY_NAME
    ]

    OCI_OPTIONAL_PARAMS = %w[
        IMAGE_ID
        ASSIGN_PUBLIC_IP
        FAULT_DOMAIN
    ]



    STATE_MAP = {
        'provisioning' => 'POWEROFF',
        'starting'     => 'RUNNING',
        'running'      => 'RUNNING',
        'stopping'     => 'POWEROFF',
        'stopped'      => 'POWEROFF',
        'terminating' => 'POWEROFF',
        'terminated'  => 'POWEROFF'
    }


    # --------------------------------------------------------------------------
    # OCI constructor, loads credentials, create oci clients
    #   @param [String] name of host in OpenNebula
    #   @param [String] ID of host in OpenNebula
    # --------------------------------------------------------------------------
    def initialize(host, id = nil)
        @host = host

        @oci_config_file = YAML.safe_load(File.read(OCI_DRIVER_CONF), [Symbol])

        # ----------------------------------------------------------------------
        # Init instance types
        # ----------------------------------------------------------------------
        @instance_types = @oci_config_file[:instance_types]
        @to_inst = {}
        @instance_types.keys.each  do |key|
            @to_inst[key.upcase] = key
        end

        
        @regions = @oci_config_file[:regions]

        @oci_config = OCI::Config.new
        @oci_config.user = @oci_config_file[:user]
        @oci_config.tenancy = @oci_config_file[:tenancy]
        @oci_config.fingerprint = @oci_config_file[:fingerprint]
        @oci_config.key_file = @oci_config_file[:key_file]
        @oci_config.region = @oci_config_file[:regions]['default']
        @oci_config.validate

        load_default_template_values
    end

   
    # --------------------------------------------------------------------------
    # DEPLOY action
    # --------------------------------------------------------------------------
    def deploy(id, host, xml_text, lcm_state, deploy_id)
        if %w[BOOT BOOT_FAILURE].include?(lcm_state)
            @defaults = load_default_template_values

            oci_info = get_deployment_info(host, xml_text)

            opts = {}
            
            OCI_REQUIRED_PARAMS.each do |item|
                opts[item] = value_from_xml(oci_info, item) || @defaults[item]
            end


            OCI_OPTIONAL_PARAMS.each do |item|
                opts[item] = value_from_xml(oci_info, item) || @defaults[item]
            end

            OCI_REQUIRED_PARAMS.each do |item|
                if opts[item] == nil
                    STDERR.puts(
                        "Missing "<<
                        item)
                    exit(-1)
                end
            end

            compute_client = OCI::Core::ComputeClient.new(config: @oci_config)

            request = OCI::Core::Models::LaunchInstanceDetails.new
            request.availability_domain = opts['AVAILABILITY_DOMAIN']
            request.compartment_id = opts['COMPARTMENT_ID']
            request.display_name = opts['DISPLAY_NAME']
            request.image_id = opts['IMAGE_ID']
            request.shape = opts['SHAPE']
            request.subnet_id = opts['SUBNET_ID']
            request.metadata = { 'ssh_authorized_keys' => opts['SSH_KEY']} 
            request.freeform_tags = {'OpenNebula' => ''+id.to_s}
            launch_instance_response = compute_client.launch_instance(request)
            instance = launch_instance_response.data

            #puts "Launched instance '#{instance.display_name}' [#{instance.id}]"
            #print 'Waiting to reach running state.'
            #$stdout.flush

            begin
                compute_client.get_instance(instance.id)
                                .wait_until(:lifecycle_state,
                                            OCI::Core::Models::Instance::LIFECYCLE_STATE_RUNNING) do |resp|

                    lifecycle_state = resp.data.lifecycle_state
                    if [OCI::Core::Models::Instance::LIFECYCLE_STATE_TERMINATED,
                        OCI::Core::Models::Instance::LIFECYCLE_STATE_TERMINATING].include?(lifecycle_state)
                        STDERR.puts("Instance failed to provision. ")
                        exit(-1)
                    end

                    print '.'
                    $stdout.flush
                end

                #puts ''
                #puts "Instance '#{instance.display_name}' is now running."
            rescue => e
                STDERR.puts(e.message)
                exit(-1)
            end
            puts instance.id
        else
            restore(deploy_id)
            deploy_id
        end

    end


    def restore(deploy_id)
        compute_client = get_instance(deploy_id)
        begin
            compute_client.instance_action(deploy_id,'START')
        rescue => e
            STDERR.puts e.message
            exit(-1)
        end
    end

    # Shutdown a SoftLayer instance
    def shutdown(deploy_id, lcm_state)
        compute_client = get_instance(deploy_id)
        begin
            case lcm_state
                when "SHUTDOWN"
                    compute_client.terminate_instance(deploy_id)
                when "SHUTDOWN_POWEROFF", "SHUTDOWN_UNDEPLOY"
                    compute_client.instance_action(deploy_id,'STOP')
            end
        rescue => e
            STDERR.puts e.message
            exit(-1)
        end
    end

    # Reboot a SoftLayer instance
    def reboot(deploy_id)
        compute_client = get_instance(deploy_id)
        begin
            compute_client.instance_action(deploy_id,'RESET')
        rescue => e
            STDERR.puts e.message
            exit(-1)
        end
    end

    # Cancel a SoftLayer instance
    def cancel(deploy_id)
        compute_client = get_instance(deploy_id)
        begin
            compute_client.terminate_instance(deploy_id)
        rescue => e
            STDERR.puts e.message
            exit(-1)
        end
    end

    # Stop a SoftLayer instance
    def save(deploy_id)
        compute_client = get_instance(deploy_id)
        begin
            compute_client.instance_action(deploy_id,'STOP')
        rescue => e
            STDERR.puts e.message
            exit(-1)
        end
    end


    # Get info (IP, and state) for an OCI instance
    def poll(id, deploy_id)
        instance = get_instance(deploy_id)
        instance_details = instance.get_instance(deploy_id).data
        parse_poll(instance_details, deploy_id)
    end

private

    # Get the OCI section of the template. If more than one OCI
    # section, the DISPLAY_NAME element is used and matched with the host
    def get_deployment_info(host, xml_text)
        
        xml = REXML::Document.new xml_text
        oci = nil

        #all_oci_elements = xml.root.get_elements("//USER_TEMPLATE/PUBLIC_CLOUD")
        all_oci_elements = xml.root.get_elements("//ROOT/PUBLIC_CLOUD")     #For testing. Actual uses user_template/public_cloud

        all_oci_elements = all_oci_elements.select { |element|
             element.elements["TYPE"].text.downcase.eql? "oci"
        }

        #puts host
        # Select the correct OCI host from the template if it exists
        all_oci_elements.each { |element|
            #puts "this" 
            #puts element
            cloud_host = element.elements["DISPLAY_NAME"]
            type       = element.elements["TYPE"].text

            if cloud_host and cloud_host.text.upcase.eql? host.upcase
                oci = element
            end
        }

        if !oci
            STDERR.puts(
                "Cannot find OCI host information in VM template "<<
                "or ambigous definition of OCI templates ")
            exit(-1)
        end

        oci      
    end


    # Retrieve the VM information from the OCI instance
    def parse_poll(instance_details, deploy_id)
        #puts instance_details 
        #puts "\n\n\n"
        metrics = {}

        metrics_detail = OCI::Monitoring::Models::SummarizeMetricsDataDetails.new()
        metrics_detail.namespace = 'oci_computeagent'
        metrics_detail.end_time = DateTime.now
        metrics_detail.start_time = metrics_detail.end_time - (1/24.0)


        worker = OCI::Monitoring::MonitoringClient.new(config: @oci_config, region: @oci_config.region)

        puts instance_details.lifecycle_state
        OCI_POLL_ATTRS.each do |metric|
            metrics_detail.query = metric+'[1h]{resourceId = "' +deploy_id+'"}.mean()'
            metrics_response = worker.summarize_metrics_data(instance_details.compartment_id, metrics_detail)
            print metrics_response.data[0].name + ": " 
            puts metrics_response.data[0].aggregated_datapoints[0].value
        end
    end

    # Helper method to retrieve values from xml
    def value_from_xml(xml, name)
        if xml
            element = xml.elements[name]
            element.text.strip if element && element.text
        end
    end


    # Load the default values that will be used to create a new instance, if
    # not provided in the template. These values are defined in the
    # OCI_DRIVER_DEFAULT file
    def load_default_template_values
        @defaults = Hash.new

        if File.exists?(OCI_DRIVER_DEFAULT)
            fd  = File.new(OCI_DRIVER_DEFAULT)
            xml = REXML::Document.new fd
            fd.close()

            return if !xml || !xml.root

            oci = xml.root.elements["OCI"]

            return if !oci
            
            
            OCI_REQUIRED_PARAMS.each do |item|
                @defaults[item] = value_from_xml(oci, item)
            end

            OCI_OPTIONAL_PARAMS.each do |item|
                @defaults[item] = value_from_xml(oci, item)
            end

            """@defaults.each do |key, value|
                puts key +\" :\" + value
            end"""

        end
    end
    
    # Retrieve the instance from OCI
    def get_instance(id)
        begin
            compute_client = OCI::Core::ComputeClient.new(config: @oci_config)
            instance = compute_client.get_instance(id)
            return compute_client
        rescue => e
            STDERR.puts "Instance #{id} does not exist"
            exit(-1)
        end
    end

end 