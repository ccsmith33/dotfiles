# QuickShell Architecture Map (end-4/dots-hyprland)

Read-only audit of `/home/ccsmith33/end-4-dots/dots/.config/quickshell/ii/` to plan how the **deployment-pipeline teaching cockpit** plugs into end-4's QuickShell shell. Captured 2026-04-27 from end-4's main branch at the time of fork.

This is a **planning doc**, not config. Lives in the dotfiles repo for future reference; not applied to `~`.

---

## 1. Entry point & shell structure

`shell.qml` is the root. It uses a `ShellRoot` and instantiates **panel families** via lazy `PanelFamilyLoader` components:

```qml
ShellRoot {
    property list<string> families: ["ii", "waffle"]
    PanelFamilyLoader { identifier: "ii"; component: IllogicalImpulseFamily {} }
    PanelFamilyLoader { identifier: "waffle"; component: WaffleFamily {} }
}
```

On startup, `shell.qml` calls `.load()` on services: `MaterialThemeLoader`, `Hyprsunset`, `FirstRunExperience`, `ConflictKiller`, `Cliphist`, `Wallpapers`, `Updates`. Also wires `IpcHandler` and `GlobalShortcut` bindings to switch families.

**Key insight:** the shell does not hardcode a panel list — UI composition is delegated to the active family. Extending = adding a family or injecting panels into an existing one.

---

## 2. Module pattern (3 representative examples)

### 2a. Bar — `modules/ii/bar/Bar.qml` (261 lines)

Per-monitor top panel. Pattern:
- `Scope` wraps a `Variants` loop over monitors (`Quickshell.screens` filtered by config).
- Each monitor → `LazyLoader` → `PanelWindow`.
- `PanelWindow` uses `WlrLayershell` with namespace `"quickshell:bar"`.
- Reactive to `GlobalStates.barOpen` and `GlobalStates.superDown` via `Connections`.
- `IpcHandler` (target `"bar"`) provides `toggle()`, `open()`, `close()`.
- `GlobalShortcut` (name `"barToggle"`) binds keybinds.

### 2b. Overview — `modules/ii/overview/Overview.qml` (221 lines)

Full-screen search + workspace grid. Pattern:
- Single `PanelWindow` (not per-monitor).
- `WlrLayershell.layer: WlrLayer.Top` for highest z-order.
- Visibility bound to `GlobalStates.overviewOpen`.
- Uses `GlobalFocusGrab` to auto-dismiss on Escape.
- **This is the template to clone for the cockpit.**

### 2c. Sidebar Right — `modules/ii/sidebarRight/SidebarRight.qml` (111 lines)

Anchored drawer for notifications/toggles/calendar. Pattern:
- Single `PanelWindow` anchored `right: true`.
- `Loader` with `keepRightSidebarLoaded` config option (preload content even when hidden).

### Common pattern across all modules:
```qml
Scope {
    PanelWindow {
        visible: GlobalStates.someOpenFlag
        WlrLayershell.namespace: "quickshell:moduleName"
        // content...
    }
    IpcHandler { target: "moduleName"; function toggle(): void { ... } }
    GlobalShortcut { name: "moduleToggle"; onPressed: { ... } }
}
```

---

## 3. Services pattern

`services/` (~40 services). Each is a `pragma Singleton` QML object exposing reactive properties + methods. Three categories:

**A. Direct bindings to `Quickshell.Services.*`**
- `Audio.qml` (140 lines) — wraps Pipewire sink/source.
- `Battery.qml` (109 lines) — wraps UPower.

