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

Boot the ucore-hci live ISO (or any Fedora CoreOS live ISO), then:

```bash
# Identify your disk
lsblk

# Install — adapt /dev/nvme0n1 to your disk
sudo coreos-installer install /dev/nvme0n1 --ignition-file ucore-hci.ign

# Reboot into the installed system
sudo reboot
```

## Alternatively: rebase from Fedora CoreOS

Boot vanilla Fedora CoreOS with the Ignition file, then rebase:

```bash
sudo rpm-ostree rebase --experimental \
  ostree-unverified-registry:ghcr.io/ublue-os/ucore-hci:stable-zfs
sudo systemctl reboot
```

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
