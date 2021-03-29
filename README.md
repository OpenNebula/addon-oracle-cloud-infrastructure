# Oracle Cloud Infrastructure (OCI) Driver

## Description

[Oracle Cloud Infrastructure](https://www.oracle.com/cloud/) (OCI) is an IaaS that delivers on-premises, high-performance computing power to run cloud native and enterprise company’s IT workloads. OCI provides real-time elasticity for enterprise applications by combining Oracle's autonomous services, integrated security, and serverless compute. Available for public cloud.

This cloud bursting driver helps the user combine local resources of their private cloud with resources from OCI. It allows deploying Virtual Machines seamlessly on OCI.

## Development
To contribute bug patches or new features, you can use the github Pull Request model. It is assumed that code and documentation are contributed under the Apache License 2.0.

## Authors

* [Yash Lamba - Oracle Cloud Engineering](https://www.linkedin.com/in/yashlamba/)

## Compatibility

* This addon is compatible with OpenNebula versions 5.12.

## Features

* Cloud Bursting to Oracle Cloud Infrastructure

## Requirements

* [Ruby SDK for OCI](https://rubygems.org/gems/oci/versions/2.0.4)
* [Nokogiri](https://rubygems.org/gems/nokogiri/versions/1.11.2)
* An Oracle Cloud Infrastructure account. (Start with a Free Trial / Always Free Oracle Cloud account. Click [here](https://www.oracle.com/cloud/free/#always-free) for details.
* An OCI user in a group with a policy that grants the desired permissions.
* A keypair used for signing API requests, with the public key uploaded to OCI. 

Note: The user whose credentials are being used, needs to have the required permissions to create the specified instance shape in the specified compartment in the specified region. The instance shape must be available and must have availability, as per quota policies and tenancy limits.

## Installation

To install this add-on, please follow the following steps:
1. Clone this repository and run install.sh:
    
    sudo ./install.sh -u oneadmin -g oneadmin
    
2. Add the following section to the file '/etc/one/oned.conf'

        #OCI
        VM_MAD = [
            name       = "oci",
            executable = "one_vmm_sh",
            arguments  = "-t 15 -r 0 oci",
            type       = "xml" ]
            
3. Add the following section to the file '/etc/one/monitord.conf'

        #OCI
        IM_MAD = [
            name       = "oci",
            executable = "one_im_sh",
            arguments  = "-c -t 1 -r 0 oci" ]
            

## Configuration

The OCI driver uses two configuration files:

* /etc/one/oci_driver.conf: Configures access to OCI.
* /etc/one/oci_driver.default: Default values for templates deployed in OCI.

### oci_driver.conf

The file oci_driver.conf has the following 3 sections:
1. **Host** - In this section you can list the hosts that you wish to use. There is no limit on the number of hosts you can list. Each host is defined by the following details:
    * Tenancy OCID 
    * User OCID
    * User Fingerprint
    * Path to PEM key file
    * Region - The OCI region in which the instance will be created. The region will be one of those mentioned in the regions section below.
    * Capacity - The capacity section is used by OpenNebula to calculate the host capacity. Every instance mentioned in the instance_types section (more on that below) needs to have an entry such as this:  Shape: Count.
    
    In this case, Opennebula will compute the host capacity by multiplying the number of cpus used by the shape with the given count and then taking a sum over all the shapes. Opennebula will do the same thing for memory.
    
    The thing to note is that the count given for each shape doesn't limit you to that many instances of the shape. You could create more instances of that shape using the driver, as long as the used capacity does not exceed the total capacity, as calculated above.
    
    A host entry would look similar to the following 
    
            <host_name>:
                :tenancy: <tenancy_ocid>
                :user: <user_ocid>
                :fingerprint: <user_fingerprint>
                :key_file: <path_to_.pem_file>
                :region: ashburn
                :capacity:
                    VM.Standard.E3.Flex: 1
                    BM.Standard2.52: 0
                    BM.Standard.E3.128: 0
                    BM.DenseIO2.52: 0
                    BM.GPU3.8: 0
                    BM.GPU4.8: 0
                    BM.HPC2.36: 0   
                    VM.Standard2.1: 1
                    VM.Standard2.2: 1
                    VM.Standard2.4: 1
                    VM.Standard2.8: 0
                    VM.Standard2.16: 0
                    VM.Standard2.24: 0
                    VM.Standard.E2.1.Micro: 0
                    VM.DenseIO2.8: 0
                    VM.DenseIO2.16: 0
                    VM.DenseIO2.24: 0
                    VM.GPU3.1: 0
                    VM.GPU3.2: 0
                    VM.GPU3.4: 0
    
2. **Regions** - A dictionary of regions currently available on OCI. This section lets you use a short name of the region rather than the full name understood by OCI. In the future, if a new region becomes available, you will have to create a new entry in the file in order to use the region. Please note that your OCI tenancy needs to be subscribed to a region to use it. Simply mentioning the region in the file does not subscribe your tenancy to it.

3. **Instance_types** - A dictionary of Instance Types or shapes that you want to use on OCI. Each instance has the associated cpu count and memory size in GB. Unless a shape is listed here, you will not be able to spin it up in OCI using the driver. Therefore, in the future, if a new shape becomes available, you will be responsible for creating an entry for it in this section. Same goes for removing entries of retiring shapes and updating the cpu or memory of a shape, if Oracle changes the associated value.

**Note**: Please do not modify the regions section and instance_types section, unless you are sure of the impact of your changes.

### oci_driver.default

The driver defaults need to have certain values:
1. HOST - The name of the host to be used for the virtual machine. This host must be defined in the configuration file.
2. AVAILABILITY_DOMAIN - The availability domain in the host's region to be used for the instance. This has to be mentioned even for regions with 1 availability domain. For example: US-ASHBURN-AD-1, if the host's region is ashburn.
3. COMPARTMENT_ID - The OCID of the compartment where the virtual machine will be created.
4. SHAPE - The default shape to be used for the virtual machine.
5. SUBNET_ID - The OCID of the sub-network to be used for the virtual machine.
6. SSH_KEY - The public ssh-key to be used to log into the system.
7. IMAGE_ID - The OCID of the operating system image to be used for the system. The image can be a custom image.
8. ASSIGN_PUBLIC_IP (Optional) - YES is the default value, but you could set it to NO.
9. DISPLAY_NAME (Optional) - The display name of the instance in the OCI console.

Note: OpenNebula needs to be restarted, once the configuration file is updated.

## Usage

onehost create <host_name> --im oci --vm oci

### OCI Specific Template Attributes

In order to deploy an instance in OCI through OpenNebula you must include an PUBLIC_CLOUD section in the virtual machine template. 

A sample template is given below:

    PUBLIC_CLOUD=[
       AVAILABILITY_DOMAIN = "kZAQ:US-ASHBURN-AD-1",
       COMPARTMENT_ID = "<compartment_ocid>",
       DISPLAY_NAME = "Sample Instance 1",
       HOST = "<host_name>",
       IMAGE_ID = "<image_ocid>",
       SHAPE = "VM.Standard2.1",
       SSH_KEY = "<public_ssh_key>",
       SUBNET_ID = "<subnet_ocid>",
       TYPE = "oci"
    ]

    #Add this if you want to use only OCI
    #SCHED_REQUIREMENTS = 'HYPERVISOR = "oci"'

## Limitations

The usual OpenNebula functionality for snapshotting, hot-plugging, or migration is not available with Oracle Cloud Infrastructure.

## References

[Open Nebula Softlayer Add-On](https://github.com/OpenNebula/addon-softlayer)

## License

Apache License, Version 2.0  
