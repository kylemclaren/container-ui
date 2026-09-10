# Compose projects

ContainerUI can import Compose files and manage their services as a project through
[Mcrich23/Container-Compose 1.1.0](https://github.com/Mcrich23/Container-Compose/tree/1.1.0).
This is an optional executable, separate from Apple's `container` CLI:

```sh
brew install container-compose
container-compose --version
# container-compose version 1.1.0
```

Use **Settings → Compose projects** to specify a custom executable path. The app
also checks `/opt/homebrew/bin/container-compose` and `/usr/local/bin/container-compose`.
Other tools named `container-compose`, and other versions, are rejected until their
command behavior has been verified. No Docker daemon is required.

## Workflow

1. Open **Projects → Import Compose…** and choose `compose.yaml`, `compose.yml`, or
   another Compose YAML file. Import is read-only and does not start containers.
2. Review services, image/build sources, published ports, dependencies, profiles,
   and compatibility diagnostics. Give each project a unique top-level `name`.
3. Choose **Start project → Start / recreate…** or **Rebuild & start…**.
   Confirm the recreation of existing project containers. Output remains available
   while you navigate to other screens, with the latest 3,000 lines and a Copy action.
4. Open each service's **Inspect**, **Logs**, or **Console** actions. Status follows
   the app's existing container monitor. Projects also appear in ⌘K navigation.
5. **Stop project** stops every running container carrying that project's ownership
   label, including services from previously enabled profiles. It preserves
   containers, networks, and volumes. **Forget project** only removes the saved file
   reference; it does not stop containers or delete files.

File references and selected profiles persist across app launches. YAML and secrets
are not copied into app preferences. Relative build contexts, bind mounts, and
environment files resolve from the Compose file's directory. The backend's `.env`
handling uses that same directory. Refresh rereads files edited in your editor.

## Compatibility contract

This is **partial Compose support**, following the specified backend's behavior:

| Area | Behavior |
| --- | --- |
| Files | One Compose file per project. YAML anchors and `x-` extensions can be used. Multiple-file merging, `include`, and `extends` are not supported. |
| Services | Images, builds, command/entrypoint overrides, environment, ports, volumes, dependencies, and profiles are passed to the backend. Preview shows source values, not interpolated configuration. |
| Start | Runs `container-compose up --file … --cwd … --detach`, optionally with `--build` and repeated `--profile`. Existing service containers are recreated, replacing their writable layers. |
| Stop | Uses `container stop` on exact `com.docker.compose.project` labels. Backend 1.1.0's `down` guesses names and suppresses individual stop errors, so the app does not use it. |
| Ownership | Service grouping requires project/service labels. Prefix matches never establish ownership. Start refuses candidate container names already owned by another service or lacking ownership labels. Importing a second file with the same project name is rejected. |
| Storage | Named volumes and bind mounts survive recreation. Use volumes for persistent data. Long-form ports and mounts are not supported by this backend. |
| Networks | Explicit network names and external networks work through the backend. Networks are not automatically isolated per project. Driver options, `internal`, IPAM, static addresses, and other ignored network options are blocked. |
| Environment | Backend interpolation and environment precedence differ from Docker Compose. In particular, image and project-name interpolation are unsupported. Check `.env` values when migrating a stack. Finder-launched apps do not inherit an interactive shell's environment. |
| Health | Startup dependency checks are supported; continuous health monitoring and restart policies are not. |
| Unsupported fields | Known ignored or unsupported fields block Start with their YAML paths: examples include `restart`, `secrets`, `configs`, `network_mode`, `hostname`, deployment replicas, and unsupported build options. The source file remains editable outside the app. |

The preview is a compatibility check, not a complete Compose specification validator.
The backend performs final decoding and execution. A failed start can leave some
services running; their state remains visible and **Stop project** can stop them.
Keep ContainerUI open until the operation completes. Changing a Compose file's
project name creates a different project identity; stop the old project first.

## Validation

The regular CI suite is host-less and requires no container daemon. It tests YAML
preview, profiles/dependencies, compatibility diagnostics, persistence, exact process
arguments and working directory, ownership collisions, source changes, output,
nonzero exits, false-success detection, and stopping only owned resources.

An additional opt-in scheme exercises the real backend and runtime:

```sh
container system start
xcodegen generate
xcodebuild -scheme ContainerUIComposeIntegration \
  -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO
```

The integration test creates a uniquely named Redis + built web-image stack in a
temporary directory containing a space. It checks service labels, environment,
HTTP, service-to-service connectivity, logs, profiles, stop/recreate, and Redis
volume persistence. It removes its own containers, volume, built image, and files
on success or failure. Shared base images and the builder remain cached.
It needs network access for images and a running Apple container service on macOS 26.
