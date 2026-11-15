# Cameron

Cameron is a personal day planner for Flutter 3.50 and Dart 3.14. It has a Daily Briefing with a timeline and a Tasks & Tools view for creating, editing, and checking off tasks and sub-steps.

## Run on a device

```sh
flutter pub get
flutter run
```

Tasks work immediately and are stored by the app on the device. To use the assistant, tap the floating mic or the keyboard icon and download **BotPsy-0.8B**. The Q4_K_M weights are about 529 MB. After installation, inference uses the local GGUF through llama.cpp. [BotPsy model card](https://huggingface.co/qvac/BotPsy-0.8B-GGUFs)

Try asking “Add a high priority task to review design tokens tomorrow at 10:30 for 45 minutes.” BotPsy can create, reschedule, and complete tasks or add checklist steps. On Android and iOS, open **Tool settings** (the gear in the header) to enable **Phone calls**, **SMS**, or **Email**. Each tool starts off. Tap the mic to speak. It sends the transcript when you pause or tap the waveform. Use **Type a request** (the keyboard icon) to type. Include a phone number or email address. Cameron shows the recipient and draft for review, then opens the dialer or composer for you to place the call or send the message. These handoffs require no additional device permissions. Dictation is available on iOS and Android when the system provides on-device speech recognition. The web build supports manual planning.

Cameron prepares read-only briefings at 07:00, 12:00, and 18:00 in the device’s local time. Android WorkManager and iOS Background Tasks run them when the OS allows. Opening the briefing catches up the current time slot if the background run was delayed. Briefings use the downloaded model and the app’s own task data.

## Develop with Widget Preview

From the workspace root, use your IDE's Flutter Widget Preview panel or run:

```sh
flutter widget-preview start
```

Both previews have interactive sample tasks and an in-memory store. The previews are defined in `packages/planner_ui/lib/previews.dart`.

- `packages/planner` contains task models, storage contracts, and validated tool execution.
- `packages/planner_ui` contains the screens, editors, and shared Material 3 Expressive theme.
- `packages/planner_assistant` downloads and runs BotPsy and supplies its tool definitions.
- `lib` connects the packages to device storage, dictation, and communication.

To add a device action, register a `DeviceTool` with its fields and review action, then implement its handoff under the same tool name on the supported platforms. The registry supplies the settings switch, BotPsy schema, validation, and review UI.

```sh
flutter analyze
flutter test
dart run tool/check_botpsy.dart /path/to/directory/containing/the/gguf
```

The final command checks tool calling with `botpsy-0.8b-q4_k_m-imat.gguf` on the host. Pass `--download` in place of the directory to check the app installer using temporary weights.
