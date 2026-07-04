import Foundation

/// Recorded JSON exactly as the `container` CLI emits it (camelCase keys, ISO-8601
/// dates without fractional seconds, omitted optionals). Used to verify decoding.
enum Fixtures {
    /// `container list --all --format json` — one running, one stopped.
    static let containerList = """
    [
      {
        "configuration": {
          "id": "web",
          "image": {
            "reference": "docker.io/library/nginx:latest",
            "descriptor": { "mediaType": "application/vnd.oci.image.index.v1+json", "digest": "sha256:aaa111", "size": 1234 }
          },
          "mounts": [ { "type": "virtiofs", "source": "/host/data", "destination": "/data", "options": ["rw"] } ],
          "publishedPorts": [ { "hostAddress": "0.0.0.0", "hostPort": 8080, "containerPort": 80, "proto": "tcp", "count": 1 } ],
          "publishedSockets": [],
          "labels": { "com.example.role": "web" },
          "sysctls": {},
          "networks": [ { "network": "default", "options": { "hostname": "web" } } ],
          "rosetta": false,
          "initProcess": {
            "executable": "/docker-entrypoint.sh",
            "arguments": ["nginx", "-g", "daemon off;"],
            "environment": ["PATH=/usr/local/sbin:/usr/local/bin"],
            "workingDirectory": "/",
            "terminal": false,
            "user": { "id": { "uid": 0, "gid": 0 } },
            "supplementalGroups": [],
            "rlimits": []
          },
          "platform": { "os": "linux", "architecture": "arm64", "variant": "v8" },
          "resources": { "cpus": 4, "memoryInBytes": 1073741824, "cpuOverhead": 1 },
          "runtimeHandler": "container-runtime-linux",
          "virtualization": false,
          "ssh": false,
          "readOnly": false,
          "useInit": false,
          "capAdd": [],
          "capDrop": [],
          "creationDate": "2026-06-23T17:57:21Z"
        },
        "id": "web",
        "status": {
          "state": "running",
          "networks": [ { "network": "default", "hostname": "web", "ipv4Address": "192.168.64.3/24", "ipv4Gateway": "192.168.64.1", "macAddress": "02:42:ac:11:00:02" } ],
          "startedDate": "2026-06-23T17:57:22Z"
        }
      },
      {
        "configuration": {
          "id": "db",
          "image": {
            "reference": "docker.io/library/postgres:16",
            "descriptor": { "mediaType": "application/vnd.oci.image.index.v1+json", "digest": "sha256:bbb222", "size": 2222 }
          },
          "mounts": [],
          "publishedPorts": [],
          "publishedSockets": [],
          "labels": {},
          "sysctls": {},
          "networks": [ { "network": "default", "options": { "hostname": "db" } } ],
          "rosetta": false,
          "initProcess": {
            "executable": "/bin/sh",
            "arguments": ["-c", "sleep infinity"],
            "environment": ["PATH=/usr/bin"],
            "workingDirectory": "/",
            "terminal": false,
            "user": { "id": { "uid": 0, "gid": 0 } },
            "supplementalGroups": [],
            "rlimits": []
          },
          "platform": { "os": "linux", "architecture": "arm64", "variant": "v8" },
          "resources": { "cpus": 2, "memoryInBytes": 536870912 },
          "runtimeHandler": "container-runtime-linux",
          "virtualization": false,
          "ssh": false,
          "readOnly": false,
          "useInit": false,
          "capAdd": [],
          "capDrop": [],
          "creationDate": "2026-06-22T10:00:00Z"
        },
        "id": "db",
        "status": { "state": "stopped", "networks": [] }
      }
    ]
    """

    /// `container stats --no-stream --format json web`.
    static let stats = """
    [ { "id": "web", "memoryUsageBytes": 52428800, "memoryLimitBytes": 1073741824, "cpuUsageUsec": 1234567, "networkRxBytes": 1024, "networkTxBytes": 2048, "blockReadBytes": 4096, "blockWriteBytes": 8192, "numProcesses": 12 } ]
    """

    /// `container image list --format json`.
    static let imageList = """
    [
      {
        "id": "1a2b3c4d5e6f7081920aabbccddeeff00112233445566778899aabbccddeeff0",
        "configuration": {
          "creationDate": "2024-01-15T12:34:56Z",
          "name": "docker.io/library/alpine:latest",
          "descriptor": {
            "mediaType": "application/vnd.oci.image.index.v1+json",
            "digest": "sha256:1a2b3c4d5e6f7081920aabbccddeeff00112233445566778899aabbccddeeff0",
            "size": 1024,
            "annotations": { "org.opencontainers.image.ref.name": "alpine:latest" }
          }
        },
        "variants": [
          {
            "platform": { "os": "linux", "architecture": "arm64", "variant": "v8" },
            "digest": "sha256:abc000111222333444555666777888999",
            "size": 3987654,
            "config": {
              "created": "2024-01-15T12:34:56.000000000Z",
              "architecture": "arm64",
              "os": "linux",
              "variant": "v8",
              "rootfs": { "type": "layers", "diff_ids": ["sha256:aaaa0000", "sha256:bbbb1111"] },
              "config": { "Env": ["PATH=/usr/local/sbin:/usr/local/bin"], "Cmd": ["/bin/sh"], "WorkingDir": "/" },
              "history": [ { "created": "2024-01-15T12:34:56.000000000Z", "created_by": "/bin/sh -c #(nop) CMD", "empty_layer": true } ]
            }
          }
        ]
      }
    ]
    """

