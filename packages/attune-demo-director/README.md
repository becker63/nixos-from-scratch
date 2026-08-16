# Attune demo director

`attune-demo-director` owns only the isolated Hyprland stage and its capture
processes. Attune's tracked Node adapter remains the sole scientific/UI
boundary; the director never calls the Python campaign worker directly.

Inspection is inert:

```console
attune-demo-director --help
attune-demo-director plan --repo /home/becker/projects/attune
attune-demo-director doctor --repo /home/becker/projects/attune
```

A rehearsal requires only the exact stage phrase and writes a null
`launch_authority`:

```console
attune-demo-director rehearse \
  --repo /home/becker/projects/attune \
  --confirm RECORD-CAMPAIGN-A-STAGE-ONLY
```

A live recording additionally requires the distinct Campaign A phrase. It is
checked and discarded; state stores only the fixed SHA-256 authorization
receipt bound to the recording timestamp:

```console
attune-demo-director record \
  --repo /home/becker/projects/attune \
  --confirm RECORD-CAMPAIGN-A-STAGE-ONLY \
  --launch-confirm LAUNCH-CAMPAIGN-A-PAID-RUN \
  --audio-device '@DEFAULT_AUDIO_SINK@.monitor'
```

The audio device is explicit. Override it with an exact PipeWire/Pulse source
name when the default-sink monitor alias is not available. Spotify
authentication, exact-track playback, and later pause must all succeed before
the paid launch adapter can run.

The generated Codex prompt contains the exact session-bound `start-run`
command. `present --scene` accepts only tracked storyboard IDs. `wait begin`
and `wait end` accept only bounded reasons; `cut-plan` and `render` derive from
those intervals and never overwrite `campaign-a-master.mkv`.

Normal `stop` and `render` refuse while Campaign A reports `starting` or
`running`. Emergency capture-only teardown requires the exact printed phrase
and never signals the Python scientific worker.
