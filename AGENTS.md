# kartei

The file schema is documented at the top of `default.nix`, joining
retiolum in `README.md`.

- Add hosts with `nix run .#add-host -- --namespace NS --host NAME
  --pubkey-file ed25519_key.pub` rather than writing files by hand;
  see `--help`. Nets other than retiolum (e.g. `internet/`) are written
  by hand, copied from a sibling host.
- Match the namespace's existing hosts: most `mic92` hosts predate
  genipv6 and need `--ip6 42:0:3c46:…` and `--alias NAME.r`.
- `nix build .#checks.x86_64-linux.lint` is the fast check (duplicates,
  formats, unknown files); `nix flake check` is slow.
- Commit messages: `NS: add HOST`, `NS: <change>`. PRs go to
  `krebs/kartei` `master`.
