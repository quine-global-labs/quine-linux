# Testing a build on a Proxmox VM

`.forgejo/vm-test.sh` boots a Quine Linux live ISO on zeus's test VM,
**107** (`quine-live-test`: UEFI, q35, 8 GB, a 64 GB disk), and waits for it
to come up. Everything goes through Proxmox's API, with a token that can do
nothing else.

- **From Forgejo:** Actions → **VM test** → Run workflow, with a release tag
  (`v0.1.1-alpha.1`) or `latest` (the last build of `main`).
- **From a laptop on the tailnet:** `PVE_TOKEN=… task test:vm TAG=v0.1.1-alpha.1`.
  `TAG=latest` also needs MinIO's credentials in `RCLONE_CONFIG_STORE_*`, as
  in `iso.yml`, or an `ISO_URL`.

## What it does

1. Picks the ISO: a release's public `quine-linux-<tag>-live-x86_64.iso`,
   with its checksum from the release's `SHA256SUMS`, or for `latest` a
   3-hour presigned link to MinIO's `live/latest/live.iso`.
2. Stops VM 107, detaches its CD, deletes the old
   `local:iso/quine-linux-live-test.iso`, and has Proxmox download the new
   one straight from MinIO (checked against the checksum for a release).
3. Attaches it, boots from it first, enables the QEMU guest agent's channel,
   and starts the VM.
4. Waits (15 minutes at most) for the live system's guest agent to answer:
   Fedora's `qemu-guest-agent` is in the image (Kinoite's
   `packages/common.yaml`). It passes when it does, and reports the OS and
   kernel the guest gives, in the job summary too. It fails if the agent
   never answers: look at the VM's console in Proxmox.

The VM stays running at the live desktop afterwards, to look at in Proxmox's
console.

## The token (once, on zeus)

A user with no password and a token, allowed only what the script calls
(each from Proxmox's own permission checks):

| Where | Privileges | For |
|---|---|---|
| `/vms/107` | `VM.Audit`, `VM.PowerMgmt`, `VM.Config.CDROM`, `VM.Config.Options`, `VM.GuestAgent.Audit` | status, stop/start, the CD, boot order and agent, asking the guest its OS |
| `/storage/local` | `Datastore.AllocateTemplate`, `Datastore.Allocate`, `Datastore.Audit` | downloading the ISO; deleting the old one |
| `/nodes/zeus` | `Sys.AccessNetwork` | Proxmox downloading from a URL |

`Datastore.Allocate` on `local` also allows deleting anything else stored
there (ISOs, templates): Proxmox has no narrower right for deleting a file.

```sh
pveum role add QuineVMTest -privs "VM.Audit VM.PowerMgmt VM.Config.CDROM VM.Config.Options VM.GuestAgent.Audit"
pveum role add QuineVMTestStorage -privs "Datastore.AllocateTemplate Datastore.Allocate Datastore.Audit"
pveum role add QuineVMTestNode -privs "Sys.AccessNetwork"
pveum user add quine-ci@pve --comment "Forgejo: quine-linux's VM test (docs/VM_TEST.md)"
pveum user token add quine-ci@pve vm-test --privsep 0 --comment "quine-linux VM test"
pveum acl modify /vms/107 -user quine-ci@pve -role QuineVMTest
pveum acl modify /storage/local -user quine-ci@pve -role QuineVMTestStorage
pveum acl modify /nodes/zeus -user quine-ci@pve -role QuineVMTestNode
```

`token add` prints the secret once. Store it as the quine-global-labs (or
quine-linux) Actions secret **`PVE_TOKEN`**, in the form
`quine-ci@pve!vm-test=<secret>`.

## VM 107

It was made by hand (its description says so), not in tofu. If it stays as
the test VM, it belongs in `terraform/modules/zeus` like the others.
