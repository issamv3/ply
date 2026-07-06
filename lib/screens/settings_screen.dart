import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = context.watch<SettingsProvider>();
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v > 300) Navigator.of(context).maybePop();
      },
      child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(
            Directionality.of(context) == TextDirection.rtl
                ? LucideIcons.arrowRight
                : LucideIcons.arrowLeft,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(l10n.settings),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _SectionHeader(label: l10n.appearance),
          _SettingCard(
            children: [
              _OptionTile(
                icon: LucideIcons.sun,
                label: l10n.themeLight,
                selected: settings.themeMode == ThemeMode.light,
                onTap: () => settings.setThemeMode(ThemeMode.light),
                scheme: scheme,
              ),
              _Divider(),
              _OptionTile(
                icon: LucideIcons.moon,
                label: l10n.themeDark,
                selected: settings.themeMode == ThemeMode.dark,
                onTap: () => settings.setThemeMode(ThemeMode.dark),
                scheme: scheme,
              ),
              _Divider(),
              _OptionTile(
                icon: LucideIcons.monitor,
                label: l10n.themeSystem,
                selected: settings.themeMode == ThemeMode.system,
                onTap: () => settings.setThemeMode(ThemeMode.system),
                scheme: scheme,
              ),
            ],
          ),
          const SizedBox(height: 24),
          _SectionHeader(label: l10n.language),
          _SettingCard(
            children: [
              _OptionTile(
                icon: LucideIcons.globe,
                label: l10n.langEnglish,
                selected: settings.locale?.languageCode == 'en',
                onTap: () => settings.setLocale(const Locale('en')),
                scheme: scheme,
              ),
              _Divider(),
              _OptionTile(
                icon: LucideIcons.globe,
                label: l10n.langArabic,
                selected: settings.locale?.languageCode == 'ar',
                onTap: () => settings.setLocale(const Locale('ar')),
                scheme: scheme,
              ),
              _Divider(),
              _OptionTile(
                icon: LucideIcons.smartphone,
                label: l10n.langSystem,
                selected: settings.locale == null,
                onTap: () => settings.setLocale(null),
                scheme: scheme,
              ),
            ],
          ),
          const SizedBox(height: 24),
          _SectionHeader(label: l10n.rotate),
          _SettingCard(
            children: [
              SwitchListTile(
                value: settings.autoRotate,
                onChanged: (v) => settings.setAutoRotate(v),
                secondary: Icon(
                  LucideIcons.rotateCw,
                  color: settings.autoRotate
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                  size: 20,
                ),
                title: Text(
                  l10n.autoRotate,
                  style: TextStyle(
                    fontWeight: settings.autoRotate
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: settings.autoRotate
                        ? scheme.primary
                        : scheme.onSurface,
                  ),
                ),
                subtitle: Text(
                  l10n.autoRotateDesc,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                activeColor: scheme.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _SectionHeader(label: l10n.network),
          _SettingCard(
            children: [
              SwitchListTile(
                value: settings.fbCdnEnabled,
                onChanged: (v) => settings.setFbCdn(v),
                secondary: Icon(
                  LucideIcons.zap,
                  color: settings.fbCdnEnabled
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                  size: 20,
                ),
                title: Text(
                  l10n.fbCdn,
                  style: TextStyle(
                    fontWeight: settings.fbCdnEnabled
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: settings.fbCdnEnabled
                        ? scheme.primary
                        : scheme.onSurface,
                  ),
                ),
                subtitle: Text(
                  l10n.fbCdnDesc,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                activeColor: scheme.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _SectionHeader(label: l10n.about),
          _SettingCard(
            children: [
              ListTile(
                leading: Icon(LucideIcons.info,
                    color: scheme.onSurfaceVariant, size: 20),
                title: Text(l10n.version),
                trailing: Text(
                  '1.0.0',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10, top: 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
      ),
    );
  }
}

class _SettingCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ColorScheme scheme;

  const _OptionTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
          size: 20),
      title: Text(
        label,
        style: TextStyle(
          color: selected ? scheme.primary : scheme.onSurface,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: selected
          ? Icon(LucideIcons.check, color: scheme.primary, size: 18)
          : null,
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 52,
      endIndent: 16,
      color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.4),
    );
  }
}
