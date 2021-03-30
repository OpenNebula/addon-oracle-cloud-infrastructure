#!/usr/bin/env ruby

ONE_LOCATION = ENV["ONE_LOCATION"] if !defined?(ONE_LOCATION)

if !ONE_LOCATION
    RUBY_LIB_LOCATION = "/usr/lib/one/ruby" if !defined?(RUBY_LIB_LOCATION)
    ETC_LOCATION      = "/etc/one" if !defined?(ETC_LOCATION)
else
    RUBY_LIB_LOCATION = ONE_LOCATION + "/lib/ruby" if !defined?(RUBY_LIB_LOCATION)
    ETC_LOCATION      = ONE_LOCATION + "/etc" if !defined?(ETC_LOCATION)
end

OCI_DRIVER_CONF = "#{ETC_LOCATION}/oci_driver.conf"
OCI_DRIVER_DEFAULT = "#{ETC_LOCATION}/oci_driver.default"

$LOAD_PATH << RUBY_LIB_LOCATION

# Load OCI credentials and needed gems
require 'yaml'
require 'rubygems'
require 'oci'
require 'json'
require 'rexml/document'
require 'date'

require 'CommandManager'
require 'scripts_common'
require 'VirtualMachineDriver'
require 'opennebula'

# The main class for the OCI driver
class OCIDriver

    MONITOR_METRICS = [
        'CpuUtilization',
        'NetworksBytesIn',
        'NetworksBytesOut',
        'MemoryUtilization',
        'DiskBytesRead',
        'DiskBytesWritten',
        'DiskIopsRead',
        'DiskIopsWritten'
        ]

    MONITOR_METRICS_DICT = {
        'CpuUtilization' => 'CPU',
        'NetworksBytesIn' => 'NETRX',
        'NetworksBytesOut' => 'NETTX',
        'MemoryUtilization' => 'MEMORY',
        'DiskBytesRead' => 'DISKRDBYTES',
        'DiskBytesWritten' => 'DISKWRBYTES',
        'DiskIopsRead' => 'DISKRDIOPS',
        'DiskIopsWritten' => 'DISKWRIOPS'
        }

    OCI_REQUIRED_PARAMS = %w[
HOST
SHAPE
AVAILABILITY_DOMAIN
COMPARTMENT_ID
SUBNET_ID
SSH_KEY
IMAGE_ID
]

    OCI_OPTIONAL_PARAMS = %w[
ASSIGN_PUBLIC_IP
FAULT_DOMAIN
DISPLAY_NAME
]

    #a = RUNNING   d = POWEROFF
    STATE_MAP = {
        'PROVISIONING' => 'd',
        'STARTING'     => 'a',
        'RUNNING'      => 'a',
        'STOPPING'     => 'd',
        'STOPPED'      => 'd',
        'TERMINATING'  => 'd',
        'TERMINATED'   => 'd'
        }

    CPUSPEED = 2000 #Mhz

    # --------------------------------------------------------------------------
    # OCI constructor, loads credentials, create oci clients
    #   @param [String] name of host in OpenNebula
    #   @param [String] ID of host in OpenNebula
    # --------------------------------------------------------------------------
    def initialize(host, id = nil)
        @hypervisor = 'oci'
        @host = host

        @oci_config_file = YAML.safe_load(File.read(OCI_DRIVER_CONF), [Symbol])

        @instance_types = @oci_config_file[:instance_types]
        @to_inst = {}


        @host_capacity = @oci_config_file[@host][:capacity]

        @instance_types.keys.each do |key|
            @to_inst[key.upcase] = key
        end

        @regions = @oci_config_file[:regions]

        @oci_config = OCI::Config.new
        @oci_config.user = @oci_config_file[@host][:user]
        @oci_config.tenancy = @oci_config_file[@host][:tenancy]
        @oci_config.fingerprint = @oci_config_file[@host][:fingerprint]
        @oci_config.key_file = @oci_config_file[@host][:key_file]
        @oci_config.region = @regions[@oci_config_file[@host][:region]]
        @oci_config.validate

        @compute_client = OCI::Core::ComputeClient.new(config: @oci_config)

        load_default_template_values

    end


    # Deploy an OCI instance
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

            request = OCI::Core::Models::LaunchInstanceDetails.new
            request.availability_domain = opts['AVAILABILITY_DOMAIN']
            request.compartment_id = opts['COMPARTMENT_ID']
            request.display_name = opts['DISPLAY_NAME']
            request.image_id = opts['IMAGE_ID']
            request.shape = opts['SHAPE']
            request.subnet_id = opts['SUBNET_ID']
            request.metadata = { 'ssh_authorized_keys' => opts['SSH_KEY']}
            request.freeform_tags = {'OpenNebula' => ''+id.to_s}
            launch_instance_response = @compute_client.launch_instance(request)
            instance = launch_instance_response.data

            begin
                @compute_client.get_instance(instance.id)
                .wait_until(:lifecycle_state,
                    OCI::Core::Models::Instance::LIFECYCLE_STATE_RUNNING) do |resp|

                        lifecycle_state = resp.data.lifecycle_state
                        if [OCI::Core::Models::Instance::LIFECYCLE_STATE_TERMINATED,
                            OCI::Core::Models::Instance::LIFECYCLE_STATE_TERMINATING].include?(lifecycle_state)
                            STDERR.puts("Instance failed to provision. ")
                            exit(-1)
                        end


                    end

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


    # Restart an OCI instance
    def restore(deploy_id)
        status = check_instance_existence(deploy_id)
	if status != "STARTING" and status!= "RUNNING"
            begin
            	@compute_client.instance_action(deploy_id,'START')
            rescue => e
            	STDERR.puts e.message
            	exit(-1)
            end
	end
    end

    # Shutdown an OCI instance
    def shutdown(deploy_id, lcm_state)
        status = check_instance_existence(deploy_id)
        begin
            case lcm_state
            when "SHUTDOWN"
		if status != "TERMINATING" and status!= "TERMINATED"
                	@compute_client.terminate_instance(deploy_id)
		end
            when "SHUTDOWN_POWEROFF", "SHUTDOWN_UNDEPLOY"
                if status != "STOPPING" and status!= "STOPPED"
			@compute_client.instance_action(deploy_id,'STOP')
            	end
	    end
        rescue => e
            STDERR.puts e.message
            exit(-1)
        end
    end

    # Reboot an OCI instance
    def reboot(deploy_id)
        status = check_instance_existence(deploy_id)
	if status == "RUNNING"
            begin
            	@compute_client.instance_action(deploy_id,'RESET')
            rescue => e
            	STDERR.puts e.message
                exit(-1)
            end
	end
    end

    # Cancel an OCI instance
    def cancel(deploy_id)
        status = check_instance_existence(deploy_id)
	if status != "TERMINATING" and status!= "TERMINATED"
            begin
            	@compute_client.terminate_instance(deploy_id)
            rescue => e
            	STDERR.puts e.message
            	exit(-1)
            end
	end
    end

    # Stop an OCI instance
    def save(deploy_id)
        status = check_instance_existence(deploy_id)
        if status != "STOPPING" and status!= "STOPPED"
	    begin
            	@compute_client.instance_action(deploy_id,'STOP')
            rescue => e
            	STDERR.puts e.message
            	exit(-1)
            end
	end
    end


    # Monitor Interface
    def probe_host_system
        total_cpu, total_memory = get_host_capacity

        total_cpu *= 100
	total_memory *=(1024*1024)

        data = "HYPERVISOR=#{@hypervisor}\n"
        data << "PUBLIC_CLOUD=YES\n"
        data << "HOSTNAME=#{@host}\n"
        data << "PRIORITY=-1\n"
        data << "TOTALCPU=#{total_cpu}\n"
        data << "TOTALMEMORY=#{total_memory}\n"
        data << "CPUSPEED=#{CPUSPEED}\n"

        data
    end


    def probe_host_monitor
        total_cpu, total_memory = get_host_capacity

        used_cpu, used_memory, bandwidth   = get_host_usage

        total_cpu *= 100
        used_cpu *= 100

	total_memory *=(1024*1024)
	used_memory *=(1024*1024)
        bandwidth *= (125000000/2)

        data = "HYPERVISOR=#{@hypervisor}\n"
        data << "PUBLIC_CLOUD=YES\n"
        data << "HOSTNAME=#{@host}\n"
        data << "USEDCPU=#{used_cpu}\n"
        data << "USEDMEMORY=#{used_memory}\n"
        data << "FREECPU=#{total_cpu - used_cpu}\n"
        data << "FREEMEMORY=#{total_memory - used_memory}\n"
        data << "NETRX=#{bandwidth}\n"
        data << "NETTX=#{bandwidth}\n"

        data
    end


    def probe_vm_status
        query = "query instance resources where (freeformTags.key = 'Opennebula')"

        results = oci_search(query)

        data=""

        results.data.items.each do |result|
            data << "VM = [ ID=\"#{result.freeform_tags['OpenNebula']}\", DEPLOY_ID=\"#{result.identifier}\", UUID=\"#{result.identifier}\", STATE=\"#{result.lifecycle_state}\" ]\n"

        end

        data

    end


    def probe_vm_monitor
        query = "query instance resources where (freeformTags.key = 'Opennebula')"

        results = oci_search(query)

        data=""

        results.data.items.each do |result|
            instance_details = @compute_client.get_instance(result.identifier).data
            metrics_dict, state, timestamp = parse_poll(instance_details, result.identifier)

            metrics = ""
            metrics << "TIMESTAMP=\"#{timestamp}\"\n"

            metrics_dict.each do |metric, value|
                metrics << "#{metric}=\"#{value}\"\n"
            end
            metrics = Base64.encode64(metrics)
            metrics = metrics.gsub("\n","")

            data << "VM = [ ID =\"#{result.freeform_tags['OpenNebula']}\", UUID=\"#{result.identifier}\", MONITOR =\"#{metrics}\"]\n"
        end

        data

    end



    # Get info (IP, and state) for an OCI instance
    def poll(id, deploy_id)
        check_instance_existence(deploy_id)
        instance_details = @compute_client.get_instance(deploy_id).data

        data = ""
        metrics, state, timestamp = parse_poll(instance_details, deploy_id)

        data << "STATE=#{state} "
        metrics.each do |metric, value|
            data << "#{metric}=#{value} "
        end

        data
    end

    private

    # Get the OCI section of the template. If more than one OCI
    # section, the HOST element is used and matched with the host
    def get_deployment_info(host, xml_text)

        xml = REXML::Document.new xml_text
        oci = nil

        all_oci_elements = xml.root.get_elements("//USER_TEMPLATE/PUBLIC_CLOUD")

        all_oci_elements = all_oci_elements.select { |element|
            element.elements["TYPE"].text.downcase.eql? "oci"
            }


        # Select the correct OCI host from the template if it exists
        all_oci_elements.each { |element|
            cloud_host = element.elements["HOST"]
            type       = element.elements["TYPE"].text

            if cloud_host and cloud_host.text.upcase.eql? host.upcase
                oci = element
            end
            }

        if !oci
            raise
            "Cannot find OCI host information in VM template "\
                "or ambigous definition of OCI templates "
        end

        oci
    end


    # Retrieve the VM information from the OCI instance
    def parse_poll(instance_details, deploy_id)

        metrics_detail = OCI::Monitoring::Models::SummarizeMetricsDataDetails.new()
        metrics_detail.namespace = 'oci_computeagent'
        metrics_detail.end_time = DateTime.now
        metrics_detail.start_time = metrics_detail.end_time - (1/24.0)

        metrics = {}

        worker = OCI::Monitoring::MonitoringClient.new(config: @oci_config, region: @oci_config.region)

        if instance_details.lifecycle_state == 'RUNNING'
            begin
		    MONITOR_METRICS.each do |metric|
		        metrics_detail.query = metric+'[1h]{resourceId = "' +deploy_id+'"}.mean()'
		        metrics_response = worker.summarize_metrics_data(instance_details.compartment_id, metrics_detail)
		        metrics[MONITOR_METRICS_DICT[metrics_response.data[0].name]] = metrics_response.data[0].aggregated_datapoints[0].value

		    end
            rescue => e
            	MONITOR_METRICS.each do |metric|
                	metrics[MONITOR_METRICS_DICT[metric]] = 0
            	end
            end
        else
            MONITOR_METRICS.each do |metric|
                metrics[MONITOR_METRICS_DICT[metric]] = 0
            end
        end

        metrics['CPU'] *= (instance_details.shape_config.ocpus/100.0)
        metrics['MEMORY'] *= ((instance_details.shape_config.memory_in_gbs/100.0)*1024*1024)

        [metrics, STATE_MAP[instance_details.lifecycle_state], metrics_detail.end_time]
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

        end
    end

    # Retrieve the instance from OCI
    def check_instance_existence(id)
        begin
            instance = @compute_client.get_instance(id)
	    instance.data.lifecycle_state
        rescue => e
	    STDERR.puts e
            STDERR.puts "Instance #{id} does not exist"
            exit(-1)
        end
    end


    # Retrieve the host capacity
    def get_host_capacity
        total_memory = total_cpu = 0
        @to_inst.keys.each do |key|
            x = @host_capacity[@to_inst[key]]
            while x > 0
                total_cpu += @instance_types[@to_inst[key]]['cpu']
                total_memory += @instance_types[@to_inst[key]]['memory']
                x-=1
            end

        end

        [total_cpu, total_memory]
    end


    def get_host_usage
        used_memory = used_cpu = bandwidth = 0

        query = "query instance resources where (freeformTags.key = 'Opennebula')"

        results = oci_search(query)

        results.data.items.each do |result|
            shape = @compute_client.get_instance(result.identifier).data.shape_config
            used_memory += shape.memory_in_gbs
            used_cpu += shape.ocpus
            bandwidth += shape.networking_bandwidth_in_gbps

        end

        [used_cpu, used_memory, bandwidth]
    end


    # Get subscribed Regions
    def get_subscribed_regions
        api = OCI::Identity::IdentityClient.new(config: @oci_config)
        response = api.list_region_subscriptions(@oci_config.tenancy)

        response
    end

    # Use OCI Search API to get response to a query
    def oci_search(query)
        search_client = OCI::ResourceSearch::ResourceSearchClient.new(config: @oci_config)
        structured_search = OCI::ResourceSearch::Models::StructuredSearchDetails.new(query: query)
        results = search_client.search_resources(structured_search)

        results
    end

end

obj = OCIDriver.new('default')
