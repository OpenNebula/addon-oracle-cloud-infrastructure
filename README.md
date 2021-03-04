# Oracle Cloud Infrastructure (OCI) Driver

## Description

[Oracle Cloud Infrastructure](https://www.oracle.com/cloud/) (OCI) is an IaaS that delivers on-premises, high-performance computing power to run cloud native and enterprise company’s IT workloads. OCI provides real-time elasticity for enterprise applications by combining Oracle's autonomous services, integrated security, and serverless compute. Available for public cloud.

This cloud bursting driver helps the user combine local resources of their private cloud with resources from OCI. It allows deploying Virtual Machines seamlessly on OCI.

## Development
To contribute bug patches or new features, you can use the github Pull Request model. It is assumed that code and documentation are contributed under the Apache License 2.0.

## Authors

* Yash Lamba - Oracle Cloud Engineering

## Compatibility

* This addon is compatible with OpenNebula versions 5.12.

## Features

* Cloud Bursting to Oracle Cloud Infrastructure

## Limitations

* ...

## Requirements

* [Ruby SDK for OCI](https://rubygems.org/gems/oci/versions/2.0.4)
* An Oracle Cloud Infrastructure account. (Start with a Free Trial / Always Free Oracle Cloud account. Details here -> https://www.oracle.com/cloud/free/#always-free)
* An OCI user in a group with a policy that grants the desired permissions.
* A keypair used for signing API requests, with the public key uploaded to OCI. 

## Installation

...

## Configuration

The OCI driver uses two configuration files:

* /etc/one/oci_driver.conf: Configures access to OCI.
* /etc/one/oci_driver.default: Default values for templates deployed in OCI.

## Usage

...

## References

...

## License

Apache License, Version 2.0

## Other

...
