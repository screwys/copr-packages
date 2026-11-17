#!/usr/bin/env bash
# COPR custom source script for loupe-single-window in screwyy/nocblue.
#
# Takes Fedora's Loupe packaging at the dist-git commit of a Fedora build and
# adds the window-reuse patch. The package has its own name and conflicts with
# loupe, so enabling the COPR never replaces Fedora's Loupe; it is installed
# only when asked for by name.
#
# The build workflow fills in the commit before submitting this script.
set -euo pipefail

commit=
# Bump when the patch or packaging changes without a Fedora update.
patch_revision=1

git clone https://src.fedoraproject.org/rpms/loupe.git loupe
cd loupe
git checkout --detach "${commit:?}"

while read -r _ file _ hash; do
    file="${file#(}"
    file="${file%)}"
    curl -fsSL --retry 3 -o "${file}" \
        "https://src.fedoraproject.org/repo/pkgs/rpms/loupe/${file}/sha512/${hash}/${file}"
done <sources
sha512sum -c sources

cat >reuse-active-window.patch <<'EOF'
--- a/src/application.rs
+++ b/src/application.rs
@@ -93,8 +93,12 @@
         fn open(&self, files: &[gio::File], _hint: &str) {
             tracing::debug!("Open {} file(s)", files.len());
             let application = self.obj();
-            let win = LpWindow::new(&*application);
+            let win = application
+                .active_window()
+                .and_then(|window| window.downcast::<LpWindow>().ok())
+                .unwrap_or_else(|| LpWindow::new(&*application));
             win.image_view().set_images_from_files(files.to_vec());
+            win.present();
         }
     }

EOF

# Resolve %autorelease and %autochangelog from the dist-git history.
rpmautospec process-distgit loupe.spec loupe.spec

grep -q '^Name: *loupe$' loupe.spec
grep -q '^Release: *%autorelease$' loupe.spec
grep -q '^Source1:' loupe.spec
grep -q '^Requires: *dbus$' loupe.spec
sed -i \
    -e 's/^Name: *loupe$/Name:           loupe-single-window/' \
    -e "s/^\(Release: *%autorelease\)$/\1 -e ${patch_revision}/" \
    -e '/^Source1:/a Patch:          reuse-active-window.patch' \
    -e '/^Requires: *dbus$/i Provides:       loupe = %{version}-%{release}' \
    -e '/^Requires: *dbus$/i Conflicts:      loupe' \
    loupe.spec
