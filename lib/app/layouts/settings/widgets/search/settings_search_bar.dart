import 'dart:async';

import 'package:bluebubbles/app/layouts/settings/widgets/search/settings_search_bar_ios.dart';
import 'package:flutter/material.dart';

class SettingsSearchBar extends StatefulWidget {
  final ValueChanged<String>? onChanged;
  final bool iOS;
  final Color? tileColor;

  /// Material skin: the outlined pill from Android's Settings app.
  final bool androidStyle;

  /// Shown to the left of the field. The Settings home has no title bar on
  /// Material, so its back arrow lives here.
  final Widget? leading;

  const SettingsSearchBar(
      {super.key, this.onChanged, required this.iOS, this.tileColor, this.androidStyle = false, this.leading});

  @override
  State<SettingsSearchBar> createState() => _SettingsSearchBarState();
}

class _SettingsSearchBarState extends State<SettingsSearchBar> {
  String searchValue = '';
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounceTimer;

  void _onSearchChanged(String query) {
    setState(() {
      searchValue = query.toLowerCase();
    });

    _debounceTimer?.cancel();

    if (query.trim().isEmpty) {
      widget.onChanged?.call('');
      return;
    }

    if (query.trim().length < 3) return;

    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      widget.onChanged?.call(searchValue);
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SettingsSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // sync the controller text when widget changes
    _controller.text = searchValue;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.androidStyle) return _androidField(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
      child: widget.iOS
          ? SettingsSearchBariOS(
              // use cupertino search bar if iOS style
              controller: _controller,
              focusNode: _focusNode,
              onChanged: _onSearchChanged,
            )
          : SearchBar(
              // material themed search bar
              controller: _controller,
              focusNode: _focusNode,
              backgroundColor: widget.tileColor != null ? WidgetStatePropertyAll(widget.tileColor) : null,
              hintText: 'Search Settings',
              hintStyle: MaterialStateProperty.all(
                TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: 0.5)
                      : Colors.black.withValues(alpha: 0.5),
                ),
              ),
              padding: const WidgetStatePropertyAll<EdgeInsets>(
                EdgeInsets.symmetric(horizontal: 16.0),
              ),
              elevation: const MaterialStatePropertyAll(1),
              onChanged: _onSearchChanged,
              leading: const Icon(Icons.search),
              trailing: <Widget>[
                if (searchValue.isNotEmpty)
                  Tooltip(
                    message: 'Clear search',
                    child: IconButton(
                      onPressed: () {
                        _debounceTimer?.cancel();
                        setState(() {
                          searchValue = '';
                          _controller.text = '';
                          _focusNode.unfocus();
                        });
                        widget.onChanged?.call('');
                      },
                      icon: const Icon(Icons.clear),
                    ),
                  ),
              ],
            ),
    );
  }

  void _clear() {
    _debounceTimer?.cancel();
    setState(() {
      searchValue = '';
      _controller.text = '';
      _focusNode.unfocus();
    });
    widget.onChanged?.call('');
  }

  /// Android Settings' search field: a full-width outlined pill on the card
  /// fill, 64dp tall, search glyph and a large "Search Settings" hint. Lines up
  /// with the cards below it (16dp from the screen edge).
  Widget _androidField(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme.titleLarge!.copyWith(fontSize: 20, fontWeight: FontWeight.w400);
    return Padding(
      padding: EdgeInsets.fromLTRB(widget.leading != null ? 4 : 16, 8, 16, 12),
      child: Row(
        children: [
          if (widget.leading != null) widget.leading!,
          Expanded(
            child: SearchBar(
              controller: _controller,
              focusNode: _focusNode,
              constraints: const BoxConstraints(minHeight: 64, maxHeight: 64),
              backgroundColor: WidgetStatePropertyAll(widget.tileColor ?? scheme.surface),
              surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              elevation: const WidgetStatePropertyAll(0),
              shape: const WidgetStatePropertyAll(StadiumBorder()),
              side: WidgetStatePropertyAll(BorderSide(color: scheme.outline, width: 1)),
              padding: const WidgetStatePropertyAll(EdgeInsets.only(left: 24, right: 12)),
              hintText: 'Search Settings',
              hintStyle: WidgetStatePropertyAll(text.copyWith(color: scheme.onSurfaceVariant)),
              textStyle: WidgetStatePropertyAll(text.copyWith(color: scheme.onSurface)),
              onChanged: _onSearchChanged,
              leading: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(Icons.search, color: scheme.onSurface, size: 26),
              ),
              trailing: <Widget>[
                if (searchValue.isNotEmpty)
                  IconButton(tooltip: 'Clear search', onPressed: _clear, icon: const Icon(Icons.clear)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