    /// `container system status --format json` — running.
    static let systemStatusRunning = """
    { "apiServerAppName": "container-apiserver", "apiServerBuild": "release", "apiServerCommit": "a1b2c3d4e5f6", "apiServerVersion": "0.4.1", "appRoot": "/Users/me/Library/Application Support/com.apple.container", "installRoot": "/usr/local", "logRoot": "/Users/me/Library/Logs/com.apple.container", "status": "running" }
    """

    /// `container system status --format json` — down (note: no `logRoot`).
    static let systemStatusUnregistered = """
    { "apiServerAppName": "", "apiServerBuild": "", "apiServerCommit": "", "apiServerVersion": "", "appRoot": "", "installRoot": "", "status": "unregistered" }
    """

    /// `container system df --format json`.
    static let diskUsage = """
    { "containers": { "active": 1, "reclaimable": 0, "sizeInBytes": 104857600, "total": 3 }, "images": { "active": 2, "reclaimable": 524288000, "sizeInBytes": 1073741824, "total": 5 }, "volumes": { "active": 1, "reclaimable": 0, "sizeInBytes": 2097152, "total": 2 } }
    """

    /// `container system version --format json` — backend up (2 elements).
    static let versionUp = """
    [ { "appName": "container", "buildType": "debug", "commit": "abcdef1", "version": "0.4.1" }, { "appName": "container-apiserver", "buildType": "release", "commit": "1234abc", "version": "0.4.1" } ]
    """

    /// `container system version --format json` — backend down (1 element).
    static let versionDown = """
    [ { "appName": "container", "buildType": "debug", "commit": "abcdef1", "version": "0.4.1" } ]
    """

    /// `GET /v2/search/repositories/?query=nginx` — official + two community repos.
    static let hubSearch = """
    {
      "count": 3,
      "next": "https://hub.docker.com/v2/search/repositories/?page=2&page_size=3&query=nginx",
      "previous": "",
      "results": [
        { "repo_name": "nginx", "short_description": "Official build of Nginx.", "star_count": 21318, "pull_count": 13114222271, "repo_owner": "", "is_automated": false, "is_official": true },
        { "repo_name": "grafana/grafana", "short_description": "The open observability platform", "star_count": 456, "pull_count": 987654321, "repo_owner": "grafana", "is_automated": false, "is_official": false },
        { "repo_name": "cimg/postgres", "short_description": "", "star_count": 9, "pull_count": 719219989, "repo_owner": "cimg", "is_automated": false, "is_official": false }
      ]
    }
    """

    /// `GET /v2/repositories/library/nginx/tags/?ordering=last_updated` — one tag with
    /// an attestation ("unknown") manifest to exclude, one single-platform tag.
    static let hubTags = """
    {
      "count": 1231,
      "next": "https://hub.docker.com/v2/repositories/library/nginx/tags/?ordering=last_updated&page=2&page_size=2",
      "previous": null,
      "results": [
        { "creator": 1156886, "id": 987274600, "name": "latest", "full_size": 75271303, "last_updated": "2026-06-24T04:51:06.973034832Z",
          "images": [
            { "architecture": "amd64", "variant": null, "digest": "sha256:306d9dea", "os": "linux", "size": 75271303, "status": "active", "last_pushed": "2026-06-24T04:51:06.973034832Z" },
            { "architecture": "arm64", "variant": "v8", "digest": "sha256:aa11bb22", "os": "linux", "size": 67000000, "status": "active", "last_pushed": "2026-06-24T04:51:07.402177787Z" },
            { "architecture": "unknown", "variant": null, "digest": "sha256:39ca2ad7", "os": "unknown", "size": 4265361, "status": "active", "last_pushed": "2026-06-24T04:51:07.402177787Z" }
          ] },
        { "creator": 1156886, "id": 987274601, "name": "1.31", "full_size": 67000000, "last_updated": "2026-06-24T04:51:00Z",
          "images": [
            { "architecture": "arm64", "variant": "v8", "digest": "sha256:cc33dd44", "os": "linux", "size": 67000000, "status": "active", "last_pushed": "2026-06-24T04:51:00Z" }
          ] }
      ]
    }
    """

    static func data(_ string: String) -> Data { Data(string.utf8) }
}
