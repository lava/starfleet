# username that will own the device nodes
user := archer
guest_memory := 512M
qemu_share_path := /home/$(user)/qemu-images/share
host_ipv4 := 10.11.0.99/16
host_ipv6 := fd11::99/16
vm_names := vm0 vm1
# Name of the outward-facing network interface on the host (for internet access)
eth0 := eth0

include lib.mk

.PHONY: test

default:
	ip link show


# Each qemu guest gets their own tap device, and all
# are connected over the bridge br0.
# Communication happens inside 10.11.0.0/16 and fd11::/16,
# and the bridge itself uses the first address in that range
# so we can communicate with the guests from outside
up:
	$(call each-with-index, $(vm_names),\
		ip tuntap add name qtap__index__ mode tap user $(user))

	ip link add br0 type bridge
	
	$(call each-with-index, $(vm_names),\
		ip link set qtap__index__ master br0)
# Opposite operation would be:
#	ip link set qtap1 nomaster
	
	$(if $(host_ipv4),\
		ip addr add $(host_ipv4) dev br0)
	$(if $(host_ipv6),\
		ip addr add $(host_ipv6) dev br0)

down:
	$(call each-with-index, $(vm_names),\
		ip tuntap del name qtap__index__ mode tap)
	ip link delete br0

# qemu-run-instance-in-background(idx, name)
define qemu-run-instance-in-background
qemu-system-x86_64 \
  -enable-kvm \
  -m $(guest_memory) \
  -drive file=$(2)/image.qcow2,format=qcow2,index=0,media=disk \
  -net none \
  -netdev tap,id=net0,ifname=qtap$(1),script=no,downscript=no \
  -device rtl8139,netdev=net0,mac=52:54:00:00:00:0$(1) \
  -fsdev local,id=fs0,path=$(qemu_share_path),security_model=mapped,writeout=immediate \
  -device virtio-9p-pci,fsdev=fs0,mount_tag=wtf0 &

endef

# 52:54 is the MAC prefix for locally administered addresses
run:
	# The virtfs share can be mounted in the guest with
	#   mount -t 9p -o trans=virtio [mount tag] [mount point] -oversion=9p2000.L
	
	$(call each-with-index, $(vm_names),\
		$(call qemu-run-instance-in-background,__index__,__value__))
	
	# "br0 up" only succeeds *after* at least one connected interface
	# is already in use. See also:
	# http://lists.linuxfoundation.org/pipermail/bridge/2011-June/007711.html
	
	# Also, We can't bring up tapX before something is connected to their 
	# remote end. (Note that this wipes configuration on the other side)
	$(call each-with-index, $(vm_names),\
		sudo ip link set qtap__index__ up)
	sudo ip link set br0 up

# Note that br0 must have an assigned ipv4 or ipv6 in order for the nat to work
internet-up:
	@# Create new chain
	iptables -t nat -N QEMU_NAT
	ip6tables -t nat -N QEMU_NAT6
	
	@# Connect our chain to POSTROUTING
	iptables -t nat -A POSTROUTING -j QEMU_NAT
	ip6tables -t nat -A POSTROUTING -j QEMU_NAT6
	
	@# man iptables-extensions(8): MASQUERADE is like SNAT, but it takes the source ip that is
	@#   currently configured for the interface, and forgets all connections when the interface
	@#   goes down
	iptables -t nat \
		 -A QEMU_NAT \
		 -o $(eth0) \
		 -s 10.11.0.0/16 \
		 -j MASQUERADE
	
	ip6tables -t nat \
		 -A QEMU_NAT6 \
		 -o $(eth0) \
		 -s fd11::/16 \
		 -j MASQUERADE
	
	echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward
	echo 1 | sudo tee /proc/sys/net/ipv6/conf/all/forwarding

	# In the guest:
	#  sudo ip route add default via <host_ipv4> dev eth0
	#  sudo ip -6 route add default via <host_ipv6> dev eth0

internet-down:
	iptables -t nat -D POSTROUTING -j QEMU_NAT
	iptables -t nat -F QEMU_NAT
	iptables -t nat -X QEMU_NAT
	
	ip6tables -t nat -D POSTROUTING -j QEMU_NAT6
	ip6tables -t nat -F QEMU_NAT
	ip6tables -t nat -X QEMU_NAT

# I think this only works after the bridge is up, which only works after qemu started
# TODO: Can probably created by creating an additional veth-pair with one end connected
#       to the bridge, so we can start it up early
dhcp:
	dnsmasq \
		--no-daemon \
		--bind-interfaces \
		--interface=br0 \
		--except-interface=lo \
		--listen-address=10.11.1.1 \
		--enable-ra \
		--dhcp-leasefile=./qemu.leases \
		--dhcp-range 10.11.1.2,10.11.1.254 \
		--dhcp-range fd11::1:2,fd11::1:254
		

# apply-files-to-instance(vm_name, image_file, file_directory)
# Requires:
#  - A qemu image called $(name)/image.qcow2 in the current directory
#  - Files will be added to partition p1
define apply-files-to-instance
sudo qemu-nbd --connect /dev/nbd0 $(shell readlink -f $(2))
sudo partprobe -s /dev/nbd0
sudo mkdir -p /mnt/$(1)
sudo mount /dev/nbd0p1 /mnt/$(1)
sudo cp --no-target-directory -r $(3) /mnt/$(1)
sudo umount /mnt/$(1)
sudo qemu-nbd --disconnect /dev/nbd0

endef

# apply-files(vm_names)
define apply-files
sudo modprobe nbd max_part=8
$(foreach name, $(1),$(call apply-files-to-instance,$(name), $(name)/image.qcow2, $(name)/files))

endef

provision:
	$(call apply-files, $(vm_names))


# Requires br0 to be up
ifeq (${IMAGE},)
mount unmount:
	@echo Please set IMAGE=/path/to/image that you want to mount
else
mount:
	sudo modprobe nbd max_part=8
	sudo qemu-nbd --connect /dev/nbd0 ${IMAGE}
	sudo partprobe -s /dev/nbd0
	sudo mkdir -p /mnt/${IMAGE}
# Best guess at correct partition
	sudo mount /dev/nbd0p1 /mnt/${IMAGE}
	@echo Mounted at /mnt/${IMAGE}, dont forget to unmount after use

unmount:
	sudo umount /mnt/${IMAGE}
	sudo qemu-nbd --disconnect /dev/nbd0

endif
