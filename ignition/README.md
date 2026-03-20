# Ignition / Butane — SOC Lab Hypervisor

## Files

| File | Purpose |
|------|---------|
| `ucore-hci.bu` | Butane source (human-editable) |
| `ucore-hci.ign` | Compiled Ignition JSON (gitignored — contains your SSH pubkey, regenerate before install) |

## Compile

```bash
# Install butane (Fedora/Aurora)
rpm-ostree install butane   # or: brew install butane

# Compile
butane --strict ucore-hci.bu -o ucore-hci.ign
```

## Install on bare metal

ucore-hci has no ISO of its own. Boot the Fedora CoreOS live ISO, install
CoreOS with this Ignition file, and the autorebase units handle the rest
(two reboots to land on the signed ucore-hci image).

```bash
# Identify your disk
lsblk

# Install — adapt /dev/nvme0n1 to your disk
sudo coreos-installer install /dev/nvme0n1 --ignition-file ucore-hci.ign

# Reboot — Boot 1: rebases to ucore-hci unsigned, reboots automatically
# Boot 2: rebases to signed image, reboots automatically
# Boot 3: fully provisioned ucore-hci, all lab services start
```

## SecureBoot warning

If the machine has SecureBoot enabled, import the ublue-os MOK key after
the first successful boot or subsequent boots will fail:

```bash
sudo mokutil --import /etc/pki/akmods/certs/akmods-ublue.der
# Enter a temporary password when prompted, then reboot and enroll the key in MOK manager
```

Check BIOS → Secure Boot settings. Easiest to disable SecureBoot on a lab
machine if you don't need it.

## After first boot

`soc-lab-first-boot.service` runs automatically (once) and:
- Starts the default (NAT) libvirt network
- Defines and starts the `lab-net` network (virbr-lab, 192.168.10.0/24)
- Reserves fw-router's DHCP address (192.168.122.10)
- Creates the `soc-lab` storage pool

Then from aurora:

```bash
# 1. Copy fw-router SSH key
scp ~/.ssh/fw-router-key lefthand:~/.ssh/fw-router-key

# 2. Copy VM disk images
rsync -av --progress \
  /var/lib/libvirt/images/soc-lab/ \
  lefthand:/var/lib/libvirt/images/soc-lab/

# 3. Export + import VM definitions
for vm in fw-router wazuh splunk dc01 win-user01 win-user02 win-forensic; do
  virsh --connect qemu:///system dumpxml $vm > /tmp/${vm}.xml
  scp /tmp/${vm}.xml lefthand:/tmp/
  ssh lefthand "virsh --connect qemu:///system define /tmp/${vm}.xml"
  ssh lefthand "virsh --connect qemu:///system autostart ${vm}"
done

# 4. Start the core VMs
ssh lefthand "virsh --connect qemu:///system start fw-router"
ssh lefthand "virsh --connect qemu:///system start wazuh"
```

## Customise before provisioning

| Thing to change | Location |
|-----------------|----------|
| Hostname (`lefthand`) | `storage.files[/etc/hostname]` |
| Static IP (if needed) | Add a NetworkManager keyfile under `storage.files` |
| Add more VMs to autostart | `soc-lab-first-boot.sh` |
