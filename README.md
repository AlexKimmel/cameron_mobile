# Cameron

Cameron is a personal day planner for Flutter 3.50 and Dart 3.14. It has a Daily Briefing with a timeline and a Tasks & Tools view for creating, editing, and checking off tasks and sub-steps.

## Run on a device

```sh
flutter pub get
flutter run
```

Tasks work immediately and are stored by the app on the device. On first launch, try an example day, add your first task, or defer assistant setup. Open **Assistant models** (the chip icon in the header) to download, switch, or delete local models. BotPsy-0.8B (529 MB) is the default and Qwen3-1.7B (1.28 GB) is a larger option. To add your own model, paste a public Hugging Face file URL for a single GGUF that includes a tool-calling chat template. Cameron loads the selected model on the device for inference. [BotPsy model card](https://huggingface.co/qvac/BotPsy-0.8B-GGUFs) · [Qwen3-1.7B GGUF files](https://huggingface.co/ggml-org/Qwen3-1.7B-GGUF)

Try asking “Add a high priority task to review design tokens tomorrow at 10:30 for 45 minutes.” The assistant can create, reschedule, and complete tasks or add checklist steps. On Android and iOS, open **Tool settings** (the gear in the header) to enable **Phone calls**, **SMS**, or **Email**. Each tool starts off. Enable **Task completion** to let the assistant propose marking a task complete. Enable **Calendar events** on Android or iOS and grant Calendar access to review event titles and times for a selected date. Tap the mic to speak. When you pause or tap the waveform, Cameron shows the transcript so you can edit it, record again, or submit it. Use **Type a request** (the keyboard icon) to type. Include a phone number or email address. Cameron shows the recipient and draft for review, then opens the dialer or composer for you to place the call or send the message. These handoffs require no additional device permissions. Dictation is available on iOS and Android when the system provides on-device speech recognition. The web build supports manual planning.

Choose **Repeat** when editing an open task to set a daily, weekly, or monthly pattern, an interval, and an optional end date. A repeating task can be edited for a single occurrence or the whole series. Cameron shows the recent two weeks, upcoming month, and next occurrence beyond that window. Explicitly edited and completed occurrences stay in your plan. You can also ask the local assistant to create or reschedule a recurring task. When a timed session overlaps, Cameron shows the conflict and offers available times before saving. Use **Undo** in the confirmation after deleting a task or applying assistant task changes.

Cameron prepares read-only briefings at 07:00, 12:00, and 18:00 by default in the device’s local time. Open **Tool settings** to edit those times or opt in to **Daily briefings** notifications. Android WorkManager and iOS Background Tasks run briefings when the OS allows. Opening the briefing catches up the current time slot if the background run was delayed. Briefings use the selected model and refresh when relevant tasks change. Open **Briefing focus** to tell Cameron what to emphasize, including unfinished priorities or completed work.

On Android and iOS, enable **Scheduled tasks** or **Daily briefings** in the Notifications section under **Tool settings**. Timed tasks use their start time and date-only tasks use 09:00 local time. Use **Task reminder** in the task editor and enable **Task reminders** in Notifications to receive an early alert. Task alerts offer a ten-minute snooze. **Quiet hours** delay task alerts and snoozes until the end of the selected period. Cameron schedules up to 48 pending task alerts and refreshes the queue when tasks change or the app resumes. Background delivery follows device notification and battery settings.

Use **Backup** under **Tool settings** to export a local JSON file or preview and restore one. A restore replaces tasks and saved preferences, including tool switches, briefing focus, and notification settings. Model entries are saved as URLs so they can be downloaded from the model library.

## Develop with Widget Preview

From the workspace root, use your IDE's Flutter Widget Preview panel or run:

```sh
flutter widget-preview start
```

Both previews have interactive sample tasks and an in-memory store. The previews are defined in `packages/planner_ui/lib/previews.dart`.

- `packages/planner` contains task models, storage contracts, and validated tool execution.
- `packages/planner_ui` contains the screens, editors, and shared Material 3 Expressive theme.
- `packages/planner_assistant` downloads and runs local GGUF models and supplies its tool definitions.
- `lib` connects the packages to device storage, dictation, and communication.

To add a device action, register a `DeviceTool` with its fields and review action, then implement its handoff under the same tool name on the supported platforms. The registry supplies the settings switch, assistant tool schema, validation, and review UI.

```sh
flutter analyze
flutter test
dart run tool/check_botpsy.dart /path/to/directory/containing/the/gguf
```

The final command checks tool calling with `botpsy-0.8b-q4_k_m-imat.gguf` on the host. Pass `--download` in place of the directory to check the app installer using temporary weights. Add a Hugging Face GGUF URL after `--download` to try the same tool-calling checks with another model.
