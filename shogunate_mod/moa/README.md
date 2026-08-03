# Role MoA

`shogunate moa` runs one Shogunate role through several AGMSG identities while
keeping one representative responsible for the role's official output.

The durable state lives under `queue/moa/<role>/<task-id>/`. AGMSG carries only
an assignment path. A member must submit against the assignment digest and its
`AGENT_ID`; the representative cannot finalize until the configured quorum is
present. Finalization writes `final.txt` and `receipt.yaml`, then dissolves the
deployment when `dissolve_after: finalized` is configured.

Default profiles live in `config/moa.yaml`. A complete profile passed to
`shogunate moa deploy` applies only to that deployment and does not rewrite the
default profile.

The normal interactive path is `shogunate configure`: one member saves
`single`, while two to eight members save a default MoA. It asks for the
representative first and then the remaining members. The non-interactive
`shogunate moa configure` command remains available for automation and explicit
agent, model, runtime, quorum, or policy values.

The implementation does not start an AI CLI. `shogunate moa agmsg-setup`
registers the configured identities with AGMSG, and the existing Shogunate
runtime or an external dispatcher remains responsible for process lifecycle.
