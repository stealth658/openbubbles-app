# widgets/content/ — Reusable Settings Tile Building Blocks

These are the **primary building blocks** for all settings pages. Assemble settings UIs by composing these widgets — do not build custom `ListTile` rows from scratch.

## Files

| Widget | File | Purpose |
|--------|------|---------|
| `SettingsTile` | `settings_tile.dart` | Base row: title, subtitle, leading icon, trailing widget, onTap |
| `SettingsSwitch` | `settings_switch.dart` | Toggle row with a `BBSwitch` (skin-aware — `lib/app/components/bb_switch.dart`); tap toggles |
| `SettingsOptions<T>` | `settings_dropdown.dart` | Dropdown selector (Material) or segmented control (iOS) |
| `SettingsSlider` | `settings_slider.dart` | Slider input row with a `BBSlider` (skin-aware — `lib/app/components/bb_slider.dart`) |
| `SettingsLeadingIcon` | `settings_leading_icon.dart` | Styled leading icon (colored rounded square) |
| `SettingsSubtitle` | `settings_subtitle.dart` | Section subtitle / description text |
| `NextButton` | `next_button.dart` | Navigation arrow button for settings flows |
| `AdvancedThemingTile` | `advanced_theming_tile.dart` | Specialized color-picker tile for theme settings |
| `LogLevelSelector` | `log_level_selector.dart` | Specialized dropdown for log verbosity |

## Usage Examples

```dart
// Simple navigation row
SettingsTile(
  title: 'Notification Sound',
  subtitle: 'Tap to change',
  leading: SettingsLeadingIcon(icon: Icons.notifications, backgroundColor: Colors.blue),
  trailing: NextButton(),
  onTap: () => NavigationSvc.push(context, NotificationSoundPage()),
)

// Toggle with reactive value
Obx(() => SettingsSwitch(
  title: 'Show Delivery Timestamps',
  initialVal: SettingsSvc.settings.showDeliveryTimestamps.value,
  onChanged: (val) async {
    SettingsSvc.settings.showDeliveryTimestamps.value = val;
    await SettingsSvc.settings.saveOneAsync('showDeliveryTimestamps');
  },
))

// Dropdown selector
SettingsOptions<Skins>(
  title: 'App Skin',
  initial: SettingsSvc.settings.skin.value,
  options: Skins.values,
  textProcessing: (skin) => skin.toString().split('.').last,
  onChanged: (skin) { ... },
)
```

## Rules

- `SettingsTile` is purely presentational (no reactive observables) — wrap in `Obx()` at the call site if the value is reactive.
- `SettingsSwitch.initialVal` is the current value shown; `onChanged` is the write handler. Always persist the new value inside `onChanged` — `SettingsSvc.saveSettings()` no longer exists. Use:
  - `SettingsSvc.settings.saveOneAsync('key')` — preferred; writes just the one setting.
  - `SettingsSvc.settings.saveManyAsync(['keyA', 'keyB'])` — when one handler changes several settings at once.
  - `SettingsSvc.settings.saveAsync()` — whole-object write; only when the change is broad enough to justify it.

  The key string is the field name as it appears in `Settings.toMap()` (`lib/database/global/settings.dart`). All three are `Future`s — `await` them, or `unawaited(...)` if the handler cannot be async.
- `SettingsOptions` is generic — `T` can be any enum or value type. Provide `textProcessing` to format the display label.
- Use `SettingsLeadingIcon` for the `leading` parameter to keep visual consistency across all settings pages.

## See Also

- `widgets/tiles/` — higher-level composed tiles (may wrap these building blocks)
- `widgets/layout/` — page layout containers
- `widgets/search/` — settings search UI (see `search/CLAUDE.md`)
- `docs/COMMON_TASKS.md` — step-by-step recipe for adding a new setting
