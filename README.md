# ceerat
This repo is mainly for test/production build for render.com.  It depends on the following sub moudles which are private git repos.

The main repo contains following.
ceerat             Render deployment repo
  go.work
  render.yaml
  scripts/
  apps-repo/              submodule
  services-repo/          submodule
  contracts-repo/         submodule

Submodules (Private Visibility)
ceerat-apps-repo          real app source code
ceerat-services-repo      real backend service source code
ceerat-contracts-repo     proto/contracts source code

