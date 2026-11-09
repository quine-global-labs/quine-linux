/*
 * quine-linux: the "Data disk" step. Optionally keeps home folders, Flatpak
 * apps, containers (and a swap file) on a second disk, e.g. a large hard
 * disk next to a small SSD, the way the iMac is set up. The system itself
 * still goes where the storage step put it.
 *
 * The choice is written to /run/quine-data-disk.json ({device, name, label,
 * uuid}, or no file for "no data disk"). The kickstart %post data-disk.ks
 * (live/build.sh) reads it after installing: mounts the partition at
 * /var/hdd and binds what's on it into place, reusing an existing layout
 * (home-<user>/, flatpak/, podman-storage/, swapfile) or creating one.
 * The partition is never formatted: its files stay.
 *
 * SPDX-License-Identifier: LGPL-2.1-or-later
 */
import cockpit from "cockpit";

import React, { useContext, useEffect, useMemo, useState } from "react";
import { Alert } from "@patternfly/react-core/dist/esm/components/Alert/index.js";
import { Content } from "@patternfly/react-core/dist/esm/components/Content/index.js";
import { Form, FormGroup } from "@patternfly/react-core/dist/esm/components/Form/index.js";
import { Radio } from "@patternfly/react-core/dist/esm/components/Radio/index.js";

import { StorageContext } from "../../contexts/Common.jsx";
import { useOriginalDevices } from "../../hooks/Storage.jsx";

const _ = cockpit.gettext;
const SCREEN_ID = "quine-screen-data-disk";
const CHOICE_FILE = "/run/quine-data-disk.json";
const FILESYSTEMS = ["ext4", "xfs", "btrfs"];
// Labels that mark a partition meant for this (the iMac's is "hdd").
const DATA_LABELS = ["hdd", "data", "quine-data"];

const attr = (device, key) => device?.formatData?.attrs?.v?.[key] || "";
const diskOf = (devices, device) => {
    let d = device;
    // A partition's parent is its disk; follow until a device without parents.
    while (d?.parents?.v?.length) {
        d = devices[d.parents.v[0]];
    }
    return d;
};

export const DataDisk = ({ setIsFormValid }) => {
    const devices = useOriginalDevices();
    const { diskSelection } = useContext(StorageContext);
    const selectedDisks = useMemo(() => diskSelection?.selectedDisks || [], [diskSelection]);

    // Filesystems that could hold the data, and whether the install would
    // erase them (they're on a disk selected for the system).
    const candidates = useMemo(() => Object.values(devices || {})
            .filter(d => FILESYSTEMS.includes(d.formatData?.type?.v))
            .filter(d => !(d.children?.v?.length))
            .map(d => {
                const disk = diskOf(devices, d);
                return {
                    name: d.name.v,
                    path: d.path.v,
                    size: d.size.v,
                    fs: d.formatData.type.v,
                    label: attr(d, "label"),
                    uuid: attr(d, "uuid"),
                    diskName: disk?.name?.v,
                    diskDescription: disk?.description?.v || "",
                    onInstallDisk: selectedDisks.includes(disk?.name?.v),
                };
            })
            .sort((a, b) => a.name.localeCompare(b.name)), [devices, selectedDisks]);

    const labeled = candidates.find(c => !c.onInstallDisk && DATA_LABELS.includes(c.label.toLowerCase()));
    const [useDisk, setUseDisk] = useState(!!labeled);
    const [chosen, setChosen] = useState(labeled?.name || "");
    const chosenCandidate = candidates.find(c => c.name === chosen);
    const valid = !useDisk || (!!chosenCandidate && !chosenCandidate.onInstallDisk);

    useEffect(() => {
        setIsFormValid(valid);
    }, [valid, setIsFormValid]);

    // Keep the choice file in step with the page: written when a usable
    // partition is chosen, removed otherwise.
    useEffect(() => {
        const file = cockpit.file(CHOICE_FILE, { superuser: "try" });
        const content = useDisk && valid && chosenCandidate
            ? JSON.stringify({
                device: chosenCandidate.path,
                name: chosenCandidate.name,
                label: chosenCandidate.label,
                uuid: chosenCandidate.uuid,
            }) + "\n"
            : null;
        file.replace(content).catch(e => console.error("data disk: writing", CHOICE_FILE, e));
        return () => file.close();
    }, [useDisk, valid, chosenCandidate]);

    const describe = c => cockpit.format(
        "$0 — $1, $2$3$4",
        c.path,
        cockpit.format_bytes(c.size),
        c.fs,
        c.label ? cockpit.format(_(", label “$0”"), c.label) : "",
        c.diskDescription ? cockpit.format(" ($0)", c.diskDescription) : ""
    );

    return (
        <Form id={SCREEN_ID} isHorizontal={false}>
            <Content component="p">
                {_("The system goes on the disk you chose in the previous steps. If this computer has a second, larger disk, your home folder, Flatpak apps and containers can live there instead, so they don't fill up the system disk.")}
            </Content>
            <FormGroup role="radiogroup" isStack fieldId={SCREEN_ID + "-choice"}>
                <Radio
                  id={SCREEN_ID + "-none"}
                  name={SCREEN_ID + "-choice"}
                  isChecked={!useDisk}
                  onChange={() => setUseDisk(false)}
                  label={_("Keep everything on the system disk")}
                />
                <Radio
                  id={SCREEN_ID + "-use"}
                  name={SCREEN_ID + "-choice"}
                  isChecked={useDisk}
                  onChange={() => setUseDisk(true)}
                  label={_("Use a second disk for home folders, apps and containers")}
                  description={_("Its files are kept, nothing on it is erased. If it already holds home folders, apps and containers from an earlier install, they're used again.")}
                />
            </FormGroup>
            {useDisk && candidates.length === 0 &&
                <Alert isInline variant="warning" title={_("No usable partition found")}>
                    {_("Only an existing ext4, XFS or Btrfs partition can be used. Create one first, for example with KDE Partition Manager.")}
                </Alert>}
            {useDisk && candidates.length > 0 &&
                <FormGroup role="radiogroup" isStack label={_("Partition")} fieldId={SCREEN_ID + "-partition"}>
                    {candidates.map(c => (
                        <Radio
                          key={c.name}
                          id={SCREEN_ID + "-partition-" + c.name}
                          name={SCREEN_ID + "-partition"}
                          isChecked={chosen === c.name}
                          isDisabled={c.onInstallDisk}
                          onChange={() => setChosen(c.name)}
                          label={describe(c)}
                          description={c.onInstallDisk ? _("On the disk the system is being installed to, so it would be erased.") : ""}
                        />
                    ))}
                </FormGroup>}
            {useDisk && chosenCandidate && !chosenCandidate.onInstallDisk &&
                <Alert isInline variant="info" title={_("Create the same user name at first start")}>
                    {cockpit.format(_("Home folders already on $0 (home-<name>) are matched to users by name. When the computer first starts, create your account with the same user name as before to get your files back."), chosenCandidate.path)}
                </Alert>}
        </Form>
    );
};
