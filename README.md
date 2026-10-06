# Rin's Linux Environment Guide (Fedora Linux KDE)

This repository aims to provide a comprehensive guide as to how I like to set up my OS.

Many steps shown here are subjective and are made for *my* specific needs.

It is also good to keep in mind that my words are not of pure fact, they should be taken with a
grain of salt and your own research should be performed before modifying or applying any changes
to your own system. This is simply making what *I* like to do, public.

## My current computer specs:
* CPU: Core i7-14650HX
* RAM: 32GB DDR5-5200 (1x32)
* Boot Disk: 512GB PCI-e 4.0 NVMe
* Data Disk: 1TB PCI-e 4.0 NVMe
* GPU: RTX 4060 Mobile Max-Q

## My current peripherals:
* Keyboard: Logitech G915-X TKL
* Mouse: Logitech G305
* Monitor: LG Ultrawide (34" 3440x1440 @ 160Hz)
* Microphone: Fifine AM8
* Headset: Logitech G733
* Webcam: Logitech C270
* Controllers: 8BitDo Ultimate 2C Wireless | Sony DualSense

## Part 1 - Snapper + BTRFS

At the **Installation method** section of the installer, click the hamburger menu on the top-right and
open the storage editor. After you exit the storage editor, **Use configured storage** is automatically
selected as the installation method.

`NOTE: All changes made in this editor are performed in real time. Be careful with your data!`

### 1.1 - Boot disk layout

Partitions:
| Filesystem | Size | Mount point |
| - | - | - |
| EFI | 2GB | /boot/efi |
| BTRFS | Remainder |  |

There is no swap partition: Fedora uses **zram** *(compressed swap in RAM)* by default, which is enough
for my needs. A disk swap partition would also sit unencrypted next to the encrypted **/home**. The only
thing given up is hibernation.

There is also no separate **/boot** partition on purpose: keeping **/boot** inside the **root** subvolume
means every snapshot contains its own kernel and initramfs, so booting a snapshot from GRUB always loads
a kernel matching that snapshot's modules.

Subvolumes:
| Name | Mount point |
| - | - |
| root | / |
| local | /usr/local |
| srv | /srv |
| opt | /opt |
| var | /var |
| libvirt | /var/lib/libvirt |

### 1.2 - Data disk layout

Partitions
| Filesystem | Size | Mount point |
| - | - | - |
| BTRFS | All | /home |

For added security the **/home** partition is encrypted with LUKS2.

### 1.3 - Installing

From this point the system is ready to be installed, do so and reboot.

### 1.4 - Snapper + BTRFS + grub-btrfs configuration

Inside the freshly installed system, enter root mode with:

```bash
sudo -i
```

Check the current variables set in GRUB with:

```bash
grub2-editenv list
```

if **menu_auto_hide=1** is shown, unset it with:

```bash
grub2-editenv - unset menu_auto_hide
```

Re-run the list command to make sure the change was made correctly.

---

We will now exclude the snapshots directory from file indexing by opening **/etc/updatedb.conf** and adding **/.snapshots** to **PRUNEPATHS** like so:

```bash
PRUNEPATHS = "/tmp /media /dev /sys /proc /run /var/cache /var/spool /.snapshots"
```

---

We can now install some necessary packages to finish this setup:

```bash
dnf in -y snapper libdnf5-plugin-actions btrfs-assistant
```

---

After installing the packages we will now create an **.actions** file which will automatically create pre and post DNF transaction snapshots.

To do so create and open the file **/etc/dnf/libdnf5-plugins/actions.d/snapper.actions** and paste the contents of this file created by **TheLinuxLighthouse:**

[Click here to open the file on your browser](https://github.com/thelinuxlighthouse/System_Administration/blob/main/snapper_btrfs_dnf/_etc_dnf_libdnf5-plugins_actions.d_snapper.actions)

A verbatim backup of this file is kept in this repository at [dotfiles/etc/dnf/libdnf5-plugins/actions.d/snapper.actions](dotfiles/etc/dnf/libdnf5-plugins/actions.d/snapper.actions) *(upstream commit `758c4fc`, SHA-256 `3fd75063e4145d3e3abac9250a444465dbcf128583f47cbc982bf97c2739798b`)*.

This file makes so that whenever packages are installed or uninstalled from your system through DNF, pre-transaction and post-transaction snapshots are automatically created, allowing you to easily roll back your system to a previous working state if something were to break *(see [1.5 - Restoring a snapshot](#15---restoring-a-snapshot))*. This is rare, but its good to have.

Snapshots of transactions touching critical packages (kernel, systemd, glibc, bootloader, GPU drivers...) are also tagged with **important=yes**, which snapper's cleanup keeps separately from regular snapshots.

--- 

After that, we can now configure snapper using BTRFS Assistant where we will create a new snapper configuration.

To do so open the BTRFS Assistant application and go to the **Snapper Settings** tab.

Click on **New**, set the **Config name** to **root** and the **Backup path** to **/**, then click on **Save**.

The config **must** be named **root**: the actions file above and the `snapper` commands below don't pass `-c <config>`, so they all use the config named **root**.

Now you can set up snapper however you want. The configuration that I go for is the following:

* Enable timeline snapshots
  * Set hourly to 0
  * Set daily to 0
  * Set weekly to 1
  * Set monthly to 0
  * Set yearly to 0
  * Leave number as is, it is set from the terminal further below
* Enable **Snapper timeline enabled** and **Snapper cleanup enabled**

This keeps one weekly timeline snapshot. Note that timeline snapshots are still *taken* every hour, the
daily cleanup job is what prunes them down to the weekly one, so up to a day's worth of hourly snapshots
can exist at a time.

If you enable the **Snapper boot enabled** option it will make snapper create a new snapshot on every boot, which is unnecessary for me.

With your desired configuration set, you can now click **Save** on the top-right and click on **Apply systemd changes** on the bottom-right.

---

We will now enable BTRFS quotas and set up the snapshots directory.

Enable BTRFS quotas by running the command:

```bash
btrfs quota enable /
```

...or by clicking the **Enable Btrfs Quotas** button on the **Overview** tab of BTRFS Assistant.

Now setup snapper and check that the configuration is up and running:

```bash
snapper setup-quota && snapper ls
```

---

With quotas enabled, snapper can also clean up snapshots based on how much space they use, but only if
the snapshot limits are written as **min-max ranges**. A single number disables this.

Set the DNF snapshot limits as ranges with:

```bash
snapper -c root set-config NUMBER_LIMIT=2-20 NUMBER_LIMIT_IMPORTANT=4-10
```

This configures snapper to keep:

* Up to the 20 most recent DNF snapshots. Every transaction creates a **pre** and a **post** snapshot, so
  this covers the last 10 transactions.
* Up to 10 additional older snapshots tagged **important** *(see the actions file above)*.

If snapshots take more than half of the filesystem *(`SPACE_LIMIT=0.5`)* or free space drops below 20%
*(`FREE_LIMIT=0.2`)*, the cleanup job keeps deleting the oldest snapshots until it gets back under those
limits, down to a minimum of 2 regular and 4 important snapshots.

`WARNING: BTRFS Assistant can't display ranges and shows number as 0. If you ever click Save on the Snapper Settings tab again, it will write NUMBER_LIMIT=0 and the next cleanup will delete all DNF snapshots older than an hour. Re-run the command above after saving anything there.`

Check the values with:

```bash
snapper -c root get-config | grep NUMBER_LIMIT
```

---

You will now edit the **/etc/fstab** file to include an entry for **/.snapshots**.

This is needed because btrfs snapshots don't include nested subvolumes: when you boot into a snapshot, its **/.snapshots** would be empty and snapper wouldn't work from inside it. The fstab entry mounts the real one in every case.

First, run this command to make sure the **.snapshots** subvolume is present:

```bash
btrfs subvolume list /
```

It is generally at the bottom of the list and should look something like this:

```bash
ID xxx gen xxx top level xxx path .snapshots
```

Next, edit your fstab to include it. The easiest way is to copy and paste the root entry *(generally the first one)* and change **/** to **/.snapshots** and **subvol=root** to **subvol=root/.snapshots**, keeping the other options as they are.

The entry should look something like this:

```bash
UUID=XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX /.snapshots btrfs subvol=root/.snapshots,compress=zstd:1 0 0
```

Save and exit then run:

```bash
systemctl daemon-reload && mount -a
```

You can now check if **/.snapshots** has been properly mounted by looking for its entry with:

```bash
df -h
```

---

Last step, enable grub-btrfs to make sure our bootloader is aware of our snapshots configuration so that it presents it to you and allows you to boot from them, otherwise they are useless.

To do so, enable the grub-btrfs copr repository and install its package with:

```bash
dnf copr enable -y jmarcoshp/grub-btrfs && dnf in -y grub-btrfs
```

This COPR packages the latest upstream [grub-btrfs](https://github.com/Antynea/grub-btrfs) release *(v4.14)*, patched with Fedora's GRUB paths.

After installing we can now enable its daemon, which watches **/.snapshots** and updates the GRUB menu whenever a snapshot is created or deleted:

```bash
systemctl enable --now grub-btrfsd.service
```

The daemon only reacts to changes, so generate the GRUB menu once right away so the snapshots submenu shows up on the next boot:

```bash
grub2-mkconfig -o /boot/grub2/grub.cfg
```

### 1.5 - Restoring a snapshot

`snapper rollback` does **not** work with this layout: it works by changing the btrfs default subvolume,
but Fedora always mounts **subvol=root** explicitly *(in fstab and in the kernel's rootflags)*, so the
change is ignored. Instead, BTRFS Assistant is used: it renames the current **root** subvolume to a backup
and puts a writable copy of the snapshot in its place.

Only the **root** subvolume is restored, which includes **/boot** and the kernel. **/home**, **/var**,
**/opt**, **/srv**, **/usr/local** and **/var/lib/libvirt** keep their current state.

1. Reboot, open the **Fedora Linux snapshots** submenu in GRUB and boot the snapshot you want to go back
   to. To undo a DNF transaction, pick its **pre** snapshot.

   The snapshot boots read-only. The desktop should still work since **/home** and **/var** are separate
   writable subvolumes, but some things may complain. Use this boot to make sure the snapshot actually works.

2. Open BTRFS Assistant, go to the **Snapper** tab, then **Browse/Restore**. Set **Select target** to **root**,
   select the snapshot you booted into and click **Restore**. Confirm, optionally giving the backup a name.

3. Reboot right away and boot the default entry.

4. Once everything works, delete the backup: on the **Subvolumes** tab of BTRFS Assistant, select
   **root_backup_\<date\>** and click **Delete**. Until then it keeps using disk space. To undo the restore
   instead, select it and click **Restore Backup**.

If the desktop doesn't start from the snapshot, switch to a TTY *(Ctrl+Alt+F3)*, log in and do it from the
terminal:

```bash
sudo btrfs-assistant -l
```

```bash
sudo btrfs-assistant -r <index>
```

`NOTE: <index> is the number in the first column of the list, not the snapper snapshot number. There is no confirmation prompt.`

## Part 2 - Editing system files

All files in this part are owned by root, so enter root mode with:

```bash
sudo -i
```

### 2.1 - Global environment variables

Open the file **/etc/environment** and add the following lines:

```bash
COMPOSE_BAKE=true
DXVK_ASYNC=1
DXVK_HUD=compiler
MANGOHUD=1
```

This file is read at login for every user and every session *(desktop, TTY and SSH)*, regardless of the shell used.
It only accepts plain **KEY=VALUE** lines: no `export`, and variables such as **$HOME** are not expanded.

What each variable does:

* **COMPOSE_BAKE=true**: makes Docker Compose use Bake to build images.
* **DXVK_ASYNC=1**: enables asynchronous shader compilation in DXVK builds that support it *(dxvk-async/gplasync)*, reducing stutter. Regular DXVK ignores it.
* **DXVK_HUD=compiler**: shows an indicator in DXVK games while shaders are being compiled.
* **MANGOHUD=1**: enables the MangoHud overlay in every Vulkan application.

### 2.2 - PATH

Since **/etc/environment** can't expand **$HOME**, the PATH additions go in a script under **/etc/profile.d**
instead. Create the file **/etc/profile.d/user-paths.sh** with the following contents
*(also available at [dotfiles/etc/profile.d/user-paths.sh](dotfiles/etc/profile.d/user-paths.sh))*:

```bash
# Add per-user directories to PATH
user_paths=(
    "$HOME/.cargo/bin"
    "$HOME/.dotnet/tools"
)

for dir in "${user_paths[@]}"; do
    case ":$PATH:" in
        *":$dir:"*) ;;
        *) PATH="$PATH:$dir" ;;
    esac
done
export PATH
unset dir user_paths
```

To add more directories in the future, just add a new line to the **user_paths** array.

On Fedora, the scripts in **/etc/profile.d** are loaded both by the desktop session at login and by every
terminal you open, so these directories are available everywhere. They are added at the end of PATH, so
they never take precedence over system binaries.

---

After a logout and login *(or a reboot)*, check that everything is set with:

```bash
printenv | grep -E "COMPOSE_BAKE|DXVK|MANGOHUD" && echo $PATH
```

### 2.3 - DNF parallel downloads

Open the file **/etc/dnf/dnf.conf** and add the following line under the **[main]** section:

```bash
max_parallel_downloads=16
```

...or set it with the command:

```bash
dnf config-manager setopt max_parallel_downloads=16
```

This lets DNF download up to 16 packages at the same time instead of the default 3 *(the maximum is 20)*.

Check the value with:

```bash
dnf --dump-main-config | grep max_parallel_downloads
```

## Part 3 - Name your machine

Fedora 43 introduced a new installer, which unlike the previous one, doesn't give us the option to
set our machine's hostname, which I find really dumb... but oh well.

You can easily change it by running:

```bash
sudo hostnamectl set-hostname <whatever>
```

Then reboot.

## Part 4 - Set up DNF repositories

In contrast to Ubuntu, Fedora's default repositories are great, you have a really nice and **UPDATED** collection
of packages.
But... not all is perfect, we are missing some software, especially proprietary software.

### 4.1 - RPM Fusion

RPM Fusion gives you access to a lot of third party packages, both open-source and proprietary. As a general
rule of thumb it is advised to add it to your system as to get access to many mainstream and useful programs.

You can add it by running the following commands:

```bash
sudo dnf in -y \
    https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
sudo dnf group upgrade core -y
sudo dnf4 group install core -y
```

### 4.2 - Flathub

No need to explain, its flathub.

```bash
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
```

### 4.3 - Nvidia

If you have a NVIDIA GPU, you can install their proprietary drivers with:

```bash
sudo dnf in -y akmod-nvidia xorg-x11-drv-nvidia-cuda
```

`WARNING: Do NOT reboot right after the installation finishes!`

The driver's kernel modules are compiled in the background after the installation, which can take a few
minutes. Rebooting before they are done leaves you without a working driver. Check if they have been compiled
with:

```bash
modinfo -F version nvidia
```

If it prints the driver version *(e.g. 580.xx.xx)*, the modules are ready. If it prints
**ERROR: Module nvidia not found**, they are still compiling, wait a bit and try again.

---

`WARNING: If Secure Boot is enabled, the modules won't load until their signing key is enrolled.`

Check if Secure Boot is enabled with:

```bash
mokutil --sb-state
```

If it is, the modules have been signed with a key generated by akmods, which your firmware doesn't trust yet.
Once the modules are compiled, enroll that key with:

```bash
sudo mokutil --import /etc/pki/akmods/certs/public_key.der
```

You will be asked to create a one-time password. On the next reboot a blue **MOK Management** screen shows up:
choose **Enroll MOK**, **Continue**, **Yes**, enter that password and reboot.

---

`WARNING: If /home is encrypted, the modules must be included in the initramfs.`

Otherwise the driver takes over the display while the passphrase prompt for **/home** is being shown at boot,
which can leave you with a black screen instead of the prompt. Create the file **/etc/dracut.conf.d/nvidia.conf**
with the following contents:

```bash
add_drivers+=" nvidia nvidia_modeset nvidia_uvm nvidia_drm "
```

RPM Fusion intentionally leaves the modules out of the initramfs, because a copy in there won't be updated
along with the driver: after every NVIDIA driver or kernel update, the old modules in the initramfs would get
loaded against the new driver and the GPU would stop working, unless the initramfs is regenerated once the
new modules are compiled.

To do that automatically, install the **nvidia-initramfs** hook from this repository. Every time akmods
finishes compiling the modules *(it installs them through DNF as a **kmod-nvidia-\<kernel version\>** package)*,
a DNF action calls the script, which regenerates the initramfs of that kernel. From the root of a clone of
this repository, run:

```bash
sudo install -Dm755 dotfiles/usr/local/bin/nvidia-initramfs /usr/local/bin/nvidia-initramfs
sudo install -Dm644 dotfiles/etc/dnf/libdnf5-plugins/actions.d/nvidia-initramfs.actions /etc/dnf/libdnf5-plugins/actions.d/nvidia-initramfs.actions
```

* [dotfiles/usr/local/bin/nvidia-initramfs](dotfiles/usr/local/bin/nvidia-initramfs): regenerates the
  initramfs of the kernels that have the NVIDIA modules. It does nothing if **/etc/dracut.conf.d/nvidia.conf**
  doesn't exist.
* [dotfiles/etc/dnf/libdnf5-plugins/actions.d/nvidia-initramfs.actions](dotfiles/etc/dnf/libdnf5-plugins/actions.d/nvidia-initramfs.actions):
  calls the script whenever a **kmod-nvidia-\<kernel version\>** package is installed.

Then, once the modules are compiled, regenerate the initramfs of every kernel for the first time with:

```bash
sudo nvidia-initramfs
```

From now on this happens on its own. You can see what the hook did with:

```bash
journalctl -t nvidia-initramfs
```

`NOTE: The hook runs right after akmods finishes, which can be a few minutes after an update. Before rebooting after a driver or kernel update, wait until the command above shows "Done." for the new kernel/driver version.`

## Part 5 - Multimedia

Fedora only ships codecs that are free of patent and licensing issues, so out of the box many common
formats *(H.264, HEVC, AAC...)* don't play properly. RPM Fusion *(see [4.1 - RPM Fusion](#41---rpm-fusion))*
provides the full versions.

First, replace Fedora's limited **ffmpeg-free** with the full **ffmpeg**, which is used by applications such
as Firefox and mpv:

```bash
sudo dnf swap --allowerasing -y ffmpeg-free ffmpeg
```

`--allowerasing` is needed because the full ffmpeg conflicts with the limited libraries installed alongside
ffmpeg-free *(libavcodec-free, etc.)*, which have to be removed.

Then install the multimedia group, which adds the codecs used by GStreamer-based applications:

```bash
sudo dnf in -y @multimedia --setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin
```

* `--setopt=install_weak_deps=False` skips optional packages that are only recommended by the group.
* `--exclude=PackageKit-gstreamer-plugin` skips the plugin that pops up a codec search whenever an app is
  missing one, which is unnecessary once the codecs are installed.

Both commands follow RPM Fusion's [official multimedia guide](https://rpmfusion.org/Howto/Multimedia).

### 5.1 - Hardware video decoding

By default videos are decoded by the CPU. Installing the right VA-API driver lets the GPU do it instead,
which uses much less CPU and battery.

**Intel *(integrated GPU)*:**

Fedora's Intel driver *(**libva-intel-media-driver**, installed by default)* is built without support for
H.264, HEVC, VC-1 and VVC, which covers most videos you'll come across. Replace it with RPM Fusion's full
version:

```bash
sudo dnf swap --allowerasing -y libva-intel-media-driver intel-media-driver
```

`NOTE: A plain "dnf install intel-media-driver" fails, as both packages contain the same file. Swapping removes Fedora's version in the same step.`

**NVIDIA:**

```bash
sudo dnf in -y libva-nvidia-driver
```

Keep in mind that this driver:

* Only does decoding, not encoding.
* Is designed for Firefox and may not work correctly in other applications.
* Requires the NVIDIA driver's modesetting to be enabled. Check it with the command below, it should print **Y**:

  ```bash
  cat /sys/module/nvidia_drm/parameters/modeset
  ```

* Is never used unless the **LIBVA_DRIVER_NAME=nvidia** environment variable is set.

On a laptop with both GPUs, leave Intel as the default: it is the GPU that's already running, so the NVIDIA
GPU can stay asleep and save battery. To use NVIDIA in a specific application, start it with:

```bash
LIBVA_DRIVER_NAME=nvidia <application>
```

Only add **LIBVA_DRIVER_NAME=nvidia** to **/etc/environment** *(see [2.1 - Global environment variables](#21---global-environment-variables))*
if your machine runs on the NVIDIA GPU alone *(e.g. a laptop with a MUX switch set to dGPU mode)*. Firefox
also needs some extra settings to use it, see the [driver's documentation](https://github.com/elFarto/nvidia-vaapi-driver#firefox).

---

Check that everything works with **vainfo**:

```bash
sudo dnf in -y libva-utils
vainfo
LIBVA_DRIVER_NAME=nvidia vainfo
```

The first command should show the **Intel iHD driver** and the second one the **NVDEC** driver, each followed
by a list of supported profiles, which should include **VAProfileH264** and **VAProfileHEVC** entries.

## Part 6 - Virtualization

### 6.1 - Installing

Install the full virtualization package group *(QEMU/KVM, libvirt, Virtual Machine Manager, etc.)*:

```bash
sudo dnf group install -y --with-optional virtualization
```

### 6.2 - User groups

By default, managing the system's VMs *(the **QEMU/KVM** connection in Virtual Machine Manager)* requires
entering your password. Add your user to the **libvirt** group so it doesn't, and to the **kvm** group, which owns
**/dev/kvm** *(the KVM hardware acceleration device)*:

```bash
sudo usermod -aG libvirt,kvm $USER
```

Log out and back in *(or reboot)* for it to take effect, then check it with:

```bash
groups
```

`NOTE: Unlike Virtual Machine Manager, virsh connects to the per-user QEMU session by default when not run as root, which has its own separate VMs and networks. That's why the virsh commands below use sudo.`

### 6.3 - Firewall backend

On Fedora, libvirt's virtual networks use the **nftables** firewall backend by default, which can leave VMs
without internet access. A common cause is Docker, which sets the policy of the firewall's forwarding chain
to drop: libvirt's nftables rules live in a separate table and can't override that, so the VMs' traffic gets
dropped. With the **iptables** backend, libvirt adds its rules to the same chains Docker uses instead.

The iptables backend needs the **iptables** command, which isn't necessarily installed:

```bash
sudo dnf in -y iptables-nft
```

Then open the file **/etc/libvirt/network.conf** and set:

```bash
firewall_backend = "iptables"
```

Restart libvirt's network daemon to apply it. Any running virtual networks have their firewall rules
recreated with the new backend:

```bash
sudo systemctl restart virtnetworkd.service
```

### 6.4 - Default network

VMs get internet access through libvirt's **default** network *(NAT on the **virbr0** bridge)*. It is
normally created when the group is installed, check it with:

```bash
sudo virsh net-list --all
```

If **default** isn't listed, define it from the template shipped with libvirt:

```bash
sudo virsh net-define /usr/share/libvirt/networks/default.xml
```

Then make sure it starts on boot and is running:

```bash
sudo virsh net-autostart default
sudo virsh net-start default
```

`NOTE: net-start fails with "network is already active" if it was already running, which is fine.`

Running `sudo virsh net-list --all` again should show **default** as **active**, with autostart set to **yes**.

### 6.5 - Disabling copy-on-write for VM disk images

BTRFS is a copy-on-write filesystem: every write to a file goes to a new location on disk. VM disk images are
large files that get small random writes all the time, which leaves them heavily fragmented and slows the VMs
down over time. Disable copy-on-write for the directory where the images are stored *(the **libvirt** subvolume
from [1.1 - Boot disk layout](#11---boot-disk-layout))*:

```bash
sudo chattr +C /var/lib/libvirt/images
```

Check it with the command below, the output should include a **C**:

```bash
lsattr -d /var/lib/libvirt/images
```

`NOTE: Do this BEFORE creating any VMs. The attribute is only inherited by files created afterwards, existing images keep copy-on-write.`

libvirt also tries to do this on its own when Virtual Machine Manager first creates its default storage pool,
but it silently skips it on failure, so it's better to set it explicitly.

Keep in mind that files without copy-on-write also lose BTRFS checksums and compression. This doesn't affect
the snapper snapshots from Part 1, as they only cover the **root** subvolume.

If you ever need to convert an existing image, copy it into the directory instead of moving it, so a new
file is created *(with the VM shut down)*:

```bash
sudo cp --reflink=never /path/to/image.qcow2 /var/lib/libvirt/images/
```

## Part 7 - Git

For authentication I use [Git Credential Manager](https://github.com/git-ecosystem/git-credential-manager)
*(GCM)*: the first time you push to GitHub, GitLab, Bitbucket or Azure DevOps over HTTPS, it signs you in
through the browser, then stores the token in KWallet so you don't have to sign in again.

### 7.1 - Installing

Install Git, the .NET SDK *(GCM is distributed as a .NET tool and requires .NET 10)* and **libsecret**
*(which GCM uses to talk to KWallet)*:

```bash
sudo dnf in -y git dotnet-sdk-10.0 libsecret
```

Then install GCM as your user, **without sudo**:

```bash
dotnet tool install -g git-credential-manager
```

It is installed to **~/.dotnet/tools**, which is already in PATH *(see [2.2 - PATH](#22---path))*. GCM isn't
packaged for Fedora, so DNF won't update it, update it from time to time with:

```bash
dotnet tool update -g git-credential-manager
```

### 7.2 - Configuring

Set your identity and a few defaults:

```bash
git config --global user.name "Rin"
git config --global user.email "rin@kmrin.net"
git config --global init.defaultBranch main
git config --global pull.rebase false
```

* **init.defaultBranch main**: names the first branch of new repositories **main** instead of **master**.
* **pull.rebase false**: `git pull` merges remote changes into your branch. Without it, `git pull` refuses to run
  when your branch and the remote have diverged, until you choose how to reconcile them.

Then make GCM store its credentials in KWallet *(through the Secret Service API)* and register it as Git's
credential helper:

```bash
git config --global credential.credentialStore secretservice
~/.dotnet/tools/git-credential-manager configure
```

`configure` adds GCM to **~/.gitconfig** as the only credential helper, along with the settings Azure DevOps
needs. Check the result with:

```bash
git config --global --list
```

## Part 8 - L2TP/IPsec VPN

My company uses an L2TP/IPsec VPN to access internal systems. KDE can set one up from its settings, but on
Fedora it won't connect until a couple of system files are changed.

These steps match the ones Fedora documents in **/usr/share/doc/NetworkManager-l2tp/README.Fedora**.

### 8.1 - Installing

```bash
sudo dnf in -y NetworkManager-l2tp plasma-nm-l2tp libreswan kernel-modules-extra
```

* **NetworkManager-l2tp**: L2TP support for NetworkManager, using the **kl2tpd** daemon.
* **plasma-nm-l2tp**: the L2TP connection editor for KDE's settings.
* **libreswan**: the IPsec implementation.
* **kernel-modules-extra**: contains the L2TP kernel modules.

### 8.2 - Kernel modules

The L2TP kernel modules are blacklisted by default, with one file per module in **/etc/modprobe.d**. Only two
of them are needed, enable them by commenting out their blacklist line:

```bash
sudo sed -e '/blacklist l2tp_netlink/s/^b/#b/g' -i /etc/modprobe.d/l2tp_netlink-blacklist.conf
sudo sed -e '/blacklist l2tp_ppp/s/^b/#b/g' -i /etc/modprobe.d/l2tp_ppp-blacklist.conf
```

`NOTE: Don't delete these files instead: they belong to the kernel package, so a deleted file comes back with the next kernel update, while an edited one is kept.`

### 8.3 - IKEv1

L2TP/IPsec uses the IKEv1 protocol, which Libreswan disables by default. Enable it in **/etc/ipsec.conf**
by replacing its commented-out **ikev1-policy** line:

```bash
sudo sed -e 's/#ikev1-policy=.*/ikev1-policy=accept/' -i /etc/ipsec.conf
```

Check it with the command below, it should print **ikev1-policy=accept**:

```bash
grep ikev1-policy /etc/ipsec.conf
```

If you already tried to connect before this change, restart IPsec so it's applied:

```bash
sudo systemctl restart ipsec
```

### 8.4 - Troubleshooting

If the connection still fails, check NetworkManager's logs and look for SELinux denials with:

```bash
journalctl -b -u NetworkManager | grep -i -E "l2tp|ipsec|pluto"
sudo ausearch -m avc -ts today
```

## 9 - Packages

### 9.1 - Removal of unnecessary packages

Some default packages I remove as I use alternatives.

```bash
sudo dnf rm -y \
  firefox \
  kwrite \
  elisa-player \
  dragon \
  libreoffice-{writer,calc,impress,draw,math}
```

### 9.2 - Direct DNF packages

```bash
sudo dnf in -y \
  plasma-browser-integration \
  python3-{devel,dbus,gobject,pandas} \
  bpython \
  java-latest-openjdk \
  kate \
  okteta \
  kvantum \
  gimp \
  kdenlive \
  smplayer \
  smplayer-themes \
  wine \
  wine.i686 \
  winetricks \
  gamemode \
  mangohud \
  goverlay \
  lutris \
  bottles \
  steam \
  flatseal \
  qbittorrent \
  filezilla \
  remmina \
  unzip \
  p7zip \
  p7zip-plugins \
  unrar \
  dolphin-devel \
  fish \
  bat \
  fzf \
  fd-find \
  fastfetch \
  clementine
```

### 9.3 - Flatpaks

* Brave Browser
* Discord
* Gear Lever
* GPU Screen Recorder
* Lossless Cut
* OBS Studio
* ONLYOFFICE Desktop Editors
* Portal for Teams
* ProtonPlus
* Spotify
* Upscaler
* Parabolic
* GNOME Calculator
* Bottles
* Dev Toolbox

### 9.4 - Outside programs

Some programs need to be manually installed from outside sources.

* Visual Studio Code
* JetBrains Toolbox
* DaVinci Resolve
* r2modman

## 10 - Docker

```bash
sudo dnf config-manager addrepo --from-repofile https://download.docker.com/linux/fedora/docker-ce.repo

sudo dnf in -y \
  docker-ce \
  docker-ce-cli \
  docker-{buildx,compose}-plugin

sudo systemctl enable --now docker
sudo usermod -aG docker $USER
```

## 11 - KDE changes

### 11.1 - Addons

* Plasmusic Toolbar - Very good media control panel.
* Remember Window Positions - Makes apps open in the same place they were once closed.

### 11.2 - Customization

* Dark mode.
* Violet accent colors.
* Papirus-Dark system-wide icons.
* papirus-folders to change the color of folder icons from blue to violet.
* CaskaydiaCove Nerd Font 10pt as the terminal font.
* Sweet Konsole terminal color scheme.
* Darkly application style ("Menu item height" set to 3).
* Klassy plasma style.
* Klassy window decorations ("Icons" set to "Use system icon theme" and button spacing set to 1)
