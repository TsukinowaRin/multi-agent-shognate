# Role MoA

`shogunate moa` runs one Shogunate role through several agent identities while
keeping one representative responsible for the role's official output.

The durable state lives under `queue/moa/<role>/<task-id>/`. Notifications carry
only an assignment path. A member must submit against the assignment digest and
its `AGENT_ID`; the representative cannot finalize until the configured quorum is
present. Finalization writes `final.txt` and `receipt.yaml`, then dissolves the
deployment when `dissolve_after: finalized` is configured.

## Notification transport

`shogunate moa deploy` notifies the **representative only**, so the role keeps a
single external address and the existing watcher escalation ladder
(`shogunate_mod/watcher/inbox_watcher.sh`) covers it without any change to
`cli.agents`. Non-representative members show
`delivery: {ok: null, detail: representative-relay}` until the representative
runs `shogunate moa notify-members <role> --task-id <id>`, which fans the
pointers out to the rest of the deployment.

The default transport writes through `shogunate_mod/inbox/write.sh`, which owns
the self-send guard, the generation gate, route policy, and report provenance.
MoA supplies the preconditions those gates expect and never modifies them; when
`queue/runtime/role_failover.yaml` exists, the sender's generation is taken from
the caller's `SHOGUNATE_ROLE_GENERATION` or read from that file.

Set `transport.mode: agmsg` in `config/settings.yaml` to keep using AGMSG
instead — the right choice where no tmux pane exists. Any other value, a missing
key, or a missing settings file selects the inbox transport.

`shogunate moa status` reports `delivery.read` by matching the deployment id
against `queue/inbox/<agent>.yaml`. The key is omitted while no matching message
exists, so "no inbox yet" stays distinct from "ignored".

## Watcher supervision

`deploy` publishes active members to `queue/runtime/moa_members.tsv`
(`agent<TAB>role<TAB>task_id<TAB>generation`); `dissolve` and a finalize that
dissolves remove those rows and delete the file once empty.
`shogunate_mod/watcher/supervisor.sh` reads that roster each tick, so members are
supervised while deployed and their watchers stop on the next tick afterwards.
Without the roster the supervisor treats them as unknown agents and
`cleanup_stale_watchers` kills their watchers within about five seconds.

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
