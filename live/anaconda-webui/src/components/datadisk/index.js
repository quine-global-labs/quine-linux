/*
 * quine-linux: the "Data disk" step (DataDisk.jsx).
 * SPDX-License-Identifier: LGPL-2.1-or-later
 */

import cockpit from "cockpit";

import { DataDisk } from "./DataDisk.jsx";

const _ = cockpit.gettext;

export class Page {
    _description = "Optionally keep home folders, Flatpak apps, containers and swap on a second disk.";

    constructor () {
        this.component = DataDisk;
        this.id = "quine-screen-data-disk";
        this.label = _("Data disk");
        this.title = _("Data disk");
    }
}
