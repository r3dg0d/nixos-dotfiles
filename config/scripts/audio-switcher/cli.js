#!/usr/bin/env node
// audio-switcher — pick default PipeWire output/input devices.
// Tab: outputs <-> inputs | up/down: move | Enter: set default | r: refresh | q: quit
// Rice: OLED black / white / neon green (#00ff41).
import React, { useEffect, useState } from "react";
import { render, Box, Text, useApp, useInput } from "ink";
import { execFile } from "node:child_process";

const h = React.createElement;
const GREEN = "#00ff41";
const RED = "#ff2b2b";

function run(cmd, args) {
  return new Promise((resolve, reject) => {
    execFile(cmd, args, { maxBuffer: 32 * 1024 * 1024 }, (err, stdout) =>
      err ? reject(err) : resolve(stdout)
    );
  });
}

async function fetchDevices() {
  // pw-dump can emit several JSON arrays back-to-back if objects changed
  // mid-dump; splice the array boundaries into one.
  const raw = await run("pw-dump", []);
  const all = JSON.parse(raw.replace(/\]\s*\[/g, ","));

  const nodes = all.filter(
    (o) =>
      o.type === "PipeWire:Interface:Node" &&
      ["Audio/Sink", "Audio/Source"].includes(o.info?.props?.["media.class"])
  );
  const meta = all.find(
    (o) =>
      o.type === "PipeWire:Interface:Metadata" &&
      o.props?.["metadata.name"] === "default"
  );
  const defaults = {};
  for (const m of meta?.metadata ?? []) {
    if (m.key === "default.audio.sink") defaults.sink = m.value?.name;
    if (m.key === "default.audio.source") defaults.source = m.value?.name;
  }
  const mk = (cls) =>
    nodes
      .filter((n) => n.info.props["media.class"] === cls)
      .map((n) => ({
        id: n.id,
        name: n.info.props["node.name"],
        label:
          n.info.props["node.description"] ??
          n.info.props["node.nick"] ??
          n.info.props["node.name"],
      }));
  return {
    outputs: mk("Audio/Sink"),
    inputs: mk("Audio/Source"),
    defaults,
  };
}

function DeviceList({ title, devices, defaultName, cursor, focused }) {
  return h(
    Box,
    { flexDirection: "column", marginRight: 2 },
    h(
      Text,
      { bold: true, color: focused ? GREEN : "white", underline: focused },
      title
    ),
    ...devices.map((d, i) => {
      const isDefault = d.name === defaultName;
      const selected = focused && i === cursor;
      return h(
        Text,
        {
          key: d.id,
          color: selected ? "black" : isDefault ? GREEN : "white",
          backgroundColor: selected ? GREEN : undefined,
        },
        `${isDefault ? "● " : "  "}${d.label}`
      );
    }),
    devices.length === 0 && h(Text, { dimColor: true }, "  (none)")
  );
}

function App() {
  const { exit } = useApp();
  const [state, setState] = useState({ outputs: [], inputs: [], defaults: {} });
  const [pane, setPane] = useState(0); // 0 = outputs, 1 = inputs
  const [cursor, setCursor] = useState(0);
  const [status, setStatus] = useState("");
  const [error, setError] = useState("");

  const refresh = () =>
    fetchDevices()
      .then((s) => setState(s))
      .catch((e) => setError(String(e)));

  useEffect(() => {
    refresh();
  }, []);

  const list = pane === 0 ? state.outputs : state.inputs;

  useInput((input, key) => {
    if (input === "q" || key.escape) exit();
    else if (key.tab || key.leftArrow || key.rightArrow) {
      setPane((p) => 1 - p);
      setCursor(0);
    } else if (key.upArrow) setCursor((c) => Math.max(0, c - 1));
    else if (key.downArrow)
      setCursor((c) => Math.min(Math.max(0, list.length - 1), c + 1));
    else if (input === "r") refresh();
    else if (key.return && list[cursor]) {
      const dev = list[cursor];
      run("wpctl", ["set-default", String(dev.id)])
        .then(() => {
          setStatus(`default ${pane === 0 ? "output" : "input"} → ${dev.label}`);
          return refresh();
        })
        .catch((e) => setError(String(e)));
    }
  });

  return h(
    Box,
    {
      flexDirection: "column",
      borderStyle: "round",
      borderColor: GREEN,
      paddingX: 1,
    },
    h(Text, { bold: true, color: GREEN }, "  Audio Switcher"),
    h(Text, { dimColor: true }, "tab: pane  ↑/↓: move  enter: set  r: refresh  q: quit"),
    h(Text, null, " "),
    h(
      Box,
      { flexDirection: "row" },
      h(DeviceList, {
        title: "\u{f057e} Outputs",
        devices: state.outputs,
        defaultName: state.defaults.sink,
        cursor,
        focused: pane === 0,
      }),
      h(DeviceList, {
        title: " Inputs",
        devices: state.inputs,
        defaultName: state.defaults.source,
        cursor,
        focused: pane === 1,
      })
    ),
    status && h(Text, { color: GREEN }, status),
    error && h(Text, { color: RED }, error)
  );
}

render(h(App));
