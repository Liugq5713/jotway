# Website publication

> Role: **Work**
> Status: awaiting a public app release and hosting target.

The local website implementation and usage images are documented in [Website and product usage images](../development/website.md). They are ready for local review; this remaining brief does not represent an online site.

Before public launch:

1. Select the public hosting target and domain. Deploy the generated static directory with directory-index routing, and check `/`, `/download` and `/privacy` over HTTPS.
2. Publish an intended stable app release, then generate public download metadata using the verified artifact and actual GitHub Release. Never relabel a local DMG as published.
3. Confirm the screenshot source hashes and advertised Action behavior match that release, and that Current documentation links include the released changes. Refresh the real captures if needed.
4. Review the published download URL, size, hash, macOS requirement, architecture, signing and notarization state. The present build flow is ad-hoc signed and not notarized; adopting another signing policy requires updating both the pipeline and disclosure.
5. Check installation and full live-window confirmation behavior separately if automated operation of the user's app is authorized. Isolated image rendering does not verify window focus, input-method composition or actual Action execution.

On deployment, update the Current website document with its durable hosting behavior and remove this Work brief.
