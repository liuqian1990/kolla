#!/bin/bash
#
# This script can be used to start a minimal set of containers that allows
# you to boot an instance.  Note that it requires that you have some openstack
# clients available: keystone, glance, and nova, as well as mysql to ensure
# services are up.  You will also need these in order to interact with the
# installation once started.

if [[ $EUID -ne 0 ]]; then
    echo "You must execute this script as root." 1>&2
    exit 1
fi

# Set SELinux to permissive
setenforce permissive

# This directory is shared with the host to allow qemu instance
# configs to remain accross restarts.  This is needed in the event libvirt
# is not installed in the system.
mkdir -p /etc/libvirt/qemu

# This should probably go into nova-networking or nova-compute containers.
# but you can't modprobe from a container for some reason
modprobe ebtables

MY_IP=$(ip route get $(ip route | awk '$1 == "default" {print $3}') |
    awk '$4 == "src" {print $5}')

# Source openrc for commands
source openrc

echo Starting rabbitmq.
docker-compose -f rabbitmq.yml up -d

echo Starting mariadb.
docker-compose -f mariadb.yml up -d

echo Starting keystone.
docker-compose -f keystone.yml up -d

echo Starting glance.
docker-compose -f glance-api-registry.yml up -d

echo Starting nova.
docker-compose -f nova-api-conductor-scheduler.yml up -d

echo Starting nova compute with nova networking.
docker-compose -f nova-compute-network.yml up -d

IMAGE_URL=http://download.cirros-cloud.net/0.3.3/
IMAGE=cirros-0.3.3-x86_64-disk.img
if ! [ -f "$IMAGE" ]; then
    curl -o $IMAGE $IMAGE_URL/$IMAGE
fi

until keystone user-list | grep glance
do
    echo "Waiting for OpenStack services to become available"
    sleep 2
done

sleep 3

echo Creating glance image.
glance image-create --name cirros --is-public false --disk-format qcow2 --container-format bare --file $IMAGE

echo Example usage:
echo
echo nova secgroup-add-rule default tcp 22 22 0.0.0.0/0
echo nova secgroup-add-rule default icmp -1 -1 0.0.0.0/0
echo nova network-create vmnet --fixed-range-v4=10.0.0.0/24 --bridge=br100 --multi-host=T
echo
echo nova keypair-add mykey > mykey.pem
echo chmod 600 mykey.pem
echo nova boot --flavor m1.medium --key_name mykey --image cirros kolla_vm
