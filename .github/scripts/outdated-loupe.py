#!/usr/bin/env python3
"""Print the COPR chroots whose loupe-single-window lags Fedora's stable Loupe.

Writes `builds=<json list of {chroot, commit}>` for $GITHUB_OUTPUT.
"""

import json
import pathlib
import re
import sys
import urllib.parse
import urllib.request
import xmlrpc.client

COPR = "https://copr.fedorainfracloud.org/api_3"
OWNER, PROJECT, PACKAGE = "screwyy", "nocblue", "loupe-single-window"


def copr(endpoint, **params):
    query = urllib.parse.urlencode({"ownername": OWNER, "projectname": PROJECT, **params})
    with urllib.request.urlopen(f"{COPR}/{endpoint}?{query}", timeout=60) as response:
        return json.load(response)


script = pathlib.Path("loupe/copr-source.sh").read_text()
patch_revision = re.search(r"^patch_revision=(\d+)$", script, re.M).group(1)

koji = xmlrpc.client.ServerProxy("https://koji.fedoraproject.org/kojihub", allow_none=True)
builds = copr("build/list", packagename=PACKAGE, order="id", order_type="DESC", limit=100)["items"]

outdated = []
for chroot in copr("project")["chroot_repos"]:
    release = re.fullmatch(r"fedora-(\d+)-x86_64", chroot).group(1)
    fedora = koji.getLatestBuilds(f"f{release}-updates", None, "loupe")[0]
    source = koji.getBuild(fedora["build_id"])["source"]
    commit = source.rpartition("#")[2]
    dist = f".fc{release}"
    wanted = f"{fedora['version']}-{fedora['release'].removesuffix(dist)}.{patch_revision}"
    built = next(
        (b["source_package"]["version"] for b in builds
         if b["state"] == "succeeded" and chroot in b["chroots"]),
        None,
    )
    print(f"{chroot}: Fedora {fedora['nvr']}, wanted {wanted}, built {built}", file=sys.stderr)
    if built != wanted:
        outdated.append({"chroot": chroot, "commit": commit})

print(f"builds={json.dumps(outdated)}")
