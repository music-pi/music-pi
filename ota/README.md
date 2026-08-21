# ota/ — update policy and backlog

OTA is not implemented in the current release candidate. Update by downloading
a published image, verifying its checksum, and reflashing the system partition.
The library and sample partitions remain separate, but users should still back
up their data.

Any future OTA implementation must:

- verify signed release metadata and image or package hashes before privileged
  installation;
- advance the Station release and all pinned components as one tested unit;
- install atomically with a recoverable rollback path;
- work headlessly through the mode selector; and
- never run an unauthenticated `git pull` as an update mechanism.

Track implementation and threat-model work here before enabling OTA on devices.
