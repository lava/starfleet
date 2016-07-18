## Interconnected virtual machine network

**NOTE: These files are provided in the hopes that they may be instructive,
but no effort has been expended towards turning it into a generally useful product.
Don't expect anything to work out of the box, useful error messages, etc.**

This Makefile will automatically start up a cluster of virtual machines,
all of which are connected via the internal networks `fd11::/16` and `10.11.0.0/16`.

The network can be inspected from the host machine via the interface `br0`, and
optionally internet access can be enabled for the machines.

Additionally, a global shared directory and an effort-less way of provisioning
the machines with individual configuration files are available.

# Usage

1) Generate bootable qemu images and put them in named subfolders, e.g.

    vm0/image.qcow2
    vm1/image.qcow2

and set the variable `vm_names` in the Makefile.

2)

    sudo make up
    make run

To overwrite files in the vm filesystem:

    echo "vm0" >> vm0/files/etc/hostname
    make provision

To enable internet:

    make internet-up
    (follow the directions on the guest)

To enable shared folder:

    (in the guest) mount -t 9p -o trans=virtio [mount tag] [mount point] -oversion=9p2000.L

To enable DHCP:

    make dhcp

To mount vm filesystem on host:

    make IMAGE=/path/to/image
    [...]
    make unmount IMAGE=/path/to/image