**B. External command polling (this is the pattern we'll reuse for the cockpit).**
- `HyprlandData.qml` (167 lines) — calls `hyprctl clients -j`, etc. via `Process` + `StdioCollector`, parses JSON, exposes reactive properties. Re-runs on Hyprland event.

**C. Central state**
- `GlobalStates.qml` (52 lines) — boolean flags for every UI surface (`barOpen`, `overviewOpen`, `sidebarRightOpen`, `screenLocked`, ~21 more).

Most relevant for cockpit work: the **B-pattern** (Process polling) used by `HyprlandData`. Existing `gCloud/` and `ai/` service subdirs are templates for external-API services.

---

## 4. Adding a `PipelineStatusPanel` — path of least resistance

5 small steps; no forking.

**Step 1.** Create module dir:
```
modules/ii/pipelineStatus/
  PipelineStatus.qml          # Top-level scope
  PipelineStatusWindow.qml    # PanelWindow wrapper
  PipelineStatusContent.qml   # Layout
```

**Step 2.** Implement `PipelineStatus.qml` following the common pattern (see §2). Use a unique `WlrLayershell.namespace: "quickshell:pipelineStatus"`.

**Step 3.** Register in `panelFamilies/IllogicalImpulseFamily.qml`:
```qml
import qs.modules.ii.pipelineStatus  // add to imports
// inside the Scope:
PanelLoader { component: PipelineStatus {} }
```

**Step 4.** Add the toggle flag to `services/GlobalStates.qml`:
```qml
property bool pipelineStatusOpen: false
```

**Step 5.** Bind keybind in Hyprland config:
```
bind = $mainMod, P, exec, quickshell:cmd toggle pipelineStatus
```

`IpcHandler` auto-registers commands under `quickshell:cmd <target> <function>`.

---

## 5. `panelFamilies/`

Each family encapsulates a complete cohesive UI theme — which panels to load, what layout, what styling. Two families exist:
- `IllogicalImpulseFamily.qml` (47 lines) — modern, centered overview, dual sidebars.
- `WaffleFamily.qml` (47 lines) — Win11 aesthetic.

Pattern: a `Scope` with imports + `PanelLoader { extraCondition: ...; component: ... {} }` for each panel.

`PanelLoader.qml` (helper):
```qml
LazyLoader {
    property bool extraCondition: true
    active: Config.ready && extraCondition
}
```

**Option for the cockpit:** create `panelFamilies/TeachingCockpitFamily.qml` to bundle the cockpit UI separately, register it in `shell.qml`'s `families` list, and let user IPC-switch into it for demos. This way day-to-day work stays in the IllogicalImpulse family and demos toggle into the cockpit family.

---

## 6. `scripts/`

Subdirs: `colors/` (wallpaper extraction, terminal theme), `hyprland/`, `ai/` (Ollama/Gemini), `images/`, `thumbnails/`, `videos/`. Mix of bash and Python.

Called from QML via `Process` + `StdioCollector`:
```qml
Process {
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector {
        onStreamFinished: { root.windowList = JSON.parse(text) }
    }
}
```

For the cockpit, drop scripts in `scripts/pipeline/`:
```
scripts/pipeline/fetch-docker-images.sh
scripts/pipeline/fetch-k8s-pods.sh
scripts/pipeline/fetch-azure-devops.sh
```

Wire each to a service that polls every N seconds via `Timer { interval: 5000; running: true; repeat: true; onTriggered: ...running = true }`.

---

## 7. Closest existing template

**`Overview` is it.** Full-screen overlay, reactive grid layout, dynamically populated from service state, keyboard-navigable, dismissable. Clone its structure for the cockpit:
1. Single `PanelWindow` covering the screen.
2. `Column`/`Grid` of status cards (Docker images, k8s pods, pipeline stages).
3. `Connections` to a new `PipelineData` service.
4. `IpcHandler` + `GlobalShortcut` for toggle.

---

## 8. Red flags / extension hazards

None blocking. Specifically clean:
- Panel families are lazy-loaded; safe to add new ones.
- `Config.qml` (629 lines) is a `JsonAdapter` singleton — extend it via new properties:
  ```qml
  property JsonObject pipelineStatus: JsonObject {
      property bool enable: true
      property int pollInterval: 5000
      property string kubeConfigPath: ""
  }
  ```
- `IpcHandler` is decoupled per-module; no central router to break.
- `GlobalStates` is extensible without registration.

Minor gotchas:
- `WlrLayershell` namespaces must be unique across modules. Pick distinct ones to avoid z-order conflicts.
- Icons in `assets/icons/`. Reference by filename (no extension).

---

## Cockpit-build checklist (concrete TODOs)

1. Create `modules/ii/pipelineStatus/PipelineStatus.qml`.
2. Add `pipelineStatusOpen` flag to `GlobalStates.qml`.
3. Register in `IllogicalImpulseFamily.qml` (or new `TeachingCockpitFamily`).
4. Create `services/PipelineData.qml` (singleton, Process-based, Timer-driven).
5. Write `scripts/pipeline/fetch-{docker,k8s,azure}.sh`.
6. Add keybind in Hyprland config: `bind = $mainMod, P, exec, quickshell:cmd toggle pipelineStatus`.

No fork required. The shell's `PanelFamilyLoader` + `LazyLoader` pattern handles dynamic composition cleanly. We layer on top.
